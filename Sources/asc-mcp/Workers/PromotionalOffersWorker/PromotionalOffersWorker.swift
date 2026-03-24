import Foundation
import MCP

/// PromotionalOffersWorker manages promotional offers for auto-renewable subscriptions
/// in App Store Connect
public final class PromotionalOffersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listPromotionalOffersTool(),
            getPromotionalOfferTool(),
            createPromotionalOfferTool(),
            updatePromotionalOfferTool(),
            deletePromotionalOfferTool(),
            listPromotionalOfferPricesTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "promo_offers_list":
            return try await listPromotionalOffers(params)
        case "promo_offers_get":
            return try await getPromotionalOffer(params)
        case "promo_offers_create":
            return try await createPromotionalOffer(params)
        case "promo_offers_update":
            return try await updatePromotionalOffer(params)
        case "promo_offers_delete":
            return try await deletePromotionalOffer(params)
        case "promo_offers_list_prices":
            return try await listPromotionalOfferPrices(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
