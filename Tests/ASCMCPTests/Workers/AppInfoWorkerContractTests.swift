import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("App Info Worker Contract Tests")
struct AppInfoWorkerContractTests {
    @Test("schemas expose current Apple collection controls and nullable writes")
    func schemasExposeCurrentControls() async throws {
        let worker = try await appInfoContractWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let list = try appInfoContractProperties(try #require(tools.first { $0.name == "app_info_list" }))
        #expect(list["include"] != nil)
        #expect(list["limit"] != nil)
        #expect(list["localizations_limit"] != nil)
        #expect(list["next_url"] != nil)

        let localizations = try appInfoContractProperties(
            try #require(tools.first { $0.name == "app_info_list_localizations" })
        )
        #expect(localizations["locale"] != nil)
        #expect(localizations["include"] != nil)
        #expect(localizations["limit"] != nil)
        #expect(localizations["next_url"] != nil)

        let eulaUpdate = try appInfoContractProperties(
            try #require(tools.first { $0.name == "app_info_update_eula" })
        )
        #expect(eulaUpdate["agreement_text"]?.objectValue?["type"]?.arrayValue?.compactMap(\.stringValue) == ["string", "null"])
        #expect(eulaUpdate["territory_ids"] != nil)
    }

    @Test("collection controls map to Apple query names and preserve current included resources")
    func listControlsAndIncludedResources() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [],
              "included": [
                {"type":"apps","id":"app-1","attributes":{"name":"Example"}},
                {"type":"ageRatingDeclarations","id":"age-1","attributes":{"gambling":true}}
              ],
              "meta":{"paging":{"total":0,"limit":200}}
            }
            """)
        ])
        let worker = try await appInfoContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_list",
            arguments: [
                "app_id": .string("app:1"),
                "include": .array([.string("app"), .string("ageRatingDeclaration")]),
                "limit": .int(500),
                "localizations_limit": .int(80)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/v1/apps/app%3A1/appInfos")
        let query = try appInfoContractQuery(request)
        #expect(query["include"] == "app,ageRatingDeclaration")
        #expect(query["limit"] == "200")
        #expect(query["limit[appInfoLocalizations]"] == "50")

        let payload = try appInfoContractObject(result.structuredContent)
        #expect(try appInfoContractArray(payload["included_apps"]).count == 1)
        #expect(try appInfoContractArray(payload["included_age_rating_declarations"]).count == 1)
        #expect(payload["total"]?.intValue == 0)
    }

    @Test("localization controls map to Apple filters and relationships survive decoding")
    func localizationControlsAndRelationships() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data":[{
                "type":"appInfoLocalizations",
                "id":"loc-1",
                "attributes":{"locale":"en-US","name":"Example"},
                "relationships":{"appInfo":{"data":{"type":"appInfos","id":"info-1"}}}
              }],
              "included":[{"type":"appInfos","id":"info-1","attributes":{"state":"ACCEPTED"}}],
              "meta":{"paging":{"total":1,"limit":200}}
            }
            """)
        ])
        let worker = try await appInfoContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_list_localizations",
            arguments: [
                "info_id": .string("info-1"),
                "locale": .array([.string("en-US"), .string("fr-FR")]),
                "include": .string("appInfo"),
                "limit": .int(300)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try appInfoContractQuery(request)
        #expect(query["filter[locale]"] == "en-US,fr-FR")
        #expect(query["include"] == "appInfo")
        #expect(query["limit"] == "200")

        let payload = try appInfoContractObject(result.structuredContent)
        let localization = try appInfoContractObject(try #require(appInfoContractArray(payload["localizations"]).first))
        #expect(localization["appInfoId"]?.stringValue == "info-1")
        #expect(try appInfoContractArray(payload["included_app_infos"]).count == 1)
    }

    @Test("create localization and EULA update preserve explicit null and relationship replacement")
    func nullableWritesAndRelationshipReplacement() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {"data":{"type":"appInfoLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":"Example","subtitle":null}}}
            """),
            .init(statusCode: 200, body: """
            {"data":{"type":"endUserLicenseAgreements","id":"eula-1","attributes":{"agreementText":null},"relationships":{"territories":{"data":[]}}}}
            """)
        ])
        let worker = try await appInfoContractWorker(transport: transport)

        let createResult = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_create_localization",
            arguments: [
                "info_id": .string("info-1"),
                "locale": .string("en-US"),
                "name": .string("Example"),
                "subtitle": .null
            ]
        ))
        #expect(createResult.isError != true)

        let updateResult = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_update_eula",
            arguments: [
                "eula_id": .string("eula-1"),
                "agreement_text": .null,
                "territory_ids": .array([])
            ]
        ))
        #expect(updateResult.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let createAttributes = try appInfoContractAttributes(try #require(requests.first))
        #expect(createAttributes["subtitle"] is NSNull)

        let updateBody = try appInfoContractBody(try #require(requests.last))
        let updateData = try appInfoContractDictionary(updateBody["data"])
        let updateAttributes = try appInfoContractDictionary(updateData["attributes"])
        let relationships = try appInfoContractDictionary(updateData["relationships"])
        let territories = try appInfoContractDictionary(relationships["territories"])
        #expect(updateAttributes["agreementText"] is NSNull)
        #expect((territories["data"] as? [Any])?.isEmpty == true)
    }

    @Test("update operations reject no-op calls before network")
    func rejectsNoOpUpdates() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await appInfoContractWorker(transport: transport)

        let localization = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_update_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))
        let eula = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_update_eula",
            arguments: ["eula_id": .string("eula-1")]
        ))

        #expect(localization.isError == true)
        #expect(eula.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("pagination continuation must preserve include controls")
    func paginationPreservesControls() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await appInfoContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_info_list",
            arguments: [
                "app_id": .string("app-1"),
                "include": .string("app"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appInfos?cursor=next&limit=25")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private func appInfoContractWorker(transport: TestHTTPTransport) async throws -> AppInfoWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppInfoWorker(httpClient: client)
}

private func appInfoContractQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func appInfoContractProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AppInfoContractTestError.expectedObject
    }
    return properties
}

private func appInfoContractBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func appInfoContractAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try appInfoContractBody(request)
    let data = try appInfoContractDictionary(body["data"])
    return try appInfoContractDictionary(data["attributes"])
}

private func appInfoContractDictionary(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func appInfoContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw AppInfoContractTestError.expectedObject
    }
    return object
}

private func appInfoContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw AppInfoContractTestError.expectedArray
    }
    return array
}

private enum AppInfoContractTestError: Error {
    case expectedObject
    case expectedArray
}
