import Foundation
import MCP

/// OfferCodesWorker manages subscription offer codes and one-time use codes
/// in App Store Connect
public final class OfferCodesWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listOfferCodesTool(),
            createOfferCodeTool(),
            updateOfferCodeTool(),
            deactivateOfferCodeTool(),
            listOfferCodePricesTool(),
            generateOneTimeCodesTool(),
            listOneTimeCodesTool(),
            createCustomCodeTool(),
            getCustomCodeTool(),
            deactivateCustomCodeTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "offer_codes_list":
            return try await listOfferCodes(params)
        case "offer_codes_create":
            return try await createOfferCode(params)
        case "offer_codes_update":
            return try await updateOfferCode(params)
        case "offer_codes_deactivate":
            return try await deactivateOfferCode(params)
        case "offer_codes_list_prices":
            return try await listOfferCodePrices(params)
        case "offer_codes_generate_one_time":
            return try await generateOneTimeCodes(params)
        case "offer_codes_list_one_time":
            return try await listOneTimeCodes(params)
        case "offer_codes_create_custom_code":
            return try await createCustomCode(params)
        case "offer_codes_get_custom_code":
            return try await getCustomCode(params)
        case "offer_codes_deactivate_custom_code":
            return try await deactivateCustomCode(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
