import Foundation
import MCP

/// Тестирование переключения между компаниями
public func testCompanySwitching() async throws {
    print("\n🧪 ТЕСТ: Переключение между компаниями\n", to: &standardError)
    
    // 1. Создаем воркеры используя фабричный метод
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    let _ = try await WorkerManager.createForProduction(companiesWorker: companiesWorker)
    
    // 2. Проверяем загруженные компании
    let companies = await companiesWorker.manager.listCompanies()
    print("📋 Найдено компаний: \(companies.count)", to: &standardError)
    for company in companies {
        print("   • \(company.name) (ID: \(company.id))", to: &standardError)
    }
    
    // 3. Тестируем переключение между компаниями
    if companies.count >= 2 {
        print("\n🔄 ТЕСТ 1: Переключаемся на первую компанию", to: &standardError)
        _ = try await companiesWorker.manager.switchToCompany(companies[0].id)
        
        // Получаем первую компанию
        let company1 = companies[0]
        print("✅ Активная компания: \(company1.name)", to: &standardError)
        print("   Key ID: \(company1.keyID)", to: &standardError)
        print("   Issuer ID: \(company1.issuerID)", to: &standardError)
        
        // Создаем AuthWorker для первой компании
        let jwtService1 = try JWTService(company: company1)
        let authWorker1 = AuthWorker(jwtService: jwtService1)
        print("✅ AuthWorker создан для компании 1", to: &standardError)
        
        // Тест списка приложений для первой компании
        print("\n📱 ТЕСТ 2: Получаем список приложений для компании 1", to: &standardError)
        let defaultURL = await companiesWorker.manager.getDefaultURL()
        let httpClient1 = await HTTPClient(jwtService: jwtService1, baseURL: defaultURL)
        let appsWorker1 = AppsWorker(client: httpClient1)
        
        let listParams1 = CallTool.Parameters(
            name: "apps_list",
            arguments: ["limit": .int(3)]
        )
        
        let result1 = try await appsWorker1.listApps(listParams1)
        if case .text(let text) = result1.content.first {
            print(text, to: &standardError)
        }
        
        print("\n🔄 ТЕСТ 3: Переключаемся на вторую компанию", to: &standardError)
        _ = try await companiesWorker.manager.switchToCompany(companies[1].id)
        
        // Получаем вторую компанию
        let company2 = try await companiesWorker.manager.getCurrentCompany()
        print("✅ Активная компания: \(company2.name)", to: &standardError)
        print("   Key ID: \(company2.keyID)", to: &standardError)
        print("   Issuer ID: \(company2.issuerID)", to: &standardError)
        
        // Создаем AuthWorker для второй компании
        let jwtService2 = try JWTService(company: company2)
        let authWorker2 = AuthWorker(jwtService: jwtService2)
        print("✅ AuthWorker создан для компании 2", to: &standardError)
        
        // Проверяем что конфигурации разные
        if company1.keyID != company2.keyID || company1.issuerID != company2.issuerID {
            print("\n✅ ТЕСТ ПРОЙДЕН: Конфигурации разные для разных компаний", to: &standardError)
        } else {
            print("\n⚠️ ВНИМАНИЕ: Конфигурации одинаковые для разных компаний", to: &standardError)
        }
        
        // Тест списка приложений для второй компании
        print("\n📱 ТЕСТ 4: Получаем список приложений для компании 2", to: &standardError)
        let httpClient2 = await HTTPClient(jwtService: jwtService2, baseURL: defaultURL)
        let appsWorker2 = AppsWorker(client: httpClient2)
        
        let listParams2 = CallTool.Parameters(
            name: "apps_list",
            arguments: ["limit": .int(3)]
        )
        
        let result2 = try await appsWorker2.listApps(listParams2)
        if case .text(let text) = result2.content.first {
            print(text, to: &standardError)
        }
        
        // Тестируем WorkerManager переключение
        print("\n🔄 ТЕСТ 5: Тестируем переключение через WorkerManager", to: &standardError)
        
        // Симулируем вызов company_switch через WorkerManager
        let switchParams = CallTool.Parameters(
            name: "company_switch",
            arguments: ["company_id": .string(companies[0].id)]
        )
        
        // В реальном сценарии это будет вызываться через MCP сервер
        print("⚠️ Для полного теста WorkerManager нужен запущенный MCP сервер", to: &standardError)
        
    } else {
        print("\n⚠️ Недостаточно компаний для теста переключения (нужно минимум 2)", to: &standardError)
    }
    
    print("\n✅ ВСЕ ТЕСТЫ ЗАВЕРШЕНЫ", to: &standardError)
}

