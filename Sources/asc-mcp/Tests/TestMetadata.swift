import Foundation
import MCP

/// Tests app metadata operations
public func testAppMetadata() async throws {
    print("\n🧪 TEST: App metadata operations\n", to: &standardError)
    
    // Create and load companies
    let companiesManager = try CompaniesManager()
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    
    // Select first company
    let companies = await companiesWorker.manager.listCompanies()
    if !companies.isEmpty {
        _ = try await companiesWorker.manager.switchToCompany(companies[0].id)
        print("✅ Selected company: \(companies[0].name)", to: &standardError)
    }
    
    // Get current company and defaultURL
    let company = try await companiesWorker.manager.getCurrentCompany()
    let defaultURL = await companiesWorker.manager.getDefaultURL()
    let jwtService = try JWTService(company: company)
    let httpClient = await HTTPClient(jwtService: jwtService, baseURL: defaultURL)
    let appsWorker = AppsWorker(client: httpClient)
    
    // First get company's app list
    print("\n📱 Getting company app list...", to: &standardError)
    let appsResponse: ASCAppsResponse = try await appsWorker.httpClient.get(
        "/v1/apps",
        parameters: ["limit": "5"],
        as: ASCAppsResponse.self
    )
    
    guard !appsResponse.data.isEmpty else {
        print("❌ Company has no apps", to: &standardError)
        return
    }
    
    let app = appsResponse.data[0]
    let appId = app.id
    print("✅ Using app: \(app.attributes?.name ?? "N/A") (ID: \(appId))", to: &standardError)
    
    // 1. Get version list
    print("\n📋 Getting version list...", to: &standardError)
    let versionsResponse: ASCAppStoreVersionsResponse = try await appsWorker.httpClient.get(
        "/v1/apps/\(appId)/appStoreVersions",
        parameters: [
            "limit": "10",
            "fields[appStoreVersions]": "versionString,appStoreState"
        ],
        as: ASCAppStoreVersionsResponse.self
    )
    
    guard !versionsResponse.data.isEmpty else {
        print("❌ No versions found", to: &standardError)
        return
    }
    
    // Find version in PREPARE_FOR_SUBMISSION state for editing
    var editableVersion: ASCAppStoreVersion? = nil
    for version in versionsResponse.data {
        let state = version.attributes?.appStoreState ?? ""
        print("📦 Version \(version.attributes?.versionString ?? "N/A"): \(state)", to: &standardError)
        if state == "PREPARE_FOR_SUBMISSION" {
            editableVersion = version
            break
        }
    }
    
    // If no editable version, use first one for reading
    if let version = editableVersion {
        print("\n✅ Found editable version: \(version.attributes?.versionString ?? "N/A") (ID: \(version.id))", to: &standardError)
        
        // METADATA UPDATE TEST
        print("\n📝 Testing What's New update...", to: &standardError)
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
        print("\n⚠️ No version in PREPARE_FOR_SUBMISSION state for testing", to: &standardError)
        
        // Test reading metadata for latest version
        if let latestVersion = versionsResponse.data.first {
            print("\n📖 Reading metadata for version \(latestVersion.attributes?.versionString ?? "N/A")", to: &standardError)
            
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
    
    print("\n✅ METADATA TEST COMPLETED", to: &standardError)
}

