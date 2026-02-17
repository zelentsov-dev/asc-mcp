import Testing
import Foundation
import MCP
@testable import asc_mcp

@Suite("Parameter Validation Tests")
struct ParameterValidationTests {

    // MARK: - AppsWorker

    @Test("apps_get_details without app_id returns isError")
    func appsGetDetailsMissingAppId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_get_details", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("apps_get_metadata without app_id or version_id returns isError")
    func appsGetMetadataMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_get_metadata", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("apps_update_metadata without required params returns isError")
    func appsUpdateMetadataMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_update_metadata", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("apps_create_localization without required params returns isError")
    func appsCreateLocalizationMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_create_localization", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("apps_delete_localization without localization_id returns isError")
    func appsDeleteLocalizationMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_delete_localization", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - BuildsWorker

    @Test("builds_list without app_id returns isError")
    func buildsListMissingAppId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("builds_get without build_id returns isError")
    func buildsGetMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - BuildProcessingWorker

    @Test("builds_get_processing_state without build_id returns isError")
    func buildProcessingStateMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildProcessingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_get_processing_state", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("builds_update_encryption without build_id returns isError")
    func buildUpdateEncryptionMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildProcessingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_update_encryption", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("builds_check_readiness without build_id returns isError")
    func buildCheckReadinessMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildProcessingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_check_readiness", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - BuildBetaDetailsWorker

    @Test("builds_get_beta_detail without build_id returns isError")
    func buildBetaDetailMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildBetaDetailsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_get_beta_detail", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("builds_update_beta_detail without build_id returns isError")
    func buildUpdateBetaDetailMissingBuildId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildBetaDetailsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_update_beta_detail", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - AppLifecycleWorker

    @Test("app_versions_create without required params returns isError")
    func appLifecycleCreateMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_versions_create", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_versions_get without version_id returns isError")
    func appLifecycleGetMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_versions_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_versions_attach_build without required params returns isError")
    func appLifecycleAttachBuildMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_versions_attach_build", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_versions_submit_for_review without version_id returns isError")
    func appLifecycleSubmitMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_versions_submit_for_review", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - ReviewsWorker

    @Test("reviews_list without app_id returns isError")
    func reviewsListMissingAppId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "reviews_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("reviews_get without review_id returns isError")
    func reviewsGetMissingReviewId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "reviews_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("reviews_create_response without required params returns isError")
    func reviewsCreateResponseMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "reviews_create_response", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - BetaGroupsWorker

    @Test("beta_groups_list without app_id returns isError")
    func betaGroupsListMissingAppId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaGroupsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_groups_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("beta_groups_create without required params returns isError")
    func betaGroupsCreateMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaGroupsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_groups_create", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("beta_groups_delete without group_id returns isError")
    func betaGroupsDeleteMissingGroupId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaGroupsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_groups_delete", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - InAppPurchasesWorker

    @Test("iap_list without app_id returns isError")
    func iapListMissingAppId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "iap_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("iap_get without iap_id returns isError")
    func iapGetMissingId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "iap_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("iap_create without required params returns isError")
    func iapCreateMissingParams() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "iap_create", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("iap_delete without iap_id returns isError")
    func iapDeleteMissingId() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "iap_delete", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - ProvisioningWorker

    @Test("provisioning_get_bundle_id without bundle_id_resource_id returns isError")
    func provisioningGetBundleIdMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let params = CallTool.Parameters(name: "provisioning_get_bundle_id", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("provisioning_create_bundle_id without required params returns isError")
    func provisioningCreateBundleIdMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let params = CallTool.Parameters(name: "provisioning_create_bundle_id", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("provisioning_delete_bundle_id without id returns isError")
    func provisioningDeleteBundleIdMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let params = CallTool.Parameters(name: "provisioning_delete_bundle_id", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("provisioning_register_device without required params returns isError")
    func provisioningRegisterDeviceMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let params = CallTool.Parameters(name: "provisioning_register_device", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - BetaTestersWorker

    @Test("beta_testers_get without tester_id returns isError")
    func betaTestersGetMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaTestersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_testers_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("beta_testers_create without required params returns isError")
    func betaTestersCreateMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaTestersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_testers_create", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("beta_testers_delete without tester_id returns isError")
    func betaTestersDeleteMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaTestersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_testers_delete", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - AppInfoWorker

    @Test("app_info_list without app_id returns isError")
    func appInfoListMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_info_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_info_get without info_id returns isError")
    func appInfoGetMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_info_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_info_update without required params returns isError")
    func appInfoUpdateMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_info_update", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - PricingWorker

    @Test("pricing_get_availability without app_id returns isError")
    func pricingAvailabilityMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "pricing_get_availability", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("pricing_list_price_points without app_id returns isError")
    func pricingListPricePointsMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "pricing_list_price_points", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("pricing_get_price_schedule without app_id returns isError")
    func pricingGetPriceScheduleMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "pricing_get_price_schedule", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - UsersWorker

    @Test("users_get without user_id returns isError")
    func usersGetMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "users_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("users_update without required params returns isError")
    func usersUpdateMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "users_update", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("users_remove without user_id returns isError")
    func usersRemoveMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "users_remove", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - AppEventsWorker

    @Test("app_events_list without app_id returns isError")
    func appEventsListMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_events_list", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_events_get without event_id returns isError")
    func appEventsGetMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_events_get", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_events_create without required params returns isError")
    func appEventsCreateMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_events_create", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("app_events_delete without event_id returns isError")
    func appEventsDeleteMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_events_delete", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    // MARK: - AnalyticsWorker

    @Test("analytics_sales_report without required params returns isError")
    func analyticsSalesReportMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "analytics_sales_report", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("analytics_financial_report without required params returns isError")
    func analyticsFinancialReportMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "analytics_financial_report", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }

    @Test("analytics_create_report_request without required params returns isError")
    func analyticsCreateReportRequestMissing() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "analytics_create_report_request", arguments: nil)
        let result = try await worker.handleTool(params)
        #expect(result.isError == true)
    }
}
