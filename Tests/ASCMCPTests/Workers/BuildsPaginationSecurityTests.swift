import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Builds Pagination Security Tests")
struct BuildsPaginationSecurityTests {
    @Test("continuation requires explicit sort and limit to be repeated as tool arguments")
    func followsValidatedBuildsURLWithRepeatedControls() async throws {
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
                "sort": .string("version"),
                "limit": .int(50),
                "next_url": .string(
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-1&include=app%2CbuildBetaDetail%2CpreReleaseVersion%2CbuildUpload&sort=version&limit=50&cursor=next"
                )
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/builds")
        let query = buildsPaginationQueryItems(try #require(request.url))
        #expect(query["filter[app]"] == "app-1")
        #expect(query["sort"] == "version")
        #expect(query["limit"] == "50")
        #expect(query["cursor"] == "next")
    }

    @Test("sort carried only by next URL is rejected without a request")
    func rejectsSortCarriedOnlyByNextURL() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildsPaginationWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-1&include=app%2CbuildBetaDetail%2CpreReleaseVersion%2CbuildUpload&sort=version&limit=25&cursor=next"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
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
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-2&include=app%2CbuildBetaDetail%2CpreReleaseVersion%2CbuildUpload&sort=-uploadedDate&limit=25&cursor=bad"
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
                    "https://api.example.test/v1/builds?filter%5Bapp%5D=app-1&filter%5BprocessingState%5D=PROCESSING&include=app%2CbuildBetaDetail%2CpreReleaseVersion%2CbuildUpload&sort=-uploadedDate&limit=25&cursor=bad"
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
                    "https://api.example.test/v1/users?filter%5Bapp%5D=app-1&include=app%2CbuildBetaDetail%2CpreReleaseVersion%2CbuildUpload&sort=-uploadedDate&limit=25&cursor=bad"
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
