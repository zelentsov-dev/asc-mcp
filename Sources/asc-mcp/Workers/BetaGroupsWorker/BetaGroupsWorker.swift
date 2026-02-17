import Foundation
import MCP

/// BetaGroupsWorker manages TestFlight beta groups in App Store Connect
public final class BetaGroupsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listBetaGroupsTool(),
            createBetaGroupTool(),
            updateBetaGroupTool(),
            deleteBetaGroupTool(),
            addTestersTool(),
            removeTestersTool(),
            listTestersTool(),
            addBuildsTool(),
            removeBuildsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "beta_groups_list":
            return try await listBetaGroups(params)
        case "beta_groups_create":
            return try await createBetaGroup(params)
        case "beta_groups_update":
            return try await updateBetaGroup(params)
        case "beta_groups_delete":
            return try await deleteBetaGroup(params)
        case "beta_groups_add_testers":
            return try await addTesters(params)
        case "beta_groups_remove_testers":
            return try await removeTesters(params)
        case "beta_groups_list_testers":
            return try await listTesters(params)
        case "beta_groups_add_builds":
            return try await addBuilds(params)
        case "beta_groups_remove_builds":
            return try await removeBuilds(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
