import Foundation
import MCP

/// SubscriptionsWorker manages auto-renewable subscriptions, subscription groups,
/// localizations, prices, and submission in App Store Connect
public final class SubscriptionsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listSubscriptionsTool(),
            getSubscriptionTool(),
            createSubscriptionTool(),
            updateSubscriptionTool(),
            deleteSubscriptionTool(),
            listSubscriptionLocalizationsTool(),
            createSubscriptionLocalizationTool(),
            updateSubscriptionLocalizationTool(),
            deleteSubscriptionLocalizationTool(),
            listSubscriptionPricesTool(),
            listSubscriptionPricePointsTool(),
            createSubscriptionGroupTool(),
            updateSubscriptionGroupTool(),
            deleteSubscriptionGroupTool(),
            submitSubscriptionTool(),
            listSubscriptionGroupLocalizationsTool(),
            createSubscriptionGroupLocalizationTool(),
            getSubscriptionGroupLocalizationTool(),
            updateSubscriptionGroupLocalizationTool(),
            deleteSubscriptionGroupLocalizationTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "subscriptions_list":
            return try await listSubscriptions(params)
        case "subscriptions_get":
            return try await getSubscription(params)
        case "subscriptions_create":
            return try await createSubscription(params)
        case "subscriptions_update":
            return try await updateSubscription(params)
        case "subscriptions_delete":
            return try await deleteSubscription(params)
        case "subscriptions_list_localizations":
            return try await listSubscriptionLocalizations(params)
        case "subscriptions_create_localization":
            return try await createSubscriptionLocalization(params)
        case "subscriptions_update_localization":
            return try await updateSubscriptionLocalization(params)
        case "subscriptions_delete_localization":
            return try await deleteSubscriptionLocalization(params)
        case "subscriptions_list_prices":
            return try await listSubscriptionPrices(params)
        case "subscriptions_list_price_points":
            return try await listSubscriptionPricePoints(params)
        case "subscriptions_create_group":
            return try await createSubscriptionGroup(params)
        case "subscriptions_update_group":
            return try await updateSubscriptionGroup(params)
        case "subscriptions_delete_group":
            return try await deleteSubscriptionGroup(params)
        case "subscriptions_submit":
            return try await submitSubscription(params)
        case "subscriptions_list_group_localizations":
            return try await listSubscriptionGroupLocalizations(params)
        case "subscriptions_create_group_localization":
            return try await createSubscriptionGroupLocalization(params)
        case "subscriptions_get_group_localization":
            return try await getSubscriptionGroupLocalization(params)
        case "subscriptions_update_group_localization":
            return try await updateSubscriptionGroupLocalization(params)
        case "subscriptions_delete_group_localization":
            return try await deleteSubscriptionGroupLocalization(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
