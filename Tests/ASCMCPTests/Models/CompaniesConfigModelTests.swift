import Testing
import Foundation
@testable import asc_mcp

@Suite("CompaniesConfig Model Tests")
struct CompaniesConfigModelTests {
    @Test func decodeWithDefaultURL() throws {
        let json = """
        {"companies":[{"id":"c1","name":"Test","key_id":"K","issuer_id":"I"}]}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(CompaniesConfig.self, from: json)
        #expect(config.defaultURL == "https://api.appstoreconnect.apple.com")
        #expect(config.companies.count == 1)
    }

    @Test func decodeWithCustomURL() throws {
        let json = """
        {"defaultURL":"https://custom.api.com","companies":[]}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(CompaniesConfig.self, from: json)
        #expect(config.defaultURL == "https://custom.api.com")
    }

    @Test func memberwiseInit() {
        let config = CompaniesConfig(companies: [])
        #expect(config.defaultURL == "https://api.appstoreconnect.apple.com")
        #expect(config.companies.isEmpty)
    }

    @Test func memberwiseInitWithCustomURL() {
        let config = CompaniesConfig(companies: [], defaultURL: "https://custom.com")
        #expect(config.defaultURL == "https://custom.com")
    }

    @Test func encodeDecodeRoundtrip() throws {
        let companies = [Company(id: "1", name: "A", keyID: "k", issuerID: "i")]
        let original = CompaniesConfig(companies: companies, defaultURL: "https://test.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompaniesConfig.self, from: data)
        #expect(decoded.defaultURL == original.defaultURL)
        #expect(decoded.companies.count == 1)
        #expect(decoded.companies[0] == original.companies[0])
    }

    @Test func decodeMultipleCompanies() throws {
        let json = """
        {"companies":[{"id":"1","name":"A","key_id":"k1","issuer_id":"i1"},{"id":"2","name":"B","key_id":"k2","issuer_id":"i2"}]}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(CompaniesConfig.self, from: json)
        #expect(config.companies.count == 2)
        #expect(config.companies[0].name == "A")
        #expect(config.companies[1].name == "B")
    }

    @Test func decodeEmptyCompanies() throws {
        let json = """
        {"companies":[]}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(CompaniesConfig.self, from: json)
        #expect(config.companies.isEmpty)
        #expect(config.defaultURL == "https://api.appstoreconnect.apple.com")
    }
}
