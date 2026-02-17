import Foundation
import MCP

/// Основная логика приложения
/// - Parameter enabledWorkers: Set of worker names to enable, nil = all workers
public func runApplication(enabledWorkers: Set<String>? = nil) async throws {
    print("🚀 Запуск App Store Connect MCP Server...", to: &standardError)

    // 1. Создаем и загружаем компании
    print("📋 Загрузка конфигурации компаний...", to: &standardError)
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    
    // Проверяем что компании загружены
    let companies = await companiesWorker.manager.listCompanies()
    guard !companies.isEmpty else {
        print("❌ Не найдено ни одной компании в конфигурации", to: &standardError)
        print("Настройте env vars или companies.json с данными ваших компаний", to: &standardError)
        exit(1)
    }
    
    print("✅ Загружено компаний: \(companies.count)", to: &standardError)
    for company in companies {
        print("   • \(company.name) (ID: \(company.id))", to: &standardError)
    }
    
    // 2. Создаем MCP сервер
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
        """,
        capabilities: Server.Capabilities(
            tools: Server.Capabilities.Tools(listChanged: true)
        )
    )
    
    // 3. Создаем менеджер воркеров с загруженными компаниями используя фабричный метод
    let workerManager = try await WorkerManager.createForProduction(
        companiesWorker: companiesWorker,
        enabledWorkers: enabledWorkers
    )
    print("✅ Воркеры инициализированы", to: &standardError)

    // 4. Регистрируем воркеры в сервере
    await workerManager.registerWorkers(in: server)
    print("✅ Воркеры зарегистрированы", to: &standardError)
    
    // 5. Запускаем сервер
    let transport = StdioTransport()
    print("🌐 MCP сервер запущен и готов к работе!", to: &standardError)
    
    do {
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
        print("✅ MCP сервер завершил работу корректно", to: &standardError)
    } catch {
        print("⚠️ MCP сервер завершил работу с ошибкой: \(error.localizedDescription)", to: &standardError)
        throw error
    }
}

