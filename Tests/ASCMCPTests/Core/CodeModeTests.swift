import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Code Mode Contract Tests")
struct CodeModeTests {
    @Test("publishes exactly the bounded Code Mode tool surface")
    func publishesExpectedTools() {
        let tools = codeModeTools()
        #expect(tools.map(\.name) == ["asc_code_search", "asc_code_get_schema", "asc_code_execute"])
        #expect(tools.allSatisfy { $0.inputSchema.objectValue?["required"] != nil })
        #expect(tools.first { $0.name == "asc_code_search" }?.description?.contains("502-tool") == true)
    }

    @Test("search returns catalog matches and clamps the requested result limit")
    func searchesCatalog() async throws {
        let runtime = CodeModeRuntime(
            dispatchTool: { _ in MCPResult.text("unused") },
            toolsProvider: {
                [
                    Tool(name: "apps_list", description: "List apps", inputSchema: .object([:])),
                    Tool(name: "builds_list", description: "List builds", inputSchema: .object([:])),
                    Tool(name: "apps_get", description: "Get app", inputSchema: .object([:]))
                ]
            }
        )

        let result = await runtime.search(query: "apps", limit: 0)
        let encoded = try JSONEncoder().encode(result)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("apps_list"))
        #expect(!text.contains("apps_get"))
        #expect(!text.contains("builds_list"))
    }

    @Test("schema lookup reports missing names without exposing unrelated schemas")
    func getsRequestedSchemas() async throws {
        let runtime = CodeModeRuntime(
            dispatchTool: { _ in MCPResult.text("unused") },
            toolsProvider: {
                [Tool(name: "apps_list", description: "List apps", inputSchema: .object(["type": .string("object")]))]
            }
        )

        let result = await runtime.schemas(names: ["apps_list", "not_registered"])
        let encoded = try JSONEncoder().encode(result)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("apps_list"))
        #expect(text.contains("not_registered"))
    }
}
