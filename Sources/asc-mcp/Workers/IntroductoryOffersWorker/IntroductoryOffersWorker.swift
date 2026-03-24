import Foundation
import MCP

/// IntroductoryOffersWorker manages introductory offers (free trials, pay-as-you-go, pay-up-front)
/// for auto-renewable subscriptions in App Store Connect
public final class IntroductoryOffersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listIntroductoryOffersTool(),
            createIntroductoryOfferTool(),
            updateIntroductoryOfferTool(),
            deleteIntroductoryOfferTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "intro_offers_list":
            return try await listIntroductoryOffers(params)
        case "intro_offers_create":
            return try await createIntroductoryOffer(params)
        case "intro_offers_update":
            return try await updateIntroductoryOffer(params)
        case "intro_offers_delete":
            return try await deleteIntroductoryOffer(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
