import Foundation
import MCP

/// BetaLicenseAgreementsWorker manages beta license agreements for TestFlight apps
/// in App Store Connect
public final class BetaLicenseAgreementsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listBetaLicenseAgreementsTool(),
            getBetaLicenseAgreementTool(),
            updateBetaLicenseAgreementTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "beta_license_list":
            return try await listBetaLicenseAgreements(params)
        case "beta_license_get":
            return try await getBetaLicenseAgreement(params)
        case "beta_license_update":
            return try await updateBetaLicenseAgreement(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
