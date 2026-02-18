import Foundation
import MCP

/// Manages apps in App Store Connect
public final class AppsWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(
        client: HTTPClient
    ) {
        self.httpClient = client
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listAppsTool(),
            getAppDetailsTool(),
            searchAppsTool(),
            listVersionsTool(),
            getAppMetadataTool(),
            updateMetadataTool(),
            createLocalizationTool(),
            deleteLocalizationTool(),
            listLocalizationsTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "apps_list":
            return try await self.listApps(params)
        case "apps_get_details":
            return try await self.getAppDetails(params)
        case "apps_search":
            return try await self.searchApps(params)
        case "apps_list_versions":
            return try await self.listAppVersions(params)
        case "apps_get_metadata":
            return try await self.getAppMetadata(params)
        case "apps_update_metadata":
            return try await self.updateMetadata(params)
        case "apps_create_localization":
            return try await self.createLocalization(params)
        case "apps_delete_localization":
            return try await self.deleteLocalization(params)
        case "apps_list_localizations":
            return try await self.listLocalizations(params)
        default:
            throw MCPError.methodNotFound("Unknown tool")
        }
    }
}
