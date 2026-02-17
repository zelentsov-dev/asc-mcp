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
        #expect(tools.count == 8)
        let names = Set(tools.map(\.name))
        #expect(names.contains("builds_get_beta_detail"))
        #expect(names.contains("builds_update_beta_detail"))
        #expect(names.contains("builds_set_beta_localization"))
        #expect(names.contains("builds_list_beta_localizations"))
    }

    // MARK: - AppLifecycleWorker (12 tools)

    @Test("AppLifecycleWorker returns 12 tools with correct names")
    func appLifecycleWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 12)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_versions_create"))
        #expect(names.contains("app_versions_list"))
        #expect(names.contains("app_versions_get"))
        #expect(names.contains("app_versions_update"))
        #expect(names.contains("app_versions_attach_build"))
        #expect(names.contains("app_versions_submit_for_review"))
        #expect(names.contains("app_versions_cancel_review"))
        #expect(names.contains("app_versions_release"))
    }

    // MARK: - ReviewsWorker (7 tools)

    @Test("ReviewsWorker returns 7 tools with correct names")
    func reviewsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 7)
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

    // MARK: - InAppPurchasesWorker (12 tools)

    @Test("InAppPurchasesWorker returns 12 tools with correct names")
    func inAppPurchasesWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 12)
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
        #expect(tools.count == 6)
        let names = Set(tools.map(\.name))
        #expect(names.contains("beta_testers_list"))
        #expect(names.contains("beta_testers_search"))
        #expect(names.contains("beta_testers_get"))
        #expect(names.contains("beta_testers_create"))
        #expect(names.contains("beta_testers_delete"))
        #expect(names.contains("beta_testers_list_apps"))
    }

    // MARK: - AppInfoWorker (6 tools)

    @Test("AppInfoWorker returns 6 tools with correct names")
    func appInfoWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 6)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_info_list"))
        #expect(names.contains("app_info_get"))
        #expect(names.contains("app_info_update"))
        #expect(names.contains("app_info_list_localizations"))
        #expect(names.contains("app_info_update_localization"))
        #expect(names.contains("app_info_create_localization"))
    }

    // MARK: - PricingWorker (6 tools)

    @Test("PricingWorker returns 6 tools with correct names")
    func pricingWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 6)
        let names = Set(tools.map(\.name))
        #expect(names.contains("pricing_list_territories"))
        #expect(names.contains("pricing_get_availability"))
        #expect(names.contains("pricing_list_price_points"))
        #expect(names.contains("pricing_get_price_schedule"))
        #expect(names.contains("pricing_set_price_schedule"))
        #expect(names.contains("pricing_list_territory_availability"))
    }

    // MARK: - UsersWorker (7 tools)

    @Test("UsersWorker returns 7 tools with correct names")
    func usersWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 7)
        let names = Set(tools.map(\.name))
        #expect(names.contains("users_list"))
        #expect(names.contains("users_get"))
        #expect(names.contains("users_update"))
        #expect(names.contains("users_remove"))
        #expect(names.contains("users_invite"))
        #expect(names.contains("users_list_invitations"))
        #expect(names.contains("users_cancel_invitation"))
    }

    // MARK: - AppEventsWorker (6 tools)

    @Test("AppEventsWorker returns 6 tools with correct names")
    func appEventsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 6)
        let names = Set(tools.map(\.name))
        #expect(names.contains("app_events_list"))
        #expect(names.contains("app_events_get"))
        #expect(names.contains("app_events_create"))
        #expect(names.contains("app_events_update"))
        #expect(names.contains("app_events_delete"))
        #expect(names.contains("app_events_list_localizations"))
    }

    // MARK: - AnalyticsWorker (4 tools)

    @Test("AnalyticsWorker returns 4 tools with correct names")
    func analyticsWorkerTools() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let tools = await worker.getTools()
        #expect(tools.count == 4)
        let names = Set(tools.map(\.name))
        #expect(names.contains("analytics_sales_report"))
        #expect(names.contains("analytics_financial_report"))
        #expect(names.contains("analytics_list_report_requests"))
        #expect(names.contains("analytics_create_report_request"))
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
        allNames += (await InAppPurchasesWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await ProvisioningWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await BetaTestersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AppInfoWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await PricingWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await UsersWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AppEventsWorker(httpClient: client).getTools()).map(\.name)
        allNames += (await AnalyticsWorker(httpClient: client).getTools()).map(\.name)

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
            tools += await InAppPurchasesWorker(httpClient: client).getTools()
            tools += await ProvisioningWorker(httpClient: client).getTools()
            tools += await BetaTestersWorker(httpClient: client).getTools()
            tools += await AppInfoWorker(httpClient: client).getTools()
            tools += await PricingWorker(httpClient: client).getTools()
            tools += await UsersWorker(httpClient: client).getTools()
            tools += await AppEventsWorker(httpClient: client).getTools()
            tools += await AnalyticsWorker(httpClient: client).getTools()
            return tools
        }()

        for tool in allTools {
            let desc = "\(tool.description)" // Works with both String and String?
            #expect(!desc.isEmpty && desc != "nil", "Tool '\(tool.name)' has empty description")
        }
    }
}
