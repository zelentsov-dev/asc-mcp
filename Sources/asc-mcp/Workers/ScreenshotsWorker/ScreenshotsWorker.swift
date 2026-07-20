import Foundation
import MCP

/// ScreenshotsWorker manages screenshots and app previews in App Store Connect
public final class ScreenshotsWorker: Sendable {
    static let screenshotDisplayTypes = [
        "APP_IPHONE_67",
        "APP_IPHONE_61",
        "APP_IPHONE_65",
        "APP_IPHONE_58",
        "APP_IPHONE_55",
        "APP_IPHONE_47",
        "APP_IPHONE_40",
        "APP_IPHONE_35",
        "APP_IPAD_PRO_3GEN_129",
        "APP_IPAD_PRO_3GEN_11",
        "APP_IPAD_PRO_129",
        "APP_IPAD_105",
        "APP_IPAD_97",
        "APP_DESKTOP",
        "APP_WATCH_ULTRA",
        "APP_WATCH_SERIES_10",
        "APP_WATCH_SERIES_7",
        "APP_WATCH_SERIES_4",
        "APP_WATCH_SERIES_3",
        "APP_APPLE_TV",
        "APP_APPLE_VISION_PRO",
        "IMESSAGE_APP_IPHONE_67",
        "IMESSAGE_APP_IPHONE_61",
        "IMESSAGE_APP_IPHONE_65",
        "IMESSAGE_APP_IPHONE_58",
        "IMESSAGE_APP_IPHONE_55",
        "IMESSAGE_APP_IPHONE_47",
        "IMESSAGE_APP_IPHONE_40",
        "IMESSAGE_APP_IPAD_PRO_3GEN_129",
        "IMESSAGE_APP_IPAD_PRO_3GEN_11",
        "IMESSAGE_APP_IPAD_PRO_129",
        "IMESSAGE_APP_IPAD_105",
        "IMESSAGE_APP_IPAD_97"
    ]

    static let previewTypes = [
        "IPHONE_67",
        "IPHONE_61",
        "IPHONE_65",
        "IPHONE_58",
        "IPHONE_55",
        "IPHONE_47",
        "IPHONE_40",
        "IPHONE_35",
        "IPAD_PRO_3GEN_129",
        "IPAD_PRO_3GEN_11",
        "IPAD_PRO_129",
        "IPAD_105",
        "IPAD_97",
        "DESKTOP",
        "APPLE_TV",
        "APPLE_VISION_PRO"
    ]

    let httpClient: HTTPClient
    let uploadService: UploadService
    let deliveryPollAttempts: Int
    let deliveryPollIntervalNanoseconds: UInt64

    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.deliveryPollAttempts = 10
        self.deliveryPollIntervalNanoseconds = 1_000_000_000
    }

    init(
        httpClient: HTTPClient,
        uploadService: UploadService,
        deliveryPollAttempts: Int,
        deliveryPollIntervalNanoseconds: UInt64
    ) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.deliveryPollAttempts = max(1, deliveryPollAttempts)
        self.deliveryPollIntervalNanoseconds = deliveryPollIntervalNanoseconds
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
            uploadScreenshotBatchTool()
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
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
