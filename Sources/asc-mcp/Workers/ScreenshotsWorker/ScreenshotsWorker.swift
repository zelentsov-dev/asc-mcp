import Foundation
import MCP

/// ScreenshotsWorker manages screenshots and app previews in App Store Connect
public final class ScreenshotsWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listScreenshotSetsTool(),
            createScreenshotSetTool(),
            deleteScreenshotSetTool(),
            listScreenshotsTool(),
            createScreenshotTool(),
            deleteScreenshotTool(),
            reorderScreenshotsTool(),
            listPreviewSetsTool(),
            createPreviewSetTool(),
            deletePreviewSetTool(),
            createPreviewTool(),
            deletePreviewTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "screenshots_list_sets":
            return try await listScreenshotSets(params)
        case "screenshots_create_set":
            return try await createScreenshotSet(params)
        case "screenshots_delete_set":
            return try await deleteScreenshotSet(params)
        case "screenshots_list":
            return try await listScreenshots(params)
        case "screenshots_create":
            return try await createScreenshot(params)
        case "screenshots_delete":
            return try await deleteScreenshot(params)
        case "screenshots_reorder":
            return try await reorderScreenshots(params)
        case "screenshots_list_preview_sets":
            return try await listPreviewSets(params)
        case "screenshots_create_preview_set":
            return try await createPreviewSet(params)
        case "screenshots_delete_preview_set":
            return try await deletePreviewSet(params)
        case "screenshots_create_preview":
            return try await createPreview(params)
        case "screenshots_delete_preview":
            return try await deletePreview(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
