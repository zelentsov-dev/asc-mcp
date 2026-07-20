import Foundation
import MCP

/// SubscriptionsWorker manages auto-renewable subscriptions, subscription groups,
/// localizations, prices, and submission in App Store Connect
public final class SubscriptionsWorker: Sendable {
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
    static let subscriptionCatalogSortValues = ["name", "-name"]
    static let subscriptionGroupSortValues = ["referenceName", "-referenceName"]
    static let subscriptionVersionStates = [
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
            listSubscriptionsTool(),
            getSubscriptionTool(),
            createSubscriptionTool(),
            updateSubscriptionTool(),
            deleteSubscriptionTool(),
            listSubscriptionLocalizationsTool(),
            createSubscriptionLocalizationTool(),
            updateSubscriptionLocalizationTool(),
            deleteSubscriptionLocalizationTool(),
            listSubscriptionPricesTool(),
            listSubscriptionPricePointsTool(),
            createSubscriptionGroupTool(),
            updateSubscriptionGroupTool(),
            deleteSubscriptionGroupTool(),
            submitSubscriptionTool(),
            listSubscriptionGroupLocalizationsTool(),
            createSubscriptionGroupLocalizationTool(),
            getSubscriptionGroupLocalizationTool(),
            updateSubscriptionGroupLocalizationTool(),
            deleteSubscriptionGroupLocalizationTool(),
            deleteSubscriptionPriceTool(),
            uploadSubscriptionImageTool(),
            getSubscriptionImageTool(),
            deleteSubscriptionImageTool(),
            uploadSubscriptionReviewScreenshotTool(),
            getSubscriptionReviewScreenshotTool(),
            deleteSubscriptionReviewScreenshotTool(),
            listSubscriptionImagesTool(),
            getSubscriptionReviewScreenshotForSubscriptionTool()
        ] + v3CommerceTools() + subscriptionPlanAvailabilityTools() + versionedMetadataTools()
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "subscriptions_list":
            return try await listSubscriptions(params)
        case "subscriptions_get":
            return try await getSubscription(params)
        case "subscriptions_create":
            return try await createSubscription(params)
        case "subscriptions_update":
            return try await updateSubscription(params)
        case "subscriptions_delete":
            return try await deleteSubscription(params)
        case "subscriptions_list_localizations":
            return legacySubscriptionResult(
                try await listSubscriptionLocalizations(params),
                tool: params.name
            )
        case "subscriptions_create_localization":
            return legacySubscriptionResult(
                try await createSubscriptionLocalization(params),
                tool: params.name
            )
        case "subscriptions_update_localization":
            return legacySubscriptionResult(
                try await updateSubscriptionLocalization(params),
                tool: params.name
            )
        case "subscriptions_delete_localization":
            return legacySubscriptionResult(
                try await deleteSubscriptionLocalization(params),
                tool: params.name
            )
        case "subscriptions_list_prices":
            return try await listSubscriptionPrices(params)
        case "subscriptions_list_price_points":
            return try await listSubscriptionPricePoints(params)
        case "subscriptions_create_group":
            return try await createSubscriptionGroup(params)
        case "subscriptions_update_group":
            return try await updateSubscriptionGroup(params)
        case "subscriptions_delete_group":
            return try await deleteSubscriptionGroup(params)
        case "subscriptions_submit":
            return legacySubscriptionResult(
                try await submitSubscription(params),
                tool: params.name
            )
        case "subscriptions_list_group_localizations":
            return legacySubscriptionResult(
                try await listSubscriptionGroupLocalizations(params),
                tool: params.name
            )
        case "subscriptions_create_group_localization":
            return legacySubscriptionResult(
                try await createSubscriptionGroupLocalization(params),
                tool: params.name
            )
        case "subscriptions_get_group_localization":
            return legacySubscriptionResult(
                try await getSubscriptionGroupLocalization(params),
                tool: params.name
            )
        case "subscriptions_update_group_localization":
            return legacySubscriptionResult(
                try await updateSubscriptionGroupLocalization(params),
                tool: params.name
            )
        case "subscriptions_delete_group_localization":
            return legacySubscriptionResult(
                try await deleteSubscriptionGroupLocalization(params),
                tool: params.name
            )
        case "subscriptions_delete_price":
            return try await deleteSubscriptionPrice(params)
        case "subscriptions_upload_image":
            return legacySubscriptionResult(
                try await uploadSubscriptionImage(params),
                tool: params.name
            )
        case "subscriptions_get_image":
            return legacySubscriptionResult(
                try await getSubscriptionImage(params),
                tool: params.name
            )
        case "subscriptions_delete_image":
            return legacySubscriptionResult(
                try await deleteSubscriptionImage(params),
                tool: params.name
            )
        case "subscriptions_upload_review_screenshot":
            return try await uploadSubscriptionReviewScreenshot(params)
        case "subscriptions_get_review_screenshot":
            return try await getSubscriptionReviewScreenshot(params)
        case "subscriptions_delete_review_screenshot":
            return try await deleteSubscriptionReviewScreenshot(params)
        case "subscriptions_list_images":
            return legacySubscriptionResult(
                try await listSubscriptionImages(params),
                tool: params.name
            )
        case "subscriptions_get_review_screenshot_for_subscription":
            return try await getSubscriptionReviewScreenshotForSubscription(params)
        case "subscriptions_list_groups":
            return try await listSubscriptionGroups(params)
        case "subscriptions_get_group":
            return try await getSubscriptionGroup(params)
        case "subscriptions_submit_group":
            return legacySubscriptionResult(
                try await submitSubscriptionGroup(params),
                tool: params.name
            )
        case "subscriptions_get_localization":
            return legacySubscriptionResult(
                try await getSubscriptionLocalization(params),
                tool: params.name
            )
        case "subscriptions_create_price":
            return try await createSubscriptionPrice(params)
        case "subscriptions_get_price_point":
            return try await getSubscriptionPricePoint(params)
        case "subscriptions_list_price_point_equalizations":
            return try await listSubscriptionPricePointEqualizations(params)
        case "subscriptions_list_price_point_adjusted_equalizations":
            return try await listSubscriptionPricePointAdjustedEqualizations(params)
        case "subscriptions_get_availability":
            return try await getSubscriptionAvailability(params)
        case "subscriptions_set_availability":
            return try await setSubscriptionAvailability(params)
        case "subscriptions_list_available_territories":
            return try await listSubscriptionAvailableTerritories(params)
        case "subscriptions_create_plan_availability":
            return try await createSubscriptionPlanAvailability(params)
        case "subscriptions_get_plan_availability":
            return try await getSubscriptionPlanAvailability(params)
        case "subscriptions_update_plan_availability":
            return try await updateSubscriptionPlanAvailability(params)
        case "subscriptions_list_plan_availabilities":
            return try await listSubscriptionPlanAvailabilities(params)
        case "subscriptions_list_plan_availability_territories":
            return try await listSubscriptionPlanAvailabilityTerritories(params)
        case "subscriptions_get_promoted_purchase":
            return try await getSubscriptionPromotedPurchase(params)
        case "subscriptions_inventory":
            return try await getSubscriptionsInventory(params)
        case "subscriptions_pricing_summary":
            return try await getSubscriptionPricingSummary(params)
        case "subscriptions_prepare_offer_prices":
            return try await prepareSubscriptionOfferPrices(params)
        case "subscriptions_create_version":
            return try await createSubscriptionVersion(params)
        case "subscriptions_get_version":
            return try await getSubscriptionVersion(params)
        case "subscriptions_list_versions":
            return try await listSubscriptionVersions(params)
        case "subscriptions_list_version_localizations":
            return try await listSubscriptionVersionLocalizations(params)
        case "subscriptions_create_version_localization":
            return try await createSubscriptionVersionLocalization(params)
        case "subscriptions_get_version_localization":
            return try await getSubscriptionVersionLocalization(params)
        case "subscriptions_update_version_localization":
            return try await updateSubscriptionVersionLocalization(params)
        case "subscriptions_delete_version_localization":
            return try await deleteSubscriptionVersionLocalization(params)
        case "subscriptions_list_version_images":
            return try await listSubscriptionVersionImages(params)
        case "subscriptions_upload_version_image":
            return try await uploadSubscriptionVersionImage(params)
        case "subscriptions_get_version_image":
            return try await getSubscriptionVersionImage(params)
        case "subscriptions_delete_version_image":
            return try await deleteSubscriptionVersionImage(params)
        case "subscriptions_create_group_version":
            return try await createSubscriptionGroupVersion(params)
        case "subscriptions_get_group_version":
            return try await getSubscriptionGroupVersion(params)
        case "subscriptions_list_group_versions":
            return try await listSubscriptionGroupVersions(params)
        case "subscriptions_list_group_version_localizations":
            return try await listSubscriptionGroupVersionLocalizations(params)
        case "subscriptions_create_group_version_localization":
            return try await createSubscriptionGroupVersionLocalization(params)
        case "subscriptions_get_group_version_localization":
            return try await getSubscriptionGroupVersionLocalization(params)
        case "subscriptions_update_group_version_localization":
            return try await updateSubscriptionGroupVersionLocalization(params)
        case "subscriptions_delete_group_version_localization":
            return try await deleteSubscriptionGroupVersionLocalization(params)
        case "subscriptions_list_intro_offers",
            "subscriptions_create_intro_offer",
            "subscriptions_update_intro_offer",
            "subscriptions_delete_intro_offer",
            "subscriptions_list_promotional_offers",
            "subscriptions_get_promotional_offer",
            "subscriptions_create_promotional_offer",
            "subscriptions_update_promotional_offer",
            "subscriptions_delete_promotional_offer",
            "subscriptions_list_promotional_offer_prices",
            "subscriptions_list_offer_codes",
            "subscriptions_get_offer_code",
            "subscriptions_create_offer_code",
            "subscriptions_update_offer_code",
            "subscriptions_deactivate_offer_code",
            "subscriptions_list_offer_code_prices",
            "subscriptions_generate_one_time_codes",
            "subscriptions_list_one_time_codes",
            "subscriptions_get_one_time_code",
            "subscriptions_get_one_time_code_values",
            "subscriptions_create_custom_code",
            "subscriptions_get_custom_code",
            "subscriptions_update_custom_code",
            "subscriptions_deactivate_custom_code",
            "subscriptions_list_winback_offers",
            "subscriptions_get_winback_offer",
            "subscriptions_create_winback_offer",
            "subscriptions_update_winback_offer",
            "subscriptions_delete_winback_offer",
            "subscriptions_list_winback_offer_prices":
            return try await forwardSubscriptionCommerceTool(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
