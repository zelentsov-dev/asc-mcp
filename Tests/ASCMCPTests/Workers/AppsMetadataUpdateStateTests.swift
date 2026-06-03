import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Apps Metadata Update State Tests")
struct AppsMetadataUpdateStateTests {
    @Test("rejected app version metadata update reaches Apple patch")
    func rejectedVersionUpdateReachesPatch() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "REJECTED")),
            .init(statusCode: 200, body: localizationsBody(id: "loc-ko", locale: "ko")),
            .init(statusCode: 200, body: localizationUpdateBody(id: "loc-ko", locale: "ko", keywords: "map,friends,location"))
        ])
        let worker = try await makeAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("ko"),
                "keywords": .string("map,friends,location")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 3)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "GET", "PATCH"])
        let patch = try #require(requests.last)
        #expect(patch.url?.path == "/v1/appStoreVersionLocalizations/loc-ko")
        let body = try #require(await transport.recordedBodyStrings().last)
        #expect(body.contains(#""keywords":"map,friends,location""#))
    }

    @Test("metadata rejected app version metadata update reaches Apple patch")
    func metadataRejectedVersionUpdateReachesPatch() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "METADATA_REJECTED")),
            .init(statusCode: 200, body: localizationsBody(id: "loc-th", locale: "th")),
            .init(statusCode: 200, body: localizationUpdateBody(id: "loc-th", locale: "th", keywords: "family,map,safety"))
        ])
        let worker = try await makeAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("th"),
                "keywords": .string("family,map,safety")
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 3)
        let patch = try #require(await transport.recordedRequests().last)
        #expect(patch.httpMethod == "PATCH")
        #expect(patch.url?.path == "/v1/appStoreVersionLocalizations/loc-th")
    }

    @Test("Apple patch conflict remains MCP error")
    func applePatchConflictRemainsMCPError() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appVersionBody(state: "WAITING_FOR_REVIEW")),
            .init(statusCode: 200, body: localizationsBody(id: "loc-tr", locale: "tr")),
            .init(statusCode: 409, body: """
            {
              "errors": [
                {
                  "status": "409",
                  "code": "STATE_ERROR",
                  "detail": "This version localization is not editable in the current state."
                }
              ]
            }
            """)
        ])
        let worker = try await makeAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("tr"),
                "keywords": .string("map,friends,tracker")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 3)
        #expect(appsMetadataText(result).contains("API error (409)"))
        #expect(appsMetadataText(result).contains("not editable"))
    }
}

private func makeAppsWorker(transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func appVersionBody(state: String) -> String {
    """
    {
      "data": {
        "type": "appStoreVersions",
        "id": "ver-1",
        "attributes": {
          "platform": "IOS",
          "versionString": "3.3",
          "appStoreState": "\(state)"
        }
      }
    }
    """
}

private func localizationsBody(id: String, locale: String) -> String {
    """
    {
      "data": [
        {
          "type": "appStoreVersionLocalizations",
          "id": "\(id)",
          "attributes": {
            "locale": "\(locale)"
          }
        }
      ]
    }
    """
}

private func localizationUpdateBody(id: String, locale: String, keywords: String) -> String {
    """
    {
      "data": {
        "type": "appStoreVersionLocalizations",
        "id": "\(id)",
        "attributes": {
          "locale": "\(locale)",
          "keywords": "\(keywords)"
        }
      }
    }
    """
}

private func appsMetadataText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}
