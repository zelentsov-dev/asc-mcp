import Foundation
import MCP

/// BetaAppWorker manages beta app localizations, review submissions, and review details
/// for TestFlight apps in App Store Connect
public final class BetaAppWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listLocalizationsTool(),
            createLocalizationTool(),
            getLocalizationTool(),
            updateLocalizationTool(),
            deleteLocalizationTool(),
            submitForReviewTool(),
            listSubmissionsTool(),
            getSubmissionTool(),
            getReviewDetailsTool(),
            updateReviewDetailsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "beta_app_list_localizations":
            return try await listLocalizations(params)
        case "beta_app_create_localization":
            return try await createLocalization(params)
        case "beta_app_get_localization":
            return try await getLocalization(params)
        case "beta_app_update_localization":
            return try await updateLocalization(params)
        case "beta_app_delete_localization":
            return try await deleteLocalization(params)
        case "beta_app_submit_for_review":
            return try await submitForReview(params)
        case "beta_app_list_submissions":
            return try await listSubmissions(params)
        case "beta_app_get_submission":
            return try await getSubmission(params)
        case "beta_app_get_review_details":
            return try await getReviewDetails(params)
        case "beta_app_update_review_details":
            return try await updateReviewDetails(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
