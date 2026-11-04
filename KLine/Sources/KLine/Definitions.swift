import Foundation

/// A module described in our own JSON format, written from captured traffic, so the app needs no
/// BMW data files. Example:
///
///     { "id": "dme_s54", "name": "Engine (DME)", "protocol": "ds2", "address": 18,
///       "serial": { "baud": 9600, "parity": "even" },
///       "ident": { "request": "00", "fields": [ { "id": "part", "label": "BMW part number",
///                  "offset": 1, "length": 7, "type": "ascii" } ] },
///       "values": [ { "request": "0B 03", "fields": [ { "id": "rpm", "label": "Engine speed",
///                  "offset": 1, "length": 2, "type": "u16be", "scale": 1, "unit": "rpm" } ] } ] }
///
/// Offsets are into the response data (after the address/length header; DS2 status byte is offset 0).
public struct ModuleDefinition: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var `protocol`: KLineProtocol
    public var address: UInt8
    public var serial: SerialSettings?
    public var ident: Request?
    public var faults: FaultRequest?
    public var values: [Request]?

    public struct SerialSettings: Codable, Sendable {
        public var baud: Int
        public var parity: SerialPort.Parity
    }

    public struct Request: Codable, Sendable {
        /// Request data bytes as hex, e.g. "0B 03"
        public var request: String
        public var fields: [Field]
        /// DS2: response status byte that means OK (default A0); KWP: positive response SID
        public var okStatus: String?
    }

    public struct FaultRequest: Codable, Sendable {
        public var request: String
        /// Offset of the first fault record and each record's size in the response data
        public var firstRecord: Int
        public var recordLength: Int
        /// Fault code position inside a record
        public var codeOffset: Int
        public var codeLength: Int
        /// Optional: count byte offset (otherwise records fill the rest of the response)
        public var countOffset: Int?
        /// Our own English texts by code (hex string), written from observation and service info
        public var texts: [String: String]?
        public var clear: String?
    }

    public struct Field: Codable, Sendable {
        public var id: String
        public var label: String
        public var help: String?
        public var offset: Int
        public var length: Int
        public var type: FieldType
        public var scale: Double?
        public var add: Double?
        public var unit: String?
        /// For enums: raw value (decimal string) → text
        public var map: [String: String]?
        /// For bit flags: which bit of the byte at offset
        public var bit: Int?
    }

    public enum FieldType: String, Codable, Sendable { case u8, s8, u16be, s16be, u16le, s16le, u32be, ascii, hex, bcd, bit }
}

public struct DecodedValue: Sendable, Equatable {
    public let id: String
    public let label: String
    public let text: String
    public let number: Double?
    public let unit: String?
}

public enum DecodeError: Error, CustomStringConvertible {
    case short(field: String, need: Int, have: Int), badStatus(UInt8)
    public var description: String {
        switch self {
        case let .short(f, n, h): "response too short for \(f): need \(n) bytes, have \(h)"
        case let .badStatus(s): "module answered with status \(String(format: "%02X", s))"
        }
    }
}

public enum Decoder {
    public static func decode(_ field: ModuleDefinition.Field, in data: [UInt8]) throws -> DecodedValue {
        let end = field.offset + (field.type == .bit ? 1 : field.length)
        guard end <= data.count else { throw DecodeError.short(field: field.id, need: end, have: data.count) }
        let b = Array(data[field.offset..<end])
        func be() -> UInt64 { b.reduce(0) { $0 << 8 | UInt64($1) } }
        func le() -> UInt64 { b.reversed().reduce(0) { $0 << 8 | UInt64($1) } }
        var raw: Double?
        var text: String
        switch field.type {
        case .u8, .u16be, .u32be: raw = Double(be())
        case .u16le: raw = Double(le())
        case .s8: raw = Double(Int8(bitPattern: b[0]))
        case .s16be: raw = Double(Int16(bitPattern: UInt16(be())))
        case .s16le: raw = Double(Int16(bitPattern: UInt16(le())))
        case .bit: raw = Double((b[0] >> UInt8(field.bit ?? 0)) & 1)
        case .ascii: raw = nil
        case .hex: raw = nil
        case .bcd: raw = Double(b.reduce(0) { $0 * 100 + Int($1 >> 4) * 10 + Int($1 & 0x0F) })
        }
        if let r = raw {
            if let m = field.map?[String(Int(r))] { return DecodedValue(id: field.id, label: field.label, text: m, number: r, unit: nil) }
            let v = r * (field.scale ?? 1) + (field.add ?? 0)
            text = v == v.rounded() && abs(v) < 1e12 ? String(Int64(v)) : String(format: "%.2f", v)
            return DecodedValue(id: field.id, label: field.label, text: text, number: v, unit: field.unit)
        }
        text = field.type == .ascii
            ? String(decoding: b.filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            : b.hex
        return DecodedValue(id: field.id, label: field.label, text: text, number: nil, unit: field.unit)
    }

    /// Check the status/positive-response byte, then decode every field
    public static func decode(_ request: ModuleDefinition.Request, response: Frame, proto: KLineProtocol) throws -> [DecodedValue] {
        if let first = response.data.first {
            let ok = request.okStatus.flatMap { UInt8($0, radix: 16) } ?? (proto == .ds2 ? 0xA0 : nil)
            if let ok, first != ok { throw DecodeError.badStatus(first) }
            if proto == .kwp2000star, first == 0x7F { throw DecodeError.badStatus(response.data.count > 2 ? response.data[2] : first) }
        }
        return try request.fields.map { try decode($0, in: response.data) }
    }
}

/// Talks to one module using its definition
public final class ModuleClient {
    public let definition: ModuleDefinition
    public let session: KLineSession
    public init(definition: ModuleDefinition, session: KLineSession) { self.definition = definition; self.session = session }

    func frame(_ hex: String) -> Frame {
        let data = [UInt8](hex: hex) ?? []
        return definition.protocol == .ds2 ? Frame(ds2: definition.address, data: data) : Frame(kwp: definition.address, data: data)
    }

    public func run(_ request: ModuleDefinition.Request) throws -> [DecodedValue] {
        let reply = try session.exchange(frame(request.request))
        return try Decoder.decode(request, response: reply, proto: definition.protocol)
    }

    public func readFaults() throws -> [(code: String, text: String)] {
        guard let f = definition.faults else { return [] }
        let reply = try session.exchange(frame(f.request))
        let d = reply.data
        var codes: [(String, String)] = []
        var i = f.firstRecord
        let limit = f.countOffset.map { min(d.count, f.firstRecord + Int(d[$0]) * f.recordLength) } ?? d.count
        while i + f.recordLength <= limit {
            let code = Array(d[(i + f.codeOffset)..<(i + f.codeOffset + f.codeLength)]).hex.replacingOccurrences(of: " ", with: "")
            codes.append((code, f.texts?[code] ?? "Fault \(code)"))
            i += f.recordLength
        }
        return codes
    }
}
