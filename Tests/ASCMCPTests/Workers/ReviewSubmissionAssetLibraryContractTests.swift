import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Review submission Asset Library contracts")
struct ReviewSubmissionAssetLibraryContractTests {
    @Test("Mixed review items preserve image video and legacy identities")
    func mixedItems() async throws {
        let body = #"""
        {
          "data":[
            {"type":"reviewSubmissionItems","id":"image-item","attributes":{"state":"READY_FOR_REVIEW"},"relationships":{"appAssetLibraryImage":{"data":{"type":"appAssetLibraryImages","id":"image-1"}}}},
            {"type":"reviewSubmissionItems","id":"video-item","attributes":{"state":"ACCEPTED"},"relationships":{"appAssetLibraryVideo":{"data":{"type":"appAssetLibraryVideos","id":"video-1"}}}},
            {"type":"reviewSubmissionItems","id":"legacy-item","attributes":{"state":"APPROVED"},"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"version-1"}}}}
          ],
          "included":[
            {"type":"appAssetLibraryImages","id":"image-1","attributes":{"referenceName":"Image","state":"PREPARE_FOR_SUBMISSION","specId":"image-spec","uploadOperations":[{"url":"https://upload.example.test/SECRET_UPLOAD_PATH","requestHeaders":[{"name":"Authorization","value":"SECRET_HEADER_VALUE"}]}],"unexpectedPrivateField":"SECRET_EXTRA_VALUE"},"links":{"self":"https://upload.example.test/SECRET_ASSET_LINK"},"relationships":{"unknown":{"data":{"id":"SECRET_RELATION_VALUE"}}}},
            {"type":"appAssetLibraryVideos","id":"video-1","attributes":{"referenceName":"Video","state":"ACCEPTED","specId":"video-spec","fileSize":1024}},
            {"type":"appStoreVersions","id":"version-1","attributes":{"versionString":"4.2"}}
          ],
          "links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items"}
        }
        """#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await assetReviewWorker(transport)
        let result = try await worker.handleTool(.init(name: "review_submissions_list_items", arguments: ["submission_id": .string("sub-1")]))
        #expect(result.isError != true)
        let payload = try assetReviewObject(result.structuredContent)
        let items = try #require(payload["items"]?.arrayValue)
        #expect(items.count == 3)
        for (index, relation, type, id) in [
            (0, "appAssetLibraryImage", "appAssetLibraryImages", "image-1"),
            (1, "appAssetLibraryVideo", "appAssetLibraryVideos", "video-1"),
            (2, "appStoreVersion", "appStoreVersions", "version-1")
        ] {
            let item = try assetReviewObject(items[index])
            #expect(item["resource_type"] == .string(relation))
            #expect(item["resource_id"] == .string(id))
            #expect(item["resource_jsonapi_type"] == .string(type))
            #expect(try assetReviewObject(item["relations"]?.arrayValue?.first)["scoped"] == .bool(false))
        }
        let included = try #require(payload["included"]?.arrayValue)
        let image = try assetReviewObject(included.first)
        #expect(try assetReviewObject(image["attributes"])["referenceName"] == .string("Image"))
        #expect(try assetReviewObject(image["attributes"])["uploadOperations"] == nil)
        #expect(image["links"] == nil)
        #expect(image["relationships"] == nil)
        let serialized = String(decoding: try JSONEncoder().encode(result.structuredContent), as: UTF8.self)
        #expect(!serialized.contains("SECRET_"))
        let request = try #require(await transport.recordedRequests().first)
        let query = try assetReviewQuery(request)
        #expect(query["include"]?.contains("appAssetLibraryImage") == true)
        #expect(query["include"]?.contains("appAssetLibraryVideo") == true)
        #expect(query["fields[reviewSubmissionItems]"]?.contains("appAssetLibraryImage") == true)
        #expect(query["fields[reviewSubmissionItems]"]?.contains("appAssetLibraryVideo") == true)
        for field in ["fields[appAssetLibraryImages]", "fields[appAssetLibraryVideos]"] {
            #expect(query[field]?.contains("state") == true)
            #expect(query[field]?.contains("uploadOperations") == false)
        }
    }

    @Test("Submission get retains included asset item identities")
    func submissionGetIncludesAssetItems() async throws {
        let body = #"""
        {
          "data":{"type":"reviewSubmissions","id":"sub-1","attributes":{"state":"READY_FOR_REVIEW","platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"items":{"data":[{"type":"reviewSubmissionItems","id":"image-item"},{"type":"reviewSubmissionItems","id":"video-item"}]}}},
          "included":[
            {"type":"reviewSubmissionItems","id":"image-item","attributes":{"state":"READY_FOR_REVIEW"},"relationships":{"appAssetLibraryImage":{"data":{"type":"appAssetLibraryImages","id":"image-1"}}}},
            {"type":"reviewSubmissionItems","id":"video-item","attributes":{"state":"READY_FOR_REVIEW"},"relationships":{"appAssetLibraryVideo":{"data":{"type":"appAssetLibraryVideos","id":"video-1"}}}}
          ],
          "links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}
        }
        """#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await assetReviewWorker(transport)
        let result = try await worker.handleTool(.init(name: "review_submissions_get", arguments: ["submission_id": .string("sub-1")]))
        #expect(result.isError != true)
        let payload = try assetReviewObject(result.structuredContent)
        let included = try #require(payload["included_items"]?.arrayValue)
        #expect(included.count == 2)
        let imageItem = try assetReviewObject(included[0])
        let relations = try assetReviewObject(imageItem["relationships"])
        let image = try assetReviewObject(try assetReviewObject(relations["appAssetLibraryImage"])["data"])
        #expect(image["id"] == .string("image-1"))
        let request = try #require(await transport.recordedRequests().first)
        #expect(try assetReviewQuery(request)["fields[reviewSubmissionItems]"]?.contains("appAssetLibraryVideo") == true)
    }

    @Test("Wrong asset identity types are rejected for direct and included items", arguments: [false, true])
    func invalidAssetRelationship(_ included: Bool) async throws {
        let badItem = #"{"type":"reviewSubmissionItems","id":"item-1","relationships":{"appAssetLibraryImage":{"data":{"type":"appAssetLibraryVideos","id":"image-1"}}}}"#
        let body = included
            ? "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"sub-1\"},\"included\":[\(badItem)],\"links\":{\"self\":\"https://api.example.test/v1/reviewSubmissions/sub-1\"}}"
            : "{\"data\":[\(badItem)],\"links\":{\"self\":\"https://api.example.test/v1/reviewSubmissions/sub-1/items\"}}"
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await assetReviewWorker(transport)
        let result = try await worker.handleTool(.init(name: included ? "review_submissions_get" : "review_submissions_list_items", arguments: ["submission_id": .string("sub-1")]))
        #expect(result.isError == true)
    }

    @Test("Asset review additions cannot use the legacy unpreviewed write path")
    func assetPreviewRequired() async throws {
        let cases: [[String: Value]] = [
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1")],
            ["submission_id": .string("sub-1"), "app_asset_library_video_id": .string("video-1")],
            ["submission_id": .string("sub-1"), "preview_id": .string("preview-1")],
            ["app_asset_library_image_id": .string("image-1"), "preview_id": .string("preview-1")],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1"), "app_asset_library_video_id": .string("video-1"), "preview_id": .string("preview-1")],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1"), "app_store_version_id": .string("version-1"), "preview_id": .string("preview-1")],
            ["submission_id": .string("sub-1"), "app_store_version_id": .string("version-1"), "preview_id": .string("preview-1")],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1"), "preview_id": .null],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .null, "preview_id": .string("preview-1")],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1"), "preview_id": .string("bad/preview")],
            ["submission_id": .string("sub-1"), "app_asset_library_image_id": .string("image-1"), "preview_id": .string("preview-1"), "unknown": .bool(true)]
        ]
        for arguments in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await assetReviewWorker(transport)
            let result = try await worker.handleTool(.init(name: "review_submissions_add_item", arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("Valid asset arguments require the injected preview coordinator", arguments: ["app_asset_library_image_id", "app_asset_library_video_id"])
    func missingCoordinator(_ field: String) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await assetReviewWorker(transport)
        let result = try await worker.handleTool(.init(name: "review_submissions_add_item", arguments: [
            "submission_id": .string("sub-1"), field: .string("asset-1"), "preview_id": .string("preview-1")
        ]))
        #expect(result.isError == true)
        #expect(try assetReviewObject(result.structuredContent)["error"]?.stringValue?.contains("assets_prepare_change") == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("Asset tool schema separates legacy and previewed calls")
    func previewSchema() async throws {
        let worker = try await assetReviewWorker(TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first { $0.name == "review_submissions_add_item" })
        let schema = try assetReviewObject(tool.inputSchema)
        #expect(schema["required"] == .array([.string("submission_id")]))
        #expect(schema["oneOf"] == nil)
        let properties = try assetReviewObject(schema["properties"])
        for name in ["app_asset_library_image_id", "app_asset_library_video_id", "preview_id"] {
            #expect(properties[name] != nil)
        }
    }
}

private func assetReviewWorker(_ transport: TestHTTPTransport) async throws -> ReviewSubmissionsWorker {
    let client = await HTTPClient(jwtService: try TestFactory.makeJWTService(), baseURL: "https://api.example.test", transport: transport, maxRetries: 1)
    return ReviewSubmissionsWorker(httpClient: client)
}

private func assetReviewObject(_ value: Value?) throws -> [String: Value] {
    try #require(value?.objectValue)
}

private func assetReviewQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    return Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
