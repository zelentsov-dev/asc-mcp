import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("In-App Purchase Images Contract Tests")
struct InAppPurchaseImagesContractTests {
    @Test("image list uses the current images relationship path")
    func imageListUsesCurrentRelationshipPath() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":42,"fileName":"offer.png","sourceFileChecksum":"abc","state":"APPROVED","imageAsset":{"templateUrl":"https://example.test/{w}x{h}","width":1200,"height":1200}}}],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/images?limit=200","next":"https://api.example.test/v2/inAppPurchases/iap-1/images?cursor=next&limit=200"}}"#
            )
        ])
        let worker = try await makeIAPImagesWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_images",
            arguments: [
                "iap_id": .string("iap-1"),
                "limit": .int(200)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v2/inAppPurchases/iap-1/images")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
        #expect(query == ["limit": "200"])

        let payload = try iapImagesObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["count"] == .int(1))
        #expect(payload["next_url"] == .string("https://api.example.test/v2/inAppPurchases/iap-1/images?cursor=next&limit=200"))
        guard case .array(let images) = payload["images"] else {
            Issue.record("Expected images array")
            return
        }
        guard case .object(let image) = images.first else {
            Issue.record("Expected image object")
            return
        }
        #expect(image["id"] == .string("image-1"))
        #expect(image["state"] == .string("APPROVED"))
    }

    @Test("image list follows a validated Apple pagination URL")
    func imageListFollowsPaginationURL() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/images?cursor=next&limit=25"}}"#
            )
        ])
        let worker = try await makeIAPImagesWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_images",
            arguments: [
                "iap_id": .string("iap-1"),
                "next_url": .string("https://api.example.test/v2/inAppPurchases/iap-1/images?cursor=next&limit=25")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v2/inAppPurchases/iap-1/images")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
        #expect(query["cursor"] == "next")
        #expect(query["limit"] == "25")
    }

    @Test("foreign pagination URL is rejected without a request")
    func foreignPaginationURLIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPImagesWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_images",
            arguments: [
                "iap_id": .string("iap-1"),
                "next_url": .string("https://example.invalid/v2/inAppPurchases/iap-1/images?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("same-host pagination URL for another path is rejected without a request")
    func wrongPaginationPathIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPImagesWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_images",
            arguments: [
                "iap_id": .string("iap-1"),
                "next_url": .string("https://api.example.test/v2/inAppPurchases/iap-1/inAppPurchaseImages?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("pagination URL for another in-app purchase is rejected without a request")
    func wrongPaginationParentIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeIAPImagesWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_images",
            arguments: [
                "iap_id": .string("iap-1"),
                "next_url": .string("https://api.example.test/v2/inAppPurchases/iap-2/images?cursor=bad")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private func makeIAPImagesWorker(transport: TestHTTPTransport) async throws -> InAppPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
}

private func iapImagesObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw InAppPurchaseImagesContractTestFailure.expectedObject
    }
    return object
}

private enum InAppPurchaseImagesContractTestFailure: Error {
    case expectedObject
}
