import Testing
import Foundation
@testable import asc_mcp

@Suite("JSONValue Tests")
struct JSONValueTests {
    @Test func decodeString() throws {
        let json = "\"hello\"".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .string(let s) = value {
            #expect(s == "hello")
        } else {
            Issue.record("Expected string")
        }
    }

    @Test func decodeInt() throws {
        let json = "42".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .int(let i) = value {
            #expect(i == 42)
        } else {
            Issue.record("Expected int")
        }
    }

    @Test func decodeBool() throws {
        let json = "true".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .bool(let b) = value {
            #expect(b == true)
        } else {
            Issue.record("Expected bool")
        }
    }

    @Test func decodeNull() throws {
        let json = "null".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .null = value {
            // expected
        } else {
            Issue.record("Expected null")
        }
    }

    @Test func decodeArray() throws {
        let json = "[1,\"two\",true]".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .array(let arr) = value {
            #expect(arr.count == 3)
        } else {
            Issue.record("Expected array")
        }
    }

    @Test func decodeObject() throws {
        let json = "{\"key\":\"value\"}".data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        if case .object(let dict) = value {
            #expect(dict["key"] != nil)
        } else {
            Issue.record("Expected object")
        }
    }

    @Test func asAnyString() {
        let value = JSONValue.string("test")
        let any = value.asAny
        #expect(any as? String == "test")
    }

    @Test func asAnyInt() {
        let value = JSONValue.int(42)
        let any = value.asAny
        #expect(any as? Int == 42)
    }

    @Test func roundtrip() throws {
        let original = JSONValue.object(["name": .string("test"), "count": .int(5), "active": .bool(true)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        if case .object(let dict) = decoded {
            if case .string(let name) = dict["name"] {
                #expect(name == "test")
            } else {
                Issue.record("Expected string for name")
            }
        } else {
            Issue.record("Expected object")
        }
    }
}
