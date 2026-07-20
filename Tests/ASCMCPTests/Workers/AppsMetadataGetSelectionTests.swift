import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Apps Metadata Get Selection Tests")
struct AppsMetadataGetSelectionTests {
    @Test("metadata auto-selection prefers rejected version over ready for sale")
    func metadataAutoSelectionPrefersRejectedVersion() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsBody([
                versionJSON(id: "ver-sale", version: "3.2", state: "READY_FOR_SALE"),
                versionJSON(id: "ver-rejected", version: "3.3", state: "REJECTED")
            ])),
            .init(statusCode: 200, body: metadataLocalizationsBody(id: "loc-rejected", locale: "ko"))
        ])
        let worker = try await makeMetadataGetAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "locale": .string("ko")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "GET"])
        #expect(requests.last?.url?.path == "/v1/appStoreVersions/ver-rejected/appStoreVersionLocalizations")
        let version = try metadataVersionObject(result)
        #expect(version["id"] as? String == "ver-rejected")
        #expect(version["appStoreState"] as? String == "REJECTED")
    }

    @Test("metadata auto-selection prefers metadata rejected version over ready for sale")
    func metadataAutoSelectionPrefersMetadataRejectedVersion() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsBody([
                versionJSON(id: "ver-sale", version: "3.2", state: "READY_FOR_SALE"),
                versionJSON(id: "ver-metadata-rejected", version: "3.3", state: "METADATA_REJECTED")
            ])),
            .init(statusCode: 200, body: metadataLocalizationsBody(id: "loc-metadata-rejected", locale: "th"))
        ])
        let worker = try await makeMetadataGetAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "locale": .string("th")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.last?.url?.path == "/v1/appStoreVersions/ver-metadata-rejected/appStoreVersionLocalizations")
        let version = try metadataVersionObject(result)
        #expect(version["id"] as? String == "ver-metadata-rejected")
        #expect(version["appStoreState"] as? String == "METADATA_REJECTED")
    }
}

private func makeMetadataGetAppsWorker(transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func versionsBody(_ versions: [String]) -> String {
    """
    {
      "data": [
        \(versions.joined(separator: ",\n        "))
      ]
    }
    """
}

private func versionJSON(id: String, version: String, state: String) -> String {
    """
    {
      "type": "appStoreVersions",
      "id": "\(id)",
      "attributes": {
        "platform": "IOS",
        "versionString": "\(version)",
        "appStoreState": "\(state)"
      }
    }
    """
}

private func metadataLocalizationsBody(id: String, locale: String) -> String {
    """
    {
      "data": [
        {
          "type": "appStoreVersionLocalizations",
          "id": "\(id)",
          "attributes": {
            "locale": "\(locale)",
            "keywords": "map,friends,location"
          },
          "relationships": {
            "appStoreVersion": {
              "data": { "type": "appStoreVersions", "id": "\(id.contains("metadata-rejected") ? "ver-metadata-rejected" : "ver-rejected")" }
            }
          }
        }
      ]
    }
    """
}

private func metadataGetText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private func metadataVersionObject(_ result: CallTool.Result) throws -> [String: Any] {
    let data = Data(metadataGetText(result).utf8)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object?["version"] as? [String: Any])
}
