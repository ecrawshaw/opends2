// WiFi OBD adapter: K-line and CAN bridges for the KLine package (and other tools).
//
//   TCP 23    K-line raw bytes both ways. Whatever arrives goes out on the K-line; everything the
//             transceiver hears (our own echo + the module's answer) comes back. One client at a time.
//   TCP 3333  CAN, SLCAN (Lawicel) text protocol, so python-can / SavvyCAN / slcand work too:
//             S0..S8 bitrate (10k..1M, S6 = 500k), O open, L open listen-only, C close,
//             tIIILDD.. send 11-bit, TIIIIIIIILDD.. send 29-bit, M/m acceptance code/mask (SJA1000
//             format, applied on next open), V version, F status. Received frames come back as t/T lines.
//   HTTP 80   /status                        JSON: firmware, K-line settings, CAN state, battery, WiFi
//             /config?baud=10400&parity=none K-line UART (BMW DS2/KWP2000*: 9600 even; OBD: 10400 none)
//             /kinit?mode=fast               ISO 14230 fast init (25 ms low, 25 ms high), then send
//                                            StartCommunication yourself over port 23
//             /kinit?mode=slow&addr=33       ISO 9141 / 14230 5-baud init; returns the key bytes
//             /wifi                          JSON: saved networks, which one is joined
//             /wifi?ssid=..&pass=..          save a network to join (up to 4: home, phone hotspot, ...)
//             /wifi?forget=..  /wifi?ap_pass=..
//             /power?sleep_min=20&run_volts=13.2&low_volts=11.8   (sleep_min=0: never sleep)
//
// The adapter always runs its own network "OBD-Adapter" at 192.168.4.1, and also joins the strongest
// saved network in range, where it's found as obdadapter.local.
//
// Pin 16 is powered with the car off, so it deep-sleeps when nobody has connected for sleep_min minutes
// and the engine isn't running (below run_volts the alternator isn't charging; ignition-on-engine-off
// looks the same as parked, so voltage alone can't tell those apart), or after 2 idle minutes below
// low_volts. Asleep, it checks the battery every 30 s and wakes once the engine runs; replugging it
// also wakes it.
// All protocol knowledge (DS2, KWP, ISO-TP, OBD-II) lives on the client; this stays a bridge.
#include <Arduino.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include "driver/twai.h"
#include "esp_sleep.h"

#define FIRMWARE "0.3"
#define AP_SSID "OBD-Adapter"
#define AP_PASS_DEFAULT "obdadapter"
// 100k / 15k divider from OBD pin 16: 16 V -> 2.1 V at the ADC (the C3 reads up to ~2.5 V)
#define BATT_RATIO ((100.0 + 15.0) / 15.0)
// Send what the K-line delivered once it's been quiet this long (a byte is ~1 ms), so an answer
// usually travels as one packet instead of one per byte.
#define FLUSH_GAP_US 3000
#define MAX_NETS 4
#define SLEEP_CHECK_S 30

static WiFiServer kServer(23), canServer(3333);
static WebServer web(80);
static WiFiClient kClient, canClient;
static Preferences prefs;
static String powerText();
static void touch();

// ---------------------------------------------------------------- K-line

static uint32_t kBaud = 9600;
static bool kEven = true;
static uint8_t kBuf[512];
static size_t kLen = 0;
static uint32_t kLastRxUs = 0;

static void startUart() {
  Serial1.end();
  Serial1.setRxBufferSize(1024);
  Serial1.begin(kBaud, kEven ? SERIAL_8E1 : SERIAL_8N1, K_RX, K_TX);
  while (Serial1.available()) Serial1.read();
  kLen = 0;
}

// Drive the K-line directly (UART detached). The L9637D has no transmit timeout, so long lows work.
static void kPin(bool high, uint32_t ms) {
  digitalWrite(K_TX, high ? HIGH : LOW);
  delay(ms);
}

static void handleKinit() {
  touch();
  String mode = web.arg("mode");
  if (web.hasArg("baud")) kBaud = web.arg("baud").toInt();
  else kBaud = 10400;
  kEven = false;
  Serial1.end();
  pinMode(K_TX, OUTPUT);
  if (mode == "fast") {
    kPin(true, 300);   // bus idle (W5)
    kPin(false, 25);   // TiniL
    kPin(true, 25);    // rest of TWuP
    startUart();
    return web.send(200, "application/json", "{\"ok\":true}");
  }
  if (mode != "slow") return web.send(400, "text/plain", "mode must be fast or slow");
  uint8_t addr = web.hasArg("addr") ? strtol(web.arg("addr").c_str(), nullptr, 16) : 0x33;
  kPin(true, 300);
  kPin(false, 200);                                   // start bit
  for (int i = 0; i < 8; i++) kPin((addr >> i) & 1, 200);  // address, LSB first (bit 7 = parity)
  digitalWrite(K_TX, HIGH);                           // stop bit; the ECU answers at kBaud
  startUart();
  // Collect the ECU's 0x55 sync + 2 key bytes (W1 <= 300 ms, W2/W3 <= 20 ms), ignoring our own echo
  uint8_t got[8];
  size_t n = 0;
  uint32_t t0 = millis();
  while (millis() - t0 < 600 && n < 3) {
    if (Serial1.available()) {
      uint8_t b = Serial1.read();
      if (n == 0 && b != 0x55) continue;
      got[n++] = b;
    }
  }
  if (n < 3) return web.send(504, "application/json", "{\"ok\":false,\"error\":\"no sync from ECU\"}");
  delay(30);                                          // W4 25-50 ms
  Serial1.write((uint8_t)~got[2]);                    // inverted KB2
  Serial1.flush();
  uint8_t inv = 0;
  t0 = millis();
  bool sawEcho = false, ok = false;
  while (millis() - t0 < 100) {
    if (!Serial1.available()) continue;
    uint8_t b = Serial1.read();
    if (!sawEcho && b == (uint8_t)~got[2]) { sawEcho = true; continue; }
    inv = b; ok = true; break;                        // ECU's inverted address
  }
  char j[160];
  snprintf(j, sizeof(j), "{\"ok\":%s,\"kb1\":\"%02X\",\"kb2\":\"%02X\",\"invAddr\":\"%02X\"}",
           ok && inv == (uint8_t)~addr ? "true" : "false", got[1], got[2], inv);
  web.send(200, "application/json", j);
}

static void kLoop() {
  if (kServer.hasClient()) {  // a new connection replaces the old one (e.g. the app restarted)
    if (kClient) kClient.stop();
    kClient = kServer.available();
    kClient.setNoDelay(true);
    while (Serial1.available()) Serial1.read();
    kLen = 0;
  }
  if (kClient && kClient.connected()) {
    uint8_t tx[256];
    int n = kClient.available();
    if (n > 0) Serial1.write(tx, kClient.read(tx, min(n, (int)sizeof(tx))));
  }
  while (Serial1.available() && kLen < sizeof(kBuf)) {
    kBuf[kLen++] = Serial1.read();
    kLastRxUs = micros();
  }
  if (kLen && (kLen == sizeof(kBuf) || micros() - kLastRxUs > FLUSH_GAP_US)) {
    if (kClient && kClient.connected()) kClient.write(kBuf, kLen);
    kLen = 0;
  }
}

// ---------------------------------------------------------------- CAN (TWAI) over SLCAN

static int canBitrate = 6;  // S6 = 500k
static bool canOpen = false, canListenOnly = false;
static uint32_t canCode = 0, canMask = 0xFFFFFFFF;  // accept all
static String canLine;
static uint32_t canRx = 0, canTx = 0, canErr = 0;

static twai_timing_config_t timingFor(int s) {
  switch (s) {
#ifdef TWAI_TIMING_CONFIG_10KBITS  // classic ESP32 bottoms out at 25k; no OBD bus is that slow anyway
    case 0: return TWAI_TIMING_CONFIG_10KBITS();
    case 1: return TWAI_TIMING_CONFIG_20KBITS();
#endif
    case 2: return TWAI_TIMING_CONFIG_50KBITS();
    case 3: return TWAI_TIMING_CONFIG_100KBITS();
    case 4: return TWAI_TIMING_CONFIG_125KBITS();
    case 5: return TWAI_TIMING_CONFIG_250KBITS();
    case 7: return TWAI_TIMING_CONFIG_800KBITS();
    case 8: return TWAI_TIMING_CONFIG_1MBITS();
    default: return TWAI_TIMING_CONFIG_500KBITS();
  }
}

static void canClose() {
  if (!canOpen) return;
  twai_stop();
  twai_driver_uninstall();
  canOpen = false;
}

static bool canStart(bool listenOnly) {
  canClose();
  twai_general_config_t g = TWAI_GENERAL_CONFIG_DEFAULT((gpio_num_t)CAN_TX, (gpio_num_t)CAN_RX,
                                                        listenOnly ? TWAI_MODE_LISTEN_ONLY : TWAI_MODE_NORMAL);
  g.rx_queue_len = 64;
  g.tx_queue_len = 8;
  twai_timing_config_t t = timingFor(canBitrate);
  twai_filter_config_t f = {.acceptance_code = canCode, .acceptance_mask = canMask, .single_filter = true};
  if (twai_driver_install(&g, &t, &f) != ESP_OK) return false;
  if (twai_start() != ESP_OK) { twai_driver_uninstall(); return false; }
  canOpen = true;
  canListenOnly = listenOnly;
  return true;
}

static void canReply(const char* s) { if (canClient && canClient.connected()) canClient.print(s); }

static int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  c |= 0x20;
  return c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

static bool parseHex(const String& s, int from, int len, uint32_t& out) {
  if ((int)s.length() < from + len) return false;
  out = 0;
  for (int i = from; i < from + len; i++) {
    int v = hexVal(s[i]);
    if (v < 0) return false;
    out = out << 4 | v;
  }
  return true;
}

static void canCommand(const String& c) {
  if (c.isEmpty()) return canReply("\r");
  switch (c[0]) {
    case 'S':
      if (c.length() == 2 && c[1] >= '0' && c[1] <= '8' && !canOpen) { canBitrate = c[1] - '0'; return canReply("\r"); }
      return canReply("\a");
    case 'O': return canReply(canStart(false) ? "\r" : "\a");
    case 'L': return canReply(canStart(true) ? "\r" : "\a");
    case 'C': canClose(); return canReply("\r");
    case 'M': { uint32_t v; if (parseHex(c, 1, 8, v) && !canOpen) { canCode = v; return canReply("\r"); } return canReply("\a"); }
    case 'm': { uint32_t v; if (parseHex(c, 1, 8, v) && !canOpen) { canMask = v; return canReply("\r"); } return canReply("\a"); }
    case 'V': return canReply("V0102\r");
    case 'N': return canReply("NOBD1\r");
    case 'Z': return canReply("\r");  // timestamps: not supported, accepted
    case 'F': {
      twai_status_info_t st;
      uint8_t flags = 0;
      if (canOpen && twai_get_status_info(&st) == ESP_OK) {
        if (st.rx_missed_count) flags |= 0x08;
        if (st.state == TWAI_STATE_BUS_OFF) flags |= 0x80;
        if (st.tx_error_counter > 127 || st.rx_error_counter > 127) flags |= 0x20;
      }
      char b[6]; snprintf(b, sizeof(b), "F%02X\r", flags); return canReply(b);
    }
    case 't': case 'T': {
      bool ext = c[0] == 'T';
      int idLen = ext ? 8 : 3;
      uint32_t id, dlc;
      if (!canOpen || canListenOnly || !parseHex(c, 1, idLen, id) || !parseHex(c, 1 + idLen, 1, dlc) || dlc > 8)
        return canReply("\a");
      twai_message_t m = {};
      m.extd = ext;
      m.identifier = id;
      m.data_length_code = dlc;
      for (uint32_t i = 0; i < dlc; i++) {
        uint32_t v;
        if (!parseHex(c, 2 + idLen + i * 2, 2, v)) return canReply("\a");
        m.data[i] = v;
      }
      if (twai_transmit(&m, pdMS_TO_TICKS(20)) != ESP_OK) { canErr++; return canReply("\a"); }
      canTx++;
      return canReply(ext ? "Z\r" : "z\r");
    }
  }
  canReply("\a");
}

static void canLoop() {
  if (canServer.hasClient()) {
    if (canClient) canClient.stop();
    canClient = canServer.available();
    canClient.setNoDelay(true);
    canLine = "";
  }
  if (canClient && canClient.connected()) {
    while (canClient.available()) {
      char ch = canClient.read();
      if (ch == '\r' || ch == '\n') { if (ch == '\r' || !canLine.isEmpty()) canCommand(canLine); canLine = ""; }
      else if (canLine.length() < 40) canLine += ch;
    }
  } else if (canOpen && !canClient.connected()) {
    canClose();  // nobody listening: get off the car's bus
  }
  if (!canOpen) return;
  twai_message_t m;
  char out[600];
  size_t o = 0;
  while (o < sizeof(out) - 32 && twai_receive(&m, 0) == ESP_OK) {
    canRx++;
    if (m.rtr) continue;
    o += m.extd ? snprintf(out + o, 12, "T%08lX", (unsigned long)m.identifier) : snprintf(out + o, 6, "t%03lX", (unsigned long)m.identifier);
    out[o++] = '0' + m.data_length_code;
    for (int i = 0; i < m.data_length_code; i++) o += snprintf(out + o, 3, "%02X", m.data[i]);
    out[o++] = '\r';
  }
  if (o && canClient.connected()) canClient.write((const uint8_t*)out, o);
  twai_status_info_t st;
  if (twai_get_status_info(&st) == ESP_OK && st.state == TWAI_STATE_BUS_OFF) {
    canErr++;
    canClose();  // wrong bitrate or wiring: stay off the bus until the client reopens
  }
}

// ---------------------------------------------------------------- HTTP / WiFi

static float batteryVolts() {
  uint32_t mv = 0;
  for (int i = 0; i < 8; i++) mv += analogReadMilliVolts(BATT_PIN);
  return mv / 8 / 1000.0 * BATT_RATIO;
}

static String wifiText() {
  String s = String("AP ") + AP_SSID + " " + WiFi.softAPIP().toString();
  if (WiFi.status() == WL_CONNECTED) s += ", joined " + WiFi.SSID() + " " + WiFi.localIP().toString();
  return s;
}

static void handleStatus() {
  touch();
  static const char* rates[] = {"10k", "20k", "50k", "100k", "125k", "250k", "500k", "800k", "1M"};
  float v = batteryVolts();
  String j = "{\"firmware\":\"" FIRMWARE "\",\"baud\":" + String(kBaud) + ",\"parity\":\"" + (kEven ? "even" : "none") + "\"";
  j += ",\"batteryVolts\":" + (v < 1 ? String("null") : String(v, 2));
  j += ",\"can\":\"" + String(canOpen ? (canListenOnly ? "listen " : "open ") : "closed ") + rates[canBitrate] +
       " rx " + canRx + " tx " + canTx + " err " + canErr + "\"";
  j += ",\"wifi\":\"" + wifiText() + "\",\"uptime\":" + String(millis() / 1000);
  j += ",\"power\":\"" + powerText() + "\"}";
  web.send(200, "application/json", j);
}

static void handleConfig() {
  touch();
  if (web.hasArg("baud")) {
    long b = web.arg("baud").toInt();
    if (b < 1200 || b > 125000) return web.send(400, "text/plain", "baud must be 1200-125000");
    kBaud = b;
  }
  if (web.hasArg("parity")) {
    String p = web.arg("parity");
    if (p != "even" && p != "none") return web.send(400, "text/plain", "parity must be even or none");
    kEven = p == "even";
  }
  startUart();
  handleStatus();
}

// ---------------------------------------------------------------- saved networks

struct Net { String ssid, pass; };
static Net nets[MAX_NETS];
static int netCount = 0;
static uint32_t joinStarted = 0, lastScan = 0;
static bool clientBusy();

static void loadNets() {
  netCount = 0;
  for (int i = 0; i < MAX_NETS; i++) {
    String s = prefs.getString(("n" + String(i) + "s").c_str(), "");
    if (!s.isEmpty()) nets[netCount++] = {s, prefs.getString(("n" + String(i) + "p").c_str(), "")};
  }
  String old = prefs.getString("ssid", "");  // firmware 0.2 kept a single network
  if (!old.isEmpty() && netCount == 0) nets[netCount++] = {old, prefs.getString("pass", "")};
}

static void saveNets() {
  for (int i = 0; i < MAX_NETS; i++) {
    prefs.putString(("n" + String(i) + "s").c_str(), i < netCount ? nets[i].ssid : "");
    prefs.putString(("n" + String(i) + "p").c_str(), i < netCount ? nets[i].pass : "");
  }
  prefs.remove("ssid");
  prefs.remove("pass");
}

// Not joined: scan now and then, join the strongest saved network in range. Never while a client is
// connected, since scanning hops channels and can disturb the adapter's own network.
static void staLoop() {
  if (netCount == 0 || WiFi.status() == WL_CONNECTED || clientBusy()) return;
  int16_t found = WiFi.scanComplete();
  if (found == WIFI_SCAN_RUNNING) return;
  if (found >= 0) {
    int best = -1, bestRssi = -1000;
    for (int i = 0; i < found; i++)
      for (int n = 0; n < netCount; n++)
        if (WiFi.SSID(i) == nets[n].ssid && WiFi.RSSI(i) > bestRssi) { best = n; bestRssi = WiFi.RSSI(i); }
    WiFi.scanDelete();
    if (best >= 0) {
      WiFi.begin(nets[best].ssid.c_str(), nets[best].pass.c_str());
      joinStarted = millis();
    }
    return;
  }
  if (millis() - joinStarted < 15000 || millis() - lastScan < 15000) return;
  lastScan = millis();
  WiFi.scanNetworks(true);
}

static String jsonEscape(const String& s) {
  String o;
  for (char c : s) { if (c == '"' || c == '\\') o += '\\'; if ((uint8_t)c >= 0x20) o += c; }
  return o;
}

static String htmlEscape(const String& s) {
  String o;
  for (char c : s) {
    if (c == '<') o += "&lt;"; else if (c == '>') o += "&gt;"; else if (c == '&') o += "&amp;";
    else if (c == '\'') o += "&#39;"; else if (c == '"') o += "&quot;"; else o += c;
  }
  return o;
}

static String urlEncode(const String& s) {
  String o;
  char b[4];
  for (uint8_t c : s) {
    if (isalnum(c) || c == '-' || c == '_' || c == '.') o += (char)c;
    else { snprintf(b, sizeof(b), "%%%02X", c); o += b; }
  }
  return o;
}

static void sendNets() {
  String j = "{\"saved\":[";
  for (int i = 0; i < netCount; i++) j += (i ? ",\"" : "\"") + jsonEscape(nets[i].ssid) + "\"";
  j += "],\"joined\":";
  j += WiFi.status() == WL_CONNECTED ? "\"" + jsonEscape(WiFi.SSID()) + "\",\"ip\":\"" + WiFi.localIP().toString() + "\"" : String("null");
  web.send(200, "application/json", j + "}");
}

static void touch();

static void handleWifi() {
  touch();
  if (web.hasArg("ap_pass")) {
    String p = web.arg("ap_pass");
    if (p.length() < 8) return web.send(400, "text/plain", "ap_pass needs 8+ characters");
    prefs.putString("ap_pass", p);
    web.send(200, "text/plain", "saved, restarting\n");
    delay(300);
    ESP.restart();
  }
  if (web.hasArg("forget")) {
    String f = web.arg("forget");
    int w = 0;
    for (int i = 0; i < netCount; i++) if (nets[i].ssid != f) nets[w++] = nets[i];
    netCount = w;
    saveNets();
    if (WiFi.status() == WL_CONNECTED && WiFi.SSID() == f) WiFi.disconnect();
  }
  if (web.hasArg("ssid") && !web.arg("ssid").isEmpty()) {
    String ss = web.arg("ssid");
    int i = 0;
    while (i < netCount && nets[i].ssid != ss) i++;
    if (i == netCount) {  // new; when full, drop the oldest
      if (netCount == MAX_NETS) { for (int k = 1; k < MAX_NETS; k++) nets[k - 1] = nets[k]; netCount--; }
      i = netCount++;
    }
    nets[i] = {ss, web.arg("pass")};
    saveNets();
    lastScan = joinStarted = 0;
    if (WiFi.status() != WL_CONNECTED) { WiFi.disconnect(); lastScan = millis() - 15000; }
  }
  if (web.hasArg("ui")) { web.sendHeader("Location", "/"); return web.send(303); }
  sendNets();
}

// ---------------------------------------------------------------- power

static uint32_t lastActivity = 0, lastPowerCheck = 0, lowSince = 0;
static int sleepMin = 20;
static float runVolts = 13.2, lowVolts = 11.8;

static void touch() { lastActivity = millis(); }

static void loadPower() {
  sleepMin = prefs.getInt("sleep_min", 20);
  runVolts = prefs.getFloat("run_v", 13.2);
  lowVolts = prefs.getFloat("low_v", 11.8);
}

static float batteryVolts();

static void goToSleep() {
  Serial.println("sleeping");
  canClose();
  Serial1.end();
  WiFi.mode(WIFI_OFF);
  digitalWrite(LED_PIN, !LED_ON);
  // Hold both transmit lines recessive (high) so neither bus is pulled while the chip is asleep
  for (int pin : {K_TX, CAN_TX}) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, HIGH);
    gpio_hold_en((gpio_num_t)pin);
  }
  gpio_deep_sleep_hold_en();
  esp_sleep_enable_timer_wakeup((uint64_t)SLEEP_CHECK_S * 1000000);
  esp_deep_sleep_start();
}

// Woken by the timer: go straight back to sleep unless the engine is running. Takes a few ms.
static void sleepCheckOnWake() {
  if (esp_sleep_get_wakeup_cause() != ESP_SLEEP_WAKEUP_TIMER) return;
  float v = batteryVolts();
  if (v >= 1 && v < runVolts) {
    esp_sleep_enable_timer_wakeup((uint64_t)SLEEP_CHECK_S * 1000000);
    esp_deep_sleep_start();
  }
}

static void powerLoop() {
  if (clientBusy()) touch();
  if (millis() - lastPowerCheck < 5000) return;
  lastPowerCheck = millis();
  float v = batteryVolts();
  if (sleepMin <= 0 || v < 1) return;  // disabled, or on USB power at the bench
  if (v >= runVolts) { touch(); lowSince = 0; return; }  // engine running
  uint32_t idle = millis() - lastActivity;
  if (v < lowVolts) {
    if (!lowSince) lowSince = millis();
    if (millis() - lowSince > 120000 && idle > 120000) goToSleep();
  } else lowSince = 0;
  if (idle > (uint32_t)sleepMin * 60000) goToSleep();
}

static String powerText() {
  if (sleepMin <= 0) return "never sleeps";
  char b[96];
  snprintf(b, sizeof(b), "sleeps after %d min idle below %.1f V (sooner below %.1f V)", sleepMin, runVolts, lowVolts);
  return b;
}

static void handlePower() {
  touch();
  if (web.hasArg("sleep_min")) { sleepMin = constrain(web.arg("sleep_min").toInt(), 0, 1440); prefs.putInt("sleep_min", sleepMin); }
  if (web.hasArg("run_volts")) { runVolts = constrain(web.arg("run_volts").toFloat(), 12.0, 15.0); prefs.putFloat("run_v", runVolts); }
  if (web.hasArg("low_volts")) { lowVolts = constrain(web.arg("low_volts").toFloat(), 10.0, 13.0); prefs.putFloat("low_v", lowVolts); }
  if (web.hasArg("ui")) { web.sendHeader("Location", "/"); return web.send(303); }
  web.send(200, "application/json", "{\"power\":\"" + powerText() + "\"}");
}

static void handleRoot() {
  touch();
  String h = "<meta name=viewport content='width=device-width'><h3>OBD adapter " FIRMWARE "</h3>"
             "<p>K-line on port 23, CAN (SLCAN) on port 3333. <a href=/status>status</a></p><p>" + wifiText() + "</p>"
             "<h4>Networks to join</h4><ul>";
  for (int i = 0; i < netCount; i++)
    h += "<li>" + htmlEscape(nets[i].ssid) + " <a href='/wifi?ui=1&forget=" + urlEncode(nets[i].ssid) + "'>forget</a></li>";
  if (netCount == 0) h += "<li>none</li>";
  h += "</ul><form action=/wifi method=post><input type=hidden name=ui value=1>"
       "<input name=ssid placeholder=network> <input name=pass type=password placeholder=password> <button>Add</button></form>"
       "<h4>Power</h4><p>" + powerText() + "</p><form action=/power method=post><input type=hidden name=ui value=1>"
       "minutes <input name=sleep_min size=4 value=" + String(sleepMin) + "> <button>Save</button> (0 = never)</form>";
  web.send(200, "text/html", h);
}

static bool clientBusy() { return (kClient && kClient.connected()) || (canClient && canClient.connected()); }

void setup() {
  for (int pin : {K_TX, CAN_TX}) gpio_hold_dis((gpio_num_t)pin);
  gpio_deep_sleep_hold_dis();
  prefs.begin("adapter", false);
  loadPower();
  sleepCheckOnWake();

  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, !LED_ON);
  startUart();
  loadNets();

  WiFi.persistent(false);  // networks live in prefs; don't let the SDK rewrite flash on every join
  WiFi.mode(WIFI_AP_STA);
  WiFi.setSleep(false);  // power save adds 100+ ms latency spikes
  WiFi.setAutoReconnect(true);
  WiFi.softAP(AP_SSID, prefs.getString("ap_pass", AP_PASS_DEFAULT).c_str());
  MDNS.begin("obdadapter");
  MDNS.addService("http", "tcp", 80);
  MDNS.addService("kline", "tcp", 23);
  MDNS.addService("slcan", "tcp", 3333);

  web.on("/", handleRoot);
  web.on("/status", handleStatus);
  web.on("/config", handleConfig);
  web.on("/kinit", handleKinit);
  web.on("/wifi", handleWifi);
  web.on("/power", handlePower);
  web.begin();
  kServer.begin();
  kServer.setNoDelay(true);
  canServer.begin();
  canServer.setNoDelay(true);
  touch();
  Serial.printf("OBD adapter %s: %s, %d saved network(s), %s\n", FIRMWARE, wifiText().c_str(), netCount, powerText().c_str());
}

void loop() {
  web.handleClient();
  kLoop();
  canLoop();
  staLoop();
  powerLoop();
  // Solid while a client is connected, slow blink while waiting
  digitalWrite(LED_PIN, clientBusy() || (millis() / 1000) % 2 ? LED_ON : !LED_ON);
}
