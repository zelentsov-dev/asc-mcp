import Foundation
import MCP

/// BetaTestersWorker manages TestFlight beta testers in App Store Connect
public final class BetaTestersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listBetaTestersTool(),
            searchBetaTestersTool(),
            getBetaTesterTool(),
            createBetaTesterTool(),
            deleteBetaTesterTool(),
            listBetaTesterAppsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "beta_testers_list":
            return try await listBetaTesters(params)
        case "beta_testers_search":
            return try await searchBetaTesters(params)
        case "beta_testers_get":
            return try await getBetaTester(params)
        case "beta_testers_create":
            return try await createBetaTester(params)
        case "beta_testers_delete":
            return try await deleteBetaTester(params)
        case "beta_testers_list_apps":
            return try await listBetaTesterApps(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
