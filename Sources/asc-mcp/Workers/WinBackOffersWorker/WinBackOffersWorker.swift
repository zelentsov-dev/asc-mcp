import Foundation
import MCP

/// WinBackOffersWorker manages win-back offers for auto-renewable subscriptions
/// in App Store Connect
public final class WinBackOffersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listWinBackOffersTool(),
            createWinBackOfferTool(),
            updateWinBackOfferTool(),
            deleteWinBackOfferTool(),
            listWinBackOfferPricesTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "winback_list":
            return try await listWinBackOffers(params)
        case "winback_create":
            return try await createWinBackOffer(params)
        case "winback_update":
            return try await updateWinBackOffer(params)
        case "winback_delete":
            return try await deleteWinBackOffer(params)
        case "winback_list_prices":
            return try await listWinBackOfferPrices(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
