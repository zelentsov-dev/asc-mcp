import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("MCP Result Builder Tests")
struct MCPResultBuilderTests {
    @Test("text content uses current MCP text case shape")
    func textContentUsesCurrentShape() throws {
        let content = MCPContent.text("hello")

        guard case .text(let text, let annotations, let meta) = content else {
            Issue.record("Expected text content")
            return
        }

        #expect(text == "hello")
        #expect(annotations == nil)
        #expect(meta == nil)
    }

    @Test("JSON result includes text and structuredContent")
    func jsonResultIncludesTextAndStructuredContent() throws {
        let value = try MCPValue.fromAny([
            "success": true,
            "items": [1, "two"]
        ])

        let result = MCPResult.json(value)

        #expect(result.structuredContent == value)
        #expect(result.isError == nil)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("\"success\" : true"))
        #expect(text.contains("\"items\""))
    }

    @Test("error result sets isError and structured error payload")
    func errorResultSetsIsError() throws {
        let result = MCPResult.error("Bad input")

        #expect(result.isError == true)
        #expect(result.structuredContent != nil)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text == "Error: Bad input")
    }

    @Test("fromAny handles nulls, dates, and nested dictionaries")
    func fromAnyHandlesCommonResultDictionaries() throws {
        let date = Date(timeIntervalSince1970: 0)
        let value = try MCPValue.fromAny([
            "name": "Demo",
            "count": 2,
            "enabled": true,
            "missing": NSNull(),
            "date": date,
            "nested": ["key": "value"]
        ])

        guard case .object(let object) = value else {
            Issue.record("Expected object")
            return
        }

        #expect(object["name"] == .string("Demo"))
        #expect(object["count"] == .int(2))
        #expect(object["enabled"] == .bool(true))
        #expect(object["missing"] == .null)
        #expect(object["date"] == .string("1970-01-01T00:00:00Z"))
    }
}
