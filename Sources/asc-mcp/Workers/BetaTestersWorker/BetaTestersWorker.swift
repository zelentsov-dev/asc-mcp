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
            listBetaTesterAppsTool(),
            sendInvitationTool(),
            addToGroupsTool(),
            removeFromGroupsTool(),
            addToBuildsTool(),
            removeFromBuildsTool(),
            removeFromAppTool()
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
        case "beta_testers_send_invitation":
            return try await sendInvitation(params)
        case "beta_testers_add_to_groups":
            return try await addToGroups(params)
        case "beta_testers_remove_from_groups":
            return try await removeFromGroups(params)
        case "beta_testers_add_to_builds":
            return try await addToBuilds(params)
        case "beta_testers_remove_from_builds":
            return try await removeFromBuilds(params)
        case "beta_testers_remove_from_app":
            return try await removeFromApp(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
