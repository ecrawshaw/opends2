import Foundation

public struct CANFrame: Equatable, Sendable, CustomStringConvertible {
    public var id: UInt32
    public var extended: Bool
    public var data: [UInt8]
    public init(id: UInt32, extended: Bool = false, data: [UInt8]) { self.id = id; self.extended = extended; self.data = data }
    public var description: String { (extended ? String(format: "%08X", id) : String(format: "%03X", id)) + " " + data.hex }
}

public enum CANError: Error, CustomStringConvertible {
    case rejected(String), timeout(String), tooLong
    public var description: String {
        switch self {
        case let .rejected(c): "adapter rejected CAN command \(c)"
        case let .timeout(c): "adapter didn't answer CAN command \(c)"
        case .tooLong: "request too long for a single CAN frame"
        }
    }
}

/// CAN through the adapter's SLCAN (Lawicel) port. Any SLCAN device reachable as a byte stream works.
public final class SLCANLink {
    public let link: ByteLink
    public static let bitrates: [Int: Character] = [10_000: "0", 20_000: "1", 50_000: "2", 100_000: "3", 125_000: "4",
                                                     250_000: "5", 500_000: "6", 800_000: "7", 1_000_000: "8"]
    private var pending = ""
    private var frames: [CANFrame] = []
    private var acks: [String] = []
    public var onTraffic: ((String, CANFrame) -> Void)?

    public init(link: ByteLink) { self.link = link }
    public convenience init(_ address: AdapterAddress) throws {
        self.init(link: try TcpLink(host: address.host, port: address.canPort))
    }

    /// Acceptance filter: frames whose id matches `id` on the bits set in `mask` (SJA1000 single-filter layout)
    public struct Filter: Sendable {
        public var code: UInt32, mask: UInt32
        public static let all = Filter(code: 0, mask: 0xFFFF_FFFF)
        public static func standard(id: UInt32, mask: UInt32) -> Filter {
            Filter(code: id << 21, mask: ~(mask << 21))
        }
        public static func extended(id: UInt32, mask: UInt32) -> Filter {
            Filter(code: id << 3, mask: ~(mask << 3))
        }
    }

    public func open(bitrate: Int, listenOnly: Bool = false, filter: Filter = .all) throws {
        guard let s = Self.bitrates[bitrate] else { throw CANError.rejected("bitrate \(bitrate)") }
        _ = try? command("C")
        try command("S\(s)")
        try command(String(format: "M%08X", filter.code))
        try command(String(format: "m%08X", filter.mask))
        try command(listenOnly ? "L" : "O")
        frames.removeAll()
    }

    public func close() { _ = try? command("C") }

    public func send(_ f: CANFrame) throws {
        var c = f.extended ? String(format: "T%08X", f.id) : String(format: "t%03X", f.id)
        c += String(f.data.count) + f.data.map { String(format: "%02X", $0) }.joined()
        onTraffic?("send", f)
        try command(c)
    }

    /// Next received frame, or nil after `timeout`
    public func receive(timeout: TimeInterval) throws -> CANFrame? {
        let deadline = Date().addingTimeInterval(timeout)
        while frames.isEmpty {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { return nil }
            try pump(left)
        }
        let f = frames.removeFirst()
        onTraffic?("recv", f)
        return f
    }

    public func discardReceived() { frames.removeAll() }

    /// Adapter status flags (F command): bit 7 bus-off, 5 error-passive, 3 frames lost
    public func status() throws -> UInt8 {
        UInt8(try command("F").dropFirst(), radix: 16) ?? 0
    }

    @discardableResult
    private func command(_ c: String) throws -> String {
        acks.removeAll()
        try link.write(Array((c + "\r").utf8))
        let deadline = Date().addingTimeInterval(1.5)
        while acks.isEmpty {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { throw CANError.timeout(c) }
            try pump(left)
        }
        let ack = acks.removeFirst()
        if ack == "\u{07}" { throw CANError.rejected(c) }
        return ack
    }

    /// Read whatever arrived and split it into frames and command acknowledgements
    private func pump(_ timeout: TimeInterval) throws {
        let bytes = try link.read(max: 2048, timeout: min(timeout, 0.1))
        pending += String(decoding: bytes, as: UTF8.self)
        while let i = pending.firstIndex(where: { $0 == "\r" || $0 == "\u{07}" }) {
            let token = String(pending[..<i])
            let term = pending[i]
            pending.removeSubrange(...i)
            if term == "\u{07}" { acks.append("\u{07}"); continue }
            if let f = Self.parse(token) { frames.append(f) } else { acks.append(token) }
        }
    }

    static func parse(_ s: String) -> CANFrame? {
        guard let first = s.first, first == "t" || first == "T" else { return nil }
        let ext = first == "T"
        let idLen = ext ? 8 : 3
        let chars = Array(s.utf8)
        guard chars.count >= 2 + idLen,
              let id = UInt32(String(s.dropFirst().prefix(idLen)), radix: 16),
              let dlc = Int(String(s.dropFirst(1 + idLen).prefix(1))), dlc <= 8,
              chars.count >= 2 + idLen + dlc * 2 else { return nil }
        var data: [UInt8] = []
        let hex = Array(s.dropFirst(2 + idLen))
        for i in 0..<dlc { guard let b = UInt8(String(hex[i * 2...i * 2 + 1]), radix: 16) else { return nil }; data.append(b) }
        return CANFrame(id: id, extended: ext, data: data)
    }
}

/// ISO 15765-2 (ISO-TP): requests that fit one frame, answers of any length, several ECUs at once.
public struct ISOTP {
    public let can: SLCANLink
    public var extended: Bool
    /// Which received ids are answers to us
    public var accepts: (UInt32) -> Bool
    /// Where to send flow control for an answer from `id`
    public var flowControlID: (UInt32) -> UInt32
    /// How long to keep listening after the last frame (more ECUs may still answer)
    public var quietTime: TimeInterval = 0.25
    public var firstTimeout: TimeInterval = 1.0

    public init(can: SLCANLink, extended: Bool, accepts: @escaping (UInt32) -> Bool, flowControlID: @escaping (UInt32) -> UInt32) {
        self.can = can; self.extended = extended; self.accepts = accepts; self.flowControlID = flowControlID
    }

    /// Send a single-frame request to `to`; return each answering ECU's complete message, in arrival order
    public func request(to: UInt32, _ data: [UInt8]) throws -> [(ecu: UInt32, data: [UInt8])] {
        guard data.count <= 7 else { throw CANError.tooLong }
        can.discardReceived()
        try can.send(CANFrame(id: to, extended: extended, data: pad([UInt8(data.count)] + data)))
        var done: [(UInt32, [UInt8])] = []
        var partial: [UInt32: (total: Int, data: [UInt8], next: UInt8)] = [:]
        var deadline = Date().addingTimeInterval(firstTimeout)
        while Date() < deadline {
            guard let f = try can.receive(timeout: deadline.timeIntervalSinceNow), accepts(f.id), let pci = f.data.first else { continue }
            switch pci >> 4 {
            case 0: // single frame
                let n = Int(pci & 0x0F)
                guard n > 0, f.data.count > n else { continue }
                let msg = Array(f.data[1...n])
                if msg.count == 3, msg[0] == 0x7F, msg[2] == 0x78 { // "response pending": keep waiting
                    deadline = Date().addingTimeInterval(5)
                    continue
                }
                done.append((f.id, msg))
            case 1: // first frame: tell the ECU to send the rest, no gaps, no blocks
                guard f.data.count == 8 else { continue }
                let total = Int(pci & 0x0F) << 8 | Int(f.data[1])
                partial[f.id] = (total, Array(f.data[2...]), 1)
                try can.send(CANFrame(id: flowControlID(f.id), extended: extended, data: pad([0x30, 0x00, 0x00])))
            case 2: // consecutive frame
                guard var p = partial[f.id], pci & 0x0F == p.next else { continue }
                p.data += f.data.dropFirst()
                p.next = (p.next + 1) & 0x0F
                if p.data.count >= p.total {
                    done.append((f.id, Array(p.data.prefix(p.total))))
                    partial[f.id] = nil
                } else { partial[f.id] = p }
            default: continue
            }
            // Mid-message: wait for the rest. Otherwise listen a little longer for other ECUs.
            deadline = Date().addingTimeInterval(partial.isEmpty ? quietTime : 1.0)
        }
        return done
    }

    private func pad(_ d: [UInt8]) -> [UInt8] { d + [UInt8](repeating: 0x00, count: 8 - d.count) }
}
