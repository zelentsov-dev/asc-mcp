import Foundation
import MCP

/// InAppPurchasesWorker manages IAP and subscriptions in App Store Connect
public final class InAppPurchasesWorker: Sendable {
    static let iapCatalogStates = [
        "MISSING_METADATA",
        "WAITING_FOR_UPLOAD",
        "PROCESSING_CONTENT",
        "READY_TO_SUBMIT",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "DEVELOPER_ACTION_NEEDED",
        "PENDING_BINARY_APPROVAL",
        "APPROVED",
        "DEVELOPER_REMOVED_FROM_SALE",
        "REMOVED_FROM_SALE",
        "REJECTED"
    ]
    static let iapCatalogTypes = [
        "CONSUMABLE",
        "NON_CONSUMABLE",
        "NON_RENEWING_SUBSCRIPTION"
    ]
    static let iapCatalogSortValues = ["name", "-name", "inAppPurchaseType", "-inAppPurchaseType"]
    static let iapVersionStates = [
        "PREPARE_FOR_SUBMISSION",
        "READY_FOR_REVIEW",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "ACCEPTED",
        "APPROVED",
        "REPLACED_WITH_NEW_VERSION",
        "REJECTED",
        "DEVELOPER_REJECTED"
    ]
    static let subscriptionCatalogStates = [
        "MISSING_METADATA",
        "READY_TO_SUBMIT",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "DEVELOPER_ACTION_NEEDED",
        "PENDING_BINARY_APPROVAL",
        "APPROVED",
        "DEVELOPER_REMOVED_FROM_SALE",
        "REMOVED_FROM_SALE",
        "REJECTED"
    ]
    static let subscriptionGroupSortValues = ["referenceName", "-referenceName"]
    private static let versionedArgumentNames: [String: Set<String>] = [
        "iap_create_version": ["iap_id"],
        "iap_get_version": ["version_id"],
        "iap_list_versions": ["iap_id", "filter_state", "limit", "next_url"],
        "iap_list_version_localizations": ["version_id", "limit", "next_url"],
        "iap_create_version_localization": ["version_id", "locale", "name", "description"],
        "iap_get_version_localization": ["localization_id"],
        "iap_update_version_localization": ["localization_id", "name", "description"],
        "iap_delete_version_localization": ["localization_id", "confirm_localization_id"],
        "iap_get_version_image": ["version_id"],
        "iap_list_version_images": ["version_id", "limit", "next_url"],
        "iap_upload_version_image": ["version_id", "file_path"],
        "iap_get_version_image_resource": ["image_id"],
        "iap_delete_version_image": ["image_id", "confirm_image_id"]
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
            uploadIAPReviewScreenshotTool(),
            deleteIAPReviewScreenshotTool(),
            setIAPAvailabilityTool(),
            getIAPAvailabilityTool(),
            uploadIAPImageTool(),
            getIAPImageTool(),
            deleteIAPImageTool(),
            listIAPImagesTool()
        ] + v3CommerceTools() + versionedCommerceTools()
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let allowedNames = Self.versionedArgumentNames[params.name],
           let arguments = params.arguments {
            let unknownNames = Set(arguments.keys).subtracting(allowedNames).sorted()
            guard unknownNames.isEmpty else {
                return MCPResult.error(
                    "Unknown parameter(s) for \(params.name): \(unknownNames.joined(separator: ", "))"
                )
            }
        }

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
            return try await listIAPPricePointsV3(params)
        case "iap_get_price_schedule":
            return try await getIAPPriceSchedule(params)
        case "iap_set_price_schedule":
            return try await setIAPPriceSchedule(params)
        case "iap_list_price_point_equalizations":
            return try await listIAPPricePointEqualizations(params)
        case "iap_pricing_summary":
            return try await getIAPPricingSummary(params)
        case "iap_prepare_offer_prices":
            return try await prepareIAPOfferPrices(params)
        case "iap_inventory":
            return try await getIAPInventory(params)
        case "iap_get_promoted_purchase":
            return try await getIAPPromotedPurchase(params)
        case "iap_get_review_screenshot":
            return try await getIAPReviewScreenshot(params)
        case "iap_upload_review_screenshot":
            return try await uploadIAPReviewScreenshot(params)
        case "iap_delete_review_screenshot":
            return try await deleteIAPReviewScreenshot(params)
        case "iap_set_availability":
            return try await setIAPAvailability(params)
        case "iap_get_availability":
            return try await getIAPAvailabilityV3(params)
        case "iap_list_available_territories":
            return try await listIAPAvailableTerritories(params)
        case "iap_upload_image":
            return try await uploadIAPImage(params)
        case "iap_get_image":
            return try await getIAPImage(params)
        case "iap_delete_image":
            return try await deleteIAPImage(params)
        case "iap_list_images":
            return try await listIAPImages(params)
        case "iap_list_offer_codes":
            return try await listIAPOfferCodes(params)
        case "iap_get_offer_code":
            return try await getIAPOfferCode(params)
        case "iap_create_offer_code":
            return try await createIAPOfferCode(params)
        case "iap_update_offer_code":
            return try await updateIAPOfferCode(params)
        case "iap_deactivate_offer_code":
            return try await deactivateIAPOfferCode(params)
        case "iap_list_offer_code_prices":
            return try await listIAPOfferCodePrices(params)
        case "iap_generate_one_time_codes":
            return try await generateIAPOneTimeCodes(params)
        case "iap_list_one_time_codes":
            return try await listIAPOneTimeCodes(params)
        case "iap_get_one_time_code":
            return try await getIAPOneTimeCode(params)
        case "iap_update_one_time_code":
            return try await updateIAPOneTimeCode(params)
        case "iap_deactivate_one_time_code":
            return try await deactivateIAPOneTimeCode(params)
        case "iap_get_one_time_code_values":
            return try await getIAPOneTimeCodeValues(params)
        case "iap_create_custom_code":
            return try await createIAPCustomCode(params)
        case "iap_get_custom_code":
            return try await getIAPCustomCode(params)
        case "iap_update_custom_code":
            return try await updateIAPCustomCode(params)
        case "iap_deactivate_custom_code":
            return try await deactivateIAPCustomCode(params)
        case "iap_create_version":
            return try await createIAPVersion(params)
        case "iap_get_version":
            return try await getIAPVersion(params)
        case "iap_list_versions":
            return try await listIAPVersions(params)
        case "iap_list_version_localizations":
            return try await listIAPVersionLocalizations(params)
        case "iap_create_version_localization":
            return try await createIAPVersionLocalization(params)
        case "iap_get_version_localization":
            return try await getIAPVersionLocalization(params)
        case "iap_update_version_localization":
            return try await updateIAPVersionLocalization(params)
        case "iap_delete_version_localization":
            return try await deleteIAPVersionLocalization(params)
        case "iap_get_version_image":
            return try await getIAPVersionImage(params)
        case "iap_list_version_images":
            return try await listIAPVersionImages(params)
        case "iap_upload_version_image":
            return try await uploadIAPVersionImage(params)
        case "iap_get_version_image_resource":
            return try await getIAPVersionImageResource(params)
        case "iap_delete_version_image":
            return try await deleteIAPVersionImage(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
