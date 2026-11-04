import Darwin
import Foundation
import KLine

/// Stand-in for the ESP32 WiFi adapter plus a pretend car, on local TCP ports: K-line (echoes every
/// byte like the real transceiver), CAN over SLCAN, and the HTTP settings side. Lets the TCP links,
/// OBD detection, the CLI and the MCP server be tested without hardware. All data is made up.
final class FakeAdapter {
    /// DS2 / BMW KWP2000* request frame → response frame
    var replies: [[UInt8]: [UInt8]] = FakeAdapter.demoReplies
    let klinePort: UInt16, canPort: UInt16, httpPort: UInt16
    private let kFD: Int32, canFD: Int32, httpFD: Int32
    /// After /kinit the K-line speaks ISO 14230 OBD instead of DS2
    private var klineOBD = false
    private var savedNetworks: [String] = []
    private var sleepMinutes = 20
    private var powerText: String { sleepMinutes == 0 ? "never sleeps" : "sleeps after \(sleepMinutes) min idle below 13.2 V (sooner below 11.8 V)" }

    var address: AdapterAddress {
        var a = AdapterAddress(host: "127.0.0.1")
        a.klinePort = klinePort; a.canPort = canPort; a.httpPort = httpPort
        return a
    }
    var spec: String { "127.0.0.1:\(klinePort):\(canPort):\(httpPort)" }

    static var demoReplies: [[UInt8]: [UInt8]] {
        var r: [[UInt8]: [UInt8]] = [:]
        // DS2 ident to the engine (0x12): status A0 then a 7-digit part number
        r[Frame(ds2: 0x12, data: [0x00]).bytes] = Frame(ds2: 0x12, data: [0xA0] + Array("1234567".utf8)).bytes
        // Demo values: 800 rpm, raw coolant 0xB4, clutch bit 2 set
        r[Frame(ds2: 0x12, data: [0x0B, 0x03]).bytes] = Frame(ds2: 0x12, data: [0xA0, 0x03, 0x20, 0xB4, 0x04]).bytes
        // Demo fault memory: count 2, records of 3 bytes (code hi, code lo, flags)
        r[Frame(ds2: 0x12, data: [0x04, 0x01]).bytes] = Frame(ds2: 0x12, data: [0xA0, 0x02, 0x00, 0x2A, 0x01, 0x00, 0x51, 0x00]).bytes
        // KWP2000* session start to the DSC (0x29)
        r[Frame(kwp: 0x29, data: [0x10, 0x87]).bytes] = Frame(kwp: 0xF1, source: 0x29, data: [0x50, 0x87]).bytes
        return r
    }

    /// Ports 0 = pick free ones
    init(klinePort: UInt16 = 0, canPort: UInt16 = 0, httpPort: UInt16 = 0) throws {
        (kFD, self.klinePort) = try Self.listen(klinePort)
        (canFD, self.canPort) = try Self.listen(canPort)
        (httpFD, self.httpPort) = try Self.listen(httpPort)
    }

    private static func listen(_ port: UInt16) throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0, Darwin.listen(fd, 4) == 0 else { throw TcpError.connect("127.0.0.1:\(port)", errno) }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return (fd, UInt16(bigEndian: bound.sin_port))
    }

    /// Serve all three ports on background threads
    func start() {
        Thread.detachNewThread { [self] in serve(kFD, handleKLine) }
        Thread.detachNewThread { [self] in serve(canFD, handleCAN) }
        Thread.detachNewThread { [self] in serve(httpFD, handleHTTP) }
    }

    private func serve(_ fd: Int32, _ handler: @escaping (Int32) -> Void) {
        while true {
            let c = accept(fd, nil, nil)
            guard c >= 0 else { continue }
            Thread.detachNewThread { handler(c); close(c) }
        }
    }

    private func put(_ c: Int32, _ b: [UInt8]) { _ = send(c, b, b.count, 0) }

    // MARK: K-line

    private func handleKLine(_ c: Int32) {
        var pending: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 512)
        while true {
            let n = recv(c, &buf, buf.count, 0)
            if n <= 0 { return }
            let chunk = Array(buf.prefix(n))
            put(c, chunk) // the line echoes what was sent
            pending += chunk
            while let frame = takeFrame(&pending) {
                usleep(20_000) // module think time
                if klineOBD { answerKWP(c, frame) } else if let reply = replies[frame] { put(c, reply) }
            }
        }
    }

    /// Pull one complete request off the front of the buffer
    private func takeFrame(_ b: inout [UInt8]) -> [UInt8]? {
        guard b.count >= 2 else { return nil }
        let need: Int
        if klineOBD { need = b[0] & 0x80 != 0 ? Int(b[0] & 0x3F) + 4 : Int(b[0] & 0x3F) + 2 }
        else if b[0] == 0xB8 { need = b.count >= 4 ? Int(b[3]) + 5 : Int.max }
        else { need = Int(b[1]) }
        guard need >= 3, b.count >= need else { return nil }
        defer { b.removeFirst(need) }
        return Array(b.prefix(need))
    }

    private func answerKWP(_ c: Int32, _ frame: [UInt8]) {
        let data = Array(frame[3..<(frame.count - 1)])
        let answers: [[UInt8]] = data == [0x81] ? [[0xC1, 0xEF, 0x8F]] : VirtualCar.engine(data, can: false)
        for a in answers {
            var f = [0x80 | UInt8(a.count), 0xF1, 0x10] + a
            f.append(f.reduce(0) { $0 &+ $1 })
            put(c, f)
        }
    }

    // MARK: CAN (SLCAN): the car is on 500 kbit/s, 11-bit ids

    private func handleCAN(_ c: Int32) {
        var bitrate: Character = "6"
        var open = false, listenOnly = false
        var line = ""
        var waitingFC: (id: UInt32, rest: [UInt8])?
        var buf = [UInt8](repeating: 0, count: 512)
        func say(_ s: String) { put(c, Array(s.utf8)) }
        func frame(_ id: UInt32, _ d: [UInt8]) { say(String(format: "t%03X%d", id, d.count) + d.map { String(format: "%02X", $0) }.joined() + "\r") }
        func pad(_ d: [UInt8]) -> [UInt8] { d + [UInt8](repeating: 0x00, count: 8 - d.count) }
        func respond(_ ecu: UInt32, _ msg: [UInt8]) {
            if msg.count <= 7 { frame(ecu, pad([UInt8(msg.count)] + msg)); return }
            frame(ecu, [0x10 | UInt8(msg.count >> 8), UInt8(msg.count & 0xFF)] + msg.prefix(6))
            waitingFC = (ecu, Array(msg.dropFirst(6)))
        }
        while true {
            let n = recv(c, &buf, buf.count, 0)
            if n <= 0 { return }
            for ch in String(decoding: buf.prefix(n), as: UTF8.self) {
                guard ch == "\r" else { line.append(ch); continue }
                defer { line = "" }
                guard let cmd = line.first else { say("\r"); continue }
                switch cmd {
                case "S": bitrate = line.dropFirst().first ?? "6"; say("\r")
                case "O", "L": open = true; listenOnly = cmd == "L"; say("\r")
                case "C": open = false; say("\r")
                case "M", "m", "Z": say("\r")
                case "V": say("V0102\r")
                case "F": say("F00\r")
                case "t", "T":
                    guard open, !listenOnly else { say("\u{07}"); continue }
                    say(cmd == "t" ? "z\r" : "Z\r")
                    guard bitrate == "6", cmd == "t", let f = parseLine(line) else { continue } // wrong rate/format: nobody answers
                    usleep(5_000)
                    if f.id == 0x7DF, let len = f.data.first, len <= 7 {
                        let req = Array(f.data[1...Int(len)])
                        for msg in VirtualCar.engine(req, can: true) { respond(0x7E8, msg) }
                        if let t = VirtualCar.transmission(req) { respond(0x7E9, t) }
                    } else if f.data.first == 0x30, let w = waitingFC, f.id == w.id - 8 {
                        var seq: UInt8 = 1
                        var rest = w.rest
                        while !rest.isEmpty {
                            frame(w.id, pad([0x20 | seq] + rest.prefix(7)))
                            rest = Array(rest.dropFirst(7))
                            seq = (seq + 1) & 0x0F
                        }
                        waitingFC = nil
                    }
                default: say("\u{07}")
                }
            }
        }
    }

    private func parseLine(_ s: String) -> CANFrame? {
        let chars = Array(s)
        guard chars.count >= 5, let id = UInt32(String(chars[1...3]), radix: 16), let dlc = Int(String(chars[4])),
              chars.count >= 5 + dlc * 2 else { return nil }
        let data = (0..<dlc).compactMap { UInt8(String(chars[(5 + $0 * 2)...(6 + $0 * 2)]), radix: 16) }
        return CANFrame(id: id, data: data)
    }

    // MARK: HTTP

    private func handleHTTP(_ c: Int32) {
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = recv(c, &buf, buf.count, 0)
        guard n > 0 else { return }
        let req = String(decoding: buf.prefix(n), as: UTF8.self)
        let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var code = 200
        var body = #"{"ok":true}"#
        if path.hasPrefix("/status") {
            body = #"{"firmware":"fake","baud":9600,"parity":"even","batteryVolts":12.6,"can":"closed 500k","wifi":"fake","uptime":1,"power":"\#(powerText)"}"#
        } else if path.hasPrefix("/config") {
            klineOBD = path.contains("parity=none")
        } else if path.hasPrefix("/wifi") {
            let q = URLComponents(string: path)?.queryItems ?? []
            if let ss = q.first(where: { $0.name == "ssid" })?.value, !ss.isEmpty, !savedNetworks.contains(ss) { savedNetworks.append(ss) }
            if let f = q.first(where: { $0.name == "forget" })?.value { savedNetworks.removeAll { $0 == f } }
            let list = savedNetworks.map { "\"\($0)\"" }.joined(separator: ",")
            body = "{\"saved\":[\(list)],\"joined\":\(savedNetworks.first.map { "\"\($0)\"" } ?? "null")}"
        } else if path.hasPrefix("/power") {
            if let m = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "sleep_min" })?.value.flatMap(Int.init) { sleepMinutes = m }
            body = #"{"power":"\#(powerText)"}"#
        } else if path.hasPrefix("/kinit") {
            if path.contains("mode=fast") { klineOBD = true } else { code = 504; body = #"{"ok":false,"error":"no sync from ECU"}"# }
        }
        let resp = "HTTP/1.1 \(code) X\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        put(c, Array(resp.utf8))
    }
}

/// A made-up petrol car: engine ECU (7E8 / K-line 10) with the check-engine light on and two
/// codes, plus a transmission ECU (7E9, CAN only).
enum VirtualCar {
    static let vin = "TESTVIN0123456789"
    static let supported: Set<UInt8> = [0x01, 0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11, 0x1F, 0x20, 0x21, 0x2F, 0x40, 0x42, 0x46]
    static let values: [UInt8: [UInt8]] = [
        0x01: [0x82, 0x07, 0x65, 0x21], 0x04: [0x40], 0x05: [0x7B], 0x0C: [0x1A, 0xF8], 0x0D: [0x00], 0x0F: [0x3C],
        0x11: [0x26], 0x1F: [0x01, 0x2C], 0x21: [0x00, 0x0C], 0x2F: [0x99], 0x42: [0x37, 0xF0], 0x46: [0x41],
    ]

    static func bitmap(_ base: UInt8, _ set: Set<UInt8>) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        for p in set where p > base && p <= base &+ 0x20 { let i = Int(p - base - 1); b[i / 8] |= 0x80 >> UInt8(i % 8) }
        return b
    }

    static func engine(_ req: [UInt8], can: Bool) -> [[UInt8]] {
        switch (req.first, req.count) {
        case (0x01, 2) where req[1] % 0x20 == 0: return [[0x41, req[1]] + bitmap(req[1], supported)]
        case (0x01, 2): return values[req[1]].map { [[0x41, req[1]] + $0] } ?? []
        case (0x03, 1): return can ? [[0x43, 0x02, 0x01, 0x33, 0x04, 0x20]] : [[0x43, 0x01, 0x33, 0x04, 0x20, 0x00, 0x00]]
        case (0x07, 1): return can ? [[0x47, 0x00]] : [[0x47, 0, 0, 0, 0, 0, 0]]
        case (0x04, 1): return [[0x44]]
        case (0x09, 2) where req[1] == 0x02:
            if can { return [[0x49, 0x02, 0x01] + Array(vin.utf8)] }
            let v = [0, 0, 0] + Array(vin.utf8)
            return (0..<5).map { [0x49, 0x02, UInt8($0 + 1)] + v[($0 * 4)..<($0 * 4 + 4)] }
        default: return [[0x7F, req.first ?? 0, 0x12]]
        }
    }

    static func transmission(_ req: [UInt8]) -> [UInt8]? {
        req == [0x01, 0x00] ? [0x41, 0x00, 0x80, 0x00, 0x00, 0x00] : nil
    }
}
