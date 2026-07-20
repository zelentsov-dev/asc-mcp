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
        #expect(result.content.count == 2)

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text == "Error: Bad input")
        #expect(try exactJSONMirror(from: result) == structuredJSON(from: result))
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
        let apiKeySecret = "APIKEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        let lowerSnakeSecret = "api_token_abcdefghijklmnopqrstuvwxyz012345"
        let upperSnakeSecret = "TOKEN_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        let prefixedSecret = "internal_secret-A1B2C3D4"
        let privateKeyPath = "/tmp/AuthKey_ABC123.p8"
        let privateKey = "-----BEGIN PRIVATE KEY-----\nabcdefghijklmnopqrstuvwxyzABCD\n-----END PRIVATE KEY-----"
        let result = MCPResult.error(
            "bearer \(bearer), token \(base64URL), API key \(apiKeySecret), lower \(lowerSnakeSecret), upper \(upperSnakeSecret), prefixed \(prefixedSecret), resource id: \(lowerSnakeSecret), key \(privateKeyPath)\n\(privateKey)"
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
        #expect(!text.contains(apiKeySecret))
        #expect(!text.contains(lowerSnakeSecret))
        #expect(!text.contains(upperSnakeSecret))
        #expect(!text.contains(prefixedSecret))
        #expect(!text.contains(privateKeyPath))
        #expect(!text.contains(privateKey))
    }

    @Test("identifier fields do not exempt credential-like values")
    func identifierFieldsDoNotExemptCredentials() throws {
        let token = "api_token_abcdefghijklmnopqrstuvwxyz012345"
        let apiKey = "APIKEY_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
        let result = MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Invalid recovery identifiers"),
                "resourceId": .string(token),
                "details": .object([
                    "attachment_id": .string(apiKey)
                ])
            ]),
            text: "Error: resource id: \(token); attachment_id '\(apiKey)'",
            isError: true
        )

        guard case .object(let payload)? = result.structuredContent,
              case .object(let details)? = payload["details"],
              case .text(let humanText, _, _) = result.content.first else {
            Issue.record("Expected canonical credential error")
            return
        }

        #expect(payload["resourceId"] == .string("[REDACTED]"))
        #expect(details["attachment_id"] == .string("[REDACTED]"))
        #expect(!humanText.contains(token))
        #expect(!humanText.contains(apiKey))
        #expect(try exactJSONMirror(from: result) == structuredJSON(from: result))
    }

    @Test("transport normalization redacts short credential assignments")
    func transportNormalizationRedactsShortCredentialAssignments() throws {
        let raw = CallTool.Result(
            content: [MCPContent.text(
                #"Error: request api_token=short-secret; body {"password":"tiny","authorization": "brief"}"#
            )],
            structuredContent: .object([
                "error": .string("Bad request"),
                "api_token": .string("short-secret"),
                "details": .object([
                    "password": .string("tiny"),
                    "authorization": .string("brief")
                ])
            ]),
            isError: true
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .text(let humanText, _, _) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent,
              case .object(let details)? = payload["details"] else {
            Issue.record("Expected normalized short-credential error")
            return
        }

        #expect(!humanText.contains("short-secret"))
        #expect(!humanText.contains("tiny"))
        #expect(!humanText.contains("brief"))
        #expect(payload["api_token"] == .string("[REDACTED]"))
        #expect(details["password"] == .string("[REDACTED]"))
        #expect(details["authorization"] == .string("[REDACTED]"))
        let mirror = try exactJSONMirror(from: normalized)
        #expect(!mirror.contains("short-secret"))
        #expect(!mirror.contains("tiny"))
        #expect(!mirror.contains("brief"))
        #expect(mirror == (try structuredJSON(from: normalized)))
        #expect(MCPResult.normalizeForTransport(normalized) == normalized)
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

    @Test("transport normalization preserves rich errors and appends one exact mirror")
    func transportNormalizationPreservesRichErrors() throws {
        let bearer = "abc_def-123~+/=="
        let privateKeyPath = "/tmp/AuthKey_ABC123.p8"
        let annotations = Resource.Annotations(audience: [.user], priority: 0.9)
        let textMetadata = Metadata(additionalFields: ["source": .string("worker")])
        let resultMetadata = Metadata(additionalFields: ["request": .string("req-123")])
        let image = Tool.Content.image(
            data: "encoded-image",
            mimeType: "image/png",
            annotations: nil,
            _meta: nil
        )
        let raw = CallTool.Result(
            content: [
                .text(
                    text: "Error: Upload failed for Bearer \(bearer) using \(privateKeyPath)",
                    annotations: annotations,
                    _meta: textMetadata
                ),
                image,
                .text(text: "Retry is safe", annotations: nil, _meta: nil)
            ],
            structuredContent: .object([
                "message": .string("Upload failed for Bearer \(bearer) using \(privateKeyPath)"),
                "statusCode": .int(503),
                "retrySafe": .bool(true),
                "resource": .string("data:text/plain;base64,SGVsbG8="),
                "progress": .double(1.0),
                "api_token": .string("secret-token")
            ]),
            isError: true,
            _meta: resultMetadata
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        #expect(normalized.isError == true)
        #expect(normalized._meta == resultMetadata)
        #expect(normalized.content.contains(image))
        #expect(normalized.content.count == 4)

        guard case .text(let humanText, let preservedAnnotations, let preservedMetadata) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent else {
            Issue.record("Expected normalized text and structured error")
            return
        }

        #expect(preservedAnnotations == annotations)
        #expect(preservedMetadata == textMetadata)
        #expect(humanText.contains("Bearer [REDACTED]"))
        #expect(humanText.contains("[REDACTED_PRIVATE_KEY_PATH]"))
        #expect(!humanText.contains(bearer))
        #expect(!humanText.contains(privateKeyPath))
        #expect(payload["success"] == .bool(false))
        #expect(payload["error"] == .string(
            "Upload failed for Bearer [REDACTED] using [REDACTED_PRIVATE_KEY_PATH]"
        ))
        #expect(payload["details"] == .null)
        #expect(payload["statusCode"] == .int(503))
        #expect(payload["retrySafe"] == .bool(true))
        #expect(payload["resource"] == .string("data:text/plain;base64,SGVsbG8="))
        #expect(payload["progress"] == .double(1.0))
        #expect(payload["api_token"] == .string("[REDACTED]"))
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
        #expect(MCPResult.normalizeForTransport(normalized) == normalized)
    }

    @Test("transport normalization wraps non-object details and preserves non-text content")
    func transportNormalizationWrapsNonObjectDetails() throws {
        let audio = Tool.Content.audio(
            data: "encoded-audio",
            mimeType: "audio/wav",
            annotations: nil,
            _meta: nil
        )
        let raw = CallTool.Result(
            content: [audio],
            structuredContent: .array([.string("upstream failure"), .double(.nan)]),
            isError: true
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .text(let humanText, _, _) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent else {
            Issue.record("Expected synthesized text and structured error")
            return
        }

        #expect(humanText == "Error: Tool execution failed")
        #expect(normalized.content.contains(audio))
        #expect(payload["success"] == .bool(false))
        #expect(payload["error"] == .string("Tool execution failed"))
        #expect(payload["details"] == .array([.string("upstream failure"), .null]))
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
        #expect(MCPResult.normalizeForTransport(normalized) == normalized)
    }

    @Test("transport normalization replaces unsafe pre-existing JSON mirrors")
    func transportNormalizationReplacesUnsafeJSONMirrors() throws {
        let rawPayload: Value = .object([
            "error": .string("Bad input"),
            "api_token": .string("short-secret")
        ])
        let rawMirror = try MCPValue.prettyJSONString(from: rawPayload)
        let raw = CallTool.Result(
            content: [
                MCPContent.text(rawMirror),
                MCPContent.text("Error: Bad input")
            ],
            structuredContent: rawPayload,
            isError: true
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        #expect(normalized.content.count == 2)
        guard case .text(let humanText, _, _) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent else {
            Issue.record("Expected safe normalized error")
            return
        }
        #expect(humanText == "Error: Bad input")
        #expect(payload["api_token"] == .string("[REDACTED]"))
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
        for content in normalized.content {
            if case .text(let text, _, _) = content {
                #expect(!text.contains("short-secret"))
            }
        }
    }

    @Test("transport normalization leaves successful results unchanged")
    func transportNormalizationLeavesSuccessUnchanged() {
        let result = CallTool.Result(
            content: [MCPContent.text("Success")],
            structuredContent: .object(["success": .bool(true)]),
            isError: nil,
            _meta: Metadata(additionalFields: ["source": .string("worker")])
        )

        #expect(MCPResult.normalizeForTransport(result) == result)
    }
}

private func exactJSONMirror(from result: CallTool.Result) throws -> String {
    guard case .text(let mirror, _, _) = result.content.last else {
        Issue.record("Expected JSON mirror as the last text content block")
        throw MCPResultBuilderTestFailure.missingMirror
    }
    return mirror
}

private func structuredJSON(from result: CallTool.Result) throws -> String {
    guard let structuredContent = result.structuredContent else {
        Issue.record("Expected structured content")
        throw MCPResultBuilderTestFailure.missingStructuredContent
    }
    return try MCPValue.compactJSONString(from: structuredContent)
}

private enum MCPResultBuilderTestFailure: Error {
    case missingMirror
    case missingStructuredContent
}
