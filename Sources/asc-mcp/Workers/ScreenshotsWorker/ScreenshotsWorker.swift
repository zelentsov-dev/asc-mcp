import Foundation
import MCP

/// ScreenshotsWorker manages screenshots and app previews in App Store Connect
public final class ScreenshotsWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService

    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listScreenshotSetsTool(),
            createScreenshotSetTool(),
            deleteScreenshotSetTool(),
            listScreenshotsTool(),
            uploadScreenshotTool(),
            getScreenshotTool(),
            deleteScreenshotTool(),
            reorderScreenshotsTool(),
            listPreviewSetsTool(),
            createPreviewSetTool(),
            deletePreviewSetTool(),
            uploadPreviewTool(),
            getPreviewTool(),
            listPreviewsTool(),
            deletePreviewTool(),
            uploadScreenshotBatchTool(),
            updatePreviewTool()
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
        case "screenshots_upload":
            return try await uploadScreenshot(params)
        case "screenshots_get":
            return try await getScreenshot(params)
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
        case "screenshots_upload_preview":
            return try await uploadPreview(params)
        case "screenshots_get_preview":
            return try await getPreview(params)
        case "screenshots_list_previews":
            return try await listPreviews(params)
        case "screenshots_delete_preview":
            return try await deletePreview(params)
        case "screenshots_upload_batch":
            return try await uploadScreenshotBatch(params)
        case "screenshots_update_preview":
            return try await updatePreview(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
