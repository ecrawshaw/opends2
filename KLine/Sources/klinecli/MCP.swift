import Foundation
import KLine

/// MCP server over stdio (`kline mcp`), so an AI assistant can read the car through the adapter.
/// Generic OBD-II (any car) plus definition-driven BMW modules. Deliberately read-only: no raw
/// sends, no clearing codes, no actuations or coding — those stay behind the app's confirmations.
final class MCPServer {
    let adapterSpec: String
    let definitions: [ModuleDefinition]
    private var link: ByteLink?
    private var obd: OBD?

    init(adapter: String, definitionsDir: String?) {
        adapterSpec = adapter
        var defs: [ModuleDefinition] = []
        if let dir = definitionsDir, let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for f in files.sorted() where f.hasSuffix(".json") {
                let path = (dir as NSString).appendingPathComponent(f)
                do { defs.append(try JSONDecoder().decode(ModuleDefinition.self, from: Data(contentsOf: URL(fileURLWithPath: path)))) }
                catch { FileHandle.standardError.write(Data("skipping \(f): \(error)\n".utf8)) }
            }
        }
        definitions = defs
    }

    func run() {
        while let line = readLine() {
            guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            guard let id = msg["id"] else { continue } // notifications need no answer
            let method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]
            switch method {
            case "initialize":
                reply(id, result: [
                    "protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "kline", "version": "0.1"],
                    "instructions": "Reads a car through the WiFi OBD adapter. obd_* tools work on any car since 1996 (generic OBD-II: engine/emissions data, check-engine codes). identify/read_values/read_faults reach BMW E-series modules that have definitions. Read-only: it cannot clear codes or change anything. Ask the user to switch the ignition on (engine may run) before reading.",
                ])
            case "ping": reply(id, result: [:])
            case "tools/list": reply(id, result: ["tools": tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                do { reply(id, result: ["content": [["type": "text", "text": try call(name, args)]]]) }
                catch { link = nil; obd = nil; reply(id, result: ["content": [["type": "text", "text": "Error: \(error)"]], "isError": true]) }
            default: reply(id, error: [-32601, "unknown method \(method)"])
            }
        }
    }

    private var tools: [[String: Any]] {
        let moduleArg: [String: Any] = ["type": "object", "required": ["module"], "properties": [
            "module": ["type": "string", "description": "Module id from list_modules"]]]
        let none: [String: Any] = ["type": "object", "properties": [:]]
        return [
            ["name": "obd_info", "description": "Any car: detect the OBD-II protocol, read the VIN, check-engine light state, stored/pending/permanent trouble codes and emissions readiness monitors.",
             "inputSchema": none, "annotations": ["readOnlyHint": true]],
            ["name": "obd_live", "description": "Any car: read every live engine value the car supports (rpm, coolant temp, fuel trims, voltage, …) once. Call again to see changes.",
             "inputSchema": ["type": "object", "properties": [
                "pids": ["type": "array", "items": ["type": "string"], "description": "Optional mode-01 PIDs in hex (e.g. [\"0C\",\"05\"]); default all supported"]]],
             "annotations": ["readOnlyHint": true]],
            ["name": "list_modules", "description": "Modules this server has definitions for (id, name, protocol, address, what can be read).",
             "inputSchema": ["type": "object", "properties": [:]], "annotations": ["readOnlyHint": true]],
            ["name": "adapter_status", "description": "WiFi adapter firmware, UART settings and car battery voltage.",
             "inputSchema": ["type": "object", "properties": [:]], "annotations": ["readOnlyHint": true]],
            ["name": "identify", "description": "Ask a module to identify itself. Give a module id, or a DS2 address in hex (e.g. \"12\" for the engine) to probe one with no definition.",
             "inputSchema": ["type": "object", "properties": [
                "module": ["type": "string"], "address": ["type": "string", "description": "DS2 address, hex"]]],
             "annotations": ["readOnlyHint": true]],
            ["name": "read_values", "description": "Read every live value the module's definition describes, with units.",
             "inputSchema": moduleArg, "annotations": ["readOnlyHint": true]],
            ["name": "read_faults", "description": "Read the module's fault memory (codes and descriptions). Does not clear anything.",
             "inputSchema": moduleArg, "annotations": ["readOnlyHint": true]],
        ]
    }

    private func call(_ name: String, _ args: [String: Any]) throws -> String {
        switch name {
        case "obd_info":
            let o = try obdConnection()
            var out = ["Protocol: \(o.transport.name)", "VIN: \((try? o.vin()) ?? nil ?? "not reported")"]
            for r in try o.readiness() {
                out.append("ECU \(r.ecu): check-engine light \(r.milOn ? "ON" : "off"), \(r.dtcCount) stored code(s)")
                let notReady = r.monitors.filter { !$0.complete }.map(\.name)
                out.append("  readiness: \(r.monitors.count - notReady.count)/\(r.monitors.count) complete" + (notReady.isEmpty ? "" : "; not ready: \(notReady.joined(separator: ", "))"))
            }
            for kind in [OBD.DTCKind.stored, .pending, .permanent] {
                let all = (try? o.dtcs(kind)) ?? [:]
                let list = all.flatMap { ecu, codes in codes.map { "\($0) (\(ecu))" } }
                out.append("\(kind) codes: \(list.isEmpty ? "none" : list.joined(separator: ", "))")
            }
            return out.joined(separator: "\n")
        case "obd_live":
            let o = try obdConnection()
            var values: [PIDValue] = []
            if let pids = args["pids"] as? [String], !pids.isEmpty {
                for p in pids.compactMap({ UInt8($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }) { values += try o.read(p) }
            } else { values = try o.readAll() }
            return values.isEmpty ? "No supported values." : values.map { "\($0.ecu)  \($0.text)" }.joined(separator: "\n")
        case "list_modules":
            if definitions.isEmpty { return "No module definitions loaded (pass --defs <folder>). identify with an address still works." }
            return definitions.map { d in
                var can = [String]()
                if d.ident != nil { can.append("identify") }
                if !(d.values ?? []).isEmpty { can.append("values") }
                if d.faults != nil { can.append("faults") }
                return "\(d.id): \(d.name) (\(d.protocol.rawValue), address \(String(format: "%02X", d.address)); \(can.joined(separator: ", ")))"
            }.joined(separator: "\n")
        case "adapter_status":
            guard let tcp = try connect() as? TcpLink else { return "Connected through a USB cable (\(adapterSpec)); no adapter status." }
            let s = try tcp.status()
            return "Firmware \(s.firmware), K-line \(s.baud) baud parity \(s.parity), WiFi \(s.wifi), up \(s.uptime) s, battery \(s.batteryVolts.map { String(format: "%.1f V", $0) } ?? "not measured")" + (s.power.map { ", \($0)" } ?? "")
        case "identify":
            if let m = args["module"] as? String {
                let d = try module(m)
                guard let ident = d.ident else { return "\(d.name) has no ident request defined." }
                return try format(client(d).run(ident))
            }
            guard let a = args["address"] as? String, let addr = UInt8(a.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                throw MCPError("give module or address")
            }
            let s = try session(.ds2)
            let r = try s.exchange(Frame(ds2: addr, data: [0x00]))
            let text = String(decoding: r.data.dropFirst().filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
            return "Module \(String(format: "%02X", addr)) answered, status \(String(format: "%02X", r.data.first ?? 0)).\nRaw: \(r.data.hex)\nPrintable: \(text)"
        case "read_values":
            let d = try module(args["module"] as? String ?? "")
            let c = try client(d)
            var out: [String] = []
            for req in d.values ?? [] {
                do { out.append(format(try c.run(req))) } catch { out.append("request \(req.request): \(error)") }
            }
            return out.isEmpty ? "\(d.name) has no values defined." : out.joined(separator: "\n")
        case "read_faults":
            let d = try module(args["module"] as? String ?? "")
            guard d.faults != nil else { return "\(d.name) has no fault request defined." }
            let f = try client(d).readFaults()
            return f.isEmpty ? "\(d.name): no faults stored." : f.map { "\($0.code): \($0.text)" }.joined(separator: "\n")
        default: throw MCPError("unknown tool \(name)")
        }
    }

    private func format(_ v: [DecodedValue]) -> String {
        v.map { "\($0.label): \($0.text)\($0.unit.map { " \($0)" } ?? "")" }.joined(separator: "\n")
    }

    private func module(_ id: String) throws -> ModuleDefinition {
        guard let d = definitions.first(where: { $0.id == id }) else { throw MCPError("no module \"\(id)\"; see list_modules") }
        return d
    }

    /// OBD and the BMW tools can't share the K-line connection; whichever is used drops the other
    private func obdConnection() throws -> OBD {
        if let obd { return obd }
        link = nil
        let o = try OBD.connect(AdapterAddress(spec: adapterSpec))
        obd = o
        return o
    }

    private func connect() throws -> ByteLink {
        obd = nil
        if let link { return link }
        let l = try Adapter.open(adapterSpec)
        link = l
        return l
    }

    private func session(_ proto: KLineProtocol) throws -> KLineSession {
        let s = KLineSession(link: try connect(), proto: proto)
        Adapter.tune(s)
        return s
    }

    private func client(_ d: ModuleDefinition) throws -> ModuleClient {
        ModuleClient(definition: d, session: try session(d.protocol))
    }

    private func reply(_ id: Any, result: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": result]) }
    private func reply(_ id: Any, error: [Any]) { send(["jsonrpc": "2.0", "id": id, "error": ["code": error[0], "message": error[1]]]) }
    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        FileHandle.standardOutput.write(d + Data("\n".utf8))
    }
}

struct MCPError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
