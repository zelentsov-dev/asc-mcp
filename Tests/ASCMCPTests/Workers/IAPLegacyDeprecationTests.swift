import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("IAP Legacy Deprecation Tests")
struct IAPLegacyDeprecationTests {
    @Test("legacy tool descriptions name exact versioned replacements")
    func descriptionsNameReplacements() async throws {
        let worker = try await legacyIAPWorker(TestHTTPTransport(responses: []))
        let tools = Dictionary(uniqueKeysWithValues: await worker.getTools().map { ($0.name, $0) })
        let replacements: [String: [String]] = [
            "iap_list_localizations": ["iap_list_versions", "iap_list_version_localizations"],
            "iap_create_localization": ["iap_list_versions", "iap_create_version", "iap_create_version_localization"],
            "iap_update_localization": ["iap_update_version_localization"],
            "iap_delete_localization": ["iap_delete_version_localization"],
            "iap_submit_for_review": ["iap_list_versions", "iap_create_version", "review_submissions_create", "review_submissions_add_item", "review_submissions_submit"],
            "iap_upload_image": ["iap_list_versions", "iap_create_version", "iap_upload_version_image"],
            "iap_get_image": ["iap_get_version_image_resource"],
            "iap_delete_image": ["iap_delete_version_image"],
            "iap_list_images": ["iap_list_versions", "iap_get_version_image"]
        ]

        for (toolName, replacementNames) in replacements {
            let description = try #require(tools[toolName]?.description)
            #expect(description.contains("Apple 4.4.1 release notes deprecate"))
            #expect(description.contains("auto-migration"))
            for replacement in replacementNames {
                #expect(description.contains(replacement))
            }
        }
    }

    @Test("supported IAP catalog list is not decorated as a deprecated localization tool")
    func supportedCatalogListIsNotDeprecated() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/inAppPurchasesV2?limit=25"}}"#
            )
        ])
        let worker = try await legacyIAPWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError != true)
        let payload = try legacyIAPValueObject(result.structuredContent)
        #expect(payload["deprecated"] == nil)
        #expect(payload["deprecated_since"] == nil)
        #expect(payload["warnings"] == nil)
        #expect(payload["replacement_tools"] == nil)
    }

    @Test("legacy non-upload tools preserve their Apple operation and add a structured warning", arguments: IAPLegacyCase.allCases)
    fileprivate func legacyToolPreservesOperation(_ testCase: IAPLegacyCase) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: testCase.responseBody)
        ])
        let worker = try await legacyIAPWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.tool,
            arguments: testCase.arguments
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == testCase.method)
        #expect(request.url?.path == testCase.path)
        let payload = try legacyIAPValueObject(result.structuredContent)
        #expect(payload["deprecated"] == .bool(true))
        #expect(payload["deprecated_since"] == .string("App Store Connect API 4.4.1"))
        guard case .array(let warnings)? = payload["warnings"],
              case .array(let replacementTools)? = payload["replacement_tools"] else {
            throw IAPLegacyTestFailure.expectedObject
        }
        #expect(warnings.compactMap(\.stringValue).first?.contains(testCase.tool) == true)
        #expect(Set(replacementTools.compactMap(\.stringValue)) == Set(testCase.replacements))
    }

    @Test("legacy upload preserves v1 transaction and warns only after success")
    func legacyUploadPreservesTransactionAndWarns() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iap-legacy-image-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let reservation = #"{"data":{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"AWAITING_UPLOAD","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk","length":5,"offset":0,"requestHeaders":[]}]}}}"#
        let committed = #"{"data":{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"APPROVED"}}}"#
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reservation),
            .init(statusCode: 200, body: committed)
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_image",
            arguments: ["iap_id": .string("iap-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/inAppPurchaseImages",
            "/v1/inAppPurchaseImages/image-1"
        ])
        let payload = try legacyIAPValueObject(result.structuredContent)
        #expect(payload["deprecated"] == .bool(true))
        #expect(payload["replacement_tools"] == .array([
            .string("iap_list_versions"),
            .string("iap_create_version"),
            .string("iap_upload_version_image")
        ]))
    }

    @Test("legacy delete compatibility paths preserve typed ambiguous outcomes", arguments: [
        IAPLegacyDeleteFailureCase(
            tool: "iap_delete_localization",
            arguments: ["localization_id": .string("loc-1")],
            statusCode: 500,
            expectedCommitState: "unknown"
        ),
        IAPLegacyDeleteFailureCase(
            tool: "iap_delete_image",
            arguments: ["image_id": .string("image-1")],
            statusCode: 202,
            expectedCommitState: "committed_unverified"
        )
    ])
    fileprivate func legacyDeletesPreserveTypedAmbiguousOutcomes(
        _ testCase: IAPLegacyDeleteFailureCase
    ) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: "")
        ])
        let worker = try await legacyIAPWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.tool,
            arguments: testCase.arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try legacyIAPValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string(testCase.expectedCommitState))
        #expect(payload["retrySafe"] == .bool(false))
    }
}

private struct IAPLegacyDeleteFailureCase: Sendable, CustomTestStringConvertible {
    let tool: String
    let arguments: [String: Value]
    let statusCode: Int
    let expectedCommitState: String
    var testDescription: String { "\(tool)-\(statusCode)" }
}

private enum IAPLegacyCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case listLocalizations
    case createLocalization
    case updateLocalization
    case deleteLocalization
    case submit
    case getImage
    case deleteImage
    case listImages

    var testDescription: String { rawValue }

    var tool: String {
        switch self {
        case .listLocalizations: "iap_list_localizations"
        case .createLocalization: "iap_create_localization"
        case .updateLocalization: "iap_update_localization"
        case .deleteLocalization: "iap_delete_localization"
        case .submit: "iap_submit_for_review"
        case .getImage: "iap_get_image"
        case .deleteImage: "iap_delete_image"
        case .listImages: "iap_list_images"
        }
    }

    var arguments: [String: Value] {
        switch self {
        case .listLocalizations, .listImages:
            ["iap_id": .string("iap-1")]
        case .createLocalization:
            [
                "iap_id": .string("iap-1"),
                "locale": .string("en-US"),
                "name": .string("Premium")
            ]
        case .updateLocalization:
            ["localization_id": .string("loc-1"), "name": .string("Premium")]
        case .deleteLocalization:
            ["localization_id": .string("loc-1")]
        case .submit:
            ["iap_id": .string("iap-1")]
        case .getImage, .deleteImage:
            ["image_id": .string("image-1")]
        }
    }

    var method: String {
        switch self {
        case .listLocalizations, .getImage, .listImages: "GET"
        case .createLocalization, .submit: "POST"
        case .updateLocalization: "PATCH"
        case .deleteLocalization, .deleteImage: "DELETE"
        }
    }

    var path: String {
        switch self {
        case .listLocalizations: "/v2/inAppPurchases/iap-1/inAppPurchaseLocalizations"
        case .createLocalization: "/v1/inAppPurchaseLocalizations"
        case .updateLocalization, .deleteLocalization: "/v1/inAppPurchaseLocalizations/loc-1"
        case .submit: "/v1/inAppPurchaseSubmissions"
        case .getImage, .deleteImage: "/v1/inAppPurchaseImages/image-1"
        case .listImages: "/v2/inAppPurchases/iap-1/images"
        }
    }

    var statusCode: Int {
        switch self {
        case .createLocalization, .submit: 201
        case .deleteLocalization, .deleteImage: 204
        default: 200
        }
    }

    var responseBody: String {
        switch self {
        case .listLocalizations:
            #"{"data":[],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/inAppPurchaseLocalizations?limit=25"}}"#
        case .createLocalization, .updateLocalization:
            #"{"data":{"type":"inAppPurchaseLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":"Premium","description":"Copy"}}}"#
        case .deleteLocalization, .deleteImage:
            ""
        case .getImage:
            #"{"data":{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"APPROVED"}}}"#
        case .listImages:
            #"{"data":[],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/images?limit=25"}}"#
        case .submit:
            #"{"data":{"type":"inAppPurchaseSubmissions","id":"submission-1"}}"#
        }
    }

    var replacements: [String] {
        switch self {
        case .listLocalizations: ["iap_list_versions", "iap_list_version_localizations"]
        case .createLocalization: ["iap_list_versions", "iap_create_version", "iap_create_version_localization"]
        case .updateLocalization: ["iap_update_version_localization"]
        case .deleteLocalization: ["iap_delete_version_localization"]
        case .submit: ["iap_list_versions", "iap_create_version", "review_submissions_create", "review_submissions_add_item", "review_submissions_submit"]
        case .getImage: ["iap_get_version_image_resource"]
        case .deleteImage: ["iap_delete_version_image"]
        case .listImages: ["iap_list_versions", "iap_get_version_image"]
        }
    }
}

private func legacyIAPWorker(_ transport: TestHTTPTransport) async throws -> InAppPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
}

private func legacyIAPValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw IAPLegacyTestFailure.expectedObject
    }
    return object
}

private enum IAPLegacyTestFailure: Error {
    case expectedObject
}
