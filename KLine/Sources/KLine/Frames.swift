import Foundation

/// The two framings used on the E-series diagnostic K-line.
public enum KLineProtocol: String, Codable, Sendable {
    /// DS2 (E30/E36/E38/E39/E46 body and engine modules):
    /// `address, length, data…, checksum` where length counts every byte including itself and the
    /// checksum, and the checksum is the XOR of all preceding bytes. Responses repeat the module's
    /// address and start with a status byte (0xA0 = OK).
    case ds2
    /// BMW "KWP2000*" (e.g. Teves MK60 DSC on the E46): `0xB8, target, source, length, data…, checksum`
    /// with an explicit length byte (data only) and an 8-bit sum checksum. Tester address 0xF1.
    case kwp2000star
}

public struct Frame: Equatable, Sendable, CustomStringConvertible {
    public let proto: KLineProtocol
    /// DS2: the module address. KWP2000*: the target address.
    public let address: UInt8
    /// KWP2000* only: the sender (0xF1 for the tester, the module address in responses)
    public let source: UInt8?
    public let data: [UInt8]

    public init(ds2 address: UInt8, data: [UInt8]) { proto = .ds2; self.address = address; source = nil; self.data = data }
    public init(kwp target: UInt8, source: UInt8 = 0xF1, data: [UInt8]) { proto = .kwp2000star; address = target; self.source = source; self.data = data }

    public var bytes: [UInt8] {
        switch proto {
        case .ds2:
            var b = [address, UInt8(data.count + 3)] + data
            b.append(b.reduce(0, ^))
            return b
        case .kwp2000star:
            var b = [0xB8, address, source ?? 0xF1, UInt8(data.count)] + data
            b.append(b.reduce(0) { $0 &+ $1 })
            return b
        }
    }

    public var description: String { bytes.hex }
}

public enum FrameError: Error, Equatable, CustomStringConvertible {
    case badChecksum(expected: UInt8, got: UInt8)
    case badLength
    case badHeader(UInt8)
    public var description: String {
        switch self {
        case let .badChecksum(e, g): "bad checksum (expected \(String(format: "%02X", e)), got \(String(format: "%02X", g)))"
        case .badLength: "bad length"
        case let .badHeader(h): "unexpected header byte \(String(format: "%02X", h))"
        }
    }
}

/// Splits a byte stream into frames. Feed bytes as they arrive; complete frames come out.
public struct FrameParser {
    public let proto: KLineProtocol
    private var buffer: [UInt8] = []
    public init(_ proto: KLineProtocol) { self.proto = proto }

    /// How many bytes the frame starting at buffer[0] needs, once enough header has arrived
    private func needed() -> Int? {
        switch proto {
        case .ds2: return buffer.count >= 2 ? Int(buffer[1]) : nil
        case .kwp2000star: return buffer.count >= 4 ? Int(buffer[3]) + 5 : nil
        }
    }

    public mutating func feed(_ bytes: [UInt8]) throws -> [Frame] {
        buffer += bytes
        var out: [Frame] = []
        while let n = needed(), buffer.count >= n {
            let raw = Array(buffer.prefix(n))
            buffer.removeFirst(n)
            out.append(try Self.decode(raw, proto))
        }
        return out
    }

    public var pending: Int { buffer.count }

    /// Decode one complete frame
    public static func decode(_ raw: [UInt8], _ proto: KLineProtocol) throws -> Frame {
        switch proto {
        case .ds2:
            guard raw.count >= 3, Int(raw[1]) == raw.count else { throw FrameError.badLength }
            let cs = raw.dropLast().reduce(0, ^)
            guard cs == raw.last! else { throw FrameError.badChecksum(expected: cs, got: raw.last!) }
            return Frame(ds2: raw[0], data: Array(raw[2..<(raw.count - 1)]))
        case .kwp2000star:
            guard raw.count >= 5 else { throw FrameError.badLength }
            guard raw[0] == 0xB8 else { throw FrameError.badHeader(raw[0]) }
            guard Int(raw[3]) + 5 == raw.count else { throw FrameError.badLength }
            let cs = raw.dropLast().reduce(0) { $0 &+ $1 }
            guard cs == raw.last! else { throw FrameError.badChecksum(expected: cs, got: raw.last!) }
            return Frame(kwp: raw[1], source: raw[2], data: Array(raw[4..<(raw.count - 1)]))
        }
    }
}

public extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
    init?(hex: String) {
        let parts = hex.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        var out: [UInt8] = []
        for p in parts {
            guard let v = UInt8(p.hasPrefix("0x") ? String(p.dropFirst(2)) : p, radix: 16) else { return nil }
            out.append(v)
        }
        self = out
    }
}
