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

    @Test("error result preserves long semantic identifiers")
    func errorResultPreservesLongSemanticIdentifiers() throws {
        let message = "Use beta_app_create_localization or pricing_get_availability_v2 with REPLACE_INTRO_OFFERS"
        let result = MCPResult.error(message)

        guard case .text(let text, _, _) = result.content.first,
              case .object(let payload)? = result.structuredContent else {
            Issue.record("Expected text and structured error content")
            return
        }

        #expect(text == "Error: \(message)")
        #expect(payload["error"] == .string(message))
    }

    @Test("error result still redacts bearer, base64url, and private-key secrets")
    func errorResultRedactsCredentials() throws {
        let bearer = "abc_def-123~+/=="
        let base64URL = "eyJhbGciOiJFUzI1NiJ9_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
        let lowerSnakeSecret = "api_token_abcdefghijklmnopqrstuvwxyz012345"
        let upperSnakeSecret = "TOKEN_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        let prefixedSecret = "internal_secret-A1B2C3D4"
        let privateKeyPath = "/tmp/AuthKey_ABC123.p8"
        let privateKey = "-----BEGIN PRIVATE KEY-----\nabcdefghijklmnopqrstuvwxyzABCD\n-----END PRIVATE KEY-----"
        let result = MCPResult.error(
            "bearer \(bearer), token \(base64URL), lower \(lowerSnakeSecret), upper \(upperSnakeSecret), prefixed \(prefixedSecret), key \(privateKeyPath)\n\(privateKey)"
        )

        guard case .text(let text, _, _) = result.content.first,
              case .object(let payload)? = result.structuredContent,
              case .string(let error)? = payload["error"] else {
            Issue.record("Expected text and structured error content")
            return
        }

        #expect(text.contains("Bearer [REDACTED]"))
        #expect(text.contains("token [REDACTED]"))
        #expect(text.contains("key [REDACTED_PRIVATE_KEY_PATH]"))
        #expect(text.contains("[REDACTED_PRIVATE_KEY]"))
        #expect(error.contains("Bearer [REDACTED]"))
        #expect(error.contains("token [REDACTED]"))
        #expect(error.contains("key [REDACTED_PRIVATE_KEY_PATH]"))
        #expect(error.contains("[REDACTED_PRIVATE_KEY]"))
        #expect(!text.contains(bearer))
        #expect(!text.contains(base64URL))
        #expect(!text.contains(lowerSnakeSecret))
        #expect(!text.contains(upperSnakeSecret))
        #expect(!text.contains(prefixedSecret))
        #expect(!text.contains(privateKeyPath))
        #expect(!text.contains(privateKey))
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

    @Test("JSON result sanitizes nested sensitive fields in structured and text output")
    func jsonResultSanitizesNestedSensitiveFields() throws {
        let result = MCPResult.jsonObject([
            "success": true,
            "review_details": [
                "attributes": [
                    "demoAccountName": "demo@example.com",
                    "demoAccountPassword": "super-secret",
                    "api_token": "token-value",
                    "privateKeyContent": "private-key-value"
                ]
            ]
        ])

        guard case .object(let root)? = result.structuredContent,
              case .object(let details)? = root["review_details"],
              case .object(let attributes)? = details["attributes"] else {
            Issue.record("Expected nested structured object")
            return
        }

        #expect(attributes["demoAccountName"] == .string("demo@example.com"))
        #expect(attributes["demoAccountPassword"] == .string("[REDACTED]"))
        #expect(attributes["api_token"] == .string("[REDACTED]"))
        #expect(attributes["privateKeyContent"] == .string("[REDACTED]"))

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(!text.contains("super-secret"))
        #expect(!text.contains("token-value"))
        #expect(!text.contains("private-key-value"))
    }
}
