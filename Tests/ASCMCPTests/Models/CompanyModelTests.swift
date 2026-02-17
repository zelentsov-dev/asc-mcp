import Testing
import Foundation
@testable import asc_mcp

@Suite("Company Model Tests")
struct CompanyModelTests {
    @Test func decodeFromJSON() throws {
        let json = """
        {"id":"c1","name":"Corp","key_id":"K1","issuer_id":"I1","key_path":"/tmp/k.p8","key_content":"PEM_DATA"}
        """.data(using: .utf8)!
        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.id == "c1")
        #expect(company.name == "Corp")
        #expect(company.keyID == "K1")
        #expect(company.issuerID == "I1")
        #expect(company.privateKeyPath == "/tmp/k.p8")
        #expect(company.privateKeyContent == "PEM_DATA")
        #expect(company.vendorNumber == nil)
    }

    @Test func decodeWithVendorNumber() throws {
        let json = """
        {"id":"c1","name":"Corp","key_id":"K1","issuer_id":"I1","vendor_number":"87654321"}
        """.data(using: .utf8)!
        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.vendorNumber == "87654321")
    }

    @Test func decodeWithoutOptionalFields() throws {
        let json = """
        {"id":"c1","name":"Corp","key_id":"K1","issuer_id":"I1"}
        """.data(using: .utf8)!
        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.privateKeyPath == "")
        #expect(company.privateKeyContent == nil)
        #expect(company.vendorNumber == nil)
    }

    @Test func memberwiseInit() {
        let company = Company(id: "x", name: "X", keyID: "k", issuerID: "i", privateKeyPath: "/p", privateKeyContent: "c", vendorNumber: "12345")
        #expect(company.id == "x")
        #expect(company.name == "X")
        #expect(company.keyID == "k")
        #expect(company.issuerID == "i")
        #expect(company.privateKeyPath == "/p")
        #expect(company.privateKeyContent == "c")
        #expect(company.vendorNumber == "12345")
    }

    @Test func memberwiseInitDefaults() {
        let company = Company(id: "x", name: "X", keyID: "k", issuerID: "i")
        #expect(company.privateKeyPath == "")
        #expect(company.privateKeyContent == nil)
        #expect(company.vendorNumber == nil)
    }

    @Test func equatable() {
        let a = Company(id: "1", name: "A", keyID: "k", issuerID: "i")
        let b = Company(id: "1", name: "A", keyID: "k", issuerID: "i")
        #expect(a == b)
    }

    @Test func notEqual() {
        let a = Company(id: "1", name: "A", keyID: "k", issuerID: "i")
        let b = Company(id: "2", name: "B", keyID: "k", issuerID: "i")
        #expect(a != b)
    }

    @Test func identifiable() {
        let company = Company(id: "test-id", name: "Test", keyID: "k", issuerID: "i")
        #expect(company.id == "test-id")
    }

    @Test func encodeDecodeRoundtrip() throws {
        let original = Company(id: "rt", name: "Roundtrip", keyID: "rk", issuerID: "ri", privateKeyContent: "pem")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Company.self, from: data)
        #expect(decoded == original)
    }

    @Test func encodeDecodeRoundtripWithPath() throws {
        let original = Company(id: "rt", name: "RT", keyID: "k", issuerID: "i", privateKeyPath: "/path/key.p8")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Company.self, from: data)
        #expect(decoded == original)
        #expect(decoded.privateKeyPath == "/path/key.p8")
    }

    @Test func decodeMissingRequiredField() {
        let json = """
        {"id":"c1","key_id":"K1","issuer_id":"I1"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Company.self, from: json)
        }
    }

    @Test func decodeMissingKeyID() {
        let json = """
        {"id":"c1","name":"Corp","issuer_id":"I1"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Company.self, from: json)
        }
    }
}
