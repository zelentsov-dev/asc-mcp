import Foundation
import MCP

/// BuildBetaDetailsWorker manages build beta details and TestFlight settings
public final class BuildBetaDetailsWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            getBetaDetailTool(),
            updateBetaDetailTool(),
            setBetaLocalizationTool(),
            listBetaLocalizationsTool(),
            getBetaGroupsTool(),
            getBetaTestersTool(),
            addToBetaGroupsTool(),
            sendBetaNotificationTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "builds_get_beta_detail":
            return try await getBetaDetail(params)
        case "builds_update_beta_detail":
            return try await updateBetaDetail(params)
        case "builds_set_beta_localization":
            return try await setBetaLocalization(params)
        case "builds_list_beta_localizations":
            return try await listBetaLocalizations(params)
        case "builds_get_beta_groups":
            return try await getBetaGroups(params)
        case "builds_get_beta_testers":
            return try await getBetaTesters(params)
        case "builds_add_to_beta_groups":
            return try await addToBetaGroups(params)
        case "builds_send_beta_notification":
            return try await sendBetaNotification(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}