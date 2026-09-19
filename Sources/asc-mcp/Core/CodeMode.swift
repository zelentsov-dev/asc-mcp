import Foundation
import JavaScriptCore
import MCP

/// Code Mode public tool definitions and bounded JavaScript execution.
/// Domain calls are re-entered through WorkerManager's canonical dispatcher.
final class CodeModeRuntime: @unchecked Sendable {
    private let dispatchTool: @Sendable (CallTool.Parameters) async throws -> CallTool.Result
    private let toolsProvider: @Sendable () async -> [Tool]
    private let maxSourceLength = 64_000
    private let maxToolCalls = 25
    private let maxOutputLength = 16_000
    private let timeout: TimeInterval = 30

    init(
        dispatchTool: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result,
        toolsProvider: @escaping @Sendable () async -> [Tool]
    ) {
        self.dispatchTool = dispatchTool
        self.toolsProvider = toolsProvider
    }

    func search(query: String, limit: Int) async -> CallTool.Result {
        let boundedLimit = min(max(limit, 1), 20)
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tools = await toolsProvider()
        let matches = tools.filter { normalized.isEmpty || $0.name.lowercased().contains(normalized) || $0.description?.lowercased().contains(normalized) == true }
        let values = matches.prefix(boundedLimit).map { tool in
            Value.object([
                "name": .string(tool.name),
                "description": .string(tool.description ?? "")
            ])
        }
        return MCPResult.json(.object([
            "success": .bool(true),
            "count": .int(matches.count),
            "results": .array(Array(values))
        ]))
    }

    func schemas(names: [String]) async -> CallTool.Result {
        let requested = Set(names)
        let tools = await toolsProvider()
        let found = tools.filter { requested.contains($0.name) }
        let values = found.map { tool in
            Value.object([
                "name": .string(tool.name),
                "description": .string(tool.description ?? ""),
                "inputSchema": tool.inputSchema
            ])
        }
        let missing = names.filter { name in !found.contains { tool in tool.name == name } }
        return MCPResult.json(.object([
            "success": .bool(true),
            "schemas": .array(values),
            "missing": .array(missing.map(Value.string))
        ]))
    }

    func execute(source: String) async -> CallTool.Result {
        guard !source.isEmpty, source.utf8.count <= maxSourceLength else {
            return MCPResult.error("Code Mode source exceeds the 64KB limit.")
        }

        let bridge = Bridge(dispatchTool: dispatchTool, maxToolCalls: maxToolCalls, maxOutputLength: maxOutputLength)
        let box = ExecutionResultBox()
        let context = JSContext()!
        context.exceptionHandler = { _, exception in
            box.value = JSONSerializationError.message(exception)
        }
        context.setObject(bridge.callToolBlock(), forKeyedSubscript: "__asc_call" as NSString)
            let wrapped = "(function(){\nconst asc = { callTool: (name, args) => JSON.parse(__asc_call(name, args || {})) };\nreturn (function(){\n\(source)\n})();\n})()"
            if box.value.isEmpty, let value = context.evaluateScript(wrapped), !value.isUndefined {
                if let object = value.toObject(), JSONSerialization.isValidJSONObject(object) {
                    if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) {
                        box.value = text
                    }
                } else if let text = value.toString() {
                    box.value = text
                }
            }
            if box.value.isEmpty { box.value = "null" }
            if box.value.utf8.count > self.maxOutputLength { box.value = "{\"success\":false,\"error\":\"Code Mode output exceeded the 16KB limit.\"}" }
        return MCPResult.text(box.value)
    }
}

private final class ExecutionResultBox: @unchecked Sendable {
    var value = ""
}

private final class Bridge: @unchecked Sendable {
    private let dispatchTool: @Sendable (CallTool.Parameters) async throws -> CallTool.Result
    private let maxToolCalls: Int
    private let maxOutputLength: Int
    private var callCount = 0
    private let lock = NSLock()

    init(dispatchTool: @escaping @Sendable (CallTool.Parameters) async throws -> CallTool.Result, maxToolCalls: Int, maxOutputLength: Int) {
        self.dispatchTool = dispatchTool
        self.maxToolCalls = maxToolCalls
        self.maxOutputLength = maxOutputLength
    }

    func callToolBlock() -> @convention(block) (String, JSValue) -> String {
        return { [self] name, arguments in
            lock.lock()
            guard callCount < maxToolCalls else { lock.unlock(); return "{\"success\":false,\"error\":\"Code Mode tool-call limit exceeded.\"}" }
            callCount += 1
            lock.unlock()
            guard let raw = arguments.toObject() as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let value = try? JSONDecoder().decode(Value.self, from: data),
                  let object = value.objectValue else {
                return "{\"success\":false,\"error\":\"Code Mode arguments must be an object.\"}"
            }
            let params = CallTool.Parameters(name: name, arguments: object)
            let semaphore = DispatchSemaphore(value: 0)
            let outputBox = ExecutionResultBox()
            outputBox.value = "{\"success\":false,\"error\":\"Code Mode call failed.\"}"
            Task { [dispatchTool, maxOutputLength, params, outputBox] in
                do {
                    let response = try await dispatchTool(params)
                    if let data = try? JSONEncoder().encode(response), let text = String(data: data, encoding: .utf8) {
                        outputBox.value = String(text.prefix(maxOutputLength))
                    }
                } catch { }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 25)
            return outputBox.value
        }
    }
}

private enum JSONSerializationError {
    static func message(_ exception: JSValue?) -> String {
        let message = exception?.toString() ?? "Code Mode execution failed."
        return "{\"success\":false,\"error\":\"\(message.replacingOccurrences(of: "\\\"", with: "'"))\"}"
    }
}

func codeModeTools() -> [Tool] {
    [
        Tool(name: "asc_code_search", description: "Search the App Store Connect tool catalog without loading the full 502-tool surface.", inputSchema: .object(["type": .string("object"), "properties": .object(["query": .object(["type": .string("string")]), "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(20)])]), "required": .array([.string("query")])])),
        Tool(name: "asc_code_get_schema", description: "Retrieve exact input schemas for manifest-backed App Store Connect tools.", inputSchema: .object(["type": .string("object"), "properties": .object(["names": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "minItems": .int(1)])]), "required": .array([.string("names")])])),
        Tool(name: "asc_code_execute", description: "Execute bounded JavaScript Code Mode. Use asc.callTool(name, args) for manifest-backed reads and mutations; existing read-only and mutation policy gates remain authoritative.", inputSchema: .object(["type": .string("object"), "properties": .object(["code": .object(["type": .string("string"), "maxLength": .int(64_000)])]), "required": .array([.string("code")])] ))
    ]
}
