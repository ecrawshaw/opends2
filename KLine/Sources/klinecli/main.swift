import Foundation
import KLine

/// Scripted stand-in for the cable: echoes what's written, then plays back a canned answer.
final class FakeLink: ByteLink {
    var replies: [[UInt8]: [UInt8]] = [:]
    var echo = true
    private var queue: [UInt8] = []
    func write(_ bytes: [UInt8]) throws { if echo { queue += bytes }; queue += replies[bytes] ?? [] }
    func read(max: Int, timeout: TimeInterval) throws -> [UInt8] {
        let n = Swift.min(max, queue.count); defer { queue.removeFirst(n) }; return Array(queue.prefix(n))
    }
    func flushInput() { queue.removeAll() }
}

var failures = 0
func check(_ cond: @autoclosure () throws -> Bool, _ what: String) {
    do { if try cond() { print("  ok   \(what)") } else { failures += 1; print("  FAIL \(what)") } }
    catch { failures += 1; print("  FAIL \(what): \(error)") }
}

func selftest() {
    print("Frames")
    check(Frame(ds2: 0x12, data: [0x00]).bytes == [0x12, 0x04, 0x00, 0x16], "DS2 ident request to 0x12 is 12 04 00 16 (XOR checksum)")
    check(Frame(kwp: 0x29, data: [0x10, 0x87]).bytes == [0xB8, 0x29, 0xF1, 0x02, 0x10, 0x87, 0x6B], "KWP2000* session request B8 29 F1 02 10 87 + sum 6B")
    check(try FrameParser.decode([0xB8, 0xF1, 0x29, 0x02, 0x50, 0x87, 0xAB], .kwp2000star) == Frame(kwp: 0xF1, source: 0x29, data: [0x50, 0x87]),
          "KWP2000* decodes B8 F1 29 02 50 87 AB (checksum AB)")
    check((try? FrameParser.decode([0xB8, 0xF1, 0x29, 0x02, 0x50, 0x87, 0xAC], .kwp2000star)) == nil, "KWP2000* rejects a bad checksum")
    check((try? FrameParser.decode([0x12, 0x05, 0xA0, 0x01, 0x00], .ds2)) == nil, "DS2 rejects a bad checksum")
    var p = FrameParser(.ds2)
    let split = Frame(ds2: 0x12, data: [0xA0, 0x31, 0x32]).bytes
    check(try p.feed(Array(split.prefix(3))).isEmpty && p.feed(Array(split.dropFirst(3))).count == 1, "DS2 parser reassembles a frame split across reads")

    print("Session")
    let link = FakeLink()
    let req = Frame(ds2: 0x12, data: [0x00])
    link.replies[req.bytes] = Frame(ds2: 0x12, data: [0xA0] + Array("1234567".utf8)).bytes
    let s = KLineSession(link: link, proto: .ds2)
    check(try s.exchange(req).data.first == 0xA0, "DS2 exchange skips the cable echo and returns the module's answer")
    link.echo = false
    check((try? s.exchange(req, retries: 0)) == nil, "missing echo is reported (cable in the wrong mode)")
    link.echo = true

    print("Definitions")
    let json = #"""
    { "id": "demo", "name": "Demo", "protocol": "ds2", "address": 18,
      "ident": { "request": "00", "fields": [ { "id": "part", "label": "BMW part number", "offset": 1, "length": 7, "type": "ascii" } ] },
      "values": [ { "request": "0B 03", "fields": [
         { "id": "rpm", "label": "Engine speed", "offset": 1, "length": 2, "type": "u16be", "unit": "rpm" },
         { "id": "clt", "label": "Coolant temperature", "offset": 3, "length": 1, "type": "u8", "scale": 0.75, "add": -48, "unit": "°C" },
         { "id": "clutch", "label": "Clutch pressed", "offset": 4, "length": 1, "type": "bit", "bit": 2, "map": { "0": "No", "1": "Yes" } } ] } ] }
    """#
    do {
        let def = try JSONDecoder().decode(ModuleDefinition.self, from: Data(json.utf8))
        let vreq = Frame(ds2: 0x12, data: [0x0B, 0x03])
        link.replies[vreq.bytes] = Frame(ds2: 0x12, data: [0xA0, 0x03, 0x20, 0xB4, 0x04]).bytes
        let client = ModuleClient(definition: def, session: s)
        let ident = try client.run(def.ident!)
        check(ident.first?.text == "1234567", "ident ascii field decodes")
        let v = try client.run(def.values![0])
        check(v[0].text == "800", "u16be 0x0320 = 800 rpm")
        check(v[1].text == "87", "u8 0xB4 × 0.75 − 48 = 87 °C")
        check(v[2].text == "Yes", "bit 2 of 0x04 maps to Yes")
        link.replies[vreq.bytes] = Frame(ds2: 0x12, data: [0xA2]).bytes
        check((try? client.run(def.values![0])) == nil, "DS2 status A2 (rejected) is reported as an error")
    } catch { failures += 1; print("  FAIL definitions: \(error)") }

    print("WiFi adapter (local fake)")
    do {
        let fake = try FakeAdapter()
        fake.start()
        let tcp = try TcpLink(fake.address)
        let ts = KLineSession(link: tcp, proto: .ds2)
        Adapter.tune(ts)
        check(try ts.exchange(req).data.first == 0xA0, "DS2 ident over TCP: echo skipped, answer returned")
        let ks = KLineSession(link: tcp, proto: .kwp2000star)
        Adapter.tune(ks)
        check(try ks.exchange(Frame(kwp: 0x29, data: [0x10, 0x87])).data == [0x50, 0x87], "KWP2000* session start to the DSC over TCP")
        check((try? ts.exchange(Frame(ds2: 0x40, data: [0x00]), retries: 0)) == nil, "silent module times out instead of hanging")
        check(try ts.exchange(req).data.first == 0xA0, "link still usable after a timeout")
        check((try? TcpLink(host: "127.0.0.1", port: 1, timeout: 1)) == nil, "absent adapter fails fast")
        check(try tcp.status().batteryVolts == 12.6, "adapter status over HTTP")

        print("OBD-II over CAN (fake car: 500k 11-bit, engine 7E8 + transmission 7E9)")
        let obd = try OBD.connect(fake.address)
        check(obd.transport.name.contains("11-bit, 500"), "auto-detects \(obd.transport.name)")
        let sup = try obd.supportedPIDs()
        check(sup["7E8"]?.isSuperset(of: [0x0C, 0x05, 0x42, 0x46]) == true && sup["7E9"] == [0x01], "supported PIDs per ECU, following the 00/20/40 chain")
        check(try obd.read(0x0C).first?.value == 1726, "engine speed 1A F8 = 1726 rpm")
        check(try obd.read(0x42).first?.text == "Control module voltage: 14.32 V", "control module voltage 37 F0 = 14.32 V")
        check(try obd.vin() == VirtualCar.vin, "VIN via multi-frame ISO-TP with flow control")
        check(try obd.dtcs()["7E8"] == ["P0133", "P0420"], "stored codes P0133, P0420")
        check(try obd.dtcs(.pending)["7E8"] == [], "no pending codes")
        let rd = try obd.readiness().first
        check(rd?.milOn == true && rd?.dtcCount == 2, "check-engine light on, 2 codes")
        check(rd?.monitors.filter { !$0.complete }.map(\.name) == ["Catalyst", "Oxygen sensor"], "catalyst and O2 monitors incomplete")
        check(try obd.readAll().count == 11, "readAll decodes every supported known PID")

        print("OBD-II over K-line (fake car: ISO 14230 fast init)")
        var noCAN = fake.address
        noCAN.canPort = 1
        let kobd = try OBD.connect(noCAN)
        check(kobd.transport.name.contains("14230"), "falls back to \(kobd.transport.name)")
        check(try kobd.read(0x05).first?.value == 83, "coolant 7B = 83 °C over K-line")
        check(try kobd.dtcs()["10"] == ["P0133", "P0420"], "codes from a zero-padded K-line answer")
        check(try kobd.vin() == VirtualCar.vin, "VIN reassembled from five K-line frames")
    } catch { failures += 1; print("  FAIL tcp/obd: \(error)") }

    print("K-line OBD framing")
    let two: [UInt8] = [0x48, 0x6B, 0x10, 0x41, 0x0D, 0x32, 0x43, 0x48, 0x6B, 0x18, 0x41, 0x0D, 0x32, 0x4B]
    let p9141 = KLineOBDTransport.parse9141(two)
    check(p9141.count == 2 && p9141[0].ecu == "10" && p9141[1].ecu == "18" && p9141[1].data == [0x41, 0x0D, 0x32], "ISO 9141-2: splits two ECUs' answers with no length byte")
    check(KLineOBDTransport.parseKWP([0x83, 0xF1, 0x10, 0x41, 0x0D, 0x32, 0x04]).first?.data == [0x41, 0x0D, 0x32], "ISO 14230: length from the format byte")
    check(OBD.dtcString(0xC1, 0x23) == "U0123" && OBD.dtcString(0x41, 0x00) == "C0100", "DTC letters from the top two bits")

    print("Trace import")
    let trc = """
    executeJob('dsc_mk60.prg'): 'R50_ASC_DSC_BLEEDMASTER_FA' ''
     (Send sim): B8 29 F1 02 10 87
     (Rec sim interface): B8 F1 29 02 50 87 AB
    """
    let ex = TraceImport.exchanges(fromTrace: trc)
    check(ex.count == 1 && ex[0].job == "dsc_mk60 R50_ASC_DSC_BLEEDMASTER_FA" && ex[0].response?.last == 0xAB, "pairs request and response with the job name")
    print(failures == 0 ? "All passed" : "\(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

func traceSummary(_ path: String) {
    guard let text = try? String(contentsOfFile: path, encoding: .isoLatin1) else { print("can't read \(path)"); exit(1) }
    let ex = TraceImport.exchanges(fromTrace: text)
    var seen = Set<String>()
    print("\(ex.count) exchanges")
    for e in ex {
        let key = "\(e.job ?? "?")|\(e.request.hex)"
        guard seen.insert(key).inserted else { continue }
        print("\(e.job ?? "?")\n   > \(e.request.hex)\n   < \(e.response?.hex ?? "(no answer)")")
    }
}

func ident(port: String, address: UInt8) {
    do {
        let link = try Adapter.open(port)
        let s = KLineSession(link: link, proto: .ds2)
        Adapter.tune(s)
        s.onTraffic = { dir, b in print("\(dir == "send" ? ">" : "<") \(b.hex)") }
        let reply = try s.exchange(Frame(ds2: address, data: [0x00]))
        print("status \(String(format: "%02X", reply.data.first ?? 0)), \(reply.data.count) bytes")
    } catch { print("error: \(error)"); exit(1) }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "selftest": selftest()
case "trace" where args.count == 2: traceSummary(args.last!)
case "fake-adapter":
    do {
        let f = try FakeAdapter(klinePort: 2323, canPort: 2333, httpPort: 2380)
        f.start()
        print("fake adapter + pretend car running. Use adapter address \(f.spec)")
        while true { sleep(3600) }
    } catch { print("error: \(error)"); exit(1) }
case "obd" where args.count >= 2:
    obdCommand(AdapterAddress(spec: args[args.startIndex + 1]), Array(args.dropFirst(2)))
case "mcp":
    var a = Array(args.dropFirst())
    func opt(_ name: String) -> String? {
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        defer { a.removeSubrange(i...(i + 1)) }
        return a[i + 1]
    }
    MCPServer(adapter: opt("--adapter") ?? TcpLink.defaultHost, definitionsDir: opt("--defs")).run()
case "ident" where args.count == 3: ident(port: args[args.startIndex + 1], address: UInt8(args.last!.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0x12)
default:
    print("""
    usage: kline selftest
           kline trace <ifh.trc>          list request/response pairs from a recorded session
           kline ident <adapter> <address>   DS2 identify one module, e.g. 192.168.4.1 12 or /dev/cu.usbserial-XXXX 12
           kline obd <adapter> [info|live|codes|clear --yes]   generic OBD-II, any car (CAN or K-line)
           kline fake-adapter               pretend WiFi adapter + car on 127.0.0.1 (ports 2323/2333/2380)
           kline mcp [--adapter <adapter>] [--defs <folder>]   read-only MCP server on stdio
    """)
}

func obdCommand(_ address: AdapterAddress, _ rest: [String]) {
    do {
        let obd = try OBD.connect(address) { print("  \($0)") }
        print("Protocol: \(obd.transport.name)")
        switch rest.first ?? "info" {
        case "info":
            print("VIN: \((try? obd.vin()) ?? nil ?? "not reported")")
            for r in try obd.readiness() {
                print("ECU \(r.ecu): check-engine light \(r.milOn ? "ON" : "off"), \(r.dtcCount) stored code(s), \(r.diesel ? "diesel" : "petrol") monitors:")
                for m in r.monitors { print("   \(m.complete ? "ready    " : "NOT READY") \(m.name)") }
            }
            fallthrough
        case "codes":
            for kind in [OBD.DTCKind.stored, .pending, .permanent] {
                for (ecu, codes) in (try? obd.dtcs(kind)) ?? [:] where !codes.isEmpty {
                    print("\(kind) codes from \(ecu): \(codes.joined(separator: ", "))")
                }
            }
        case "live":
            for v in try obd.readAll() { print("\(v.ecu)  \(v.text)") }
        case "clear":
            guard rest.contains("--yes") else {
                print("This clears stored codes, turns off the check-engine light and resets the readiness monitors")
                print("(the car will fail an emissions test until they've run again). Re-run with --yes to do it.")
                exit(1)
            }
            print(try obd.clearDTCs() ? "Codes cleared." : "No ECU confirmed the clear (engine running? some cars need it off).")
        default: print("unknown obd command \(rest.first!)")
        }
    } catch { print("error: \(error)"); exit(1) }
}
