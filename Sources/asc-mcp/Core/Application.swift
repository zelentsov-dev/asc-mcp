import Foundation
import MCP

/// Main application logic.
/// - Parameter options: Runtime options selected from command line arguments.
public func runApplication(options: AppRuntimeOptions = AppRuntimeOptions()) async throws {
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
        version: ServerVersion.current,
        instructions: """
        MCP server for App Store Connect API with multi-company support.

        Available companies:
        \(companies.map { "- \($0.name)" }.joined(separator: "\n"))

        Start with:
        - company_list — list all companies
        - company_switch — select a company to work with
        - company_current — show current active company

        \(options.readOnlyMode ? "Read-only mode is enabled. Tools that can create, update, upload, submit, release, delete, revoke, clear, cancel, or otherwise mutate App Store Connect are blocked before execution.\n" : "")

        After selecting a company, use:
        - auth_* — authentication
        - apps_* — app management and metadata
        - accessibility_* — App Store accessibility declarations by device family
        - webhooks_* — webhook notifications, delivery diagnostics, signature verification, payload parsing, and triage
        - xcode_cloud_* — Xcode Cloud products, workflows, builds, artifacts, issues, test results, and SCM resources
        - builds_* — build management
        - build_uploads_* — resumable build upload creation, transfer, commit, and processing status
        - export_compliance_* — encryption declarations, documents, build linkage, and export-compliance readiness
        - app_versions_* — version lifecycle (create, submit, release)
        - reviews_* — customer reviews
        - beta_groups_* — TestFlight groups, public-link recruitment criteria, and compatibility checks
        - beta_feedback_* — TestFlight feedback screenshots, crash submissions, and crash logs
        - beta_testers_* — TestFlight testers
        - iap_* — in-app purchases and subscriptions
        - provisioning_* — bundle IDs, devices, certificates, profiles
        - app_info_* — app info and categories
        - pricing_* — territories and pricing
        - users_* — team members and roles
        - app_events_* — in-app events
        - analytics_* — sales and financial reports
        - subscriptions_* -- subscription and offer management (groups, products, prices, availability, intro/promotional/offer-code/win-back offers)
        - sandbox_* -- sandbox testers management (list, update, clear purchase history)
        - beta_app_* -- beta app localizations, review submissions, review details
        - pre_release_* -- pre-release versions (list, get, builds)
        - beta_license_* -- beta license agreements (list, get, update)
        - screenshots_* -- screenshots and app previews management
        - assets_* -- reusable App Asset Library images, videos, and placements; prepare a preview before applying a change
        - custom_pages_* -- custom product pages
        - ppo_* -- product page optimization (A/B testing)
        - promoted_* -- promoted in-app purchases
        - metrics_* -- performance overviews, metrics, diagnostics, and TestFlight usage metrics
        - review_attachments_* -- app store review attachments (upload, get, delete, list)
        - review_submissions_* -- App Store review submission inspection, recovery, item assembly, submission, and cancellation

        Asset Library changes require assets_prepare_change followed by assets_apply_change with the returned single-use preview_id. Review the concrete effects before applying. Image/video additions through review_submissions_add_item consume the same preview and require its exact submission and asset IDs. Legacy screenshots_* IDs and contracts remain separate. Read-only mode permits asset inspection and preview preparation, but blocks applying changes.
        """,
        capabilities: Server.Capabilities(
            tools: Server.Capabilities.Tools(listChanged: true)
        )
    )

    // 3. Create worker manager with loaded companies using factory method
    let workerManager = try await WorkerManager.createForProduction(
        companiesWorker: companiesWorker,
        enabledWorkers: options.enabledWorkers,
        readOnlyMode: options.readOnlyMode
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
