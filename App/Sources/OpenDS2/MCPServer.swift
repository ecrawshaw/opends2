import AppKit
import Foundation
import Network

/// A small MCP server (Streamable HTTP, JSON responses only) inside the app, so Claude can read the car
/// through the same engine and cable the app uses. Listens on 127.0.0.1 only and needs a bearer token.
/// Read-only jobs run straight away; anything that changes the car opens the app's confirmation dialog
/// and waits for the person at the car.
final class MCPServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 47146

    let port: UInt16
    let token: String
    private weak var state: AppState?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mcp.server")

    init(state: AppState, port: UInt16, token: String) {
        self.state = state
        self.port = port
        self.token = token
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() { listener?.cancel() }

    // MARK: HTTP

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                Task { await self.handle(request, conn) }
            } else if done || error != nil || buffer.count > 4 << 20 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, json: Any? = nil, extra: [String: String] = [:]) {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) } ?? Data()
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func handle(_ req: HTTPRequest, _ conn: NWConnection) async {
        guard req.path == "/mcp" else { return respond(conn, status: "404 Not Found") }
        // Browsers send Origin; refuse anything that isn't a local page (DNS-rebinding protection)
        if let origin = req.headers["origin"], !(origin.contains("://localhost") || origin.contains("://127.0.0.1")) {
            return respond(conn, status: "403 Forbidden")
        }
        guard req.headers["authorization"] == "Bearer \(token)" else {
            return respond(conn, status: "401 Unauthorized", json: ["error": "missing or wrong bearer token"])
        }
        guard req.method == "POST" else { return respond(conn, status: "405 Method Not Allowed", extra: ["Allow": "POST"]) }
        guard let msg = try? JSONSerialization.jsonObject(with: req.body) else {
            return respond(conn, status: "400 Bad Request", json: rpcError(nil, -32700, "Parse error"))
        }
        if let batch = msg as? [[String: Any]] {
            var replies: [[String: Any]] = []
            for m in batch { if let r = await dispatch(m) { replies.append(r) } }
            return replies.isEmpty ? respond(conn, status: "202 Accepted") : respond(conn, status: "200 OK", json: replies)
        }
        guard let m = msg as? [String: Any] else { return respond(conn, status: "400 Bad Request", json: rpcError(nil, -32600, "Invalid request")) }
        if let reply = await dispatch(m) { respond(conn, status: "200 OK", json: reply) } else { respond(conn, status: "202 Accepted") }
    }

    // MARK: JSON-RPC

    private func rpcError(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func dispatch(_ m: [String: Any]) async -> [String: Any]? {
        let method = m["method"] as? String ?? ""
        let params = m["params"] as? [String: Any] ?? [:]
        await state?.recordMCPActivity(method == "tools/call" ? (params["name"] as? String ?? "tools/call") : method)
        guard let id = m["id"] else { return nil } // notification
        switch method {
        case "initialize":
            return ["jsonrpc": "2.0", "id": id, "result": [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "opends2", "version": "0.1"],
                "instructions": MCPTools.instructions,
            ]]
        case "ping":
            return ["jsonrpc": "2.0", "id": id, "result": [:]]
        case "tools/list":
            return ["jsonrpc": "2.0", "id": id, "result": ["tools": MCPTools.definitions]]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let state else { return rpcError(id, -32603, "App is closing") }
            let (text, isError) = await MCPTools.call(name, args, state: state)
            return ["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": text]], "isError": isError]]
        default:
            return rpcError(id, -32601, "Method not found: \(method)")
        }
    }
}

/// Just enough HTTP/1.1 request parsing for MCP clients: headers plus a Content-Length body
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(first[0])
        path = String(first[1].split(separator: "?").first ?? "")
        self.headers = headers
        body = data[bodyStart..<(bodyStart + length)]
    }
}
