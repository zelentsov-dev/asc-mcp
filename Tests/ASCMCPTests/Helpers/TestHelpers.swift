import Foundation
import Testing
import CryptoKit
import MCP
@testable import asc_mcp

// MARK: - Test Factory

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

    /// Create a CompaniesManager from a temporary config.
    static func makeCompaniesManager(
        company: Company? = nil,
        companies: [Company]? = nil,
        defaultURL: String = "https://api.appstoreconnect.apple.com"
    ) throws -> CompaniesManager {
        let config = CompaniesConfig(
            companies: companies ?? [company ?? makeCompany()],
            defaultURL: defaultURL
        )
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

    /// Create a WorkerManager through the production factory with a custom CompaniesManager.
    static func makeProductionWorkerManager(
        companies: [Company],
        defaultURL: String = "https://api.appstoreconnect.apple.com",
        enabledWorkers: Set<String>? = nil,
        readOnlyMode: Bool = false
    ) async throws -> WorkerManager {
        let companiesWorker = CompaniesWorker(
            manager: try makeCompaniesManager(companies: companies, defaultURL: defaultURL)
        )
        return try await WorkerManager.createForProduction(
            companiesWorker: companiesWorker,
            enabledWorkers: enabledWorkers,
            readOnlyMode: readOnlyMode
        )
    }

    /// Collect current tool definitions grouped by README worker key.
    static func collectWorkerToolSnapshots() async throws -> [ASCWorkerToolSnapshot] {
        try await ASCToolCatalogFactory.collectWorkerToolSnapshots()
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

// MARK: - HTTP Transport Test Double

actor TestHTTPTransport: HTTPTransport {
    struct Response: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let data: Data

        init(statusCode: Int, headers: [String: String] = [:], body: String) {
            self.statusCode = statusCode
            self.headers = headers
            self.data = Data(body.utf8)
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw ASCError.network("No mock response queued")
        }

        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.data, httpResponse)
    }

    func requestCount() -> Int {
        requests.count
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func recordedBodyStrings() -> [String] {
        requests.map { request in
            request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }
}

// MARK: - JSON Encoding Helper

/// Encode a value to JSON and decode it back (roundtrip test)
func roundtrip<T: Codable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}
