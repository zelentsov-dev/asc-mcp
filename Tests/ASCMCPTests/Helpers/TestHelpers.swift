import Foundation
import Testing
import CryptoKit
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
