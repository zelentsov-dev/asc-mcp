import Foundation
import MCP

/// BuildsWorker manages app builds in App Store Connect
public final class BuildsWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listBuildsTool(),
            getBuildTool(),
            findBuildByNumberTool(),
            listBuildsForVersionTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "builds_list":
            return try await listBuilds(params)
        case "builds_get":
            return try await getBuild(params)
        case "builds_find_by_number":
            return try await findBuildByNumber(params)
        case "builds_list_for_version":
            return try await listBuildsForVersion(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}