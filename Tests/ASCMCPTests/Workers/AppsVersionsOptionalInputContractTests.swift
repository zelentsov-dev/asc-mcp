import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Apps and Versions Optional Input Contract Tests")
struct AppsVersionsOptionalInputContractTests {
    @Test("tool schemas expose the Apple 4.4.1 collection filters")
    func schemasExposeCollectionFilters() async throws {
        let appsWorker = try await makeOptionalAppsWorker(TestHTTPTransport(responses: []))
        let lifecycleWorker = try await makeOptionalLifecycleWorker(TestHTTPTransport(responses: []))

        let appsList = try optionalInputProperties(await appsWorker.getTools(), named: "apps_list")
        for field in [
            "app_ids", "skus", "app_store_version_ids", "app_store_states", "platforms",
            "app_version_states", "review_submission_states", "review_submission_platforms"
        ] {
            #expect(appsList[field]?.objectValue?["type"] == .string("array"))
            #expect(appsList[field]?.objectValue?["minItems"] == .int(1))
        }
        #expect(appsList["has_game_center_enabled_versions"]?.objectValue?["type"] == .string("boolean"))
        #expect(appsList["app_store_states"]?.objectValue?["deprecated"] == .bool(true))
        #expect(appsList["has_game_center_enabled_versions"]?.objectValue?["deprecated"] == .bool(true))

        let lightweightVersions = try optionalInputProperties(await appsWorker.getTools(), named: "apps_list_versions")
        for field in ["version_ids", "version_strings", "app_store_states", "app_version_states", "platforms"] {
            #expect(lightweightVersions[field]?.objectValue?["type"] == .string("array"))
        }
        #expect(lightweightVersions["app_store_states"]?.objectValue?["deprecated"] == .bool(true))

        let localizations = try optionalInputProperties(await appsWorker.getTools(), named: "apps_list_localizations")
        #expect(localizations["locales"]?.objectValue?["type"] == .string("array"))
        #expect(localizations["limit"]?.objectValue?["default"] == .int(200))

        let versions = try optionalInputProperties(await lifecycleWorker.getTools(), named: "app_versions_list")
        #expect(versions["version_ids"]?.objectValue?["type"] == .string("array"))
        #expect(versions["version_strings"]?.objectValue?["type"] == .string("array"))

        for toolName in ["app_versions_create", "app_versions_update"] {
            let properties = try optionalInputProperties(await lifecycleWorker.getTools(), named: toolName)
            #expect(properties["uses_idfa"]?.objectValue?["type"] == .array([.string("boolean"), .string("null")]))
            #expect(properties["uses_idfa"]?.objectValue?["deprecated"] == .bool(true))
        }
    }

    @Test("apps list forwards every supported filter and preserves continuation scope")
    func appsListForwardsFilters() async throws {
        let query = [
            "cursor": "page-2",
            "limit": "50",
            "sort": "-name",
            "filter[id]": "app-1,app-2",
            "filter[sku]": "SKU-1,SKU-2",
            "filter[appStoreVersions]": "ver-1,ver-2",
            "filter[appStoreVersions.appStoreState]": "READY_FOR_SALE",
            "filter[appStoreVersions.platform]": "IOS,MAC_OS",
            "filter[appStoreVersions.appVersionState]": "READY_FOR_DISTRIBUTION",
            "filter[reviewSubmissions.state]": "WAITING_FOR_REVIEW,IN_REVIEW",
            "filter[reviewSubmissions.platform]": "IOS",
            "exists[gameCenterEnabledVersions]": "false"
        ]
        let nextURL = optionalInputURL(path: "/v1/apps", query: query)
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps", next: nextURL)),
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps", next: nil))
        ])
        let worker = try await makeOptionalAppsWorker(transport)
        var arguments = optionalAppsListArguments()

        let first = try await worker.handleTool(.init(name: "apps_list", arguments: arguments))
        arguments["next_url"] = .string(nextURL)
        let second = try await worker.handleTool(.init(name: "apps_list", arguments: arguments))

        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let values = optionalInputQuery(request)
            for (name, value) in query where name != "cursor" {
                #expect(values[name] == value)
            }
        }
        #expect(optionalInputQuery(requests[1])["cursor"] == "page-2")
    }

    @Test("lightweight version list forwards Apple filters")
    func lightweightVersionListForwardsFilters() async throws {
        let query = [
            "cursor": "page-2",
            "fields[appStoreVersions]": "platform,versionString,appVersionState,appStoreState,createdDate",
            "limit": "200",
            "filter[id]": "ver-1,ver-2",
            "filter[versionString]": "1.0,2.0",
            "filter[appStoreState]": "READY_FOR_SALE",
            "filter[appVersionState]": "READY_FOR_DISTRIBUTION",
            "filter[platform]": "IOS,VISION_OS"
        ]
        let nextURL = optionalInputURL(path: "/v1/apps/app-1/appStoreVersions", query: query)
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps/app-1/appStoreVersions", next: nextURL)),
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps/app-1/appStoreVersions", next: nil))
        ])
        let worker = try await makeOptionalAppsWorker(transport)
        var arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "version_ids": .array([.string("ver-1"), .string("ver-2")]),
            "version_strings": .array([.string("1.0"), .string("2.0")]),
            "app_store_states": .array([.string("READY_FOR_SALE")]),
            "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
            "platforms": .array([.string("IOS"), .string("VISION_OS")])
        ]

        let first = try await worker.handleTool(.init(name: "apps_list_versions", arguments: arguments))
        arguments["next_url"] = .string(nextURL)
        let second = try await worker.handleTool(.init(name: "apps_list_versions", arguments: arguments))

        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let values = optionalInputQuery(request)
            for (name, value) in query where name != "cursor" {
                #expect(values[name] == value)
            }
        }
        #expect(optionalInputQuery(requests[1])["cursor"] == "page-2")
    }

    @Test("localization list forwards locale and page size")
    func localizationListForwardsFilters() async throws {
        let query = [
            "cursor": "page-2",
            "fields[appStoreVersionLocalizations]": "locale,description,whatsNew,keywords,promotionalText,supportUrl,marketingUrl,appStoreVersion",
            "filter[locale]": "en-US,de-DE",
            "include": "appStoreVersion",
            "limit": "75"
        ]
        let nextURL = optionalInputURL(
            path: "/v1/appStoreVersions/ver-1/appStoreVersionLocalizations",
            query: query
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: optionalVersionBody()),
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/appStoreVersions/ver-1/appStoreVersionLocalizations", next: nextURL)),
            .init(statusCode: 200, body: optionalVersionBody()),
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/appStoreVersions/ver-1/appStoreVersionLocalizations", next: nil))
        ])
        let worker = try await makeOptionalAppsWorker(transport)
        var arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "version_id": .string("ver-1"),
            "locales": .array([.string("en-US"), .string("de-DE")]),
            "limit": .int(75)
        ]

        let first = try await worker.handleTool(.init(name: "apps_list_localizations", arguments: arguments))
        arguments["next_url"] = .string(nextURL)
        let second = try await worker.handleTool(.init(name: "apps_list_localizations", arguments: arguments))

        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)
        for request in [requests[1], requests[3]] {
            let values = optionalInputQuery(request)
            for (name, value) in query where name != "cursor" {
                #expect(values[name] == value)
            }
        }
        #expect(optionalInputQuery(requests[3])["cursor"] == "page-2")
    }

    @Test("lifecycle version list forwards ID and version-string filters")
    func lifecycleVersionListForwardsFilters() async throws {
        let query = [
            "cursor": "page-2",
            "include": "build,appStoreVersionPhasedRelease",
            "filter[id]": "ver-1,ver-2",
            "filter[versionString]": "3.0,3.1",
            "limit": "25"
        ]
        let nextURL = optionalInputURL(path: "/v1/apps/app-1/appStoreVersions", query: query)
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps/app-1/appStoreVersions", next: nextURL)),
            .init(statusCode: 200, body: optionalInputPage(path: "/v1/apps/app-1/appStoreVersions", next: nil))
        ])
        let worker = try await makeOptionalLifecycleWorker(transport)
        var arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "version_ids": .array([.string("ver-1"), .string("ver-2")]),
            "version_strings": .array([.string("3.0"), .string("3.1")])
        ]

        let first = try await worker.handleTool(.init(name: "app_versions_list", arguments: arguments))
        arguments["next_url"] = .string(nextURL)
        let second = try await worker.handleTool(.init(name: "app_versions_list", arguments: arguments))

        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let values = optionalInputQuery(request)
            for (name, value) in query where name != "cursor" {
                #expect(values[name] == value)
            }
        }
        #expect(optionalInputQuery(requests[1])["cursor"] == "page-2")
    }

    @Test("invalid collection arrays fail before network access")
    func invalidArraysFailBeforeNetwork() async throws {
        let appsTransport = TestHTTPTransport(responses: [])
        let appsWorker = try await makeOptionalAppsWorker(appsTransport)
        let appsResult = try await appsWorker.handleTool(.init(
            name: "apps_list",
            arguments: ["app_ids": .array([])]
        ))

        let lifecycleTransport = TestHTTPTransport(responses: [])
        let lifecycleWorker = try await makeOptionalLifecycleWorker(lifecycleTransport)
        let lifecycleResult = try await lifecycleWorker.handleTool(.init(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "version_strings": .array([.string(" ")])
            ]
        ))

        #expect(appsResult.isError == true)
        #expect(lifecycleResult.isError == true)
        #expect(await appsTransport.requestCount() == 0)
        #expect(await lifecycleTransport.requestCount() == 0)
    }

    @Test("usesIdfa preserves omission, explicit null, and boolean values")
    func usesIdfaPreservesTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersions","id":"ver-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersions","id":"ver-1","attributes":{"usesIdfa":false}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersions","id":"ver-2"}}"#)
        ])
        let worker = try await makeOptionalLifecycleWorker(transport)

        let create = try await worker.handleTool(.init(
            name: "app_versions_create",
            arguments: [
                "app_id": .string("app-1"),
                "platform": .string("IOS"),
                "version_string": .string("4.0"),
                "uses_idfa": .null
            ]
        ))
        let update = try await worker.handleTool(.init(
            name: "app_versions_update",
            arguments: [
                "version_id": .string("ver-1"),
                "uses_idfa": .bool(false)
            ]
        ))
        let omitted = try await worker.handleTool(.init(
            name: "app_versions_create",
            arguments: [
                "app_id": .string("app-1"),
                "platform": .string("IOS"),
                "version_string": .string("4.1")
            ]
        ))

        #expect(create.isError != true)
        #expect(update.isError != true)
        #expect(omitted.isError != true)
        let bodies = await transport.recordedBodyStrings()
        let createAttributes = try optionalInputAttributes(bodies[0])
        let updateAttributes = try optionalInputAttributes(bodies[1])
        let omittedAttributes = try optionalInputAttributes(bodies[2])
        #expect(createAttributes["usesIdfa"] is NSNull)
        #expect(updateAttributes["usesIdfa"] as? Bool == false)
        #expect(omittedAttributes["usesIdfa"] == nil)
    }

    @Test("manifest closes every Apps and AppLifecycle optional-input warning")
    func manifestClassifiesEveryOptionalInput() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let auditedTools: Set<String> = [
            "apps_get_details", "apps_get_metadata", "apps_list", "apps_list_localizations",
            "apps_list_versions", "apps_update_metadata", "app_versions_cancel_review",
            "app_versions_create", "app_versions_get", "app_versions_list", "app_versions_release",
            "app_versions_set_review_details", "app_versions_submit_for_review", "app_versions_update",
            "app_versions_update_age_rating"
        ]
        let mappings = try auditedTools.map { try #require(manifest.mapping(for: $0)) }
        let classifications = mappings.flatMap { mapping in
            mapping.operations.flatMap { $0.optionalParameterClassifications ?? [] }
        }

        #expect(classifications.count == 119)
        #expect(classifications.filter { $0.disposition == .internalControl }.count == 1)
        #expect(classifications.filter { $0.disposition == .intentionallyOmitted }.count == 118)
        #expect(classifications.allSatisfy { $0.reviewAtSpec == "4.4.1" && !$0.reason.isEmpty })

        let expectedBindings: [(String, String, String?, String?)] = [
            ("apps_list", "app_ids", "filter[id]", nil),
            ("apps_list", "skus", "filter[sku]", nil),
            ("apps_list", "app_store_version_ids", "filter[appStoreVersions]", nil),
            ("apps_list", "app_store_states", "filter[appStoreVersions.appStoreState]", nil),
            ("apps_list", "platforms", "filter[appStoreVersions.platform]", nil),
            ("apps_list", "app_version_states", "filter[appStoreVersions.appVersionState]", nil),
            ("apps_list", "review_submission_states", "filter[reviewSubmissions.state]", nil),
            ("apps_list", "review_submission_platforms", "filter[reviewSubmissions.platform]", nil),
            ("apps_list", "has_game_center_enabled_versions", "exists[gameCenterEnabledVersions]", nil),
            ("apps_list_versions", "version_ids", "filter[id]", nil),
            ("apps_list_versions", "version_strings", "filter[versionString]", nil),
            ("apps_list_versions", "app_store_states", "filter[appStoreState]", nil),
            ("apps_list_versions", "app_version_states", "filter[appVersionState]", nil),
            ("apps_list_versions", "platforms", "filter[platform]", nil),
            ("apps_list_localizations", "locales", "filter[locale]", nil),
            ("apps_list_localizations", "limit", "limit", nil),
            ("app_versions_list", "version_ids", "filter[id]", nil),
            ("app_versions_list", "version_strings", "filter[versionString]", nil),
            ("app_versions_create", "uses_idfa", nil, "/data/attributes/usesIdfa"),
            ("app_versions_update", "uses_idfa", nil, "/data/attributes/usesIdfa")
        ]

        for (tool, field, appleName, jsonPointer) in expectedBindings {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.fields.contains { binding in
                binding.toolField == field && binding.appleName == appleName && binding.jsonPointer == jsonPointer
            })
        }
    }
}

private func makeOptionalAppsWorker(_ transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func makeOptionalLifecycleWorker(_ transport: TestHTTPTransport) async throws -> AppLifecycleWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppLifecycleWorker(httpClient: client)
}

private func optionalInputProperties(_ tools: [Tool], named name: String) throws -> [String: Value] {
    let tool = try #require(tools.first { $0.name == name })
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw OptionalInputContractTestError.expectedProperties
    }
    return properties
}

private func optionalAppsListArguments() -> [String: Value] {
    [
        "limit": .int(50),
        "sort": .string("-name"),
        "app_ids": .array([.string("app-1"), .string("app-2")]),
        "skus": .array([.string("SKU-1"), .string("SKU-2")]),
        "app_store_version_ids": .array([.string("ver-1"), .string("ver-2")]),
        "app_store_states": .array([.string("READY_FOR_SALE")]),
        "platforms": .array([.string("IOS"), .string("MAC_OS")]),
        "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
        "review_submission_states": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW")]),
        "review_submission_platforms": .array([.string("IOS")]),
        "has_game_center_enabled_versions": .bool(false)
    ]
}

private func optionalInputPage(path: String, next: String?) -> String {
    let nextField = next.map { #", "next": "\#($0)""# } ?? ""
    return #"{"data":[],"links":{"self":"https://api.example.test\#(path)"\#(nextField)}}"#
}

private func optionalVersionBody() -> String {
    #"{"data":{"type":"appStoreVersions","id":"ver-1","relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
}

private func optionalInputURL(path: String, query: [String: String]) -> String {
    var components = URLComponents(string: "https://api.example.test\(path)")!
    components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
    return components.url!.absoluteString
}

private func optionalInputQuery(_ request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
        return [:]
    }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

private func optionalInputAttributes(_ body: String) throws -> [String: Any] {
    let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    let data = try #require(object["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private enum OptionalInputContractTestError: Error {
    case expectedProperties
}
