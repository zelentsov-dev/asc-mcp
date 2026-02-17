import Foundation
import MCP

/// CustomProductPagesWorker manages custom product pages in App Store Connect
public final class CustomProductPagesWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listCustomPagesTool(),
            getCustomPageTool(),
            createCustomPageTool(),
            updateCustomPageTool(),
            deleteCustomPageTool(),
            listVersionsTool(),
            createVersionTool(),
            listLocalizationsTool(),
            createLocalizationTool(),
            updateLocalizationTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "custom_pages_list":
            return try await listCustomPages(params)
        case "custom_pages_get":
            return try await getCustomPage(params)
        case "custom_pages_create":
            return try await createCustomPage(params)
        case "custom_pages_update":
            return try await updateCustomPage(params)
        case "custom_pages_delete":
            return try await deleteCustomPage(params)
        case "custom_pages_list_versions":
            return try await listVersions(params)
        case "custom_pages_create_version":
            return try await createVersion(params)
        case "custom_pages_list_localizations":
            return try await listLocalizations(params)
        case "custom_pages_create_localization":
            return try await createLocalization(params)
        case "custom_pages_update_localization":
            return try await updateLocalization(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
