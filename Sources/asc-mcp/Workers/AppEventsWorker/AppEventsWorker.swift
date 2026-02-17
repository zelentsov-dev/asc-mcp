import Foundation
import MCP

/// AppEventsWorker manages in-app events for App Store featuring
public final class AppEventsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listAppEventsTool(),
            getAppEventTool(),
            createAppEventTool(),
            updateAppEventTool(),
            deleteAppEventTool(),
            listAppEventLocalizationsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "app_events_list":
            return try await listAppEvents(params)
        case "app_events_get":
            return try await getAppEvent(params)
        case "app_events_create":
            return try await createAppEvent(params)
        case "app_events_update":
            return try await updateAppEvent(params)
        case "app_events_delete":
            return try await deleteAppEvent(params)
        case "app_events_list_localizations":
            return try await listAppEventLocalizations(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
