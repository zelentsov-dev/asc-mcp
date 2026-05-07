import Foundation
import Testing
import CryptoKit
import MCP
@testable import asc_mcp

// MARK: - Test Factory

struct WorkerToolSnapshot: Sendable {
    let key: String
    let readmeName: String
    let tools: [Tool]

    var count: Int {
        tools.count
    }
}

/// Factory for creating test objects without network dependencies
enum TestFactory {
    /// Generate an in-memory P256 private key in PEM format
    static var testPEM: String {
        P256.Signing.PrivateKey().pemRepresentation
    }

    /// Create a test Company with in-memory key
    static func makeCompany(
        id: String = "test-company",
        name: String = "Test Company",
        keyID: String = "TEST_KEY_ID",
        issuerID: String = "TEST_ISSUER_ID"
    ) -> Company {
        Company(
            id: id,
            name: name,
            keyID: keyID,
            issuerID: issuerID,
            privateKeyContent: testPEM
        )
    }

    /// Create a JWTService with in-memory key (no file access)
    static func makeJWTService(company: Company? = nil) throws -> JWTService {
        try JWTService(company: company ?? makeCompany())
    }

    /// Create an HTTPClient backed by a test JWTService (no real HTTP calls)
    static func makeHTTPClient(jwtService: JWTService? = nil) async throws -> HTTPClient {
        let jwt = try jwtService ?? makeJWTService()
        return await HTTPClient(jwtService: jwt, baseURL: "https://test.example.com")
    }

    /// Create a CompaniesManager from a temporary single-company config.
    static func makeCompaniesManager(company: Company? = nil) throws -> CompaniesManager {
        let config = CompaniesConfig(companies: [company ?? makeCompany()])
        let data = try JSONEncoder().encode(config)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-test-companies-\(UUID().uuidString).json")
        try data.write(to: url)
        return try CompaniesManager(configPath: url.path)
    }

    /// Create a WorkerManager with test dependencies.
    static func makeWorkerManager(enabledWorkers: Set<String>? = nil, readOnlyMode: Bool = false) async throws -> WorkerManager {
        let companiesWorker = CompaniesWorker(manager: try makeCompaniesManager())
        let jwtService = try makeJWTService()
        let httpClient = await HTTPClient(jwtService: jwtService, baseURL: "https://test.example.com")
        let dependencies = WorkerDependencies(
            companiesWorker: companiesWorker,
            jwtService: jwtService,
            httpClient: httpClient,
            authWorker: AuthWorker(jwtService: jwtService)
        )
        return await WorkerManager(dependencies: dependencies, enabledWorkers: enabledWorkers, readOnlyMode: readOnlyMode)
    }

    /// Collect current tool definitions grouped by README worker key.
    static func collectWorkerToolSnapshots() async throws -> [WorkerToolSnapshot] {
        let client = try await makeHTTPClient()
        let uploadService = UploadService()
        let companiesManager = try makeCompaniesManager()
        let companiesWorker = CompaniesWorker(manager: companiesManager)
        let authWorker = AuthWorker(jwtService: try makeJWTService())

        return [
            WorkerToolSnapshot(key: "company", readmeName: "Company Management", tools: await companiesWorker.getTools()),
            WorkerToolSnapshot(key: "auth", readmeName: "Authentication", tools: await authWorker.getTools()),
            WorkerToolSnapshot(key: "apps", readmeName: "Apps Management", tools: await AppsWorker(client: client).getTools()),
            WorkerToolSnapshot(key: "webhooks", readmeName: "Webhook Notifications", tools: await WebhooksWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "xcode_cloud", readmeName: "Xcode Cloud", tools: await XcodeCloudWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "builds", readmeName: "Builds", tools: await BuildsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "build_processing", readmeName: "Build Processing", tools: await BuildProcessingWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "build_beta", readmeName: "TestFlight Beta Details", tools: await BuildBetaDetailsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "versions", readmeName: "App Version Lifecycle", tools: await AppLifecycleWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "reviews", readmeName: "Customer Reviews", tools: await ReviewsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "beta_groups", readmeName: "TestFlight Beta Groups", tools: await BetaGroupsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "beta_feedback", readmeName: "TestFlight Beta Feedback", tools: await BetaFeedbackWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "beta_testers", readmeName: "TestFlight Beta Testers", tools: await BetaTestersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "iap", readmeName: "In-App Purchases", tools: await InAppPurchasesWorker(httpClient: client, uploadService: uploadService).getTools()),
            WorkerToolSnapshot(key: "subscriptions", readmeName: "Subscriptions", tools: await SubscriptionsWorker(httpClient: client, uploadService: uploadService).getTools()),
            WorkerToolSnapshot(key: "offer_codes", readmeName: "Offer Codes", tools: await OfferCodesWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "winback", readmeName: "Win-Back Offers", tools: await WinBackOffersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "intro_offers", readmeName: "Introductory Offers", tools: await IntroductoryOffersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "promo_offers", readmeName: "Promotional Offers", tools: await PromotionalOffersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "sandbox", readmeName: "Sandbox Testers", tools: await SandboxTestersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "beta_app", readmeName: "Beta App", tools: await BetaAppWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "pre_release", readmeName: "Pre-Release Versions", tools: await PreReleaseVersionsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "beta_license", readmeName: "Beta License Agreements", tools: await BetaLicenseAgreementsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "provisioning", readmeName: "Provisioning", tools: await ProvisioningWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "app_info", readmeName: "App Info", tools: await AppInfoWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "pricing", readmeName: "Pricing", tools: await PricingWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "users", readmeName: "Users", tools: await UsersWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "app_events", readmeName: "App Events", tools: await AppEventsWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "analytics", readmeName: "Analytics", tools: await AnalyticsWorker(httpClient: client, companiesManager: companiesManager).getTools()),
            WorkerToolSnapshot(key: "screenshots", readmeName: "Screenshots & Previews", tools: await ScreenshotsWorker(httpClient: client, uploadService: uploadService).getTools()),
            WorkerToolSnapshot(key: "custom_pages", readmeName: "Custom Product Pages", tools: await CustomProductPagesWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "ppo", readmeName: "Product Page Optimization (A/B Tests)", tools: await ProductPageOptimizationWorker(httpClient: client).getTools()),
            WorkerToolSnapshot(key: "promoted", readmeName: "Promoted Purchases", tools: await PromotedPurchasesWorker(httpClient: client, uploadService: uploadService).getTools()),
            WorkerToolSnapshot(key: "review_attachments", readmeName: "Review Attachments", tools: await ReviewAttachmentsWorker(httpClient: client, uploadService: uploadService).getTools()),
            WorkerToolSnapshot(key: "metrics", readmeName: "Performance Metrics", tools: await MetricsWorker(httpClient: client).getTools())
        ]
    }

    /// Collect all current tool definitions from registered workers.
    static func collectAllWorkerTools() async throws -> [Tool] {
        try await collectWorkerToolSnapshots().flatMap(\.tools)
    }
}

// MARK: - Fixture Loading

/// Load JSON fixture from bundle
func loadFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw FixtureError.notFound(name)
    }
    return try Data(contentsOf: url)
}

/// Decode a fixture JSON file into a Decodable type
func decodeFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let data = try loadFixture(name)
    return try JSONDecoder().decode(type, from: data)
}

enum FixtureError: Error {
    case notFound(String)
}

// MARK: - JSON Encoding Helper

/// Encode a value to JSON and decode it back (roundtrip test)
func roundtrip<T: Codable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}
