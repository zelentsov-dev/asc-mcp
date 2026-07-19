import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Builds Pagination Security Tests")
struct BuildsPaginationSecurityTests {
    @Test("continuation accepts the prior explicit sort without repeating it")
    func followsValidatedBuildsURLWithPriorSort() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/builds?cursor=next"}}"#
            )
        ])
        let worker = try await makeBuildsPaginationWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-1&include=app%2CbuildBetaDetail%2CpreReleaseVersion&sort=version&cursor=next"
                )
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/builds")
        let query = buildsPaginationQueryItems(try #require(request.url))
        #expect(query["filter[app]"] == "app-1")
        #expect(query["sort"] == "version")
        #expect(query["cursor"] == "next")
    }

    @Test("next URL with another app filter is rejected without a request")
    func rejectsMismatchedAppFilter() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildsPaginationWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-2&include=app%2CbuildBetaDetail%2CpreReleaseVersion&sort=-uploadedDate&cursor=bad"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("next URL with another optional filter is rejected without a request")
    func rejectsMismatchedOptionalFilter() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildsPaginationWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "processing_state": .string("VALID"),
                "next_url": .string(
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-1&filter%5BprocessingState%5D=PROCESSING&include=app%2CbuildBetaDetail%2CpreReleaseVersion&sort=-uploadedDate&cursor=bad"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("same-host next URL for another collection is rejected without a request")
    func rejectsSameHostCrossRouteURL() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildsPaginationWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(
                    "https://api.example.test/v1/users?filter%5Bapp%5D=app-1&include=app%2CbuildBetaDetail%2CpreReleaseVersion&sort=-uploadedDate&cursor=bad"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private func makeBuildsPaginationWorker(transport: TestHTTPTransport) async throws -> BuildsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return BuildsWorker(httpClient: client)
}

private func buildsPaginationQueryItems(_ url: URL) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}
