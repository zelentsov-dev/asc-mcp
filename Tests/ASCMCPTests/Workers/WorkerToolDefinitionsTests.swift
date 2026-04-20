import Testing
import Foundation
import MCP
@testable import asc_mcp

@Suite("Worker Tool Definitions Tests")
struct WorkerToolDefinitionsTests {

    // MARK: - AppsWorker (9 tools)

    @Test("AppsWorker returns 9 tools with correct names")
    func appsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("apps_list"))
        #expect(names.contains("apps_get_details"))
        #expect(names.contains("apps_search"))
        #expect(names.contains("apps_list_versions"))
        #expect(names.contains("apps_get_metadata"))
        #expect(names.contains("apps_update_metadata"))
        #expect(names.contains("apps_create_localization"))
        #expect(names.contains("apps_delete_localization"))
        #expect(names.contains("apps_list_localizations"))
    }

    // MARK: - BuildsWorker (4 tools)

    @Test("BuildsWorker returns 4 tools with correct names")
    func buildsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 4)
        let names = Set(tools.map(\.name))
        #expect(names.contains("builds_list"))
        #expect(names.contains("builds_get"))
        #expect(names.contains("builds_find_by_number"))
        #expect(names.contains("builds_list_for_version"))
    }

    // MARK: - BuildProcessingWorker (4 tools)

    @Test("BuildProcessingWorker returns 4 tools with correct names")
    func buildProcessingWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildProcessingWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 4)
        let names = Set(tools.map(\.name))
        #expect(names.contains("builds_get_processing_state"))
        #expect(names.contains("builds_update_encryption"))
        #expect(names.contains("builds_get_processing_status"))
        #expect(names.contains("builds_check_readiness"))
    }

    // MARK: - BuildBetaDetailsWorker (8 tools)

    @Test("BuildBetaDetailsWorker returns 8 tools with correct names")
    func buildBetaDetailsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildBetaDetailsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 11)
        let names = Set(tools.map(\.name))
        #expect(names.contains("builds_get_beta_detail"))
        #expect(names.contains("builds_update_beta_detail"))
        #expect(names.contains("builds_set_beta_localization"))
        #expect(names.contains("builds_list_beta_localizations"))
    }

    // MARK: - AppLifecycleWorker (13 tools)

    @Test("AppLifecycleWorker returns 13 tools with correct names")
    func appLifecycleWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 14)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_versions_create"))
        #expect(names.contains("app_versions_list"))
        #expect(names.contains("app_versions_get"))
        #expect(names.contains("app_versions_update"))
        #expect(names.contains("app_versions_attach_build"))
        #expect(names.contains("app_versions_submit_for_review"))
        #expect(names.contains("app_versions_cancel_review"))
        #expect(names.contains("app_versions_get_phased_release"))
        #expect(names.contains("app_versions_release"))
    }

    // MARK: - ReviewsWorker (7 tools)

    @Test("ReviewsWorker returns 7 tools with correct names")
    func reviewsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 8)
        let names = Set(tools.map(\.name))
        #expect(names.contains("reviews_list"))
        #expect(names.contains("reviews_get"))
        #expect(names.contains("reviews_list_for_version"))
        #expect(names.contains("reviews_stats"))
        #expect(names.contains("reviews_create_response"))
        #expect(names.contains("reviews_delete_response"))
        #expect(names.contains("reviews_get_response"))
    }

    // MARK: - BetaGroupsWorker (9 tools)

    @Test("BetaGroupsWorker returns 9 tools with correct names")
    func betaGroupsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaGroupsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("beta_groups_list"))
        #expect(names.contains("beta_groups_create"))
        #expect(names.contains("beta_groups_update"))
        #expect(names.contains("beta_groups_delete"))
        #expect(names.contains("beta_groups_add_testers"))
        #expect(names.contains("beta_groups_remove_testers"))
        #expect(names.contains("beta_groups_list_testers"))
        #expect(names.contains("beta_groups_add_builds"))
        #expect(names.contains("beta_groups_remove_builds"))
    }

    // MARK: - InAppPurchasesWorker (22 tools)

    @Test("InAppPurchasesWorker returns 24 tools with correct names")
    func inAppPurchasesWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        #expect(tools.count == 24)
        let names = Set(tools.map(\.name))
        #expect(names.contains("iap_list"))
        #expect(names.contains("iap_get"))
        #expect(names.contains("iap_create"))
        #expect(names.contains("iap_update"))
        #expect(names.contains("iap_delete"))
        #expect(names.contains("iap_list_localizations"))
        #expect(names.contains("iap_create_localization"))
        #expect(names.contains("iap_update_localization"))
        #expect(names.contains("iap_delete_localization"))
        #expect(names.contains("iap_submit_for_review"))
        #expect(names.contains("iap_list_subscriptions"))
        #expect(names.contains("iap_get_subscription_group"))
        #expect(names.contains("iap_list_price_points"))
        #expect(names.contains("iap_get_price_schedule"))
        #expect(names.contains("iap_set_price_schedule"))
        #expect(names.contains("iap_get_review_screenshot"))
        #expect(names.contains("iap_upload_review_screenshot"))
        #expect(names.contains("iap_delete_review_screenshot"))
        #expect(names.contains("iap_set_availability"))
        #expect(names.contains("iap_get_availability"))
        #expect(names.contains("iap_upload_image"))
        #expect(names.contains("iap_get_image"))
        #expect(names.contains("iap_delete_image"))
        #expect(names.contains("iap_list_images"))
    }

    // MARK: - ProvisioningWorker (17 tools)

    @Test("ProvisioningWorker returns 17 tools with correct names")
    func provisioningWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 17)
        let names = Set(tools.map(\.name))
        #expect(names.contains("provisioning_list_bundle_ids"))
        #expect(names.contains("provisioning_get_bundle_id"))
        #expect(names.contains("provisioning_create_bundle_id"))
        #expect(names.contains("provisioning_delete_bundle_id"))
        #expect(names.contains("provisioning_list_devices"))
        #expect(names.contains("provisioning_register_device"))
        #expect(names.contains("provisioning_update_device"))
        #expect(names.contains("provisioning_list_certificates"))
        #expect(names.contains("provisioning_get_certificate"))
        #expect(names.contains("provisioning_revoke_certificate"))
        #expect(names.contains("provisioning_list_profiles"))
        #expect(names.contains("provisioning_get_profile"))
        #expect(names.contains("provisioning_delete_profile"))
        #expect(names.contains("provisioning_create_profile"))
        #expect(names.contains("provisioning_list_capabilities"))
        #expect(names.contains("provisioning_enable_capability"))
        #expect(names.contains("provisioning_disable_capability"))
    }

    // MARK: - BetaTestersWorker (6 tools)

    @Test("BetaTestersWorker returns 6 tools with correct names")
    func betaTestersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaTestersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 12)
        let names = Set(tools.map(\.name))
        #expect(names.contains("beta_testers_list"))
        #expect(names.contains("beta_testers_search"))
        #expect(names.contains("beta_testers_get"))
        #expect(names.contains("beta_testers_create"))
        #expect(names.contains("beta_testers_delete"))
        #expect(names.contains("beta_testers_list_apps"))
    }

    // MARK: - AppInfoWorker (7 tools)

    @Test("AppInfoWorker returns 7 tools with correct names")
    func appInfoWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_info_list"))
        #expect(names.contains("app_info_get"))
        #expect(names.contains("app_info_update"))
        #expect(names.contains("app_info_list_localizations"))
        #expect(names.contains("app_info_update_localization"))
        #expect(names.contains("app_info_create_localization"))
        #expect(names.contains("app_info_delete_localization"))
    }

    // MARK: - PricingWorker (9 tools)

    @Test("PricingWorker returns 9 tools with correct names")
    func pricingWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("pricing_list_territories"))
        #expect(names.contains("pricing_get_availability"))
        #expect(names.contains("pricing_list_price_points"))
        #expect(names.contains("pricing_get_price_schedule"))
        #expect(names.contains("pricing_set_price_schedule"))
        #expect(names.contains("pricing_list_territory_availability"))
        #expect(names.contains("pricing_create_availability"))
        #expect(names.contains("pricing_get_availability_v2"))
        #expect(names.contains("pricing_list_territory_availabilities"))
    }

    // MARK: - UsersWorker (7 tools)

    @Test("UsersWorker returns 7 tools with correct names")
    func usersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        let names = Set(tools.map(\.name))
        #expect(names.contains("users_list"))
        #expect(names.contains("users_get"))
        #expect(names.contains("users_update"))
        #expect(names.contains("users_remove"))
        #expect(names.contains("users_invite"))
        #expect(names.contains("users_list_invitations"))
        #expect(names.contains("users_cancel_invitation"))
    }

    // MARK: - AppEventsWorker (9 tools)

    @Test("AppEventsWorker returns 9 tools with correct names")
    func appEventsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_events_list"))
        #expect(names.contains("app_events_get"))
        #expect(names.contains("app_events_create"))
        #expect(names.contains("app_events_update"))
        #expect(names.contains("app_events_delete"))
        #expect(names.contains("app_events_list_localizations"))
        #expect(names.contains("app_events_create_localization"))
        #expect(names.contains("app_events_update_localization"))
        #expect(names.contains("app_events_delete_localization"))
    }

    // MARK: - AnalyticsWorker (11 tools)

    @Test("AnalyticsWorker returns 11 tools with correct names")
    func analyticsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 11)
        let names = Set(tools.map(\.name))
        #expect(names.contains("analytics_sales_report"))
        #expect(names.contains("analytics_app_summary"))
        #expect(names.contains("analytics_financial_report"))
        #expect(names.contains("analytics_list_report_requests"))
        #expect(names.contains("analytics_create_report_request"))
        #expect(names.contains("analytics_list_reports"))
        #expect(names.contains("analytics_get_report"))
        #expect(names.contains("analytics_list_instances"))
        #expect(names.contains("analytics_get_instance"))
        #expect(names.contains("analytics_list_segments"))
        #expect(names.contains("analytics_check_snapshot_status"))
    }

    // MARK: - SubscriptionsWorker (27 tools)

    @Test("SubscriptionsWorker returns 31 tools with correct names")
    func subscriptionsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = SubscriptionsWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        #expect(tools.count == 31)
        let names = Set(tools.map(\.name))
        #expect(names.contains("subscriptions_list"))
        #expect(names.contains("subscriptions_get"))
        #expect(names.contains("subscriptions_create"))
        #expect(names.contains("subscriptions_update"))
        #expect(names.contains("subscriptions_delete"))
        #expect(names.contains("subscriptions_list_localizations"))
        #expect(names.contains("subscriptions_create_localization"))
        #expect(names.contains("subscriptions_update_localization"))
        #expect(names.contains("subscriptions_delete_localization"))
        #expect(names.contains("subscriptions_list_prices"))
        #expect(names.contains("subscriptions_list_price_points"))
        #expect(names.contains("subscriptions_create_group"))
        #expect(names.contains("subscriptions_update_group"))
        #expect(names.contains("subscriptions_delete_group"))
        #expect(names.contains("subscriptions_submit"))
        #expect(names.contains("subscriptions_list_group_localizations"))
        #expect(names.contains("subscriptions_create_group_localization"))
        #expect(names.contains("subscriptions_get_group_localization"))
        #expect(names.contains("subscriptions_update_group_localization"))
        #expect(names.contains("subscriptions_delete_group_localization"))
        #expect(names.contains("subscriptions_delete_price"))
        #expect(names.contains("subscriptions_set_price"))
        #expect(names.contains("subscriptions_set_availability"))
        #expect(names.contains("subscriptions_upload_image"))
        #expect(names.contains("subscriptions_get_image"))
        #expect(names.contains("subscriptions_delete_image"))
        #expect(names.contains("subscriptions_upload_review_screenshot"))
        #expect(names.contains("subscriptions_get_review_screenshot"))
        #expect(names.contains("subscriptions_delete_review_screenshot"))
        #expect(names.contains("subscriptions_list_images"))
        #expect(names.contains("subscriptions_get_review_screenshot_for_subscription"))
    }

    // MARK: - OfferCodesWorker (7 tools)

    @Test("OfferCodesWorker returns 7 tools with correct names")
    func offerCodesWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = OfferCodesWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        let names = Set(tools.map(\.name))
        #expect(names.contains("offer_codes_list"))
        #expect(names.contains("offer_codes_create"))
        #expect(names.contains("offer_codes_update"))
        #expect(names.contains("offer_codes_deactivate"))
        #expect(names.contains("offer_codes_list_prices"))
        #expect(names.contains("offer_codes_generate_one_time"))
        #expect(names.contains("offer_codes_list_one_time"))
    }

    // MARK: - WinBackOffersWorker (5 tools)

    @Test("WinBackOffersWorker returns 5 tools with correct names")
    func winBackOffersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = WinBackOffersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 5)
        let names = Set(tools.map(\.name))
        #expect(names.contains("winback_list"))
        #expect(names.contains("winback_create"))
        #expect(names.contains("winback_update"))
        #expect(names.contains("winback_delete"))
        #expect(names.contains("winback_list_prices"))
    }

    // MARK: - IntroductoryOffersWorker (5 tools)

    @Test("IntroductoryOffersWorker returns 5 tools with correct names")
    func introductoryOffersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = IntroductoryOffersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 5)
        let names = Set(tools.map(\.name))
        #expect(names.contains("intro_offers_list"))
        #expect(names.contains("intro_offers_create"))
        #expect(names.contains("intro_offers_set_all_territories"))
        #expect(names.contains("intro_offers_update"))
        #expect(names.contains("intro_offers_delete"))
    }

    // MARK: - PromotionalOffersWorker (6 tools)

    @Test("PromotionalOffersWorker returns 6 tools with correct names")
    func promotionalOffersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PromotionalOffersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 6)
        let names = Set(tools.map(\.name))
        #expect(names.contains("promo_offers_list"))
        #expect(names.contains("promo_offers_get"))
        #expect(names.contains("promo_offers_create"))
        #expect(names.contains("promo_offers_update"))
        #expect(names.contains("promo_offers_delete"))
        #expect(names.contains("promo_offers_list_prices"))
    }

    // MARK: - SandboxTestersWorker (3 tools)

    @Test("SandboxTestersWorker returns 3 tools with correct names")
    func sandboxTestersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = SandboxTestersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 3)
        let names = Set(tools.map(\.name))
        #expect(names.contains("sandbox_list"))
        #expect(names.contains("sandbox_update"))
        #expect(names.contains("sandbox_clear_purchase_history"))
    }

    // MARK: - BetaAppWorker (10 tools)

    @Test("BetaAppWorker returns 10 tools with correct names")
    func betaAppWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaAppWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        let names = Set(tools.map(\.name))
        #expect(names.contains("beta_app_list_localizations"))
        #expect(names.contains("beta_app_create_localization"))
        #expect(names.contains("beta_app_get_localization"))
        #expect(names.contains("beta_app_update_localization"))
        #expect(names.contains("beta_app_delete_localization"))
        #expect(names.contains("beta_app_submit_for_review"))
        #expect(names.contains("beta_app_list_submissions"))
        #expect(names.contains("beta_app_get_submission"))
        #expect(names.contains("beta_app_get_review_details"))
        #expect(names.contains("beta_app_update_review_details"))
    }

    // MARK: - PreReleaseVersionsWorker (3 tools)

    @Test("PreReleaseVersionsWorker returns 3 tools with correct names")
    func preReleaseVersionsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PreReleaseVersionsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 3)
        let names = Set(tools.map(\.name))
        #expect(names.contains("pre_release_list"))
        #expect(names.contains("pre_release_get"))
        #expect(names.contains("pre_release_list_builds"))
    }

    // MARK: - BetaLicenseAgreementsWorker (3 tools)

    @Test("BetaLicenseAgreementsWorker returns 3 tools with correct names")
    func betaLicenseAgreementsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaLicenseAgreementsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 3)
        let names = Set(tools.map(\.name))
        #expect(names.contains("beta_license_list"))
        #expect(names.contains("beta_license_get"))
        #expect(names.contains("beta_license_update"))
    }

    // MARK: - ScreenshotsWorker (17 tools)

    @Test("ScreenshotsWorker returns 17 tools with correct names")
    func screenshotsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ScreenshotsWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        #expect(tools.count == 17)
        let names = Set(tools.map(\.name))
        #expect(names.contains("screenshots_list_sets"))
        #expect(names.contains("screenshots_create_set"))
        #expect(names.contains("screenshots_delete_set"))
        #expect(names.contains("screenshots_list"))
        #expect(names.contains("screenshots_upload"))
        #expect(names.contains("screenshots_get"))
        #expect(names.contains("screenshots_delete"))
        #expect(names.contains("screenshots_reorder"))
        #expect(names.contains("screenshots_list_preview_sets"))
        #expect(names.contains("screenshots_create_preview_set"))
        #expect(names.contains("screenshots_delete_preview_set"))
        #expect(names.contains("screenshots_upload_preview"))
        #expect(names.contains("screenshots_get_preview"))
        #expect(names.contains("screenshots_list_previews"))
        #expect(names.contains("screenshots_delete_preview"))
        #expect(names.contains("screenshots_upload_batch"))
        #expect(names.contains("screenshots_update_preview"))
    }

    // MARK: - CustomProductPagesWorker (10 tools)

    @Test("CustomProductPagesWorker returns 10 tools with correct names")
    func customProductPagesWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = CustomProductPagesWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        let names = Set(tools.map(\.name))
        #expect(names.contains("custom_pages_list"))
        #expect(names.contains("custom_pages_get"))
        #expect(names.contains("custom_pages_create"))
        #expect(names.contains("custom_pages_update"))
        #expect(names.contains("custom_pages_delete"))
        #expect(names.contains("custom_pages_list_versions"))
        #expect(names.contains("custom_pages_create_version"))
        #expect(names.contains("custom_pages_list_localizations"))
        #expect(names.contains("custom_pages_create_localization"))
        #expect(names.contains("custom_pages_update_localization"))
    }

    // MARK: - ProductPageOptimizationWorker (9 tools)

    @Test("ProductPageOptimizationWorker returns 9 tools with correct names")
    func productPageOptimizationWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProductPageOptimizationWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("ppo_list_experiments"))
        #expect(names.contains("ppo_get_experiment"))
        #expect(names.contains("ppo_create_experiment"))
        #expect(names.contains("ppo_update_experiment"))
        #expect(names.contains("ppo_delete_experiment"))
        #expect(names.contains("ppo_list_treatments"))
        #expect(names.contains("ppo_create_treatment"))
        #expect(names.contains("ppo_list_treatment_localizations"))
        #expect(names.contains("ppo_create_treatment_localization"))
    }

    // MARK: - PromotedPurchasesWorker (8 tools)

    @Test("PromotedPurchasesWorker returns 8 tools with correct names")
    func promotedPurchasesWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PromotedPurchasesWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        #expect(tools.count == 9)
        let names = Set(tools.map(\.name))
        #expect(names.contains("promoted_list"))
        #expect(names.contains("promoted_get"))
        #expect(names.contains("promoted_create"))
        #expect(names.contains("promoted_update"))
        #expect(names.contains("promoted_delete"))
        #expect(names.contains("promoted_upload_image"))
        #expect(names.contains("promoted_get_image"))
        #expect(names.contains("promoted_delete_image"))
        #expect(names.contains("promoted_get_image_for_purchase"))
    }

    // MARK: - MetricsWorker (4 tools)

    @Test("MetricsWorker returns 4 tools with correct names")
    func metricsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = MetricsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 4)
        let names = Set(tools.map(\.name))
        #expect(names.contains("metrics_app_perf"))
        #expect(names.contains("metrics_build_perf"))
        #expect(names.contains("metrics_build_diagnostics"))
        #expect(names.contains("metrics_get_diagnostic_logs"))
    }

    // MARK: - Tool name uniqueness

    @Test("All tool names across all workers are unique")
    func allToolNamesUnique() async throws {
        let client = try await TestFactory.makeHTTPClient()

        var allNames: [String] = []
        allNames += (await AppsWorker(client: client).getTools()).map(\.name)
        allNames += (await BuildsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BuildProcessingWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BuildBetaDetailsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AppLifecycleWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await ReviewsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BetaGroupsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await InAppPurchasesWorker(httpClient: client, uploadService: UploadService()).getTools()).map(\.name)
        allNames += (await ProvisioningWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BetaTestersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AppInfoWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await PricingWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await UsersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AppEventsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AnalyticsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await SubscriptionsWorker(httpClient: client, uploadService: UploadService()).getTools()).map(\.name)
        allNames += (await OfferCodesWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await WinBackOffersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await IntroductoryOffersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await PromotionalOffersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await SandboxTestersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BetaAppWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await PreReleaseVersionsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BetaLicenseAgreementsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await ScreenshotsWorker(httpClient: client, uploadService: UploadService()).getTools()).map(\.name)
        allNames += (await CustomProductPagesWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await ProductPageOptimizationWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await PromotedPurchasesWorker(httpClient: client, uploadService: UploadService()).getTools()).map(\.name)
        allNames += (await MetricsWorker(httpClient: client).getTools()).map(\.name)

        let uniqueNames = Set(allNames)
        #expect(allNames.count == uniqueNames.count, "Duplicate tool names found")
    }

    // MARK: - Tool schema validation

    @Test("Every tool has a non-empty description")
    func allToolsHaveDescriptions() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let allTools: [Tool] = await {
            var tools: [Tool] = []
            tools += await AppsWorker(client: client).getTools()
            tools += await BuildsWorker(httpClient: client).getTools()
            tools += await BuildProcessingWorker(httpClient: client).getTools()
            tools += await BuildBetaDetailsWorker(httpClient: client).getTools()
            tools += await AppLifecycleWorker(httpClient: client).getTools()
            tools += await ReviewsWorker(httpClient: client).getTools()
            tools += await BetaGroupsWorker(httpClient: client).getTools()
            tools += await InAppPurchasesWorker(httpClient: client, uploadService: UploadService()).getTools()
            tools += await ProvisioningWorker(httpClient: client).getTools()
            tools += await BetaTestersWorker(httpClient: client).getTools()
            tools += await AppInfoWorker(httpClient: client).getTools()
            tools += await PricingWorker(httpClient: client).getTools()
            tools += await UsersWorker(httpClient: client).getTools()
            tools += await AppEventsWorker(httpClient: client).getTools()
            tools += await AnalyticsWorker(httpClient: client).getTools()
            tools += await SubscriptionsWorker(httpClient: client, uploadService: UploadService()).getTools()
            tools += await OfferCodesWorker(httpClient: client).getTools()
            tools += await WinBackOffersWorker(httpClient: client).getTools()
            tools += await IntroductoryOffersWorker(httpClient: client).getTools()
            tools += await PromotionalOffersWorker(httpClient: client).getTools()
            tools += await SandboxTestersWorker(httpClient: client).getTools()
            tools += await BetaAppWorker(httpClient: client).getTools()
            tools += await PreReleaseVersionsWorker(httpClient: client).getTools()
            tools += await BetaLicenseAgreementsWorker(httpClient: client).getTools()
            tools += await ScreenshotsWorker(httpClient: client, uploadService: UploadService()).getTools()
            tools += await CustomProductPagesWorker(httpClient: client).getTools()
            tools += await ProductPageOptimizationWorker(httpClient: client).getTools()
            tools += await PromotedPurchasesWorker(httpClient: client, uploadService: UploadService()).getTools()
            tools += await MetricsWorker(httpClient: client).getTools()
            tools += await ReviewAttachmentsWorker(httpClient: client, uploadService: UploadService()).getTools()
            return tools
        }()

        for tool in allTools {
            let desc = "\(tool.description)" // Works with both String and String?
            #expect(!desc.isEmpty && desc != "nil", "Tool '\(tool.name)' has empty description")
        }
    }

    // MARK: - ReviewAttachmentsWorker (4 tools)

    @Test("ReviewAttachmentsWorker returns 4 tools with correct names")
    func reviewAttachmentsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewAttachmentsWorker(httpClient: client, uploadService: UploadService())
        let tools = await worker.getTools()
        #expect(tools.count == 4)
        let names = Set(tools.map(\.name))
        #expect(names.contains("review_attachments_upload"))
        #expect(names.contains("review_attachments_get"))
        #expect(names.contains("review_attachments_delete"))
        #expect(names.contains("review_attachments_list"))
    }
}
