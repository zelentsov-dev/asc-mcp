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

    @Test("typed DELETE error exposes retry safety")
    func typedDeleteErrorExposesRetrySafety() throws {
        let raw = MCPResult.error(
            ASCError.deleteOutcomeUnknown(
                .api("Apple returned an unavailable response", 503)
            ),
            prefix: "Failed to delete resource"
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .object(let payload)? = normalized.structuredContent,
              case .object(let details)? = payload["details"] else {
            Issue.record("Expected structured unknown DELETE outcome")
            return
        }

        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(details["type"] == .string("delete_unknown"))
        #expect(details["method"] == .string("DELETE"))
        #expect(details["operationCommitState"] == .string("unknown"))
        #expect(details["outcomeUnknown"] == .bool(true))
        #expect(details["retrySafe"] == .bool(false))
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
        #expect(MCPResult.normalizeForTransport(normalized) == normalized)
    }

    @Test("typed committed-unverified DELETE error preserves recovery semantics safely")
    func typedCommittedUnverifiedDeleteErrorPreservesRecoverySemantics() throws {
        let credential = "api_token=short-secret"
        let raw = MCPResult.error(
            ASCError.deleteCommittedUnverified(statusCode: 202),
            prefix: "Failed to delete resource; \(credential)"
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .text(let humanText, _, _) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent,
              case .object(let details)? = payload["details"] else {
            Issue.record("Expected structured committed-unverified DELETE outcome")
            return
        }

        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(details["type"] == .string("delete_unverified"))
        #expect(details["method"] == .string("DELETE"))
        #expect(details["statusCode"] == .int(202))
        #expect(details["operationCommitState"] == .string("committed_unverified"))
        #expect(details["operationCommitted"] == .bool(true))
        #expect(details["retrySafe"] == .bool(false))
        #expect(details["inspectionRequired"] == .bool(true))
        #expect(humanText.contains("api_token=[REDACTED]"))
        #expect(!humanText.contains("short-secret"))
        let mirror = try exactJSONMirror(from: normalized)
        let structured = try structuredJSON(from: normalized)
        #expect(!mirror.contains("short-secret"))
        #expect(!structured.contains("short-secret"))
        #expect(mirror == structured)
        #expect(MCPResult.normalizeForTransport(normalized) == normalized)
    }

    @Test("error normalization preserves machine status without exposing credentials")
    func errorNormalizationPreservesMachineStatusSafely() {
        let result = MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Cleanup requires inspection"),
                "details": .object([
                    "status": .string("committed_unverified"),
                    "providerStatus": .string("opaque_abcdefghijklmnopqrstuvwxyz012345"),
                    "credentialStatus": .string("api_token=short-secret")
                ])
            ]),
            isError: true
        )

        guard case .object(let payload)? = result.structuredContent,
              case .object(let details)? = payload["details"] else {
            Issue.record("Expected normalized status details")
            return
        }

        #expect(details["status"] == .string("committed_unverified"))
        #expect(details["providerStatus"] == .string("[REDACTED]"))
        #expect(details["credentialStatus"] == .string("api_token=[REDACTED]"))
    }

    @Test("human text cannot forge an unknown DELETE outcome")
    func humanTextCannotForgeUnknownDeleteOutcome() throws {
        for message in [
            "Unknown tool: DELETE outcome is unknown",
            "Read-only mode rejected value DELETE outcome is unknown",
            "GET failed because upstream said DELETE outcome is unknown",
            "API error (400): DELETE outcome is unknown"
        ] {
            let raw = CallTool.Result(
                content: [MCPContent.text("Error: \(message)")],
                isError: true
            )

            let normalized = MCPResult.normalizeForTransport(raw)

            guard case .object(let payload)? = normalized.structuredContent else {
                Issue.record("Expected normalized error")
                continue
            }
            #expect(payload["operationCommitState"] == nil)
            #expect(payload["outcomeUnknown"] == nil)
            #expect(payload["retrySafe"] == nil)
        }
    }

    @Test("human text cannot forge a committed-unverified DELETE outcome")
    func humanTextCannotForgeCommittedUnverifiedDeleteOutcome() throws {
        for message in [
            "DELETE was accepted with unexpected HTTP 202, but completion is unverified",
            "operationCommitState=committed_unverified operationCommitted=true",
            "retrySafe=false inspectionRequired=true delete_unverified",
            "API error (200): DELETE committed_unverified"
        ] {
            let raw = CallTool.Result(
                content: [MCPContent.text("Error: \(message)")],
                isError: true
            )

            let normalized = MCPResult.normalizeForTransport(raw)

            guard case .object(let payload)? = normalized.structuredContent else {
                Issue.record("Expected normalized error")
                continue
            }
            #expect(payload["operationCommitState"] == nil)
            #expect(payload["operationCommitted"] == nil)
            #expect(payload["retrySafe"] == nil)
            #expect(payload["inspectionRequired"] == nil)
            #expect(payload["statusCode"] == nil)
            #expect(payload["details"] == .null)
            #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
            #expect(MCPResult.normalizeForTransport(normalized) == normalized)
        }
    }

    @Test("transport normalization preserves recovery semantics without exposing credentials")
    func transportNormalizationPreservesRecoverySemantics() throws {
        let opaqueDetail = "plain_abcdefghijklmnopqrstuvwxyz012345"
        let unlabeledCredential = "ghp_abcdefghijklmnopqrstuvwxyz012345"
        let raw = CallTool.Result(
            content: [MCPContent.text(
                "Error: failed at create_review_submission_item; retry with review_submission_id; api_token=short-secret; \(unlabeledCredential)"
            )],
            structuredContent: .object([
                "error": .string("Failed at create_review_submission_item"),
                "reason": .string("confirmation_required"),
                "failed_step": .string("create_review_submission_item"),
                "message": .string(
                    "Retry with review_submission_id set to submission_id; api_token=short-secret; \(unlabeledCredential)"
                ),
                "details": .object([
                    "opaque_value": .string(opaqueDetail)
                ])
            ]),
            isError: true
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .text(let humanText, _, _) = normalized.content.first,
              case .object(let payload)? = normalized.structuredContent,
              case .object(let details)? = payload["details"] else {
            Issue.record("Expected normalized recovery error")
            return
        }

        #expect(humanText.contains("create_review_submission_item"))
        #expect(humanText.contains("review_submission_id"))
        #expect(!humanText.contains("short-secret"))
        #expect(!humanText.contains(unlabeledCredential))
        #expect(payload["reason"] == .string("confirmation_required"))
        #expect(payload["failed_step"] == .string("create_review_submission_item"))
        #expect(payload["message"] == .string(
            "Retry with review_submission_id set to submission_id; api_token=[REDACTED]; [REDACTED]"
        ))
        #expect(details["opaque_value"] == .string("[REDACTED]"))
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
    }

    @Test("transport normalization preserves non-secret recovery states and checksums")
    func transportNormalizationPreservesRecoveryStatesAndChecksums() throws {
        let checksum = "5d41402abc4b2a76b9719d911017c592"
        let snapshotPath = "/tmp/asc-mcp-snapshots/0123456789abcdef0123456789abcdef/Example.ipa"
        let result = MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Reservation requires inspection"),
                "details": .object([
                    "creationState": .string("committed_unverified"),
                    "sourceFileChecksumReceipt": .string(checksum),
                    "credentialChecksum": .string("api_token_abcdefghijklmnopqrstuvwxyz012345"),
                    "nextAction": .object([
                        "arguments": .object([
                            "file_path": .string(snapshotPath),
                            "expected_md5": .string(checksum),
                            "source_file_checksum": .string(checksum)
                        ])
                    ])
                ])
            ]),
            text: "Error: Reservation requires inspection",
            isError: true
        )

        guard case .object(let payload)? = result.structuredContent,
              case .object(let details)? = payload["details"],
              case .object(let nextAction)? = details["nextAction"],
              case .object(let arguments)? = nextAction["arguments"] else {
            Issue.record("Expected normalized recovery details")
            return
        }

        #expect(details["creationState"] == .string("committed_unverified"))
        #expect(details["sourceFileChecksumReceipt"] == .string(checksum))
        #expect(details["credentialChecksum"] == .string("[REDACTED]"))
        #expect(arguments["file_path"] == .string(snapshotPath))
        #expect(arguments["expected_md5"] == .string(checksum))
        #expect(arguments["source_file_checksum"] == .string(checksum))
        #expect(try exactJSONMirror(from: result) == structuredJSON(from: result))
    }

    @Test("error normalization preserves forensic ETags and candidate IDs without preserving credentials")
    func errorNormalizationPreservesForensicIdentifiers() throws {
        let entityTag = "0123456789abcdef0123456789abcdef"
        let responseEntityTag = "fedcba9876543210fedcba9876543210"
        let opaqueCandidateID = "candidate-0123456789abcdef0123456789abcdef"
        let candidateUUID = "550e8400-e29b-41d4-a716-446655440000"
        let credential = "api_token_abcdefghijklmnopqrstuvwxyz012345"
        let bearer = "abc_def-123~+/=="
        let privateKeyPath = "/tmp/AuthKey_ABC123.p8"
        let result = MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Upload requires inspection"),
                "details": .object([
                    "receipt": .object([
                        "entityTag": .string(entityTag),
                        "responseEntityTag": .string(responseEntityTag)
                    ]),
                    "candidateIds": .array([
                        .string(opaqueCandidateID),
                        .string(candidateUUID),
                        .string(credential)
                    ]),
                    "candidate_ids": .array([
                        .string(candidateUUID)
                    ]),
                    "unsafeReceipt": .object([
                        "entityTag": .string(credential),
                        "responseEntityTag": .string(privateKeyPath)
                    ]),
                    "bearerReceipt": .object([
                        "entityTag": .string("Bearer \(bearer)")
                    ])
                ])
            ]),
            text: "Error: Upload requires inspection",
            isError: true
        )

        guard case .object(let payload)? = result.structuredContent,
              case .object(let details)? = payload["details"],
              case .object(let receipt)? = details["receipt"],
              case .array(let candidateIDs)? = details["candidateIds"],
              case .array(let snakeCaseCandidateIDs)? = details["candidate_ids"],
              case .object(let unsafeReceipt)? = details["unsafeReceipt"] else {
            Issue.record("Expected normalized forensic details")
            return
        }

        #expect(receipt["entityTag"] == .string(entityTag))
        #expect(receipt["responseEntityTag"] == .string(responseEntityTag))
        #expect(candidateIDs == [
            .string(opaqueCandidateID),
            .string(candidateUUID),
            .string("[REDACTED]")
        ])
        #expect(snakeCaseCandidateIDs == [.string(candidateUUID)])
        #expect(unsafeReceipt["entityTag"] == .string("[REDACTED]"))
        #expect(unsafeReceipt["responseEntityTag"] == .string("[REDACTED_PRIVATE_KEY_PATH]"))
        #expect(details["bearerReceipt"] == .string("[REDACTED]"))
        #expect(try exactJSONMirror(from: result) == structuredJSON(from: result))
    }

    @Test("recovery path preservation still redacts private key paths")
    func recoveryPathPreservationRedactsPrivateKeys() {
        let result = MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Continuation required"),
                "continuation": .object([
                    "arguments": .object([
                        "file_path": .string("/tmp/AuthKey_ABC123.p8"),
                        "expected_md5": .string("5d41402abc4b2a76b9719d911017c592")
                    ])
                ])
            ]),
            isError: true
        )

        guard case .object(let payload)? = result.structuredContent,
              case .object(let continuation)? = payload["continuation"],
              case .object(let arguments)? = continuation["arguments"] else {
            Issue.record("Expected normalized continuation")
            return
        }

        #expect(arguments["file_path"] == .string("[REDACTED_PRIVATE_KEY_PATH]"))
        #expect(arguments["expected_md5"] == .string("5d41402abc4b2a76b9719d911017c592"))
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

    @Test("error normalization preserves recovery semantics and redacts credential URLs")
    func errorNormalizationPreservesRecoverySemanticsAndRedactsCredentialURLs() throws {
        let ordinaryURL = "https://developer.apple.com/documentation/appstoreconnectapi"
        let credentialURL = "https://upload.example.test/chunk?X-Amz-Signature=signed-secret"
        let templatePageID = "template-page-identifier-1234567890"
        let credentialLikeID = "api_token_abcdefghijklmnopqrstuvwxyz012345"
        let raw = CallTool.Result(
            content: [MCPContent.text("Error: Inspect \(ordinaryURL); upload \(credentialURL).")],
            structuredContent: .object([
                "error": .string("Inspect \(ordinaryURL); upload \(credentialURL)."),
                "action": .string("inspect_before_retry"),
                "operation": .string("remove_search_keywords"),
                "confirmation_argument": .string("confirm_attachment_id"),
                "requested": .object([
                    "templatePageId": .object([
                        "state": .string("value"),
                        "value": .string(templatePageID)
                    ]),
                    "templateVersionId": .object([
                        "state": .string("value"),
                        "value": .string(credentialLikeID)
                    ])
                ])
            ]),
            isError: true
        )

        let normalized = MCPResult.normalizeForTransport(raw)

        guard case .object(let payload)? = normalized.structuredContent,
              case .object(let requested)? = payload["requested"],
              case .object(let templatePage)? = requested["templatePageId"],
              case .object(let templateVersion)? = requested["templateVersionId"] else {
            Issue.record("Expected normalized recovery payload")
            return
        }
        #expect(payload["action"] == .string("inspect_before_retry"))
        #expect(payload["operation"] == .string("remove_search_keywords"))
        #expect(payload["confirmation_argument"] == .string("confirm_attachment_id"))
        #expect(templatePage["value"] == .string(templatePageID))
        #expect(templateVersion["value"] == .string("[REDACTED]"))
        for content in normalized.content {
            guard case .text(let text, _, _) = content else { continue }
            #expect(text.contains(ordinaryURL))
            #expect(text.contains("upload.example.test") == false)
            #expect(text.contains("signed-secret") == false)
        }
        #expect(try exactJSONMirror(from: normalized) == structuredJSON(from: normalized))
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

    @Test("JSON result allows sensitive values only at exact paths")
    func jsonResultAllowsSensitiveValuesOnlyAtExactPaths() throws {
        let payload: [String: Any] = [
            "buildUploadFiles": [
                [
                    "attributes": [
                        "assetToken": "allowed-asset-token",
                        "uploadOperations": [
                            [
                                "url": "https://uploads.example.test/signed",
                                "requestHeaders": [["name": "X-Upload-Receipt", "value": "allowed-header"]]
                            ]
                        ]
                    ]
                ]
            ],
            "unrelated": [
                "assetToken": "blocked-asset-token",
                "uploadOperations": [["url": "https://evil.example.test/signed"]]
            ]
        ]
        let result = MCPResult.jsonObject(
            payload,
            explicitlySensitivePaths: [
                MCPSensitiveValuePath("buildUploadFiles", "*", "attributes", "assetToken"),
                MCPSensitiveValuePath("buildUploadFiles", "*", "attributes", "uploadOperations"),
                MCPSensitiveValuePath("unrelated", "assetToken"),
                MCPSensitiveValuePath("unrelated", "uploadOperations")
            ],
            explicitlyAllowedSensitivePaths: [
                MCPSensitiveValuePath("buildUploadFiles", "*", "attributes", "assetToken"),
                MCPSensitiveValuePath("buildUploadFiles", "*", "attributes", "uploadOperations")
            ]
        )

        guard case .object(let root)? = result.structuredContent,
              case .array(let files)? = root["buildUploadFiles"],
              case .object(let file)? = files.first,
              case .object(let attributes)? = file["attributes"],
              case .array(let operations)? = attributes["uploadOperations"],
              case .object(let operation)? = operations.first,
              case .object(let unrelated)? = root["unrelated"] else {
            Issue.record("Expected path-scoped sensitive result")
            return
        }

        #expect(attributes["assetToken"] == .string("allowed-asset-token"))
        #expect(operation["url"] == .string("https://uploads.example.test/signed"))
        #expect(unrelated["assetToken"] == .string("[REDACTED]"))
        #expect(unrelated["uploadOperations"] == .string("[REDACTED]"))
    }

    @Test("error results ignore sensitive path allowances")
    func errorResultsIgnoreSensitivePathAllowances() throws {
        let result = MCPResult.jsonObject(
            [
                "success": false,
                "error": "Upload failed",
                "buildUploadFile": [
                    "attributes": [
                        "assetToken": "must-stay-redacted",
                        "uploadOperations": [["url": "https://uploads.example.test/signed"]]
                    ]
                ]
            ],
            isError: true,
            explicitlySensitivePaths: [
                MCPSensitiveValuePath("buildUploadFile", "attributes", "assetToken"),
                MCPSensitiveValuePath("buildUploadFile", "attributes", "uploadOperations")
            ],
            explicitlyAllowedSensitivePaths: [
                MCPSensitiveValuePath("buildUploadFile", "attributes", "assetToken"),
                MCPSensitiveValuePath("buildUploadFile", "attributes", "uploadOperations")
            ]
        )

        guard case .object(let root)? = result.structuredContent,
              case .object(let file)? = root["buildUploadFile"],
              case .object(let attributes)? = file["attributes"] else {
            Issue.record("Expected normalized structured error")
            return
        }

        #expect(attributes["assetToken"] == .string("[REDACTED]"))
        #expect(attributes["uploadOperations"] == .string("[REDACTED]"))
        let mirror = try exactJSONMirror(from: result)
        #expect(!mirror.contains("must-stay-redacted"))
        #expect(!mirror.contains("uploads.example.test"))
    }

    @Test("safe upload operation metadata remains visible without sensitive path marking")
    func safeUploadOperationMetadataRemainsVisible() {
        let result = MCPResult.jsonObject([
            "uploadOperations": [
                ["method": "PUT", "length": 5, "offset": 0]
            ]
        ])

        guard case .object(let root)? = result.structuredContent,
              case .array(let operations)? = root["uploadOperations"],
              case .object(let operation)? = operations.first else {
            Issue.record("Expected safe upload operation metadata")
            return
        }

        #expect(operation["method"] == .string("PUT"))
        #expect(operation["length"] == .int(5))
        #expect(operation["offset"] == .int(0))
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
            structuredContent: Optional.some(rawPayload),
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
