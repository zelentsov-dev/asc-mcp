import CryptoKit
import Foundation
import MCP

struct ASCWorkerToolSnapshot: Sendable {
    let key: String
    let readmeName: String
    let tools: [Tool]

    var count: Int {
        tools.count
    }
}

enum ASCToolCatalogFactory {
    private static let readmeNames: [String: String] = [
        "company": "Company Management",
        "auth": "Authentication",
        "apps": "Apps Management",
        "accessibility": "Accessibility Declarations",
        "webhooks": "Webhook Notifications",
        "xcode_cloud": "Xcode Cloud",
        "builds": "Builds",
        "build_processing": "Build Processing",
        "export_compliance": "Export Compliance",
        "build_beta": "TestFlight Beta Details",
        "versions": "App Version Lifecycle",
        "reviews": "Customer Reviews",
        "beta_groups": "TestFlight Beta Groups",
        "beta_feedback": "TestFlight Beta Feedback",
        "beta_testers": "TestFlight Beta Testers",
        "iap": "In-App Purchases",
        "subscriptions": "Subscriptions",
        "sandbox": "Sandbox Testers",
        "beta_app": "Beta App",
        "pre_release": "Pre-Release Versions",
        "beta_license": "Beta License Agreements",
        "provisioning": "Provisioning",
        "app_info": "App Info",
        "pricing": "Pricing",
        "users": "Users",
        "app_events": "App Events",
        "analytics": "Analytics",
        "screenshots": "Screenshots & Previews",
        "custom_pages": "Custom Product Pages",
        "ppo": "Product Page Optimization (A/B Tests)",
        "promoted": "Promoted Purchases",
        "review_attachments": "Review Attachments",
        "metrics": "Performance Metrics"
    ]

    static func collectWorkerToolSnapshots() async throws -> [ASCWorkerToolSnapshot] {
        let company = Company(
            id: "contract-check",
            name: "Contract Check",
            keyID: "CONTRACT_CHECK",
            issuerID: "CONTRACT_CHECK",
            privateKeyContent: P256.Signing.PrivateKey().pemRepresentation,
            vendorNumber: "CONTRACT_CHECK"
        )
        let companiesManager = try CompaniesManager(
            config: CompaniesConfig(companies: [company]),
            configSource: "in-memory contract catalog"
        )
        let jwtService = try JWTService(company: company)
        let httpClient = await HTTPClient(
            jwtService: jwtService,
            baseURL: "https://api.appstoreconnect.apple.com"
        )
        let companiesWorker = CompaniesWorker(manager: companiesManager)
        let authWorker = AuthWorker(jwtService: jwtService)
        let dependencies = WorkerDependencies(
            companiesWorker: companiesWorker,
            jwtService: jwtService,
            httpClient: httpClient,
            authWorker: authWorker
        )
        let manager = await WorkerManager(dependencies: dependencies)
        let snapshots = await manager.collectWorkerToolSnapshots()
        let descriptorKeys = Set(snapshots.map(\.key))
        guard descriptorKeys == WorkerManager.validWorkerFilterKeys else {
            throw ASCToolCatalogError.workerRegistryDrift(
                descriptorOnly: descriptorKeys.subtracting(WorkerManager.validWorkerFilterKeys).sorted(),
                filterOnly: WorkerManager.validWorkerFilterKeys.subtracting(descriptorKeys).sorted()
            )
        }
        return snapshots
    }

    static func readmeName(for workerKey: String) -> String {
        readmeNames[workerKey] ?? workerKey
    }
}

enum ASCToolCatalogError: Error, LocalizedError, Equatable {
    case workerRegistryDrift(descriptorOnly: [String], filterOnly: [String])

    var errorDescription: String? {
        switch self {
        case .workerRegistryDrift(let descriptorOnly, let filterOnly):
            "Worker registry drift: descriptor-only [\(descriptorOnly.joined(separator: ", "))], filter-only [\(filterOnly.joined(separator: ", "))]."
        }
    }
}
