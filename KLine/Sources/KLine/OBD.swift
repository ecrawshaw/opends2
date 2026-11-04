import Foundation

// Generic OBD-II (SAE J1979 / ISO 15031-5): the emissions diagnostics every car since 1996 (US),
// 2001 (EU petrol) or 2004 (EU diesel) must answer, over whichever physical layer the car uses.

public struct OBDResponse: Sendable {
    /// Who answered: "7E8", "18DAF110", or the K-line source address "10"
    public let ecu: String
    /// Service response bytes, e.g. 41 0C 1A F8
    public let data: [UInt8]
}

public enum OBDError: Error, CustomStringConvertible {
    case noProtocol, noAnswer([UInt8]), initFailed(String)
    public var description: String {
        switch self {
        case .noProtocol: "No OBD-II answer on CAN or K-line. Is the ignition on? (Pre-2008 Ford/GM using J1850 isn't supported.)"
        case let .noAnswer(r): "no answer to \(r.hex)"
        case let .initFailed(m): "K-line init failed: \(m)"
        }
    }
}

public protocol OBDTransport: AnyObject {
    var name: String { get }
    var isCAN: Bool { get }
    func request(_ data: [UInt8]) throws -> [OBDResponse]
}

// MARK: - CAN (ISO 15765-4)

public final class CANTransport: OBDTransport {
    public let can: SLCANLink
    public let bitrate: Int
    public let extended: Bool
    private let isotp: ISOTP
    public var name: String { "ISO 15765-4 CAN (\(extended ? "29" : "11")-bit, \(bitrate / 1000) kbit/s)" }
    public var isCAN: Bool { true }

    public init(can: SLCANLink, bitrate: Int, extended: Bool) throws {
        self.can = can; self.bitrate = bitrate; self.extended = extended
        if extended {
            // Answers: 18DA F1 xx; flow control goes to 18DA xx F1
            try can.open(bitrate: bitrate, filter: .extended(id: 0x18DA_F100, mask: 0x1FFF_FF00))
            isotp = ISOTP(can: can, extended: true, accepts: { $0 & 0x1FFF_FF00 == 0x18DA_F100 },
                          flowControlID: { 0x18DA_00F1 | ($0 & 0xFF) << 8 })
        } else {
            // Answers: 7E8–7EF; flow control goes to the ECU's request id, 8 lower
            try can.open(bitrate: bitrate, filter: .standard(id: 0x7E8, mask: 0x7F8))
            isotp = ISOTP(can: can, extended: false, accepts: { $0 & 0x7F8 == 0x7E8 }, flowControlID: { $0 - 8 })
        }
    }

    public func request(_ data: [UInt8]) throws -> [OBDResponse] {
        try isotp.request(to: extended ? 0x18DB_33F1 : 0x7DF, data).map {
            OBDResponse(ecu: extended ? String(format: "%08X", $0.ecu) : String(format: "%03X", $0.ecu), data: $0.data)
        }
    }
}

// MARK: - K-line (ISO 14230-4 KWP2000 and ISO 9141-2)

public final class KLineOBDTransport: OBDTransport {
    public enum Kind: Sendable { case kwpFast, kwpSlow, iso9141 }
    public let link: TcpLink
    public private(set) var kind: Kind
    private var lastActivity = Date.distantPast
    public var onTraffic: ((String, [UInt8]) -> Void)?
    public var isCAN: Bool { false }
    public var name: String {
        switch kind {
        case .kwpFast: "ISO 14230-4 KWP2000 (fast init)"
        case .kwpSlow: "ISO 14230-4 KWP2000 (5-baud init)"
        case .iso9141: "ISO 9141-2"
        }
    }

    /// Wake the car's K-line. Tries fast init, then 5-baud init (which also tells 9141 from 14230).
    public init(link: TcpLink, only: Kind? = nil) throws {
        self.link = link
        kind = only ?? .kwpFast
        if only == nil || only == .kwpFast, (try? wake(.kwpFast)) != nil { kind = .kwpFast; return }
        if only == .kwpFast { throw OBDError.initFailed("no answer to fast init") }
        kind = try wake(.kwpSlow)
    }

    @discardableResult
    private func wake(_ k: Kind) throws -> Kind {
        switch k {
        case .kwpFast:
            try link.fastInit()
            let start: [UInt8] = [0xC1, 0x33, 0xF1, 0x81]
            let replies = try Self.parseKWP(transact(start + [Self.sum(start)]))
            guard replies.contains(where: { $0.data.first == 0xC1 }) else { throw OBDError.initFailed("no StartCommunication answer") }
            lastActivity = Date()
            return .kwpFast
        case .kwpSlow, .iso9141:
            let kb = try link.slowInit(address: 0x33)
            guard kb.ok else { throw OBDError.initFailed(kb.error ?? "bad key bytes") }
            usleep(60_000) // P3min before the first request
            lastActivity = Date()
            return kb.kb2?.uppercased() == "8F" ? .kwpSlow : .iso9141
        }
    }

    public func request(_ data: [UInt8]) throws -> [OBDResponse] {
        // The ECU drops the session after 5 s of silence (P3max)
        if Date().timeIntervalSince(lastActivity) > 4 { try wake(kind) }
        let frame: [UInt8]
        switch kind {
        case .iso9141: frame = [0x68, 0x6A, 0xF1] + data
        case .kwpFast, .kwpSlow: frame = [0xC0 | UInt8(data.count), 0x33, 0xF1] + data
        }
        let raw = try transact(frame + [Self.sum(frame)])
        lastActivity = Date()
        return kind == .iso9141 ? Self.parse9141(raw) : Self.parseKWP(raw)
    }

    /// Send, swallow our echo, then collect everything until the line goes quiet (several ECUs may answer)
    private func transact(_ bytes: [UInt8]) throws -> [UInt8] {
        link.flushInput()
        try link.write(bytes)
        onTraffic?("send", bytes)
        var echo: [UInt8] = []
        while echo.count < bytes.count {
            let c = try link.read(max: bytes.count - echo.count, timeout: 1.0)
            if c.isEmpty { break }
            echo += c
        }
        guard echo == bytes else { throw SessionError.echoMismatch(sent: bytes, got: echo) }
        var got: [UInt8] = []
        var timeout: TimeInterval = 1.0
        while true {
            let c = try link.read(max: 512, timeout: timeout)
            if c.isEmpty { break }
            got += c
            timeout = 0.2
        }
        if !got.isEmpty { onTraffic?("recv", got) }
        return got
    }

    static func sum(_ b: [UInt8]) -> UInt8 { b.reduce(0) { $0 &+ $1 } }

    /// ISO 14230 frames: format byte (length in the low 6 bits, or a separate length byte when 0),
    /// target, source, data, 8-bit sum
    public static func parseKWP(_ b: [UInt8]) -> [OBDResponse] {
        var out: [OBDResponse] = []
        var i = 0
        while i < b.count {
            let fmt = b[i]
            let hasAddr = fmt & 0x80 != 0
            var idx = i + 1 + (hasAddr ? 2 : 0)
            var len = Int(fmt & 0x3F)
            if len == 0 { guard idx < b.count else { break }; len = Int(b[idx]); idx += 1 }
            let end = idx + len
            guard end < b.count, sum(Array(b[i..<end])) == b[end] else { i += 1; continue } // resync
            out.append(OBDResponse(ecu: hasAddr ? String(format: "%02X", b[i + 2]) : "?", data: Array(b[idx..<end])))
            i = end + 1
        }
        return out
    }

    /// ISO 9141-2 frames have no length byte: 48 6B <ecu> data… sum, at most 7 data bytes.
    /// Split where the checksum fits and the next frame header begins.
    public static func parse9141(_ b: [UInt8]) -> [OBDResponse] {
        var out: [OBDResponse] = []
        var i = 0
        frames: while i + 4 < b.count {
            guard b[i] == 0x48, b[i + 1] == 0x6B else { i += 1; continue }
            for n in 5...11 where i + n <= b.count {
                let f = Array(b[i..<(i + n)])
                let nextIsHeader = i + n == b.count || (i + n + 1 < b.count && b[i + n] == 0x48 && b[i + n + 1] == 0x6B)
                if sum(Array(f.dropLast())) == f.last!, nextIsHeader {
                    out.append(OBDResponse(ecu: String(format: "%02X", f[2]), data: Array(f[3..<(n - 1)])))
                    i += n
                    continue frames
                }
            }
            i += 1
        }
        return out
    }
}

// MARK: - OBD-II services

public struct PIDValue: Sendable {
    public let ecu: String
    public let pid: UInt8
    public let name: String
    public let value: Double
    public let unit: String
    public var text: String {
        let v = value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(format: "%.2f", value)
        return "\(name): \(v)\(unit.isEmpty ? "" : " \(unit)")"
    }
}

public struct Readiness: Sendable {
    public let ecu: String
    public let milOn: Bool
    public let dtcCount: Int
    public let diesel: Bool
    /// monitor name → complete?
    public let monitors: [(name: String, complete: Bool)]
}

public final class OBD {
    public let transport: OBDTransport
    public init(transport: OBDTransport) { self.transport = transport }

    /// Find the car's protocol: CAN first (listening before talking, so a wrong bitrate never
    /// disturbs a busy bus), then the K-line.
    public static func connect(_ address: AdapterAddress, log: (String) -> Void = { _ in }) throws -> OBD {
        if let can = try? SLCANLink(address) {
            var rates = [500_000, 250_000]
            for r in rates {
                try? can.open(bitrate: r, listenOnly: true)
                if (try? can.receive(timeout: 0.4)) != nil { log("CAN traffic at \(r / 1000) kbit/s"); rates = [r]; break }
            }
            can.close()
            for r in rates {
                for ext in [false, true] {
                    log("trying CAN \(ext ? "29" : "11")-bit \(r / 1000) kbit/s")
                    guard let t = try? CANTransport(can: can, bitrate: r, extended: ext) else { continue }
                    if let resp = try? t.request([0x01, 0x00]), resp.contains(where: { $0.data.first == 0x41 }) { return OBD(transport: t) }
                }
            }
            can.close()
        }
        log("trying K-line")
        let link = try TcpLink(address)
        guard let t = try? KLineOBDTransport(link: link) else { throw OBDError.noProtocol }
        guard let resp = try? t.request([0x01, 0x00]), resp.contains(where: { $0.data.first == 0x41 }) else { throw OBDError.noProtocol }
        return OBD(transport: t)
    }

    /// Positive answers only (service + 0x40)
    func ask(_ data: [UInt8]) throws -> [OBDResponse] {
        try transport.request(data).filter { $0.data.first == data[0] &+ 0x40 }
    }

    /// Mode 01 PIDs each ECU supports (follows the 00/20/40… chain)
    public func supportedPIDs() throws -> [String: Set<UInt8>] {
        var out: [String: Set<UInt8>] = [:]
        var base: UInt8 = 0
        while true {
            let r = try ask([0x01, base])
            if r.isEmpty { break }
            var more = false
            for resp in r where resp.data.count >= 6 && resp.data[1] == base {
                for i in 0..<32 where resp.data[2 + i / 8] & (0x80 >> UInt8(i % 8)) != 0 {
                    out[resp.ecu, default: []].insert(base &+ UInt8(i + 1))
                }
                if out[resp.ecu]?.contains(base &+ 0x20) == true { more = true }
            }
            if !more || base >= 0xC0 { break }
            base += 0x20
        }
        return out
    }

    public func read(_ pid: UInt8) throws -> [PIDValue] {
        guard let def = OBDPIDs.table[pid] else { return [] }
        return try ask([0x01, pid]).compactMap { r in
            guard r.data.count >= 2 + def.bytes, r.data[1] == pid else { return nil }
            return PIDValue(ecu: r.ecu, pid: pid, name: def.name, value: def.decode(Array(r.data[2..<(2 + def.bytes)])), unit: def.unit)
        }
    }

    /// Every supported PID we know how to decode, from every ECU
    public func readAll() throws -> [PIDValue] {
        let supported = try supportedPIDs()
        let pids = Set(supported.values.flatMap { $0 }).filter { OBDPIDs.table[$0] != nil }.sorted()
        var out: [PIDValue] = []
        for p in pids { out += (try? read(p)) ?? [] }
        return out
    }

    public func readiness() throws -> [Readiness] {
        try ask([0x01, 0x01]).compactMap { r in
            guard r.data.count >= 6 else { return nil }
            let a = r.data[2], b = r.data[3], c = r.data[4], d = r.data[5]
            let diesel = b & 0x08 != 0
            var m: [(String, Bool)] = []
            for (bit, name) in [(0, "Misfire"), (1, "Fuel system"), (2, "Components")] where b & (1 << bit) != 0 {
                m.append((name, b & (0x10 << bit) == 0))
            }
            let names = diesel
                ? [0: "NMHC catalyst", 1: "NOx/SCR", 3: "Boost pressure", 5: "Exhaust gas sensor", 6: "Particulate filter", 7: "EGR/VVT"]
                : [0: "Catalyst", 1: "Heated catalyst", 2: "Evaporative system", 3: "Secondary air", 5: "Oxygen sensor", 6: "Oxygen sensor heater", 7: "EGR/VVT"]
            for (bit, name) in names.sorted(by: { $0.key < $1.key }) where c & (1 << bit) != 0 {
                m.append((name, d & (1 << bit) == 0))
            }
            return Readiness(ecu: r.ecu, milOn: a & 0x80 != 0, dtcCount: Int(a & 0x7F), diesel: diesel, monitors: m)
        }
    }

    public enum DTCKind: UInt8, Sendable { case stored = 0x03, pending = 0x07, permanent = 0x0A }

    public func dtcs(_ kind: DTCKind = .stored) throws -> [String: [String]] {
        var out: [String: [String]] = [:]
        for r in try ask([kind.rawValue]) {
            // CAN answers carry a count byte; K-line answers are 3 codes per frame, zero-padded
            let body = transport.isCAN ? Array(r.data.dropFirst(2)) : Array(r.data.dropFirst())
            var codes = out[r.ecu] ?? []
            var i = 0
            while i + 1 < body.count {
                if body[i] != 0 || body[i + 1] != 0 { codes.append(Self.dtcString(body[i], body[i + 1])) }
                i += 2
            }
            out[r.ecu] = codes
        }
        return out
    }

    /// Clears stored codes and turns the check-engine light off. Also resets readiness monitors,
    /// so the car will fail an emissions test until they've run again.
    public func clearDTCs() throws -> Bool {
        try !ask([0x04]).isEmpty
    }

    public func vin() throws -> String? {
        let r = try ask([0x09, 0x02])
        guard !r.isEmpty else { return nil }
        // CAN: one message 49 02 01 + 17 chars. K-line: five frames 49 02 n + 4 bytes.
        let parts = r.filter { $0.data.count > 3 }.sorted { $0.data[2] < $1.data[2] }
        let bytes = parts.flatMap { $0.data.dropFirst(3) }.filter { $0 >= 0x20 && $0 < 0x7F }
        let s = String(decoding: bytes, as: UTF8.self)
        return s.isEmpty ? nil : String(s.suffix(17))
    }

    public static func dtcString(_ a: UInt8, _ b: UInt8) -> String {
        let letter = ["P", "C", "B", "U"][Int(a >> 6)]
        return letter + String((a >> 4) & 0x03) + String(format: "%01X%02X", a & 0x0F, b)
    }
}

// MARK: - PID definitions (SAE J1979 formulas)

public struct PIDDef: Sendable {
    public let name: String
    public let unit: String
    public let bytes: Int
    public let decode: @Sendable ([UInt8]) -> Double
}

public enum OBDPIDs {
    @Sendable static func ab(_ b: [UInt8]) -> Double { Double(Int(b[0]) << 8 | Int(b[1])) }
    @Sendable static func pct(_ b: [UInt8]) -> Double { Double(b[0]) * 100 / 255 }
    @Sendable static func trim(_ b: [UInt8]) -> Double { Double(b[0]) / 1.28 - 100 }
    @Sendable static func temp(_ b: [UInt8]) -> Double { Double(b[0]) - 40 }

    public static let table: [UInt8: PIDDef] = [
        0x04: PIDDef(name: "Engine load", unit: "%", bytes: 1, decode: pct),
        0x05: PIDDef(name: "Coolant temperature", unit: "°C", bytes: 1, decode: temp),
        0x06: PIDDef(name: "Short-term fuel trim bank 1", unit: "%", bytes: 1, decode: trim),
        0x07: PIDDef(name: "Long-term fuel trim bank 1", unit: "%", bytes: 1, decode: trim),
        0x08: PIDDef(name: "Short-term fuel trim bank 2", unit: "%", bytes: 1, decode: trim),
        0x09: PIDDef(name: "Long-term fuel trim bank 2", unit: "%", bytes: 1, decode: trim),
        0x0A: PIDDef(name: "Fuel pressure", unit: "kPa", bytes: 1, decode: { Double($0[0]) * 3 }),
        0x0B: PIDDef(name: "Intake manifold pressure", unit: "kPa", bytes: 1, decode: { Double($0[0]) }),
        0x0C: PIDDef(name: "Engine speed", unit: "rpm", bytes: 2, decode: { ab($0) / 4 }),
        0x0D: PIDDef(name: "Vehicle speed", unit: "km/h", bytes: 1, decode: { Double($0[0]) }),
        0x0E: PIDDef(name: "Ignition timing advance", unit: "°", bytes: 1, decode: { Double($0[0]) / 2 - 64 }),
        0x0F: PIDDef(name: "Intake air temperature", unit: "°C", bytes: 1, decode: temp),
        0x10: PIDDef(name: "Mass air flow", unit: "g/s", bytes: 2, decode: { ab($0) / 100 }),
        0x11: PIDDef(name: "Throttle position", unit: "%", bytes: 1, decode: pct),
        0x14: PIDDef(name: "O2 sensor bank 1 sensor 1", unit: "V", bytes: 2, decode: { Double($0[0]) / 200 }),
        0x15: PIDDef(name: "O2 sensor bank 1 sensor 2", unit: "V", bytes: 2, decode: { Double($0[0]) / 200 }),
        0x1F: PIDDef(name: "Time since engine start", unit: "s", bytes: 2, decode: ab),
        0x21: PIDDef(name: "Distance driven with check-engine light on", unit: "km", bytes: 2, decode: ab),
        0x22: PIDDef(name: "Fuel rail pressure (relative)", unit: "kPa", bytes: 2, decode: { ab($0) * 0.079 }),
        0x23: PIDDef(name: "Fuel rail pressure", unit: "kPa", bytes: 2, decode: { ab($0) * 10 }),
        0x2C: PIDDef(name: "Commanded EGR", unit: "%", bytes: 1, decode: pct),
        0x2D: PIDDef(name: "EGR error", unit: "%", bytes: 1, decode: trim),
        0x2E: PIDDef(name: "Commanded evaporative purge", unit: "%", bytes: 1, decode: pct),
        0x2F: PIDDef(name: "Fuel level", unit: "%", bytes: 1, decode: pct),
        0x30: PIDDef(name: "Warm-ups since codes cleared", unit: "", bytes: 1, decode: { Double($0[0]) }),
        0x31: PIDDef(name: "Distance since codes cleared", unit: "km", bytes: 2, decode: ab),
        0x33: PIDDef(name: "Barometric pressure", unit: "kPa", bytes: 1, decode: { Double($0[0]) }),
        0x3C: PIDDef(name: "Catalyst temperature bank 1 sensor 1", unit: "°C", bytes: 2, decode: { ab($0) / 10 - 40 }),
        0x42: PIDDef(name: "Control module voltage", unit: "V", bytes: 2, decode: { ab($0) / 1000 }),
        0x43: PIDDef(name: "Absolute load", unit: "%", bytes: 2, decode: { ab($0) * 100 / 255 }),
        0x44: PIDDef(name: "Commanded air-fuel ratio (lambda)", unit: "", bytes: 2, decode: { ab($0) * 2 / 65536 }),
        0x45: PIDDef(name: "Relative throttle position", unit: "%", bytes: 1, decode: pct),
        0x46: PIDDef(name: "Ambient air temperature", unit: "°C", bytes: 1, decode: temp),
        0x47: PIDDef(name: "Absolute throttle position B", unit: "%", bytes: 1, decode: pct),
        0x49: PIDDef(name: "Accelerator pedal position D", unit: "%", bytes: 1, decode: pct),
        0x4C: PIDDef(name: "Commanded throttle actuator", unit: "%", bytes: 1, decode: pct),
        0x4D: PIDDef(name: "Time run with check-engine light on", unit: "min", bytes: 2, decode: ab),
        0x4E: PIDDef(name: "Time since codes cleared", unit: "min", bytes: 2, decode: ab),
        0x5C: PIDDef(name: "Engine oil temperature", unit: "°C", bytes: 1, decode: temp),
        0x5E: PIDDef(name: "Engine fuel rate", unit: "L/h", bytes: 2, decode: { ab($0) / 20 }),
        0xA6: PIDDef(name: "Odometer", unit: "km", bytes: 4, decode: { Double(UInt32($0[0]) << 24 | UInt32($0[1]) << 16 | UInt32($0[2]) << 8 | UInt32($0[3])) / 10 }),
    ]
}
