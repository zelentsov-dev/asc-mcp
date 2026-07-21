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

    @Test("update schema exposes every nullable Apple patch attribute")
    func updateSchemaExposesNullableAttributes() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tool = try #require(await worker.getTools().first { $0.name == "webhooks_update" })
        let root = try #require(tool.inputSchema.objectValue)
        let properties = try #require(root["properties"]?.objectValue)

        for (field, concreteType) in [
            ("enabled", "boolean"),
            ("event_types", "array"),
            ("name", "string"),
            ("secret", "string"),
            ("url", "string")
        ] {
            let schema = try #require(properties[field]?.objectValue)
            let types = try #require(schema["type"]?.arrayValue)
            #expect(Set(types.compactMap(\.stringValue)) == Set([concreteType, "null"]))
        }
    }

    @Test("webhook collection limits reject invalid present values")
    func collectionLimitsRejectInvalidValues() async throws {
        for (tool, idField) in [
            ("webhooks_list", "app_id"),
            ("webhooks_list_deliveries", "webhook_id")
        ] {
            for invalid in [Value.int(0), .int(201), .string("25")] {
                let transport = TestHTTPTransport(responses: [])
                let client = await HTTPClient(
                    jwtService: try TestFactory.makeJWTService(),
                    baseURL: "https://api.example.test",
                    transport: transport,
                    maxRetries: 1
                )
                let worker = WebhooksWorker(httpClient: client)
                let result = try await worker.handleTool(.init(
                    name: tool,
                    arguments: [idField: .string("resource-1"), "limit": invalid]
                ))

                #expect(result.isError == true)
                #expect(textContent(result).contains("limit must be an integer from 1 through 200"))
                #expect(await transport.requestCount() == 0)
            }
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

    @Test("webhook mutations preserve machine-readable recovery state")
    func webhookMutationsPreserveRecoveryState() async throws {
        let secret = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 500, body: #"{"errors":[{"status":"500","detail":"unavailable"}]}"#)
        ])
        let createClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: createTransport,
            maxRetries: 1
        )
        let createWorker = WebhooksWorker(httpClient: createClient)
        let create = try await createWorker.handleTool(.init(
            name: "webhooks_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Release events"),
                "url": .string("https://example.com/webhook"),
                "secret": .string(secret),
                "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
            ]
        ))
        let createPayload = try structuredObject(create)
        #expect(create.isError == true)
        #expect(createPayload["operationCommitState"] == .string("unknown"))
        #expect(createPayload["outcomeUnknown"] == .bool(true))
        #expect(createPayload["retrySafe"] == .bool(false))

        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: "")
        ])
        let updateClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: updateTransport,
            maxRetries: 1
        )
        let updateWorker = WebhooksWorker(httpClient: updateClient)
        let update = try await updateWorker.handleTool(.init(
            name: "webhooks_update",
            arguments: [
                "webhook_id": .string("webhook-1"),
                "enabled": .bool(false)
            ]
        ))
        let updatePayload = try structuredObject(update)
        #expect(update.isError == true)
        #expect(updatePayload["operationCommitState"] == .string("committed_unverified"))
        #expect(updatePayload["operationCommitted"] == .bool(true))
        #expect(updatePayload["outcomeUnknown"] == .bool(false))
        #expect(updatePayload["retrySafe"] == .bool(false))
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

    @Test("list and get preserve included app resources")
    func listAndGetPreserveIncludedApps() async throws {
        let responseBody = """
        {
          "data": [
            {
              "type": "webhooks",
              "id": "webhook-1",
              "attributes": {
                "enabled": true,
                "eventTypes": ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
                "name": "Release events",
                "url": "https://example.com/webhook"
              },
              "relationships": {
                "app": { "data": { "type": "apps", "id": "app-1" } }
              }
            }
          ],
          "included": [
            {
              "type": "apps",
              "id": "app-1",
              "attributes": {
                "name": "Example App",
                "bundleId": "com.example.app"
              }
            }
          ],
          "links": { "self": "https://api.example.test/v1/apps/app-1/webhooks" }
        }
        """
        let singleResponseBody = """
        {
          "data": {
            "type": "webhooks",
            "id": "webhook-1",
            "attributes": {
              "enabled": true,
              "eventTypes": ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
              "name": "Release events",
              "url": "https://example.com/webhook"
            },
            "relationships": {
              "app": { "data": { "type": "apps", "id": "app-1" } }
            }
          },
          "included": [
            {
              "type": "apps",
              "id": "app-1",
              "attributes": {
                "name": "Example App",
                "bundleId": "com.example.app"
              }
            }
          ],
          "links": { "self": "https://api.example.test/v1/webhooks/webhook-1" }
        }
        """
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: responseBody),
            .init(statusCode: 200, body: singleResponseBody)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)

        let list = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "include_app": .bool(true)
                ]
            )
        )
        let get = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_get",
                arguments: [
                    "webhook_id": .string("webhook-1"),
                    "include_app": .bool(true)
                ]
            )
        )

        for result in [list, get] {
            #expect(result.isError == nil)
            let object = try structuredObject(result)
            let included = try #require(object["included"]?.arrayValue)
            let app = try #require(included.first?.objectValue)
            #expect(app["type"] == .string("apps"))
            #expect(app["id"] == .string("app-1"))
            let attributes = try #require(app["attributes"]?.objectValue)
            #expect(attributes["name"] == .string("Example App"))
            #expect(attributes["bundleId"] == .string("com.example.app"))
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems?.first { $0.name == "include" }?.value == "app")
        }
    }

    @Test("update rejects an empty patch before the network call")
    func updateRejectsEmptyPatch() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_update",
                arguments: ["webhook_id": .string("webhook-1")]
            )
        )

        #expect(result.isError == true)
        #expect(textContent(result).contains("At least one update field is required"))
        #expect(await transport.requestCount() == 0)
    }

    @Test("update preserves explicit null for every nullable Apple attribute")
    func updatePreservesExplicitNullAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"webhooks","id":"webhook-1"}}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = WebhooksWorker(httpClient: client)

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_update",
                arguments: [
                    "webhook_id": .string("webhook-1"),
                    "enabled": .null,
                    "event_types": .null,
                    "name": .null,
                    "secret": .null,
                    "url": .null
                ]
            )
        )

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        for field in ["enabled", "eventTypes", "name", "secret", "url"] {
            #expect(attributes[field] is NSNull)
        }
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
        #expect(validObject["providedSignature"] == .string(signature))
        #expect(validObject["reason"] == .null)

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
        #expect(invalidObject["reason"]?.stringValue != nil)

        let malformed = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_verify_signature",
                arguments: [
                    "secret": .string("top-secret"),
                    "signature": .string("not-a-signature"),
                    "payload": .string(payload)
                ]
            )
        )
        let malformedObject = try structuredObject(malformed)
        #expect(malformedObject["success"] == .bool(true))
        #expect(malformedObject["valid"] == .bool(false))
        #expect(malformedObject["providedSignature"] == .null)
        #expect(malformedObject["reason"]?.stringValue != nil)
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
        #expect(object["signature"] == nil)

        let event = try #require(object["event"]?.objectValue)
        #expect(event["id"] == .string("event-1"))
        #expect(event["resourceType"] == .string("webhookEvents"))
        #expect(event["eventType"] == .string("BUILD_UPLOAD_STATE_UPDATED"))
        #expect(event["payloadFormat"] == .string("json"))

        let related = try #require(event["relatedResource"]?.objectValue)
        #expect(related["type"] == .string("buildUploads"))
        #expect(related["id"] == .string("upload-1"))

        let recommendations = try #require(object["recommendedToolCalls"]?.arrayValue)
        #expect(recommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("build_uploads_get")
        })
    }

    @Test("parse payload verifies only a complete signature pair")
    func parsePayloadVerifiesCompleteSignaturePair() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let payload = Self.webhookEnvelopePayload
        let signature = Self.signature(secret: "top-secret", payload: payload)

        let verified = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_parse_payload",
                arguments: [
                    "payload": .string(payload),
                    "secret": .string("top-secret"),
                    "signature": .string("hmacsha256=\(signature)")
                ]
            )
        )

        let object = try structuredObject(verified)
        let verification = try #require(object["signature"]?.objectValue)
        #expect(verification["valid"] == .bool(true))

        for incompleteArguments: [String: Value] in [
            ["payload": .string("not-json"), "secret": .string("top-secret")],
            ["payload": .string("not-json"), "signature": .string("hmacsha256=\(signature)")]
        ] {
            let incomplete = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_parse_payload",
                    arguments: incompleteArguments
                )
            )
            #expect(incomplete.isError == true)
            #expect(textContent(incomplete).contains("secret and signature together"))
            #expect(!textContent(incomplete).contains("not valid JSON"))
        }
    }

    @Test("receiver helpers reject ambiguous raw payload inputs")
    func receiverHelpersRejectAmbiguousPayloadInputs() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let payload = Self.webhookEnvelopePayload
        let payloadBase64 = Data(payload.utf8).base64EncodedString()
        let signature = Self.signature(secret: "top-secret", payload: payload)

        let calls: [(String, [String: Value])] = [
            (
                "webhooks_verify_signature",
                [
                    "secret": .string("top-secret"),
                    "signature": .string("hmacsha256=\(signature)"),
                    "payload": .string(payload),
                    "payload_base64": .string(payloadBase64)
                ]
            ),
            (
                "webhooks_parse_payload",
                [
                    "payload": .string(payload),
                    "payload_base64": .string(payloadBase64)
                ]
            ),
            (
                "webhooks_triage_event",
                [
                    "event_type": .string("BUILD_UPLOAD_STATE_UPDATED"),
                    "payload": .string(payload),
                    "payload_base64": .string(payloadBase64)
                ]
            )
        ]

        for (name, arguments) in calls {
            let result = try await worker.handleTool(
                CallTool.Parameters(name: name, arguments: arguments)
            )
            #expect(result.isError == true)
            #expect(textContent(result).contains("exactly one of payload or payload_base64"))
        }
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
        #expect(recommendations.first { recommendation in
            recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash")
        }?.objectValue?["effect"] == .string("read_only"))
        #expect(recommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("webhooks_redeliver")
        })
        #expect(recommendations.first { recommendation in
            recommendation.objectValue?["tool"] == .string("webhooks_redeliver")
        }?.objectValue?["effect"] == .string("mutating"))
    }

    @Test("beta feedback lookups require exact related resource types")
    func betaFeedbackLookupsRequireExactResourceTypes() throws {
        let cases = [
            (
                eventType: "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED",
                expectedType: "betaFeedbackCrashSubmissions",
                lookupTool: "beta_feedback_get_crash"
            ),
            (
                eventType: "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED",
                expectedType: "betaFeedbackScreenshotSubmissions",
                lookupTool: "beta_feedback_get_screenshot"
            )
        ]

        for testCase in cases {
            let matching = ASCWebhookTriagePolicy.recommendations(
                eventType: testCase.eventType,
                relatedResource: ASCWebhookRelatedResource(type: testCase.expectedType, id: "submission-1"),
                delivery: .empty
            )
            #expect(matching.contains { $0.tool == testCase.lookupTool })

            for actualType in ["unknown", "builds"] {
                let mismatched = ASCWebhookTriagePolicy.recommendations(
                    eventType: testCase.eventType,
                    relatedResource: ASCWebhookRelatedResource(type: actualType, id: "submission-1"),
                    delivery: .empty
                )
                #expect(!mismatched.contains { $0.tool == testCase.lookupTool })

                let triage = ASCWebhookTriagePolicy.triage(
                    eventType: testCase.eventType,
                    relatedResource: ASCWebhookRelatedResource(type: actualType, id: "submission-1"),
                    delivery: .empty
                )
                let nextSteps = try #require(triage["nextSteps"] as? [String])
                #expect(nextSteps.contains { step in
                    step.contains("No executable feedback lookup") &&
                        step.contains(testCase.expectedType) &&
                        step.contains(actualType)
                })
            }

            let missing = ASCWebhookTriagePolicy.triage(
                eventType: testCase.eventType,
                relatedResource: nil,
                delivery: .empty
            )
            let missingRecommendations = try #require(
                missing["recommendedToolCalls"] as? [[String: Any]]
            )
            #expect(!missingRecommendations.contains { recommendation in
                recommendation["tool"] as? String == testCase.lookupTool
            })
            let missingNextSteps = try #require(missing["nextSteps"] as? [String])
            #expect(missingNextSteps.contains { step in
                step.contains("No executable feedback lookup") &&
                    step.contains(testCase.expectedType) &&
                    step.contains("no related resource type")
            })
        }
    }

    @Test("webhook recovery tool definitions expose mutating side effects")
    func webhookRecoveryToolsExposeSideEffects() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()

        for name in ["webhooks_redeliver", "webhooks_ping"] {
            let tool = try #require(tools.first { $0.name == name })
            let description = try #require(tool.description)
            #expect(description.contains("Mutating, non-idempotent"))
            #expect(tool.annotations.readOnlyHint == false)
            #expect(tool.annotations.idempotentHint == false)
        }

        let triage = try #require(tools.first { $0.name == "webhooks_triage_event" })
        let triageDescription = try #require(triage.description)
        #expect(triageDescription.contains("Recommendations are labeled `read_only` or `mutating`"))
        #expect(triageDescription.contains("never executes them"))
    }

    @Test("triage rejects noncanonical recommendation identifiers from payload and direct arguments")
    func triageRejectsNoncanonicalRecommendationIdentifiers() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())
        let parsedPayload = """
        {"data":{"type":"betaFeedbackCrashSubmissionCreated","id":"event-1","relationships":{"instance":{"data":{"type":"betaFeedbackCrashSubmissions","id":"   "}}}}}
        """
        let parsedResult = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_triage_event",
                arguments: ["payload": .string(parsedPayload)]
            )
        )
        let parsedObject = try structuredObject(parsedResult)
        let parsedRecommendations = try #require(parsedObject["recommendedToolCalls"]?.arrayValue)
        #expect(!parsedRecommendations.contains { recommendation in
            recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash") ||
                recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash_log")
        })
        let parsedNextSteps = try #require(parsedObject["nextSteps"]?.arrayValue)
        #expect(parsedNextSteps.contains { step in
            step.stringValue?.contains("related resource ID is not canonical") == true
        })

        for invalidID in ["bad/id", "%2F", ".."] {
            let invalidPayload = """
            {"data":{"type":"betaFeedbackCrashSubmissionCreated","id":"event-1","relationships":{"instance":{"data":{"type":"betaFeedbackCrashSubmissions","id":"\(invalidID)"}}}}}
            """
            let invalidParsedResult = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_triage_event",
                    arguments: ["payload": .string(invalidPayload)]
                )
            )
            let invalidParsedObject = try structuredObject(invalidParsedResult)
            let invalidParsedRecommendations = try #require(
                invalidParsedObject["recommendedToolCalls"]?.arrayValue
            )
            #expect(!invalidParsedRecommendations.contains { recommendation in
                recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash") ||
                    recommendation.objectValue?["tool"] == .string("beta_feedback_get_crash_log")
            })
            let invalidParsedNextSteps = try #require(invalidParsedObject["nextSteps"]?.arrayValue)
            #expect(invalidParsedNextSteps.contains { step in
                step.stringValue?.contains("canonical resource ID") == true
            })
        }

        let directResult = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_triage_event",
                arguments: [
                    "event_type": .string("BUILD_UPLOAD_STATE_UPDATED"),
                    "resource_type": .string("buildUploads"),
                    "resource_id": .string(" "),
                    "delivery_state": .string("FAILED"),
                    "delivery_id": .string(" delivery-1"),
                    "webhook_id": .string("webhook\u{0000}1")
                ]
            )
        )
        let directObject = try structuredObject(directResult)
        let directRecommendations = try #require(directObject["recommendedToolCalls"]?.arrayValue)
        #expect(directRecommendations.isEmpty)
        let directNextSteps = try #require(directObject["nextSteps"]?.arrayValue)
        #expect(directNextSteps.contains { step in
            step.stringValue?.contains("related resource ID is not canonical") == true
        })
        #expect(directNextSteps.contains { step in
            step.stringValue?.contains("delivery_id is not canonical") == true
        })
        #expect(directNextSteps.contains { step in
            step.stringValue?.contains("webhook_id is not canonical") == true
        })

        for invalidID in ["bad/id", "%2F", ".."] {
            let invalidDirectResult = try await worker.handleTool(
                CallTool.Parameters(
                    name: "webhooks_triage_event",
                    arguments: [
                        "event_type": .string("BUILD_UPLOAD_STATE_UPDATED"),
                        "resource_type": .string("buildUploads"),
                        "resource_id": .string(invalidID),
                        "delivery_state": .string("FAILED"),
                        "delivery_id": .string(invalidID),
                        "webhook_id": .string(invalidID)
                    ]
                )
            )
            let invalidDirectObject = try structuredObject(invalidDirectResult)
            let invalidDirectRecommendations = try #require(
                invalidDirectObject["recommendedToolCalls"]?.arrayValue
            )
            #expect(invalidDirectRecommendations.isEmpty)
            let invalidDirectNextSteps = try #require(invalidDirectObject["nextSteps"]?.arrayValue)
            #expect(invalidDirectNextSteps.contains { step in
                step.stringValue?.contains("canonical resource ID") == true
            })
            #expect(invalidDirectNextSteps.contains { step in
                step.stringValue?.contains("canonical delivery ID") == true
            })
            #expect(invalidDirectNextSteps.contains { step in
                step.stringValue?.contains("canonical webhook ID") == true
            })
        }
    }

    @Test("triage never recommends tools without their required identifiers")
    func triageOmitsUnexecutableRecommendations() {
        let missingIdentifierCases: [(String, ASCWebhookRelatedResource?)] = [
            ("BETA_FEEDBACK_CRASH_SUBMISSION_CREATED", nil),
            ("BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED", nil),
            ("BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED", ASCWebhookRelatedResource(
                type: "buildBetaDetails",
                id: "detail-1"
            )),
            ("BUILD_UPLOAD_STATE_UPDATED", ASCWebhookRelatedResource(
                type: "builds",
                id: "build-1"
            )),
            ("BACKGROUND_ASSET_UPLOAD_STATE_UPDATED", nil),
            ("UNSPECIALIZED_EVENT", nil)
        ]

        for (eventType, relatedResource) in missingIdentifierCases {
            #expect(ASCWebhookTriagePolicy.recommendations(
                eventType: eventType,
                relatedResource: relatedResource,
                delivery: .empty
            ).isEmpty)
        }

        let withWebhook = ASCWebhookTriagePolicy.recommendations(
            eventType: "UNSPECIALIZED_EVENT",
            relatedResource: nil,
            delivery: ASCWebhookDeliveryContext(
                deliveryID: nil,
                webhookID: "webhook-1",
                deliveryState: nil,
                httpStatusCode: nil,
                errorMessage: nil
            )
        )
        #expect(withWebhook.count == 1)
        #expect(withWebhook.first?.tool == "webhooks_list_deliveries")
        #expect(withWebhook.first?.arguments["webhook_id"] as? String == "webhook-1")
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
    {"data":{"type":"buildUploadStateUpdated","id":"inner-event-1","version":1,"attributes":{"newState":"COMPLETE"},"relationships":{"instance":{"data":{"type":"buildUploads","id":"upload-1"}}}}}
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
