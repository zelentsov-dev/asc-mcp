import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Screenshots Optional Inputs Contract Tests")
struct ScreenshotsOptionalInputsContractTests {
    @Test("screenshot and preview set lists bind Apple media filters")
    func mediaSetListFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(transport),
            uploadService: UploadService()
        )

        let screenshotResult = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "display_types": .array([.string("APP_IPHONE_67"), .string("APP_WATCH_SERIES_10")]),
                "custom_product_page_localization_ids": .array([.string("cpp-loc-1")]),
                "treatment_localization_ids": .array([.string("treatment-loc-1"), .string("treatment-loc-2")])
            ]
        ))
        let previewResult = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_preview_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "preview_types": .array([.string("IPHONE_67"), .string("APPLE_VISION_PRO")]),
                "custom_product_page_localization_ids": .array([.string("cpp-loc-2")]),
                "treatment_localization_ids": .array([.string("treatment-loc-3")])
            ]
        ))

        #expect(screenshotResult.isError != true)
        #expect(previewResult.isError != true)
        let requests = await transport.recordedRequests()
        let screenshotQuery = screenshotsQuery(try #require(requests.first))
        #expect(screenshotQuery["filter[screenshotDisplayType]"] == "APP_IPHONE_67,APP_WATCH_SERIES_10")
        #expect(screenshotQuery["filter[appCustomProductPageLocalization]"] == "cpp-loc-1")
        #expect(screenshotQuery["filter[appStoreVersionExperimentTreatmentLocalization]"] == "treatment-loc-1,treatment-loc-2")
        let previewQuery = screenshotsQuery(try #require(requests.last))
        #expect(previewQuery["filter[previewType]"] == "IPHONE_67,APPLE_VISION_PRO")
        #expect(previewQuery["filter[appCustomProductPageLocalization]"] == "cpp-loc-2")
        #expect(previewQuery["filter[appStoreVersionExperimentTreatmentLocalization]"] == "treatment-loc-3")

        let tools = await worker.getTools()
        let screenshotTool = try #require(tools.first { $0.name == "screenshots_list_sets" })
        let screenshotProperties = try screenshotsValueObject(
            try screenshotsValueObject(screenshotTool.inputSchema)["properties"]
        )
        let displayTypes = try screenshotsValueObject(screenshotProperties["display_types"])
        let displayItems = try screenshotsValueObject(displayTypes["items"])
        #expect(try screenshotsValueArray(displayItems["enum"]).contains(.string("APP_WATCH_SERIES_10")))
        let previewTool = try #require(tools.first { $0.name == "screenshots_list_preview_sets" })
        let previewProperties = try screenshotsValueObject(
            try screenshotsValueObject(previewTool.inputSchema)["properties"]
        )
        let previewTypes = try screenshotsValueObject(previewProperties["preview_types"])
        let previewItems = try screenshotsValueObject(previewTypes["items"])
        #expect(try screenshotsValueArray(previewItems["enum"]).contains(.string("APPLE_VISION_PRO")))

        let createScreenshotTool = try #require(tools.first { $0.name == "screenshots_create_set" })
        let createScreenshotProperties = try screenshotsValueObject(
            try screenshotsValueObject(createScreenshotTool.inputSchema)["properties"]
        )
        let displayType = try screenshotsValueObject(createScreenshotProperties["display_type"])
        #expect(
            try screenshotsValueArray(displayType["enum"]) ==
                ScreenshotsWorker.screenshotDisplayTypes.map(Value.string)
        )

        let createPreviewTool = try #require(tools.first { $0.name == "screenshots_create_preview_set" })
        let createPreviewProperties = try screenshotsValueObject(
            try screenshotsValueObject(createPreviewTool.inputSchema)["properties"]
        )
        let previewType = try screenshotsValueObject(createPreviewProperties["preview_type"])
        #expect(
            try screenshotsValueArray(previewType["enum"]) ==
                ScreenshotsWorker.previewTypes.map(Value.string)
        )
    }

    @Test("media set filters reject invalid arrays before transport")
    func mediaSetFilterValidation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(transport),
            uploadService: UploadService()
        )

        let duplicate = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "display_types": .array([.string("APP_IPHONE_67"), .string("APP_IPHONE_67")])
            ]
        ))
        let unsupported = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_preview_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "preview_types": .array([.string("IPHONE_FUTURE")])
            ]
        ))

        #expect(duplicate.isError == true)
        #expect(unsupported.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("media set creates reject unsupported Apple media types before transport")
    func mediaSetCreateTypeValidation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(transport),
            uploadService: UploadService()
        )

        let screenshotResult = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_create_set",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "display_type": .string("APP_IPHONE_FUTURE")
            ]
        ))
        let previewResult = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_create_preview_set",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "preview_type": .string("IPHONE_FUTURE")
            ]
        ))

        #expect(screenshotResult.isError == true)
        #expect(previewResult.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("media relationship filters reject comma-delimited values before transport")
    func mediaRelationshipFiltersRejectCommas() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(transport),
            uploadService: UploadService()
        )
        let fixtures = [
            ("screenshots_list_sets", "custom_product_page_localization_ids"),
            ("screenshots_list_sets", "treatment_localization_ids"),
            ("screenshots_list_preview_sets", "custom_product_page_localization_ids"),
            ("screenshots_list_preview_sets", "treatment_localization_ids")
        ]

        for (toolName, fieldName) in fixtures {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: toolName,
                arguments: [
                    "localization_id": .string("version-loc-1"),
                    fieldName: .array([.string("first,second")])
                ]
            ))

            #expect(result.isError == true, "Expected comma rejection for \(toolName).\(fieldName)")
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("preview upload preserves nullable frame and MIME attributes")
    func previewUploadPreservesNullableAttributes() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-preview-\(UUID().uuidString).mp4")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fixtures = [
            PreviewUploadOptionalFixture(
                name: "concrete",
                frameTimeCode: .string("00:00:02.500"),
                mimeType: .string("video/x-m4v"),
                expectedFrameTimeCode: .string("00:00:02.500"),
                expectedMimeType: .string("video/x-m4v")
            ),
            PreviewUploadOptionalFixture(
                name: "explicit null",
                frameTimeCode: .null,
                mimeType: .null,
                expectedFrameTimeCode: .null,
                expectedMimeType: .null
            ),
            PreviewUploadOptionalFixture(
                name: "omitted",
                frameTimeCode: nil,
                mimeType: nil,
                expectedFrameTimeCode: .omitted,
                expectedMimeType: .string("video/mp4")
            )
        ]

        for fixture in fixtures {
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: screenshotsPreviewReservationResponse()),
                .init(statusCode: 200, body: screenshotsPreviewCommitResponse())
            ])
            let uploadTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: "")
            ])
            let worker = ScreenshotsWorker(
                httpClient: try await screenshotsClient(apiTransport),
                uploadService: UploadService(transport: uploadTransport, batchSize: 1),
                deliveryPollAttempts: 1,
                deliveryPollIntervalNanoseconds: 0
            )
            var arguments: [String: Value] = [
                "set_id": .string("preview-set-1"),
                "file_path": .string(fileURL.path)
            ]
            arguments["preview_frame_time_code"] = fixture.frameTimeCode
            arguments["mime_type"] = fixture.mimeType

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_upload_preview",
                arguments: arguments
            ))

            #expect(result.isError != true, "Expected successful \(fixture.name) upload")
            let requests = await apiTransport.recordedRequests()
            #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
            #expect(await uploadTransport.requestCount() == 1)
            let reserveAttributes = try screenshotsAttributes(try #require(requests.first))
            let commitAttributes = try screenshotsAttributes(try #require(requests.last))
            screenshotsExpectAttribute(
                reserveAttributes,
                name: "previewFrameTimeCode",
                expected: fixture.expectedFrameTimeCode
            )
            screenshotsExpectAttribute(
                commitAttributes,
                name: "previewFrameTimeCode",
                expected: fixture.expectedFrameTimeCode
            )
            screenshotsExpectAttribute(
                reserveAttributes,
                name: "mimeType",
                expected: fixture.expectedMimeType
            )
            #expect(commitAttributes["mimeType"] == nil)
        }

        let schemaWorker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(TestHTTPTransport(responses: [])),
            uploadService: UploadService()
        )
        let tool = try #require(await schemaWorker.getTools().first { $0.name == "screenshots_upload_preview" })
        let properties = try screenshotsValueObject(try screenshotsValueObject(tool.inputSchema)["properties"])
        let frameSchema = try screenshotsValueObject(properties["preview_frame_time_code"])
        let mimeSchema = try screenshotsValueObject(properties["mime_type"])
        #expect(
            try screenshotsValueArray(frameSchema["type"]).compactMap(\.stringValue).sorted() ==
                ["null", "string"]
        )
        #expect(frameSchema["enum"] == nil)
        #expect(
            try screenshotsValueArray(mimeSchema["type"]).compactMap(\.stringValue).sorted() ==
                ["null", "string"]
        )
        #expect(mimeSchema["enum"] == nil)
    }

    @Test("preview upload rejects invalid optional attributes before transport")
    func previewUploadRejectsInvalidOptionalAttributes() async throws {
        let apiTransport = TestHTTPTransport(responses: [])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = ScreenshotsWorker(
            httpClient: try await screenshotsClient(apiTransport),
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )
        let fixtures: [(field: String, value: Value)] = [
            ("preview_frame_time_code", .string("")),
            ("preview_frame_time_code", .string(" 00:00:02.500")),
            ("preview_frame_time_code", .int(1)),
            ("mime_type", .string("")),
            ("mime_type", .string(" video/mp4")),
            ("mime_type", .int(1))
        ]

        for fixture in fixtures {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_upload_preview",
                arguments: [
                    "set_id": .string("preview-set-1"),
                    "file_path": .string("/tmp/does-not-exist.mp4"),
                    fixture.field: fixture.value
                ]
            ))

            #expect(result.isError == true, "Expected validation failure for \(fixture.field)")
        }

        #expect(await apiTransport.requestCount() == 0)
        #expect(await uploadTransport.requestCount() == 0)
    }
}

private func screenshotsClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func screenshotsAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(object["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private struct PreviewUploadOptionalFixture {
    let name: String
    let frameTimeCode: Value?
    let mimeType: Value?
    let expectedFrameTimeCode: ScreenshotsExpectedAttribute
    let expectedMimeType: ScreenshotsExpectedAttribute
}

private enum ScreenshotsExpectedAttribute {
    case string(String)
    case null
    case omitted
}

private func screenshotsExpectAttribute(
    _ attributes: [String: Any],
    name: String,
    expected: ScreenshotsExpectedAttribute
) {
    switch expected {
    case .string(let value):
        #expect(attributes[name] as? String == value)
    case .null:
        #expect(attributes[name] is NSNull)
    case .omitted:
        #expect(attributes[name] == nil)
    }
}

private func screenshotsPreviewReservationResponse() -> String {
    """
    {
      "data": {
        "type": "appPreviews",
        "id": "preview-1",
        "attributes": {
          "fileSize": 5,
          "fileName": "preview.mp4",
          "videoDeliveryState": {"state": "AWAITING_UPLOAD"},
          "uploadOperations": [{
            "method": "PUT",
            "url": "https://upload.example.test/chunk",
            "length": 5,
            "offset": 0,
            "requestHeaders": []
          }]
        }
      }
    }
    """
}

private func screenshotsPreviewCommitResponse() -> String {
    """
    {
      "data": {
        "type": "appPreviews",
        "id": "preview-1",
        "attributes": {
          "fileSize": 5,
          "fileName": "preview.mp4",
          "sourceFileChecksum": "5d41402abc4b2a76b9719d911017c592",
          "videoDeliveryState": {"state": "COMPLETE"}
        }
      }
    }
    """
}

private func screenshotsQuery(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func screenshotsValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object value")
        throw ScreenshotsContractError.invalidValue
    }
    return object
}

private func screenshotsValueArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array value")
        throw ScreenshotsContractError.invalidValue
    }
    return array
}

private enum ScreenshotsContractError: Error {
    case invalidValue
}
