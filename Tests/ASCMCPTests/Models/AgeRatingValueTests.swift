import Testing
import Foundation
@testable import asc_mcp

@Suite("AgeRatingValue Tests")
struct AgeRatingValueTests {
    @Test func decodeBool() throws {
        let json = "false".data(using: .utf8)!
        let value = try JSONDecoder().decode(AgeRatingValue.self, from: json)
        if case .bool(let b) = value {
            #expect(b == false)
        } else {
            Issue.record("Expected bool")
        }
    }

    @Test func decodeString() throws {
        let json = "\"NONE\"".data(using: .utf8)!
        let value = try JSONDecoder().decode(AgeRatingValue.self, from: json)
        if case .string(let s) = value {
            #expect(s == "NONE")
        } else {
            Issue.record("Expected string")
        }
    }

    @Test func encodeBool() throws {
        let value = AgeRatingValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AgeRatingValue.self, from: data)
        if case .bool(let b) = decoded {
            #expect(b == true)
        } else {
            Issue.record("Roundtrip failed")
        }
    }

    @Test func encodeString() throws {
        let value = AgeRatingValue.string("FREQUENT_OR_INTENSE")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AgeRatingValue.self, from: data)
        if case .string(let s) = decoded {
            #expect(s == "FREQUENT_OR_INTENSE")
        } else {
            Issue.record("Roundtrip failed")
        }
    }
}
