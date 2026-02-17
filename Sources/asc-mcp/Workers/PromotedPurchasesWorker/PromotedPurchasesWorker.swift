import Foundation
import MCP

/// PromotedPurchasesWorker manages promoted in-app purchases and subscriptions visibility in the App Store
public final class PromotedPurchasesWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    /// - Returns: Array of 5 promoted purchase tools
    public func getTools() async -> [Tool] {
        return [
            listPromotedPurchasesTool(),
            getPromotedPurchaseTool(),
            createPromotedPurchaseTool(),
            updatePromotedPurchaseTool(),
            deletePromotedPurchaseTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    /// - Returns: CallTool.Result with JSON response
    /// - Throws: MCPError if tool name is unknown
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "promoted_list":
            return try await listPromotedPurchases(params)
        case "promoted_get":
            return try await getPromotedPurchase(params)
        case "promoted_create":
            return try await createPromotedPurchase(params)
        case "promoted_update":
            return try await updatePromotedPurchase(params)
        case "promoted_delete":
            return try await deletePromotedPurchase(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
