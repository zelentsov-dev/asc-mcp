import Testing
import Foundation
@testable import asc_mcp

@Suite("JSONFormatter Tests")
struct JSONFormatterTests {
    @Test func formatSimpleObject() {
        let result = JSONFormatter.formatJSON(["key": "value"])
        #expect(result.contains("key"))
        #expect(result.contains("value"))
    }

    @Test func formatPrettyPrinted() {
        let result = JSONFormatter.formatJSON(["a": 1, "b": 2])
        #expect(result.contains("\n"))
    }

    @Test func formatCompactJSON() {
        let result = JSONFormatter.formatCompactJSON(["key": "value"])
        #expect(!result.contains("\n"))
        #expect(result.contains("key"))
    }

    @Test func formatEmptyObject() {
        let result = JSONFormatter.formatJSON([:] as [String: Any])
        #expect(result.contains("{"))
        #expect(result.contains("}"))
    }

    @Test func formatArray() {
        let result = JSONFormatter.formatJSON([1, 2, 3])
        #expect(result.contains("1"))
        #expect(result.contains("3"))
    }

    @Test func formatNestedObject() {
        let result = JSONFormatter.formatJSON(["outer": ["inner": "value"]])
        #expect(result.contains("outer"))
        #expect(result.contains("inner"))
    }
}
