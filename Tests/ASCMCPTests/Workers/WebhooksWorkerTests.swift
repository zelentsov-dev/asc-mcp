import Foundation
import CryptoKit
import MCP
import Testing
@testable import asc_mcp

@Suite("Webhooks Worker Tests")
struct WebhooksWorkerTests {
    @Test("missing required parameters return isError")
    func missingRequiredParametersReturnErrors() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let list = try await worker.handleTool(CallTool.Parameters(name: "webhooks_list", arguments: nil))
        let get = try await worker.handleTool(CallTool.Parameters(name: "webhooks_get", arguments: nil))
        let create = try await worker.handleTool(CallTool.Parameters(name: "webhooks_create", arguments: nil))
        let update = try await worker.handleTool(CallTool.Parameters(name: "webhooks_update", arguments: nil))
        let delete = try await worker.handleTool(CallTool.Parameters(name: "webhooks_delete", arguments: nil))
        let deliveries = try await worker.handleTool(CallTool.Parameters(name: "webhooks_list_deliveries", arguments: nil))
        let redeliver = try await worker.handleTool(CallTool.Parameters(name: "webhooks_redeliver", arguments: nil))
        let ping = try await worker.handleTool(CallTool.Parameters(name: "webhooks_ping", arguments: nil))
        let verify = try await worker.handleTool(CallTool.Parameters(name: "webhooks_verify_signature", arguments: nil))
        let parse = try await worker.handleTool(CallTool.Parameters(name: "webhooks_parse_payload", arguments: nil))
        let triage = try await worker.handleTool(CallTool.Parameters(name: "webhooks_triage_event", arguments: nil))

        #expect(list.isError == true)
        #expect(get.isError == true)
        #expect(create.isError == true)
        #expect(update.isError == true)
        #expect(delete.isError == true)
        #expect(deliveries.isError == true)
        #expect(redeliver.isError == true)
        #expect(ping.isError == true)
        #expect(verify.isError == true)
        #expect(parse.isError == true)
        #expect(triage.isError == true)
    }

    @Test("create validates URL and event types before network calls")
    func createValidatesURLAndEventTypes() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let badURL = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("123"),
                    "name": .string("Demo"),
                    "url": .string("not-a-url"),
                    "secret": .string("super-secret"),
                    "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                ]
            )
        )
        #expect(badURL.isError == true)

        let badEvent = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("123"),
                    "name": .string("Demo"),
                    "url": .string("https://example.com/webhook"),
                    "secret": .string("super-secret"),
                    "event_types": .array([.string("UNKNOWN_EVENT")])
                ]
            )
        )
        #expect(badEvent.isError == true)
    }

    @Test("create and update reject unsafe callback URLs before network calls")
    func createAndUpdateRejectUnsafeCallbackURLs() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)
        let secret = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        let invalidURLs = [
            "http://example.com/webhook",
            "https://user@example.com/webhook",
            "https://user:password@example.com/webhook",
            "https:///webhook",
            "https://example.com/webhook#fragment",
            "https://example.com:notaport/webhook",
            "not-a-url"
        ]

        for url in invalidURLs {
            let create = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_create",
                    arguments: [
                        "app_id": .string("app-1"),
                        "name": .string("Release events"),
                        "url": .string(url),
                        "secret": .string(secret),
                        "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                    ]
                )
            )
            #expect(create.isError == true)
            #expect(textContent(create).contains("absolute HTTPS URL"))

            let update = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_update",
                    arguments: [
                        "webhook_id": .string("webhook-1"),
                        "url": .string(url)
                    ]
                )
            )
            #expect(update.isError == true)
            #expect(textContent(update).contains("absolute HTTPS URL"))
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("create and update preserve a valid HTTPS callback port path and query")
    func createAndUpdateAcceptValidHTTPSCallbackURL() async throws {
        let callbackURL = "https://hooks.example.com:8443/app-store/events?tenant=abc&mode=full"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "webhooks",
                "id": "webhook-1",
                "attributes": {
                  "enabled": true,
                  "eventTypes": ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
                  "name": "Release events",
                  "url": "\(callbackURL)"
                }
              }
            }
            """),
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "webhooks",
                "id": "webhook-1",
                "attributes": {
                  "enabled": true,
                  "eventTypes": ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
                  "name": "Release events",
                  "url": "\(callbackURL)"
                }
              }
            }
            """)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)
        let secret = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

        let create = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("app-1"),
                    "name": .string("Release events"),
                    "url": .string(callbackURL),
                    "secret": .string(secret),
                    "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                ]
            )
        )
        let update = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_update",
                arguments: [
                    "webhook_id": .string("webhook-1"),
                    "url": .string(callbackURL)
                ]
            )
        )

        #expect(create.isError == nil)
        #expect(update.isError == nil)
        #expect(await transport.requestCount() == 2)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let body = try #require(request.httpBody)
            let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let data = try #require(root["data"] as? [String: Any])
            let attributes = try #require(data["attributes"] as? [String: Any])
            #expect(attributes["url"] as? String == callbackURL)
        }
    }

    @Test("create and update reject weak webhook secrets before network calls")
    func createAndUpdateRejectWeakSecrets() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)

        let weakSecrets = [
            "",
            "short-secret",
            String(repeating: "😀", count: 16),
            String(repeating: " ", count: 32),
            String(repeating: "a", count: 32),
            String(repeating: "abcd", count: 8),
            String(repeating: "0123456789abcdef", count: 2)
        ]
        for secret in weakSecrets {
            let create = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_create",
                    arguments: [
                        "app_id": .string("app-1"),
                        "name": .string("Release events"),
                        "url": .string("https://example.com/webhook"),
                        "secret": .string(secret),
                        "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                    ]
                )
            )
            #expect(create.isError == true)
            #expect(textContent(create).contains("at least 32 characters"))
            if !secret.isEmpty {
                #expect(!textContent(create).contains(secret))
            }

            let update = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_update",
                    arguments: [
                        "webhook_id": .string("webhook-1"),
                        "secret": .string(secret)
                    ]
                )
            )
            #expect(update.isError == true)
            #expect(textContent(update).contains("at least 32 characters"))
            if !secret.isEmpty {
                #expect(!textContent(update).contains(secret))
            }
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("create and update schemas advertise the webhook secret minimum")
    func secretSchemasAdvertiseMinimum() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()

        for toolName in ["webhooks_create", "webhooks_update"] {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try #require(tool.inputSchema.objectValue)
            let properties = try #require(root["properties"]?.objectValue)
            let secret = try #require(properties["secret"]?.objectValue)
            #expect(secret["minLength"] == .int(WebhooksWorker.minimumWebhookSecretLength))
        }
    }

    @Test("create and update schemas advertise HTTPS callback requirements")
    func callbackURLSchemasAdvertiseHTTPSRequirements() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()

        for toolName in ["webhooks_create", "webhooks_update"] {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try #require(tool.inputSchema.objectValue)
            let properties = try #require(root["properties"]?.objectValue)
            let url = try #require(properties["url"]?.objectValue)
            let description = try #require(url["description"]?.stringValue)
            #expect(description.contains("Absolute HTTPS callback URL"))
            #expect(description.contains("URL user info (user/password) and fragments are not allowed"))
        }
    }

    @Test("create accepts a strong hex-like webhook secret without returning it")
    func createAcceptsStrongSecretWithoutReturningIt() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "webhooks",
                "id": "webhook-1",
                "attributes": {
                  "enabled": true,
                  "eventTypes": ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
                  "name": "Release events",
                  "url": "https://example.com/webhook"
                }
              }
            }
            """)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)
        let secret = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("app-1"),
                    "name": .string("Release events"),
                    "url": .string("https://example.com/webhook"),
                    "secret": .string(secret),
                    "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                ]
            )
        )

        #expect(result.isError == nil)
        #expect(await transport.requestCount() == 1)
        #expect(!textContent(result).contains(secret))
        let structured = try #require(result.structuredContent)
        let structuredData = try JSONEncoder().encode(structured)
        let structuredText = try #require(String(data: structuredData, encoding: .utf8))
        #expect(!structuredText.contains(secret))
    }

    @Test("request models encode Apple OpenAPI JSON API shape")
    func requestModelsEncodeAppleShape() throws {
        let create = ASCWebhookCreateRequest(
            appID: "app-1",
            name: "Release events",
            url: "https://example.com/webhook",
            secret: "secret",
            eventTypes: ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
            enabled: true
        )

        let createJSON = try jsonObject(create)
        let createData = try #require(createJSON["data"] as? [String: Any])
        let createAttributes = try #require(createData["attributes"] as? [String: Any])
        let createRelationships = try #require(createData["relationships"] as? [String: Any])

        #expect(createData["type"] as? String == "webhooks")
        #expect(createAttributes["enabled"] as? Bool == true)
        #expect(createAttributes["name"] as? String == "Release events")
        #expect(createAttributes["secret"] as? String == "secret")
        #expect(createRelationships["app"] != nil)

        let update = ASCWebhookUpdateRequest(
            webhookID: "webhook-1",
            attributes: .init(
                enabled: false,
                eventTypes: nil,
                name: nil,
                secret: nil,
                url: nil
            )
        )
        let updateJSON = try jsonObject(update)
        let updateData = try #require(updateJSON["data"] as? [String: Any])
        let updateAttributes = try #require(updateData["attributes"] as? [String: Any])

        #expect(updateData["id"] as? String == "webhook-1")
        #expect(updateData["type"] as? String == "webhooks")
        #expect(updateAttributes["enabled"] as? Bool == false)
        #expect(updateAttributes["name"] == nil)

        let redelivery = ASCWebhookDeliveryCreateRequest(templateDeliveryID: "delivery-1")
        let redeliveryJSON = try jsonObject(redelivery)
        let redeliveryData = try #require(redeliveryJSON["data"] as? [String: Any])
        #expect(redeliveryData["type"] as? String == "webhookDeliveries")

        let ping = ASCWebhookPingCreateRequest(webhookID: "webhook-1")
        let pingJSON = try jsonObject(ping)
        let pingData = try #require(pingJSON["data"] as? [String: Any])
        #expect(pingData["type"] as? String == "webhookPings")
    }

    @Test("verify signature validates Apple x-apple-signature HMAC")
    func verifySignatureValidatesAppleHeader() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let payload = Self.webhookEnvelopePayload
        let signature = Self.signature(secret: "top-secret", payload: payload)

        let valid = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_verify_signature",
                arguments: [
                    "secret": .string("top-secret"),
                    "signature": .string("x-apple-signature:hmacsha256=\(signature)"),
                    "payload": .string(payload)
                ]
            )
        )
        let validObject = try structuredObject(valid)
        #expect(validObject["success"] == .bool(true))
        #expect(validObject["valid"] == .bool(true))
        #expect(validObject["algorithm"] == .string("hmacsha256"))

        let invalid = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_verify_signature",
                arguments: [
                    "secret": .string("top-secret"),
                    "signature": .string("hmacsha256=\(signature)"),
                    "payload": .string(payload + " ")
                ]
            )
        )
        let invalidObject = try structuredObject(invalid)
        #expect(invalidObject["success"] == .bool(true))
        #expect(invalidObject["valid"] == .bool(false))
    }

    @Test("parse payload normalizes webhook envelope and nested event payload")
    func parsePayloadNormalizesEnvelope() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_parse_payload",
                arguments: [
                    "payload": .string(Self.webhookEnvelopePayload)
                ]
            )
        )

        let object = try structuredObject(result)
        #expect(object["success"] == .bool(true))

        let event = try #require(object["event"]?.objectValue)
        #expect(event["id"] == .string("event-1"))
        #expect(event["resourceType"] == .string("webhookEvents"))
        #expect(event["eventType"] == .string("BUILD_UPLOAD_STATE_UPDATED"))
        #expect(event["payloadFormat"] == .string("json"))

        let related = try #require(event["relatedResource"]?.objectValue)
        #expect(related["type"] == .string("builds"))
        #expect(related["id"] == .string("build-1"))

        let recommendations = try #require(object["recommendedToolCalls"]?.arrayValue)
        #expect(recommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("builds_get")
        })
    }

    @Test("parse payload also accepts direct Apple event payload")
    func parsePayloadAcceptsDirectEventPayload() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_parse_payload",
                arguments: [
                    "payload": .string(Self.directAppVersionStatePayload)
                ]
            )
        )

        let object = try structuredObject(result)
        let event = try #require(object["event"]?.objectValue)
        #expect(event["eventType"] == .string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"))

        let related = try #require(event["relatedResource"]?.objectValue)
        #expect(related["type"] == .string("appStoreVersions"))
        #expect(related["id"] == .string("version-1"))
    }

    @Test("triage event maps beta feedback crashes to actionable tools")
    func triageEventMapsCrashFeedback() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_triage_event",
                arguments: [
                    "event_type": .string("BETA_FEEDBACK_CRASH_SUBMISSION_CREATED"),
                    "resource_type": .string("betaFeedbackCrashSubmissions"),
                    "resource_id": .string("crash-1"),
                    "delivery_state": .string("FAILED"),
                    "http_status_code": .int(503),
                    "delivery_id": .string("delivery-1")
                ]
            )
        )

        let object = try structuredObject(result)
        #expect(object["success"] == .bool(true))
        #expect(object["severity"] == .string("high"))

        let recommendations = try #require(object["recommendedToolCalls"]?.arrayValue)
        #expect(recommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash")
        })
        #expect(recommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("webhooks_redeliver")
        })
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func structuredObject(_ result: CallTool.Result) throws -> [String: Value] {
        guard case .object(let object) = result.structuredContent else {
            Issue.record("Expected structured object content")
            return [:]
        }
        return object
    }

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private static func signature(secret: String, payload: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    private static let nestedEventPayload = """
    {"data":{"type":"buildUploadStateUpdated","id":"inner-event-1","version":1,"attributes":{"newValue":"VALID","oldValue":"PROCESSING","timestamp":"2026-05-08T12:00:00Z"},"relationships":{"instance":{"data":{"type":"builds","id":"build-1"}}}}}
    """

    private static let webhookEnvelopePayload = """
    {"data":{"type":"webhookEvents","id":"event-1","attributes":{"eventType":"BUILD_UPLOAD_STATE_UPDATED","payload":"\(nestedEventPayload.escapedForJSONString)","ping":false,"createdDate":"2026-05-08T12:00:00Z"}}}
    """

    private static let directAppVersionStatePayload = """
    {"data":{"type":"appStoreVersionAppVersionStateUpdated","id":"direct-event-1","version":1,"attributes":{"newValue":"READY_FOR_REVIEW","oldValue":"PREPARE_FOR_SUBMISSION","timestamp":"2026-05-08T12:00:00Z"},"relationships":{"instance":{"data":{"type":"appStoreVersions","id":"version-1"}}}}}
    """
}

private extension String {
    var escapedForJSONString: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private extension Value {
    var objectValue: [String: Value]? {
        guard case .object(let object) = self else {
            return nil
        }
        return object
    }
}
