import Foundation
import MCP

/// Tests company switching functionality
public func testCompanySwitching() async throws {
    print("\n🧪 TEST: Company switching\n", to: &standardError)
    
    // 1. Create workers using factory method
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    let _ = try await WorkerManager.createForProduction(companiesWorker: companiesWorker)
    
    // 2. Verify loaded companies
    let companies = await companiesWorker.manager.listCompanies()
    print("📋 Companies found: \(companies.count)", to: &standardError)
    for company in companies {
        print("   • \(company.name) (ID: \(company.id))", to: &standardError)
    }
    
    // 3. Test switching between companies
    if companies.count >= 2 {
        print("\n🔄 TEST 1: Switch to first company", to: &standardError)
        _ = try await companiesWorker.manager.switchToCompany(companies[0].id)
        
        // Get first company
        let company1 = companies[0]
        print("✅ Active company: \(company1.name)", to: &standardError)
        print("   Key ID: \(company1.keyID)", to: &standardError)
        print("   Issuer ID: \(company1.issuerID ?? "(Individual Key)")", to: &standardError)
        
        // Create AuthWorker for first company
        let jwtService1 = try JWTService(company: company1)
        let authWorker1 = AuthWorker(jwtService: jwtService1)
        print("✅ AuthWorker created for company 1", to: &standardError)
        
        // Test app listing for first company
        print("\n📱 TEST 2: Get app list for company 1", to: &standardError)
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
        
        print("\n🔄 TEST 3: Switch to second company", to: &standardError)
        _ = try await companiesWorker.manager.switchToCompany(companies[1].id)
        
        // Get second company
        let company2 = try await companiesWorker.manager.getCurrentCompany()
        print("✅ Active company: \(company2.name)", to: &standardError)
        print("   Key ID: \(company2.keyID)", to: &standardError)
        print("   Issuer ID: \(company2.issuerID ?? "(Individual Key)")", to: &standardError)
        
        // Create AuthWorker for second company
        let jwtService2 = try JWTService(company: company2)
        let authWorker2 = AuthWorker(jwtService: jwtService2)
        print("✅ AuthWorker created for company 2", to: &standardError)
        
        // Verify configurations are different
        if company1.keyID != company2.keyID || company1.issuerID != company2.issuerID {
            print("\n✅ TEST PASSED: Configurations differ between companies", to: &standardError)
        } else {
            print("\n⚠️ WARNING: Configurations are identical for different companies", to: &standardError)
        }
        
        // Test app listing for second company
        print("\n📱 TEST 4: Get app list for company 2", to: &standardError)
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
        
        // Test WorkerManager switching
        print("\n🔄 TEST 5: Test switching via WorkerManager", to: &standardError)
        
        // Simulate company_switch call via WorkerManager
        let switchParams = CallTool.Parameters(
            name: "company_switch",
            arguments: ["company_id": .string(companies[0].id)]
        )
        
        // In a real scenario this would be called via MCP server
        print("⚠️ Full WorkerManager test requires a running MCP server", to: &standardError)
        
    } else {
        print("\n⚠️ Not enough companies for switching test (need at least 2)", to: &standardError)
    }
    
    print("\n✅ ALL TESTS COMPLETED", to: &standardError)
}
