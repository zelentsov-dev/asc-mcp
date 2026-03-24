import Foundation
import MCP

/// SandboxTestersWorker manages sandbox testers for App Store Connect
public final class SandboxTestersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listSandboxTestersTool(),
            updateSandboxTesterTool(),
            clearPurchaseHistoryTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "sandbox_list":
            return try await listSandboxTesters(params)
        case "sandbox_update":
            return try await updateSandboxTester(params)
        case "sandbox_clear_purchase_history":
            return try await clearPurchaseHistory(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
