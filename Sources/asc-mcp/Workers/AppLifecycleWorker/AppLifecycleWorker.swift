import Foundation
import MCP

/// AppLifecycleWorker manages app version lifecycle in App Store Connect
public final class AppLifecycleWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            createVersionTool(),
            listVersionsTool(),
            getVersionTool(),
            updateVersionTool(),
            attachBuildTool(),
            submitForReviewTool(),
            cancelReviewTool(),
            createPhasedReleaseTool(),
            getPhasedReleaseTool(),
            updatePhasedReleaseTool(),
            releaseVersionTool(),
            setReviewDetailsTool(),
            updateAgeRatingTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "app_versions_create":
            return try await createVersion(params)
        case "app_versions_list":
            return try await listVersions(params)
        case "app_versions_get":
            return try await getVersion(params)
        case "app_versions_update":
            return try await updateVersion(params)
        case "app_versions_attach_build":
            return try await attachBuild(params)
        case "app_versions_submit_for_review":
            return try await submitForReview(params)
        case "app_versions_cancel_review":
            return try await cancelReview(params)
        case "app_versions_create_phased_release":
            return try await createPhasedRelease(params)
        case "app_versions_get_phased_release":
            return try await getPhasedRelease(params)
        case "app_versions_update_phased_release":
            return try await updatePhasedRelease(params)
        case "app_versions_release":
            return try await releaseVersion(params)
        case "app_versions_set_review_details":
            return try await setReviewDetails(params)
        case "app_versions_update_age_rating":
            return try await updateAgeRating(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}