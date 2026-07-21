import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscription Legacy Deprecation Tests")
struct SubscriptionLegacyDeprecationTests {
    @Test("all legacy tool descriptions name every exact replacement")
    func descriptionsNameExactReplacements() async throws {
        let worker = try await legacySubscriptionWorker(TestHTTPTransport(responses: []))
        let tools = Dictionary(uniqueKeysWithValues: await worker.getTools().map { ($0.name, $0) })

        #expect(SubscriptionsWorker.legacySubscriptionReplacements.count == 16)
        for (toolName, replacements) in SubscriptionsWorker.legacySubscriptionReplacements {
            let description = try #require(tools[toolName]?.description)
            #expect(description.contains("DEPRECATED since App Store Connect API 4.4.1"))
            #expect(
                description.contains("automatic version migration") ||
                    description.contains("never creates or selects a version") ||
                    description.contains("without creating or selecting a version")
            )
            for replacement in replacements {
                #expect(description.contains(replacement))
            }
        }
    }

    @Test("legacy non-upload tools preserve exact Apple operations and add warnings only on success", arguments: SubscriptionLegacyCase.allCases)
    fileprivate func nonUploadToolsPreserveOperations(_ testCase: SubscriptionLegacyCase) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: testCase.responseBody)
        ])
        let worker = try await legacySubscriptionWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.tool,
            arguments: testCase.arguments
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == testCase.method)
        #expect(request.url?.path == testCase.path)
        let payload = try legacySubscriptionValueObject(result.structuredContent)
        #expect(payload["deprecated"] == .bool(true))
        #expect(payload["deprecated_since"] == .string("App Store Connect API 4.4.1"))
        guard case .array(let warnings)? = payload["warnings"],
              case .array(let replacementTools)? = payload["replacement_tools"] else {
            throw SubscriptionLegacyTestFailure.expectedObject
        }
        #expect(warnings.compactMap(\.stringValue).first?.contains(testCase.tool) == true)
        #expect(replacementTools.compactMap(\.stringValue) == testCase.replacements)
    }

    @Test("legacy image upload preserves its v1 transaction and adds replacements after success")
    func legacyUploadPreservesV1Transaction() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subscription-legacy-image-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let reservation = #"{"data":{"type":"subscriptionImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"AWAITING_UPLOAD","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk","length":5,"offset":0,"requestHeaders":[]}]}}}"#
        let committed = #"{"data":{"type":"subscriptionImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"APPROVED"}}}"#
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
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_image",
            arguments: [
                "subscription_id": .string("subscription-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/subscriptionImages",
            "/v1/subscriptionImages/image-1"
        ])
        let payload = try legacySubscriptionValueObject(result.structuredContent)
        #expect(payload["deprecated"] == .bool(true))
        #expect(payload["replacement_tools"] == .array([
            .string("subscriptions_create_version"),
            .string("subscriptions_upload_version_image")
        ]))
    }

    @Test("legacy validation errors are not decorated as successful deprecations")
    func failuresAreNotDecorated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await legacySubscriptionWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_localization",
            arguments: nil
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        let payload = try legacySubscriptionValueObject(result.structuredContent)
        #expect(payload["deprecated"] == nil)
        #expect(payload["warnings"] == nil)
    }
}

private enum SubscriptionLegacyCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case listLocalizations
    case createLocalization
    case getLocalization
    case updateLocalization
    case deleteLocalization
    case listGroupLocalizations
    case createGroupLocalization
    case getGroupLocalization
    case updateGroupLocalization
    case deleteGroupLocalization
    case listImages
    case getImage
    case deleteImage
    case submit
    case submitGroup

    var testDescription: String { rawValue }

    var tool: String {
        switch self {
        case .listLocalizations: "subscriptions_list_localizations"
        case .createLocalization: "subscriptions_create_localization"
        case .getLocalization: "subscriptions_get_localization"
        case .updateLocalization: "subscriptions_update_localization"
        case .deleteLocalization: "subscriptions_delete_localization"
        case .listGroupLocalizations: "subscriptions_list_group_localizations"
        case .createGroupLocalization: "subscriptions_create_group_localization"
        case .getGroupLocalization: "subscriptions_get_group_localization"
        case .updateGroupLocalization: "subscriptions_update_group_localization"
        case .deleteGroupLocalization: "subscriptions_delete_group_localization"
        case .listImages: "subscriptions_list_images"
        case .getImage: "subscriptions_get_image"
        case .deleteImage: "subscriptions_delete_image"
        case .submit: "subscriptions_submit"
        case .submitGroup: "subscriptions_submit_group"
        }
    }

    var arguments: [String: Value] {
        switch self {
        case .listLocalizations, .listImages:
            ["subscription_id": .string("subscription-1")]
        case .createLocalization:
            [
                "subscription_id": .string("subscription-1"),
                "locale": .string("en-US"),
                "name": .string("Premium")
            ]
        case .getLocalization, .deleteLocalization:
            ["localization_id": .string("localization-1")]
        case .updateLocalization:
            ["localization_id": .string("localization-1"), "name": .string("Premium")]
        case .listGroupLocalizations:
            ["subscription_group_id": .string("group-1")]
        case .createGroupLocalization:
            [
                "subscription_group_id": .string("group-1"),
                "locale": .string("en-US"),
                "name": .string("Premium Plans")
            ]
        case .getGroupLocalization, .deleteGroupLocalization:
            ["group_localization_id": .string("group-localization-1")]
        case .updateGroupLocalization:
            ["group_localization_id": .string("group-localization-1"), "name": .string("Premium Plans")]
        case .getImage, .deleteImage:
            ["image_id": .string("image-1")]
        case .submit:
            ["subscription_id": .string("subscription-1")]
        case .submitGroup:
            ["group_id": .string("group-1")]
        }
    }

    var method: String {
        switch self {
        case .listLocalizations, .getLocalization, .listGroupLocalizations, .getGroupLocalization, .listImages, .getImage:
            "GET"
        case .createLocalization, .createGroupLocalization, .submit, .submitGroup:
            "POST"
        case .updateLocalization, .updateGroupLocalization:
            "PATCH"
        case .deleteLocalization, .deleteGroupLocalization, .deleteImage:
            "DELETE"
        }
    }

    var path: String {
        switch self {
        case .listLocalizations: "/v1/subscriptions/subscription-1/subscriptionLocalizations"
        case .createLocalization: "/v1/subscriptionLocalizations"
        case .getLocalization, .updateLocalization, .deleteLocalization: "/v1/subscriptionLocalizations/localization-1"
        case .listGroupLocalizations: "/v1/subscriptionGroups/group-1/subscriptionGroupLocalizations"
        case .createGroupLocalization: "/v1/subscriptionGroupLocalizations"
        case .getGroupLocalization, .updateGroupLocalization, .deleteGroupLocalization: "/v1/subscriptionGroupLocalizations/group-localization-1"
        case .listImages: "/v1/subscriptions/subscription-1/images"
        case .getImage, .deleteImage: "/v1/subscriptionImages/image-1"
        case .submit: "/v1/subscriptionSubmissions"
        case .submitGroup: "/v1/subscriptionGroupSubmissions"
        }
    }

    var statusCode: Int {
        switch self {
        case .createLocalization, .createGroupLocalization, .submit, .submitGroup: 201
        case .deleteLocalization, .deleteGroupLocalization, .deleteImage: 204
        default: 200
        }
    }

    var responseBody: String {
        switch self {
        case .listLocalizations:
            #"{"data":[],"links":{"self":"https://api.example.test/v1/subscriptions/subscription-1/subscriptionLocalizations?limit=25"}}"#
        case .createLocalization, .updateLocalization:
            #"{"data":{"type":"subscriptionLocalizations","id":"localization-1","attributes":{"locale":"en-US","name":"Premium","description":"Copy"}}}"#
        case .getLocalization:
            #"{"data":{"type":"subscriptionLocalizations","id":"localization-1","attributes":{"locale":"en-US","name":"Premium","description":"Copy"}}}"#
        case .deleteLocalization, .deleteGroupLocalization, .deleteImage:
            ""
        case .listGroupLocalizations:
            #"{"data":[],"links":{"self":"https://api.example.test/v1/subscriptionGroups/group-1/subscriptionGroupLocalizations?limit=25"}}"#
        case .createGroupLocalization, .getGroupLocalization, .updateGroupLocalization:
            #"{"data":{"type":"subscriptionGroupLocalizations","id":"group-localization-1","attributes":{"locale":"en-US","name":"Premium Plans","customAppName":"Example Pro"}}}"#
        case .listImages:
            #"{"data":[],"links":{"self":"https://api.example.test/v1/subscriptions/subscription-1/images?limit=25"}}"#
        case .getImage:
            #"{"data":{"type":"subscriptionImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","state":"APPROVED"}}}"#
        case .submit:
            #"{"data":{"type":"subscriptionSubmissions","id":"submission-1"}}"#
        case .submitGroup:
            #"{"data":{"type":"subscriptionGroupSubmissions","id":"submission-1"}}"#
        }
    }

    var replacements: [String] {
        SubscriptionsWorker.legacySubscriptionReplacements[tool] ?? []
    }
}

private func legacySubscriptionWorker(_ transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func legacySubscriptionValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw SubscriptionLegacyTestFailure.expectedObject
    }
    return object
}

private enum SubscriptionLegacyTestFailure: Error {
    case expectedObject
}
