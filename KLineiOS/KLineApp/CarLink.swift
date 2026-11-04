import Foundation
import KLine

/// Owns the OBD connection and runs the library's blocking calls one at a time on a background
/// queue. The connection is only ever touched on that queue.
final class CarLink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "kline.car")
    private var obd: OBD?

    struct NotConnected: Error, CustomStringConvertible { var description: String { "Not connected to the car" } }

    /// Detect the car's protocol (CAN, then K-line); returns its name
    func connect(_ address: AdapterAddress, log: @escaping @Sendable (String) -> Void) async throws -> String {
        try await onQueue {
            self.obd = nil
            let o = try OBD.connect(address, log: log)
            self.obd = o
            return o.transport.name
        }
    }

    func disconnect() {
        queue.async { self.obd = nil }  // closing the sockets also takes the adapter off the CAN bus
    }

    /// Run `body` with the connection. A lost connection (adapter asleep, out of range) drops it,
    /// so the next attempt starts from a fresh protocol detection.
    func with<T>(_ body: @escaping (OBD) throws -> T) async throws -> T {
        try await onQueue {
            guard let o = self.obd else { throw NotConnected() }
            do { return try body(o) } catch let e as TcpError { self.obd = nil; throw e }
        }
    }

    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            queue.async { c.resume(with: Result { try body() }) }
        }
    }
}

/// The adapter's HTTP side (status, settings). Uses its own requests, so checking the adapter
/// never disturbs a K-line or CAN connection.
enum AdapterHTTP {
    static func status(_ a: AdapterAddress, timeout: TimeInterval = 2.5) async throws -> TcpLink.Status {
        try JSONDecoder().decode(TcpLink.Status.self, from: await get(a, "/status", timeout: timeout))
    }

    static func get(_ a: AdapterAddress, _ path: String, timeout: TimeInterval = 4) async throws -> Data {
        guard let url = URL(string: "http://\(a.host):\(a.httpPort)\(path)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
            throw AdapterError(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    /// Query string with everything but letters, digits and -._~ escaped (WiFi names and passwords
    /// can contain "&", "+" and "=", which the adapter would otherwise read as separators)
    static func query(_ items: [String: String]) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return items.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")" }
            .joined(separator: "&")
    }
}

struct AdapterError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d.isEmpty ? "adapter refused the request" : d }
}

/// Saved networks, as `/wifi` reports them
struct AdapterNetworks: Decodable {
    var saved: [String]
    var joined: String?
    var ip: String?
}
