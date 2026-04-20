import Foundation
import MCP

/// Main application logic
/// - Parameter enabledWorkers: Set of worker names to enable, nil = all workers
public func runApplication(enabledWorkers: Set<String>? = nil) async throws {
    print("🚀 Starting App Store Connect MCP Server...", to: &standardError)

    // 1. Create and load companies
    print("📋 Loading company configuration...", to: &standardError)
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)

    // Verify companies are loaded
    let companies = await companiesWorker.manager.listCompanies()
    guard !companies.isEmpty else {
        print("❌ No companies found in configuration", to: &standardError)
        print("Configure env vars or companies.json with your company data", to: &standardError)
        exit(1)
    }

    print("✅ Companies loaded: \(companies.count)", to: &standardError)
    for company in companies {
        print("   • \(company.name) (ID: \(company.id))", to: &standardError)
    }

    // 2. Create MCP server
    let server = Server(
        name: "app-store-connect-mcp",
        version: "2.0.0",
        instructions: """
        MCP server for App Store Connect API with multi-company support.

        Available companies:
        \(companies.map { "- \($0.name)" }.joined(separator: "\n"))

        Start with:
        - company_list — list all companies
        - company_switch — select a company to work with
        - company_current — show current active company

        After selecting a company, use:
        - auth_* — authentication
        - apps_* — app management and metadata
        - builds_* — build management
        - app_versions_* — version lifecycle (create, submit, release)
        - reviews_* — customer reviews
        - beta_groups_* — TestFlight groups
        - beta_testers_* — TestFlight testers
        - iap_* — in-app purchases and subscriptions
        - provisioning_* — bundle IDs, devices, certificates, profiles
        - app_info_* — app info and categories
        - pricing_* — territories and pricing
        - users_* — team members and roles
        - app_events_* — in-app events
        - analytics_* — sales and financial reports
        - subscriptions_* -- subscription management (CRUD, localizations, prices, groups)
        - offer_codes_* -- subscription offer codes
        - winback_* -- win-back offers for subscriptions
        - intro_offers_* -- subscription introductory offers (free trials, pay-as-you-go, pay-up-front)
        - promo_offers_* -- subscription promotional offers (discounts for current/former subscribers)
        - sandbox_* -- sandbox testers management (list, update, clear purchase history)
        - beta_app_* -- beta app localizations, review submissions, review details
        - pre_release_* -- pre-release versions (list, get, builds)
        - beta_license_* -- beta license agreements (list, get, update)
        - screenshots_* -- screenshots and app previews management
        - custom_pages_* -- custom product pages
        - ppo_* -- product page optimization (A/B testing)
        - promoted_* -- promoted in-app purchases
        - metrics_* -- performance metrics and diagnostics
        - review_attachments_* -- app store review attachments (upload, get, delete, list)

        ## Subscription Setup Workflow (FULL)
        When asked to set up subscriptions for an app, always follow this exact order:

        1. Find app ID: apps_list or apps_search
        2. Check existing groups: iap_list_subscriptions (app_id)
        3. Create group if needed: subscriptions_create_group (app_id, reference_name)
        4. Create group localization: subscriptions_create_group_localization (group_id, locale, name)
        5. For each subscription:
           a. subscriptions_create (group_id, name, product_id, period, group_level, review_note)
           b. subscriptions_create_localization (sub_id, locale, display_name, description ≤55 chars)
           c. Set territory availability via bash curl POST /v1/subscriptionAvailabilities
              with all 175 territories (GET /v1/territories first to get all IDs)
           d. subscriptions_list_price_points (sub_id, territory=USA) — find price point for desired price
           e. subscriptions_set_price (sub_id, price_point_id)
           f. If free trial needed: intro_offers_create (sub_id, duration, number_of_periods, offer_type=FREE_TRIAL)
        6. Review screenshot: subscriptions_upload_review_screenshot (sub_id, image_path)
           — ONLY if screenshot file path is provided; otherwise notify user it's still needed

        Notes:
        - Availability step MUST happen before set_price, otherwise price API returns 409
        - Description max length is 55 characters
        - group_level: 1 = highest tier, 2 = mid, 3 = lowest (affects upgrade/downgrade logic)
        - After all steps, subscriptions move from MISSING_METADATA → READY_TO_SUBMIT once screenshot is uploaded
        - Do NOT submit for App Store review — user does that manually
        """,
        capabilities: Server.Capabilities(
            tools: Server.Capabilities.Tools(listChanged: true)
        )
    )

    // 3. Create worker manager with loaded companies using factory method
    let workerManager = try await WorkerManager.createForProduction(
        companiesWorker: companiesWorker,
        enabledWorkers: enabledWorkers
    )
    print("✅ Workers initialized", to: &standardError)

    // 4. Register workers in server
    await workerManager.registerWorkers(in: server)
    print("✅ Workers registered", to: &standardError)

    // 5. Start server
    let transport = StdioTransport()
    print("🌐 MCP server started and ready!", to: &standardError)

    do {
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        print("✅ MCP server finished successfully", to: &standardError)
    } catch {
        print("⚠️ MCP server finished with error: \(error.localizedDescription)", to: &standardError)
        throw error
    }
}
