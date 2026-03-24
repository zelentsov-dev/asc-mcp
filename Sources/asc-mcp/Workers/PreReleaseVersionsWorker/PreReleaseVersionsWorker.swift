import Foundation
import MCP

/// PreReleaseVersionsWorker manages pre-release versions (TestFlight versions)
/// in App Store Connect
public final class PreReleaseVersionsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listPreReleaseVersionsTool(),
            getPreReleaseVersionTool(),
            listPreReleaseVersionBuildsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "pre_release_list":
            return try await listPreReleaseVersions(params)
        case "pre_release_get":
            return try await getPreReleaseVersion(params)
        case "pre_release_list_builds":
            return try await listPreReleaseVersionBuilds(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
