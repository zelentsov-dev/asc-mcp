import Foundation
import MCP

/// InAppPurchasesWorker manages IAP and subscriptions in App Store Connect
public final class InAppPurchasesWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService

    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listIAPTool(),
            getIAPTool(),
            createIAPTool(),
            updateIAPTool(),
            deleteIAPTool(),
            listIAPLocalizationsTool(),
            createIAPLocalizationTool(),
            updateIAPLocalizationTool(),
            deleteIAPLocalizationTool(),
            submitIAPForReviewTool(),
            listSubscriptionGroupsTool(),
            getSubscriptionGroupTool(),
            listIAPPricePointsTool(),
            getIAPPriceScheduleTool(),
            setIAPPriceScheduleTool(),
            getIAPReviewScreenshotTool(),
            createIAPReviewScreenshotTool(),
            setIAPAvailabilityTool(),
            getIAPAvailabilityTool(),
            uploadIAPImageTool(),
            getIAPImageTool(),
            deleteIAPImageTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "iap_list":
            return try await listIAP(params)
        case "iap_get":
            return try await getIAP(params)
        case "iap_create":
            return try await createIAP(params)
        case "iap_update":
            return try await updateIAP(params)
        case "iap_delete":
            return try await deleteIAP(params)
        case "iap_list_localizations":
            return try await listIAPLocalizations(params)
        case "iap_create_localization":
            return try await createIAPLocalization(params)
        case "iap_update_localization":
            return try await updateIAPLocalization(params)
        case "iap_delete_localization":
            return try await deleteIAPLocalization(params)
        case "iap_submit_for_review":
            return try await submitIAPForReview(params)
        case "iap_list_subscriptions":
            return try await listSubscriptionGroups(params)
        case "iap_get_subscription_group":
            return try await getSubscriptionGroup(params)
        case "iap_list_price_points":
            return try await listIAPPricePoints(params)
        case "iap_get_price_schedule":
            return try await getIAPPriceSchedule(params)
        case "iap_set_price_schedule":
            return try await setIAPPriceSchedule(params)
        case "iap_get_review_screenshot":
            return try await getIAPReviewScreenshot(params)
        case "iap_create_review_screenshot":
            return try await createIAPReviewScreenshot(params)
        case "iap_set_availability":
            return try await setIAPAvailability(params)
        case "iap_get_availability":
            return try await getIAPAvailability(params)
        case "iap_upload_image":
            return try await uploadIAPImage(params)
        case "iap_get_image":
            return try await getIAPImage(params)
        case "iap_delete_image":
            return try await deleteIAPImage(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
