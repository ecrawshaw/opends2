import Darwin
import Foundation

public enum TcpError: Error, CustomStringConvertible {
    case resolve(String), connect(String, Int32), io(Int32), closed, http(String)
    public var description: String {
        switch self {
        case let .resolve(h): "can't find adapter \(h) (is the Mac on the E46-Diag WiFi?)"
        case let .connect(h, e): "can't connect to \(h): \(String(cString: strerror(e)))"
        case let .io(e): "network I/O error: \(String(cString: strerror(e)))"
        case .closed: "adapter closed the connection"
        case let .http(m): "adapter settings: \(m)"
        }
    }
}

/// Where the WiFi adapter is: "host", or "host:kline:can:http" ports for a non-standard setup
/// (`kline fake-adapter` prints one).
public struct AdapterAddress: Sendable {
    public static let defaultHost = "192.168.4.1"
    public var host = AdapterAddress.defaultHost
    public var klinePort: UInt16 = 23
    public var canPort: UInt16 = 3333
    public var httpPort: UInt16 = 80

    public init(host: String = AdapterAddress.defaultHost) { self.host = host }
    public init(spec: String) {
        var s = spec
        if s.hasPrefix("tcp://") { s.removeFirst(6) }
        let parts = s.split(separator: ":").map(String.init)
        if let h = parts.first, !h.isEmpty { host = h }
        if parts.count > 1, let p = UInt16(parts[1]) { klinePort = p }
        if parts.count > 2, let p = UInt16(parts[2]) { canPort = p }
        if parts.count > 3, let p = UInt16(parts[3]) { httpPort = p }
    }
}

/// WiFi adapter (ESP32 + K-line and CAN transceivers, see adapter-esp32/). This is a TCP byte link;
/// on the K-line port the transceiver hears its own transmission exactly like the USB cable, so
/// KLineSession's echo check applies unchanged. Port 80 takes settings and reports status.
public final class TcpLink: ByteLink {
    public static let defaultHost = AdapterAddress.defaultHost
    public let host: String
    public let port: UInt16
    public var httpPort: UInt16 = 80
    private let fd: Int32

    /// The adapter's K-line port
    public convenience init(_ address: AdapterAddress) throws {
        try self.init(host: address.host, port: address.klinePort)
        httpPort = address.httpPort
    }

    public init(host: String = TcpLink.defaultHost, port: UInt16 = 23, timeout: TimeInterval = 3) throws {
        self.host = host
        self.port = port
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let ai = res else { throw TcpError.resolve(host) }
        defer { freeaddrinfo(res) }
        fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
        guard fd >= 0 else { throw TcpError.connect(host, errno) }
        var one: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // Non-blocking connect so an absent adapter fails in `timeout` rather than ~75 s
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        if connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else { let e = errno; close(fd); throw TcpError.connect(host, e) }
            var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if poll(&p, 1, Int32(timeout * 1000)) <= 0 { close(fd); throw TcpError.connect(host, ETIMEDOUT) }
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            guard err == 0 else { close(fd); throw TcpError.connect(host, err) }
        }
    }

    /// "host" or "host:kline:can:http"
    public convenience init(spec: String) throws { try self.init(AdapterAddress(spec: spec)) }

    deinit { close(fd) }

    public func write(_ bytes: [UInt8]) throws {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBufferPointer { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n < 0 {
                if errno == EAGAIN { var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0); _ = poll(&p, 1, 100); continue }
                throw TcpError.io(errno)
            }
            off += n
        }
    }

    public func read(max: Int, timeout: TimeInterval) throws -> [UInt8] {
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&p, 1, Int32(timeout * 1000))
        if r < 0 { throw TcpError.io(errno) }
        if r == 0 { return [] }
        var buf = [UInt8](repeating: 0, count: max)
        let n = recv(fd, &buf, max, 0)
        if n == 0 { throw TcpError.closed }
        if n < 0 { if errno == EAGAIN { return [] }; throw TcpError.io(errno) }
        return Array(buf.prefix(n))
    }

    /// Drop anything already received (late bytes from a previous exchange)
    public func flushInput() {
        var buf = [UInt8](repeating: 0, count: 512)
        while recv(fd, &buf, buf.count, 0) > 0 {}
    }

    // MARK: settings / status (HTTP on port 80)

    public struct Status: Codable, Sendable {
        public var firmware: String
        public var baud: Int
        public var parity: String
        public var batteryVolts: Double?
        public var can: String?
        public var wifi: String
        public var uptime: Int
        /// When the adapter goes to sleep (firmware 0.3+)
        public var power: String?
    }

    public func status() throws -> Status {
        try JSONDecoder().decode(Status.self, from: http("/status"))
    }

    /// Set the K-line UART (DS2 and the MK60 DSC both use 9600 baud, even parity)
    public func configure(baud: Int, parity: SerialPort.Parity) throws {
        _ = try http("/config?baud=\(baud)&parity=\(parity.rawValue)")
        flushInput()
    }

    public struct KeyBytes: Codable, Sendable { public var ok: Bool; public var kb1: String?; public var kb2: String?; public var error: String? }

    /// ISO 14230 fast init (the caller then sends StartCommunication), at 10400 baud, no parity
    public func fastInit() throws {
        _ = try http("/kinit?mode=fast&baud=10400")
        flushInput()
    }

    /// 5-baud init to `address` (0x33 = OBD functional). Key bytes say which protocol the car speaks:
    /// 08 08 / 94 94 = ISO 9141-2, xx 8F = ISO 14230 (KWP2000).
    public func slowInit(address: UInt8 = 0x33) throws -> KeyBytes {
        let kb = try JSONDecoder().decode(KeyBytes.self, from: http("/kinit?mode=slow&addr=\(String(format: "%02X", address))&baud=10400", timeout: 5))
        flushInput()
        return kb
    }

    private func http(_ path: String, timeout: TimeInterval = 3) throws -> Data {
        guard let url = URL(string: "http://\(host):\(httpPort)\(path)") else { throw TcpError.http("bad url") }
        var result: Result<Data, Error> = .failure(TcpError.http("timed out"))
        let done = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { result = .failure(err) }
            else if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                result = .failure(TcpError.http(String(decoding: data ?? Data(), as: UTF8.self)))
            } else { result = .success(data ?? Data()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return try result.get()
    }
}

/// Open whatever the user named: a serial device path, or a WiFi adapter address.
public enum Adapter {
    public static func open(_ spec: String, baud: Int = 9600, parity: SerialPort.Parity = .even) throws -> ByteLink {
        if spec.hasPrefix("/dev/") { return try SerialPort(path: spec, baud: baud, parity: parity) }
        let link = try TcpLink(spec: spec)
        // A fake adapter (kline fake-adapter) has no HTTP side; that's fine
        try? link.configure(baud: baud, parity: parity)
        return link
    }

    /// WiFi adds latency and can split a frame across packets, so allow longer gaps
    public static func tune(_ session: KLineSession) {
        guard session.link is TcpLink else { return }
        session.responseTimeout = 1.5
        session.interByteTimeout = 0.3
        session.echoTimeout = 1.0
    }
}
