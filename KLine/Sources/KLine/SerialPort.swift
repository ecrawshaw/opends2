import Darwin
import Foundation

/// Byte link to the car. The real one is a serial port; tests use a scripted fake.
public protocol ByteLink: AnyObject {
    func write(_ bytes: [UInt8]) throws
    /// Read up to `max` bytes, waiting at most `timeout` seconds for the first one
    func read(max: Int, timeout: TimeInterval) throws -> [UInt8]
    func flushInput()
}

public enum SerialError: Error, CustomStringConvertible {
    case open(String, Int32), configure(Int32), io(Int32)
    public var description: String {
        switch self {
        case let .open(p, e): "can't open \(p): \(String(cString: strerror(e)))"
        case let .configure(e): "can't configure port: \(String(cString: strerror(e)))"
        case let .io(e): "serial I/O error: \(String(cString: strerror(e)))"
        }
    }
}

/// POSIX serial port (FTDI K+DCAN cable as /dev/cu.usbserial-…), raw 8-bit, no flow control.
public final class SerialPort: ByteLink {
    public enum Parity: String, Codable, Sendable { case none, even }
    private let fd: Int32
    public let path: String

    public init(path: String, baud: Int = 9600, parity: Parity = .even) throws {
        self.path = path
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.open(path, errno) }
        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { close(fd); throw SerialError.configure(errno) }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        t.c_cflag &= ~tcflag_t(CSTOPB | CRTSCTS | PARODD)
        if parity == .even { t.c_cflag |= tcflag_t(PARENB) } else { t.c_cflag &= ~tcflag_t(PARENB) }
        cfsetspeed(&t, speed_t(baud))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { close(fd); throw SerialError.configure(errno) }
        tcflush(fd, TCIOFLUSH)
    }

    deinit { close(fd) }

    /// K+DCAN cables use DTR/RTS to switch between K-line and D-CAN and to power the line driver.
    public func setLines(dtr: Bool, rts: Bool) throws {
        var bits: Int32 = TIOCM_DTR
        _ = ioctl(fd, dtr ? TIOCMBIS : TIOCMBIC, &bits)
        bits = TIOCM_RTS
        _ = ioctl(fd, rts ? TIOCMBIS : TIOCMBIC, &bits)
    }

    public func write(_ bytes: [UInt8]) throws {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0 { if errno == EAGAIN { usleep(1000); continue }; throw SerialError.io(errno) }
            off += n
        }
        tcdrain(fd)
    }

    public func read(max: Int, timeout: TimeInterval) throws -> [UInt8] {
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&p, 1, Int32(timeout * 1000))
        if r < 0 { throw SerialError.io(errno) }
        if r == 0 { return [] }
        var buf = [UInt8](repeating: 0, count: max)
        let n = Darwin.read(fd, &buf, max)
        if n < 0 { if errno == EAGAIN { return [] }; throw SerialError.io(errno) }
        return Array(buf.prefix(n))
    }

    public func flushInput() { tcflush(fd, TCIFLUSH) }
}
