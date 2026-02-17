import Foundation
import MCP

/// Тестирование работы с метаданными приложений
public func testAppMetadata() async throws {
    print("\n🧪 ТЕСТ: Работа с метаданными приложений\n", to: &standardError)
    
    // Создаем и загружаем компании
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    
    // Выбираем первую компанию
    let companies = await companiesWorker.manager.listCompanies()
    if !companies.isEmpty {
        _ = try await companiesWorker.manager.switchToCompany(companies[0].id)
        print("✅ Выбрана компания: \(companies[0].name)", to: &standardError)
    }
    
    // Получаем текущую компанию и defaultURL
    let company = try await companiesWorker.manager.getCurrentCompany()
    let defaultURL = await companiesWorker.manager.getDefaultURL()
    let jwtService = try JWTService(company: company)
    let httpClient = await HTTPClient(jwtService: jwtService, baseURL: defaultURL)
    let appsWorker = AppsWorker(client: httpClient)
    
    // Сначала получим список приложений компании
    print("\n📱 Получаем список приложений компании...", to: &standardError)
    let appsResponse: ASCAppsResponse = try await appsWorker.httpClient.get(
        "/v1/apps",
        parameters: ["limit": "5"],
        as: ASCAppsResponse.self
    )
    
    guard !appsResponse.data.isEmpty else {
        print("❌ У компании нет приложений", to: &standardError)
        return
    }
    
    let app = appsResponse.data[0]
    let appId = app.id
    print("✅ Используем приложение: \(app.attributes?.name ?? "N/A") (ID: \(appId))", to: &standardError)
    
    // 1. Получаем список версий
    print("\n📋 Получаем список версий...", to: &standardError)
    let versionsResponse: ASCAppStoreVersionsResponse = try await appsWorker.httpClient.get(
        "/v1/apps/\(appId)/appStoreVersions",
        parameters: [
            "limit": "10",
            "fields[appStoreVersions]": "versionString,appStoreState"
        ],
        as: ASCAppStoreVersionsResponse.self
    )
    
    guard !versionsResponse.data.isEmpty else {
        print("❌ Версии не найдены", to: &standardError)
        return
    }
    
    // Ищем версию в состоянии PREPARE_FOR_SUBMISSION для редактирования
    var editableVersion: ASCAppStoreVersion? = nil
    for version in versionsResponse.data {
        let state = version.attributes?.appStoreState ?? ""
        print("📦 Версия \(version.attributes?.versionString ?? "N/A"): \(state)", to: &standardError)
        if state == "PREPARE_FOR_SUBMISSION" {
            editableVersion = version
            break
        }
    }
    
    // Если нет редактируемой версии, используем первую для чтения
    if let version = editableVersion {
        print("\n✅ Найдена редактируемая версия: \(version.attributes?.versionString ?? "N/A") (ID: \(version.id))", to: &standardError)
        
        // ТЕСТ ОБНОВЛЕНИЯ МЕТАДАННЫХ
        print("\n📝 Тестируем обновление What's New...", to: &standardError)
        let updateParams = CallTool.Parameters(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string(appId),
                "version_id": .string(version.id),
                "locale": .string("en-US"),
                "whats_new": .string("""
                Test Update from MCP Server
                
                - This is a test update
                - Testing the API integration
                - Everything works great!
                
                Updated at: \(Date().description)
                """)
            ]
        )
        
        let updateResult = try await appsWorker.updateMetadata(updateParams)
        if case .text(let text) = updateResult.content.first {
            print(text, to: &standardError)
        }
        
    } else {
        print("\n⚠️ Нет версии в состоянии PREPARE_FOR_SUBMISSION для тестирования", to: &standardError)
        
        // Тестируем чтение метаданных для последней версии
        if let latestVersion = versionsResponse.data.first {
            print("\n📖 Читаем метаданные для версии \(latestVersion.attributes?.versionString ?? "N/A")", to: &standardError)
            
            let metadataParams = CallTool.Parameters(
                name: "apps_get_metadata",
                arguments: [
                    "app_id": .string(appId),
                    "version_id": .string(latestVersion.id),
                    "locale": .string("en-US")
                ]
            )
            
            let metadataResult = try await appsWorker.getAppMetadata(metadataParams)
            if case .text(let text) = metadataResult.content.first {
                print(text, to: &standardError)
            }
        }
    }
    
    print("\n✅ ТЕСТ МЕТАДАННЫХ ЗАВЕРШЕН", to: &standardError)
}

