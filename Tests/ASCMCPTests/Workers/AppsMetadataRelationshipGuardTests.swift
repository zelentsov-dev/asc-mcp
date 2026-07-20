import Foundation
import MCP
import Testing
@testable import asc_mcp

/// Regression tests for the version-localization relationship guards.
///
/// App Store Connect only serializes a relationship's `data` linkage when the
/// request explicitly asks for it via `include=`. The read paths here do not
/// send `include=`, so the `app` / `appStoreVersion` linkages arrive as
/// `links`-only objects with no `data` member (the default JSON:API shape).
/// The guards must treat that absent linkage as "cannot verify, allow" rather
/// than as a mismatch, because a sub-resource fetched under
/// `/appStoreVersions/{id}/...` is already scoped to that id by the URL.
///
/// Every fixture here uses dummy UUIDs; no real App Store Connect ids are
/// committed.
@Suite("Apps Metadata Relationship Guard Tests")
struct AppsMetadataRelationshipGuardTests {
    // Dummy ids that stand in for the live fixtures used to reproduce the bug.
    private static let appId = "6761677637"
    private static let versionId = "00000000-1111-2222-3333-444444444444"
    private static let localizationId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private static let keywords = "screen,time,console,playstation,nintendo,windows,gaming,family,kids,gametime,limit,monitor"

    @Test("apps_get_metadata succeeds when Apple omits the appStoreVersion linkage")
    func getMetadataWithoutRelationshipData() async throws {
        let transport = TestHTTPTransport(responses: [
            // GET /v1/appStoreVersions/{id} - app relationship is links-only (no data).
            .init(statusCode: 200, body: versionDetailBodyWithoutLinkage()),
            // GET .../appStoreVersionLocalizations - appStoreVersion linkage absent.
            .init(statusCode: 200, body: localizationsBodyWithoutLinkage())
        ])
        let worker = try await makeAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string(Self.appId),
                "version_id": .string(Self.versionId),
                "locale": .string("en-US")
            ]
        ))

        #expect(result.isError != true)
        let localization = try metadataLocalizationObject(result)
        #expect(localization["keywords"] as? String == Self.keywords)
    }

    @Test("apps_list_localizations succeeds when Apple omits the app linkage")
    func listLocalizationsWithoutRelationshipData() async throws {
        let transport = TestHTTPTransport(responses: [
            // GET /v1/appStoreVersions/{id} - app relationship is links-only (no data).
            .init(statusCode: 200, body: versionDetailBodyWithoutLinkage()),
            // GET .../appStoreVersionLocalizations - appStoreVersion linkage absent.
            .init(statusCode: 200, body: localizationsBodyWithoutLinkage())
        ])
        let worker = try await makeAppsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "apps_list_localizations",
            arguments: [
                "app_id": .string(Self.appId),
                "version_id": .string(Self.versionId)
            ]
        ))

        #expect(result.isError != true)
        let object = try jsonObject(result)
        #expect(object["success"] as? Bool == true)
        let localizations = try #require(object["localizations"] as? [[String: Any]])
        #expect(localizations.contains { $0["locale"] as? String == "en-US" })
    }

    // MARK: - Fixtures (default Apple shape: relationship linkage omitted)

    private func versionDetailBodyWithoutLinkage() -> String {
        """
        {
          "data": {
            "type": "appStoreVersions",
            "id": "\(Self.versionId)",
            "attributes": {
              "platform": "IOS",
              "versionString": "1.0.5",
              "appStoreState": "READY_FOR_DISTRIBUTION"
            },
            "relationships": {
              "app": {
                "links": {
                  "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersions/\(Self.versionId)/relationships/app",
                  "related": "https://api.appstoreconnect.apple.com/v1/appStoreVersions/\(Self.versionId)/app"
                }
              }
            }
          }
        }
        """
    }

    private func localizationsBodyWithoutLinkage() -> String {
        """
        {
          "data": [
            {
              "type": "appStoreVersionLocalizations",
              "id": "\(Self.localizationId)",
              "attributes": {
                "locale": "en-US",
                "keywords": "\(Self.keywords)",
                "description": "Parental controls for the whole family."
              },
              "relationships": {
                "appStoreVersion": {
                  "links": {
                    "self": "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/\(Self.localizationId)/relationships/appStoreVersion",
                    "related": "https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/\(Self.localizationId)/appStoreVersion"
                  }
                }
              }
            }
          ]
        }
        """
    }
}

// MARK: - Helpers

private func makeAppsWorker(transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func resultText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private func jsonObject(_ result: CallTool.Result) throws -> [String: Any] {
    let data = Data(resultText(result).utf8)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object)
}

private func metadataLocalizationObject(_ result: CallTool.Result) throws -> [String: Any] {
    let object = try jsonObject(result)
    return try #require(object["localization"] as? [String: Any])
}
