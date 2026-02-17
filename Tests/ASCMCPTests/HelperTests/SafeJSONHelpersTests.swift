import Testing
import Foundation
@testable import asc_mcp

@Suite("SafeJSONHelpers Tests")
struct SafeJSONHelpersTests {
    @Test func safeValueWithValue() {
        let result = SafeJSONHelpers.safeValue("test")
        #expect(result as? String == "test")
    }

    @Test func safeValueWithNil() {
        let result = SafeJSONHelpers.safeValue(nil as String?)
        #expect(result is NSNull)
    }

    @Test func safeStringWithValue() {
        let result = SafeJSONHelpers.safeString("hello")
        #expect(result as? String == "hello")
    }

    @Test func safeStringWithNil() {
        let result = SafeJSONHelpers.safeString(nil)
        #expect(result is NSNull)
    }

    @Test func safeBoolWithValue() {
        let result = SafeJSONHelpers.safeBool(true)
        #expect(result as? Bool == true)
    }

    @Test func safeBoolWithNil() {
        let result = SafeJSONHelpers.safeBool(nil)
        #expect(result is NSNull)
    }

    @Test func safeIntWithValue() {
        let result = SafeJSONHelpers.safeInt(42)
        #expect(result as? Int == 42)
    }

    @Test func safeIntWithNil() {
        let result = SafeJSONHelpers.safeInt(nil)
        #expect(result is NSNull)
    }

    @Test func optionalJsonSafe() {
        let value: String? = "test"
        let safe = value.jsonSafe
        #expect(safe as? String == "test")

        let nilValue: String? = nil
        let nilSafe = nilValue.jsonSafe
        #expect(nilSafe is NSNull)
    }
}
