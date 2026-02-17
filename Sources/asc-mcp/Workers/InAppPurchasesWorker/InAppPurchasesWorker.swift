import Foundation
import MCP

/// InAppPurchasesWorker manages IAP and subscriptions in App Store Connect
public final class InAppPurchasesWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listIAPTool(),
            getIAPTool(),
            createIAPTool(),
            updateIAPTool(),
            deleteIAPTool(),
            listIAPLocalizationsTool(),
            createIAPLocalizationTool(),
            updateIAPLocalizationTool(),
            deleteIAPLocalizationTool(),
            submitIAPForReviewTool(),
            listSubscriptionGroupsTool(),
            getSubscriptionGroupTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "iap_list":
            return try await listIAP(params)
        case "iap_get":
            return try await getIAP(params)
        case "iap_create":
            return try await createIAP(params)
        case "iap_update":
            return try await updateIAP(params)
        case "iap_delete":
            return try await deleteIAP(params)
        case "iap_list_localizations":
            return try await listIAPLocalizations(params)
        case "iap_create_localization":
            return try await createIAPLocalization(params)
        case "iap_update_localization":
            return try await updateIAPLocalization(params)
        case "iap_delete_localization":
            return try await deleteIAPLocalization(params)
        case "iap_submit_for_review":
            return try await submitIAPForReview(params)
        case "iap_list_subscriptions":
            return try await listSubscriptionGroups(params)
        case "iap_get_subscription_group":
            return try await getSubscriptionGroup(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
