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

    @Test("preview upload binds the poster-frame time code on reserve and commit")
    func previewUploadFrameTimeCode() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-preview-\(UUID().uuidString).mp4")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
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
            """),
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "appPreviews",
                "id": "preview-1",
                "attributes": {
                  "fileSize": 5,
                  "fileName": "preview.mp4",
                  "sourceFileChecksum": "5d41402abc4b2a76b9719d911017c592",
                  "previewFrameTimeCode": "00:00:02.500",
                  "videoDeliveryState": {"state": "COMPLETE"}
                }
              }
            }
            """)
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

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload_preview",
            arguments: [
                "set_id": .string("preview-set-1"),
                "file_path": .string(fileURL.path),
                "preview_frame_time_code": .string("00:00:02.500")
            ]
        ))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        let reserveAttributes = try screenshotsAttributes(try #require(requests.first))
        let commitAttributes = try screenshotsAttributes(try #require(requests.last))
        #expect(reserveAttributes["previewFrameTimeCode"] as? String == "00:00:02.500")
        #expect(commitAttributes["previewFrameTimeCode"] as? String == "00:00:02.500")

        let tool = try #require(await worker.getTools().first { $0.name == "screenshots_upload_preview" })
        let properties = try screenshotsValueObject(try screenshotsValueObject(tool.inputSchema)["properties"])
        #expect(properties["preview_frame_time_code"] != nil)
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
