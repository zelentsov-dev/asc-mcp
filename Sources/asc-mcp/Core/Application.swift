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
        - screenshots_* -- screenshots and app previews management
        - custom_pages_* -- custom product pages
        - ppo_* -- product page optimization (A/B testing)
        - promoted_* -- promoted in-app purchases
        - metrics_* -- performance metrics and diagnostics
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
