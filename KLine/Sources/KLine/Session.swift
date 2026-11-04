import Foundation

public enum SessionError: Error, CustomStringConvertible {
    case echoMismatch(sent: [UInt8], got: [UInt8])
    case noResponse(Frame)
    case wrongSender(expected: UInt8, got: UInt8)
    public var description: String {
        switch self {
        case let .echoMismatch(s, g): "echo mismatch (sent \(s.hex), read back \(g.hex)): check the cable switch / port"
        case let .noResponse(f): "no response to \(f)"
        case let .wrongSender(e, g): "answer from \(String(format: "%02X", g)), expected \(String(format: "%02X", e))"
        }
    }
}

/// Request/response on a single-wire K-line. The K+DCAN cable hears its own transmission, so every
/// request comes back as an echo before the module answers; we read and check it, then parse the reply.
public final class KLineSession {
    public let link: ByteLink
    public let proto: KLineProtocol
    /// Max wait for the module to start answering (DS2 modules answer well within this)
    public var responseTimeout: TimeInterval = 1.0
    /// Max gap between bytes inside one frame
    public var interByteTimeout: TimeInterval = 0.1
    /// Max wait for our own echo to come back
    public var echoTimeout: TimeInterval = 0.5
    public var expectEcho = true
    /// Raw traffic log: (direction, bytes)
    public var onTraffic: ((String, [UInt8]) -> Void)?

    public init(link: ByteLink, proto: KLineProtocol) { self.link = link; self.proto = proto }

    public func exchange(_ request: Frame, retries: Int = 1) throws -> Frame {
        var lastError: Error = SessionError.noResponse(request)
        for _ in 0...retries {
            do { return try once(request) } catch { lastError = error }
        }
        throw lastError
    }

    private func readExactly(_ n: Int, firstTimeout: TimeInterval) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < n {
            let chunk = try link.read(max: n - out.count, timeout: out.isEmpty ? firstTimeout : interByteTimeout)
            if chunk.isEmpty { break }
            out += chunk
        }
        return out
    }

    private func once(_ request: Frame) throws -> Frame {
        link.flushInput()
        let bytes = request.bytes
        try link.write(bytes)
        onTraffic?("send", bytes)
        if expectEcho {
            let echo = try readExactly(bytes.count, firstTimeout: echoTimeout)
            guard echo == bytes else { throw SessionError.echoMismatch(sent: bytes, got: echo) }
        }
        var parser = FrameParser(proto)
        var got: [UInt8] = []
        var timeout = responseTimeout
        while true {
            let chunk = try link.read(max: 256, timeout: timeout)
            if chunk.isEmpty { throw SessionError.noResponse(request) }
            got += chunk
            timeout = interByteTimeout
            if let frame = try parser.feed(chunk).first {
                onTraffic?("recv", got)
                switch proto {
                case .ds2:
                    guard frame.address == request.address else { throw SessionError.wrongSender(expected: request.address, got: frame.address) }
                case .kwp2000star:
                    guard frame.source == request.address else { throw SessionError.wrongSender(expected: request.address, got: frame.source ?? 0) }
                }
                return frame
            }
        }
    }
}
