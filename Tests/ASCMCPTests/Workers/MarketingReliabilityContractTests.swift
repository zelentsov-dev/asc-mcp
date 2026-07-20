import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Marketing Reliability Contract Tests")
struct MarketingReliabilityContractTests {
    @Test("custom product page create binds the App Store version template")
    func customPageTemplateRelationship() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appCustomProductPages","id":"page-1","attributes":{"name":"Campaign"}}}"#)
        ])
        let worker = CustomProductPagesWorker(httpClient: try await marketingClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "custom_pages_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Campaign"),
                "locale": .string("en-US"),
                "template_version_id": .string("version-1")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appCustomProductPages")
        let relationships = try marketingRelationships(request)
        let template = try marketingObject(relationships["appStoreVersionTemplate"])
        let identifier = try marketingObject(template["data"])
        #expect(identifier["type"] as? String == "appStoreVersions")
        #expect(identifier["id"] as? String == "version-1")

        let tool = try #require(await worker.getTools().first { $0.name == "custom_pages_create" })
        let schema = try marketingValueObject(tool.inputSchema)
        let properties = try marketingValueObject(schema["properties"])
        #expect(properties["template_version_id"] != nil)
    }

    @Test("media set schemas expose all localization parents with exact one-of")
    func mediaSetSchemas() async throws {
        let worker = ScreenshotsWorker(
            httpClient: try await marketingClient(TestHTTPTransport(responses: [])),
            uploadService: UploadService()
        )
        let tools = await worker.getTools()

        for name in ["screenshots_create_set", "screenshots_create_preview_set"] {
            let tool = try #require(tools.first { $0.name == name })
            let schema = try marketingValueObject(tool.inputSchema)
            let properties = try marketingValueObject(schema["properties"])
            #expect(properties["localization_id"] != nil)
            #expect(properties["app_store_version_localization_id"] != nil)
            #expect(properties["custom_product_page_localization_id"] != nil)
            #expect(properties["treatment_localization_id"] != nil)
            #expect(try marketingValueArray(schema["oneOf"]).count == 4)
        }
    }

    @Test("screenshot set create maps every documented parent relationship")
    func screenshotSetParents() async throws {
        let cases: [(String, String, String)] = [
            ("localization_id", "appStoreVersionLocalization", "appStoreVersionLocalizations"),
            ("app_store_version_localization_id", "appStoreVersionLocalization", "appStoreVersionLocalizations"),
            ("custom_product_page_localization_id", "appCustomProductPageLocalization", "appCustomProductPageLocalizations"),
            ("treatment_localization_id", "appStoreVersionExperimentTreatmentLocalization", "appStoreVersionExperimentTreatmentLocalizations")
        ]

        for (input, relationship, type) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: #"{"data":{"type":"appScreenshotSets","id":"set-1","attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}}"#)
            ])
            let worker = ScreenshotsWorker(
                httpClient: try await marketingClient(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_create_set",
                arguments: [input: .string("parent-1"), "display_type": .string("APP_IPHONE_67")]
            ))

            #expect(result.isError != true)
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.url?.path == "/v1/appScreenshotSets")
            let relationships = try marketingRelationships(request)
            #expect(relationships.count == 1)
            let parent = try marketingObject(relationships[relationship])
            let identifier = try marketingObject(parent["data"])
            #expect(identifier["type"] as? String == type)
            #expect(identifier["id"] as? String == "parent-1")
        }
    }

    @Test("preview set maps PPO parent and rejects ambiguous parents before transport")
    func previewSetParentAndPreflight() async throws {
        let validTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appPreviewSets","id":"set-1","attributes":{"previewType":"IPHONE_67"}}}"#)
        ])
        let validWorker = ScreenshotsWorker(
            httpClient: try await marketingClient(validTransport),
            uploadService: UploadService()
        )
        let valid = try await validWorker.handleTool(CallTool.Parameters(
            name: "screenshots_create_preview_set",
            arguments: [
                "treatment_localization_id": .string("ppo-loc-1"),
                "preview_type": .string("IPHONE_67")
            ]
        ))

        #expect(valid.isError != true)
        let request = try #require(await validTransport.recordedRequests().first)
        #expect(request.url?.path == "/v1/appPreviewSets")
        let relationships = try marketingRelationships(request)
        let parent = try marketingObject(relationships["appStoreVersionExperimentTreatmentLocalization"])
        let identifier = try marketingObject(parent["data"])
        #expect(identifier["type"] as? String == "appStoreVersionExperimentTreatmentLocalizations")

        let invalidTransport = TestHTTPTransport(responses: [])
        let invalidWorker = ScreenshotsWorker(
            httpClient: try await marketingClient(invalidTransport),
            uploadService: UploadService()
        )
        let invalid = try await invalidWorker.handleTool(CallTool.Parameters(
            name: "screenshots_create_preview_set",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "custom_product_page_localization_id": .string("cpp-loc-1"),
                "preview_type": .string("IPHONE_67")
            ]
        ))

        #expect(invalid.isError == true)
        #expect(await invalidTransport.requestCount() == 0)
    }

    @Test("preview projection uses previewFrameImage and time code")
    func previewFrameProjection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "appPreviews",
                "id": "preview-1",
                "attributes": {
                  "previewFrameTimeCode": "00:00:03.000",
                  "previewFrameImage": {
                    "image": {"templateUrl": "https://example.test/{w}x{h}.png", "width": 1290, "height": 2796},
                    "state": {"state": "COMPLETE", "errors": [], "warnings": []}
                  },
                  "previewImage": {"templateUrl": "https://deprecated.example.test/image.png"}
                }
              }
            }
            """)
        ])
        let worker = ScreenshotsWorker(
            httpClient: try await marketingClient(transport),
            uploadService: UploadService()
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_get_preview",
            arguments: ["preview_id": .string("preview-1")]
        ))

        #expect(result.isError != true)
        let root = try marketingValueObject(result.structuredContent)
        let preview = try marketingValueObject(root["preview"])
        #expect(preview["previewFrameTimeCode"]?.stringValue == "00:00:03.000")
        #expect(preview["previewFrameImage"] != nil)
        #expect(preview["previewImage"] != nil)
    }

    @Test("promoted create omits optional enabled and returns product relationship IDs")
    func promotedCreateContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "promotedPurchases",
                "id": "promoted-1",
                "attributes": {"visibleForAllUsers": true, "enabled": true, "state": "APPROVED"}
              }
            }
            """),
            .init(statusCode: 201, body: #"{"data":{"type":"promotedPurchases","id":"promoted-2","relationships":{"subscription":{"data":{"type":"subscriptions","id":"subscription-1"}}}}}"#)
        ])
        let worker = PromotedPurchasesWorker(
            httpClient: try await marketingClient(transport),
            uploadService: UploadService()
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_create",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .bool(true),
                "iap_id": .string("iap-1")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/promotedPurchases")
        let body = try marketingRequestBody(request)
        let data = try marketingObject(body["data"])
        let attributes = try marketingObject(data["attributes"])
        #expect(attributes["enabled"] == nil)
        let relationships = try marketingObject(data["relationships"])
        #expect(relationships["inAppPurchaseV2"] != nil)
        #expect(relationships["subscription"] == nil)

        let root = try marketingValueObject(result.structuredContent)
        let purchase = try marketingValueObject(root["promoted_purchase"])
        #expect(purchase["inAppPurchaseId"]?.stringValue == "iap-1")
        #expect(purchase["subscriptionId"] == .null)

        let nullable = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_create",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .bool(true),
                "enabled": .null,
                "subscription_id": .string("subscription-1")
            ]
        ))
        #expect(nullable.isError != true)
        let nullableRequest = try #require(await transport.recordedRequests().last)
        let nullableBody = try marketingRequestBody(nullableRequest)
        let nullableData = try marketingObject(nullableBody["data"])
        let nullableAttributes = try marketingObject(nullableData["attributes"])
        #expect(nullableAttributes["enabled"] is NSNull)
    }

    @Test("promoted schema and handler enforce exactly one product")
    func promotedExactOneProduct() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = PromotedPurchasesWorker(
            httpClient: try await marketingClient(transport),
            uploadService: UploadService()
        )
        let tool = try #require(await worker.getTools().first { $0.name == "promoted_create" })
        let schema = try marketingValueObject(tool.inputSchema)
        let required = try marketingValueArray(schema["required"])
        #expect(!required.contains(.string("enabled")))
        #expect(try marketingValueArray(schema["oneOf"]).count == 2)
        let properties = try marketingValueObject(schema["properties"])
        let enabled = try marketingValueObject(properties["enabled"])
        #expect(try marketingValueArray(enabled["type"]) == [.string("boolean"), .string("null")])

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_create",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .bool(true),
                "iap_id": .string("iap-1"),
                "subscription_id": .string("subscription-1")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("promoted update preserves nullable booleans and rejects empty patches")
    func promotedUpdateNullableBooleans() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"promotedPurchases","id":"promoted-1","attributes":{"visibleForAllUsers":null,"enabled":null}}}"#)
        ])
        let worker = PromotedPurchasesWorker(
            httpClient: try await marketingClient(transport),
            uploadService: UploadService()
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "visible": .null,
                "enabled": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/promotedPurchases/promoted-1")
        let attributes = try marketingAttributes(request)
        #expect(Set(attributes.keys) == ["visibleForAllUsers", "enabled"])
        #expect(attributes.values.allSatisfy { $0 is NSNull })

        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: ["promoted_purchase_id": .string("promoted-1")]
        ))
        let malformed = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "enabled": .string("yes")
            ]
        ))
        #expect(empty.isError == true)
        #expect(malformed.isError == true)
        #expect(await transport.requestCount() == 1)

        let updateTool = try #require(await worker.getTools().first { $0.name == "promoted_update" })
        let schema = try marketingValueObject(updateTool.inputSchema)
        #expect(schema["minProperties"] == .int(2))
        let properties = try marketingValueObject(schema["properties"])
        #expect(try marketingValueArray(try marketingValueObject(properties["visible"])["type"]) == [.string("boolean"), .string("null")])
        #expect(try marketingValueArray(try marketingValueObject(properties["enabled"])["type"]) == [.string("boolean"), .string("null")])
    }

    @Test("PPO supports visionOS and complete experiment and treatment projections")
    func ppoProjection() async throws {
        let experimentTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersionExperiments","id":"experiment-1","attributes":{"name":"Vision","platform":"VISION_OS","trafficProportion":50}}}"#)
        ])
        let experimentWorker = ProductPageOptimizationWorker(httpClient: try await marketingClient(experimentTransport))
        let experimentResult = try await experimentWorker.handleTool(CallTool.Parameters(
            name: "ppo_create_experiment",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Vision"),
                "traffic_proportion": .int(50),
                "platform": .string("VISION_OS")
            ]
        ))

        #expect(experimentResult.isError != true)
        let experimentRequest = try #require(await experimentTransport.recordedRequests().first)
        #expect(experimentRequest.url?.path == "/v2/appStoreVersionExperiments")
        let experimentAttributes = try marketingAttributes(experimentRequest)
        #expect(experimentAttributes["platform"] as? String == "VISION_OS")
        let experimentRoot = try marketingValueObject(experimentResult.structuredContent)
        let experiment = try marketingValueObject(experimentRoot["experiment"])
        #expect(experiment["platform"]?.stringValue == "VISION_OS")

        let treatmentTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {
                "type": "appStoreVersionExperimentTreatments",
                "id": "treatment-1",
                "attributes": {
                  "name": "Spatial",
                  "appIconName": "VisionIcon",
                  "appIcon": {"templateUrl": "https://example.test/{w}x{h}.png", "width": 1024, "height": 1024},
                  "promotedDate": "2026-07-20T12:00:00Z"
                }
              }
            }
            """)
        ])
        let treatmentWorker = ProductPageOptimizationWorker(httpClient: try await marketingClient(treatmentTransport))
        let treatmentResult = try await treatmentWorker.handleTool(CallTool.Parameters(
            name: "ppo_create_treatment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "name": .string("Spatial"),
                "app_icon_name": .string("VisionIcon")
            ]
        ))

        #expect(treatmentResult.isError != true)
        let treatmentRequest = try #require(await treatmentTransport.recordedRequests().first)
        #expect(treatmentRequest.url?.path == "/v1/appStoreVersionExperimentTreatments")
        let treatmentAttributes = try marketingAttributes(treatmentRequest)
        #expect(treatmentAttributes["appIconName"] as? String == "VisionIcon")
        let treatmentRoot = try marketingValueObject(treatmentResult.structuredContent)
        let treatment = try marketingValueObject(treatmentRoot["treatment"])
        #expect(treatment["appIconName"]?.stringValue == "VisionIcon")
        #expect(treatment["appIcon"] != nil)
        #expect(treatment["promotedDate"]?.stringValue == "2026-07-20T12:00:00Z")

        let createExperiment = try #require(await experimentWorker.getTools().first { $0.name == "ppo_create_experiment" })
        let experimentSchema = try marketingValueObject(createExperiment.inputSchema)
        let experimentProperties = try marketingValueObject(experimentSchema["properties"])
        let platform = try marketingValueObject(experimentProperties["platform"])
        #expect(try marketingValueArray(platform["enum"]).contains(.string("VISION_OS")))
        let createTreatment = try #require(await treatmentWorker.getTools().first { $0.name == "ppo_create_treatment" })
        let treatmentSchema = try marketingValueObject(createTreatment.inputSchema)
        let treatmentProperties = try marketingValueObject(treatmentSchema["properties"])
        #expect(treatmentProperties["app_icon_name"] != nil)
    }
}

private func marketingClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func marketingRequestBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func marketingObject(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func marketingRelationships(_ request: URLRequest) throws -> [String: Any] {
    let body = try marketingRequestBody(request)
    let data = try marketingObject(body["data"])
    return try marketingObject(data["relationships"])
}

private func marketingAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try marketingRequestBody(request)
    let data = try marketingObject(body["data"])
    return try marketingObject(data["attributes"])
}

private func marketingValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object value")
        throw MarketingContractError.invalidValue
    }
    return object
}

private func marketingValueArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array value")
        throw MarketingContractError.invalidValue
    }
    return array
}

private enum MarketingContractError: Error {
    case invalidValue
}
