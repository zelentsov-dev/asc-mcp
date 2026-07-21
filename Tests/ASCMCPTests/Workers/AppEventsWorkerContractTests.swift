import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("App Events Worker Contract Tests")
struct AppEventsWorkerContractTests {
    @Test("schemas expose current Apple filters, nested limits, and nullable writes")
    func schemasExposeCurrentControls() async throws {
        let worker = try await appEventsContractWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let list = try appEventsContractProperties(try #require(tools.first { $0.name == "app_events_list" }))
        #expect(list["event_states"] != nil)
        #expect(list["event_ids"] != nil)
        #expect(list["include"] != nil)
        #expect(list["localizations_limit"] != nil)
        #expect(list["next_url"] != nil)
        for field in ["event_states", "include"] {
            let variants = try #require(list[field]?.objectValue?["oneOf"]?.arrayValue)
            let scalar = try appEventsContractObject(try #require(variants.first))
            #expect(scalar["pattern"]?.stringValue?.isEmpty == false)
        }
        let eventStateVariants = try #require(list["event_states"]?.objectValue?["oneOf"]?.arrayValue)
        let eventStateScalar = try appEventsContractObject(try #require(eventStateVariants.first))
        let eventStatePattern = try #require(eventStateScalar["pattern"]?.stringValue)
        #expect("DRAFT, READY_FOR_REVIEW".range(of: eventStatePattern, options: .regularExpression) != nil)
        #expect("DRAFT, INVALID".range(of: eventStatePattern, options: .regularExpression) == nil)

        let localizationList = try appEventsContractProperties(
            try #require(tools.first { $0.name == "app_events_list_localizations" })
        )
        #expect(localizationList["include"] != nil)
        #expect(localizationList["screenshots_limit"] != nil)
        #expect(localizationList["video_clips_limit"] != nil)
        #expect(localizationList["next_url"] != nil)

        let create = try appEventsContractProperties(try #require(tools.first { $0.name == "app_events_create" }))
        let update = try appEventsContractProperties(try #require(tools.first { $0.name == "app_events_update" }))
        #expect(update["primary_locale"] != nil)
        #expect(update["priority"] != nil)
        #expect(update["territory_schedules"]?.objectValue?["oneOf"]?.arrayValue?.count == 3)
        #expect(update["deep_link"]?.objectValue?["format"]?.stringValue == "uri")
        for properties in [create, update] {
            let purchase = try #require(properties["purchase_requirement"]?.objectValue)
            #expect(purchase["type"]?.arrayValue?.compactMap(\.stringValue) == ["string", "null"])
            #expect(purchase["enum"] == nil)
        }
    }

    @Test("current collection controls map to Apple query names")
    func collectionControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data":[{
                "type":"appEvents",
                "id":"event-1",
                "attributes":{"referenceName":"Launch","primaryLocale":"en-US","priority":"HIGH","eventState":"DRAFT"},
                "relationships":{"localizations":{"data":[{"type":"appEventLocalizations","id":"loc-1"}]}}
              }],
              "included":[{"type":"appEventLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":"Launch"}}],
              "meta":{"paging":{"total":1,"limit":200}}
            }
            """)
        ])
        let worker = try await appEventsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_list",
            arguments: [
                "app_id": .string("app-1"),
                "event_states": .array([.string("DRAFT"), .string("READY_FOR_REVIEW")]),
                "event_ids": .string("event-1,event-2"),
                "include": .array([.string("localizations")]),
                "limit": .int(200),
                "localizations_limit": .int(50)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try appEventsContractQuery(request)
        #expect(query["filter[eventState]"] == "DRAFT,READY_FOR_REVIEW")
        #expect(query["filter[id]"] == "event-1,event-2")
        #expect(query["include"] == "localizations")
        #expect(query["limit"] == "200")
        #expect(query["limit[localizations]"] == "50")

        let payload = try appEventsContractObject(result.structuredContent)
        let event = try appEventsContractObject(try #require(appEventsContractArray(payload["app_events"]).first))
        #expect(event["primaryLocale"]?.stringValue == "en-US")
        #expect(event["priority"]?.stringValue == "HIGH")
        #expect(try appEventsContractStrings(event["localizationIds"]) == ["loc-1"])
        #expect(try appEventsContractArray(payload["included_localizations"]).count == 1)
    }

    @Test("localization include limits map to relationship names")
    func localizationControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data":[{
                "type":"appEventLocalizations",
                "id":"loc-1",
                "attributes":{"locale":"en-US","name":"Launch"},
                "relationships":{
                  "appEvent":{"data":{"type":"appEvents","id":"event-1"}},
                  "appEventScreenshots":{"data":[{"type":"appEventScreenshots","id":"shot-1"}]},
                  "appEventVideoClips":{"data":[{"type":"appEventVideoClips","id":"video-1"}]}
                }
              }],
              "included":[{"type":"appEventScreenshots","id":"shot-1","attributes":{"assetToken":"token"}}],
              "meta":{"paging":{"total":1,"limit":200}}
            }
            """)
        ])
        let worker = try await appEventsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_list_localizations",
            arguments: [
                "event_id": .string("event-1"),
                "include": .array([.string("appEvent"), .string("appEventScreenshots"), .string("appEventVideoClips")]),
                "limit": .int(200),
                "screenshots_limit": .int(50),
                "video_clips_limit": .int(50)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try appEventsContractQuery(request)
        #expect(query["include"] == "appEvent,appEventScreenshots,appEventVideoClips")
        #expect(query["limit"] == "200")
        #expect(query["limit[appEventScreenshots]"] == "50")
        #expect(query["limit[appEventVideoClips]"] == "50")

        let payload = try appEventsContractObject(result.structuredContent)
        let localization = try appEventsContractObject(try #require(appEventsContractArray(payload["localizations"]).first))
        #expect(localization["appEventId"]?.stringValue == "event-1")
        #expect(try appEventsContractStrings(localization["screenshotIds"]) == ["shot-1"])
        #expect(try appEventsContractStrings(localization["videoClipIds"]) == ["video-1"])
        #expect(try appEventsContractArray(payload["included"]).count == 1)
    }

    @Test("structured territory schedules and nullable fields reach Apple body")
    func structuredSchedulesAndNullableFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {"data":{"type":"appEvents","id":"event-1","attributes":{"referenceName":"Launch","primaryLocale":"en-US","priority":"NORMAL","badge":null,"territorySchedules":[]}}}
            """)
        ])
        let worker = try await appEventsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_create",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("Launch"),
                "badge": .null,
                "deep_link": .string("ascmcp://events/launch"),
                "purchase_requirement": .string("IN_APP_PURCHASE"),
                "primary_locale": .string("en-US"),
                "priority": .string("NORMAL"),
                "territory_schedules": .array([
                    .object([
                        "territories": .array([.string("USA"), .string("CAN")]),
                        "publishStart": .string("2026-07-20T00:00:00Z"),
                        "eventStart": .string("2026-07-21T00:00:00Z"),
                        "eventEnd": .string("2026-07-22T00:00:00Z")
                    ])
                ])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let attributes = try appEventsContractAttributes(request)
        #expect(attributes["badge"] is NSNull)
        #expect(attributes["deepLink"] as? String == "ascmcp://events/launch")
        #expect(attributes["purchaseRequirement"] as? String == "IN_APP_PURCHASE")
        #expect(attributes["primaryLocale"] as? String == "en-US")
        #expect(attributes["priority"] as? String == "NORMAL")
        let schedules = try #require(attributes["territorySchedules"] as? [[String: Any]])
        #expect(schedules.first?["territories"] as? [String] == ["USA", "CAN"])
    }

    @Test("invalid payloads and no-op updates fail before network")
    func invalidPayloadsFailBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await appEventsContractWorker(transport: transport)

        let invalidSchedule = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_create",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("Launch"),
                "territory_schedules": .array([
                    .object(["territories": .string("USA")])
                ])
            ]
        ))
        let noOpEvent = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_update",
            arguments: ["event_id": .string("event-1")]
        ))
        let noOpLocalization = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_update_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))
        let invalidCreateDeepLink = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_create",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("Launch"),
                "deep_link": .string("/events/launch")
            ]
        ))
        let invalidUpdateDeepLink = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_update",
            arguments: [
                "event_id": .string("event-1"),
                "deep_link": .string("events launch")
            ]
        ))
        #expect(invalidSchedule.isError == true)
        #expect(noOpEvent.isError == true)
        #expect(noOpLocalization.isError == true)
        #expect(invalidCreateDeepLink.isError == true)
        #expect(invalidUpdateDeepLink.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("present invalid collection limits fail before network")
    func invalidLimitsFailBeforeNetwork() async throws {
        let cases: [(String, [String: Value])] = [
            ("app_events_list", ["app_id": .string("app-1"), "limit": .int(0)]),
            ("app_events_list", ["app_id": .string("app-1"), "localizations_limit": .string("50")]),
            ("app_events_get", ["event_id": .string("event-1"), "localizations_limit": .int(51)]),
            ("app_events_list_localizations", ["event_id": .string("event-1"), "limit": .int(201)]),
            ("app_events_list_localizations", ["event_id": .string("event-1"), "screenshots_limit": .int(0)]),
            ("app_events_list_localizations", ["event_id": .string("event-1"), "video_clips_limit": .string("50")])
        ]

        for (tool, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await appEventsContractWorker(transport: transport)

            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("accepted create and update identity failures are committed unverified")
    func mutationIdentityFailuresPreserveCommitState() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"apps","id":"event-1"}}"#)
        ])
        let createWorker = try await appEventsContractWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "app_events_create",
            arguments: ["app_id": .string("app-1"), "reference_name": .string("Launch")]
        ))

        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appEventLocalizations","id":"loc-other"}}"#)
        ])
        let updateWorker = try await appEventsContractWorker(transport: updateTransport)
        let update = try await updateWorker.handleTool(.init(
            name: "app_events_update_localization",
            arguments: ["localization_id": .string("loc-1"), "name": .string("Launch")]
        ))

        for result in [create, update] {
            let payload = try appEventsContractObject(result.structuredContent)
            #expect(result.isError == true)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
        }
    }

    @Test("purchase requirement forwards arbitrary Apple strings on create and update")
    func purchaseRequirementIsUnconstrained() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {"data":{"type":"appEvents","id":"event-1","attributes":{"referenceName":"Launch","purchaseRequirement":"SUBSCRIPTION"}}}
            """),
            .init(statusCode: 200, body: """
            {"data":{"type":"appEvents","id":"event-1","attributes":{"referenceName":"Launch","purchaseRequirement":"IN_APP_PURCHASE_OR_SUBSCRIPTION"}}}
            """)
        ])
        let worker = try await appEventsContractWorker(transport: transport)

        let create = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_create",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("Launch"),
                "purchase_requirement": .string("SUBSCRIPTION")
            ]
        ))
        let update = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_update",
            arguments: [
                "event_id": .string("event-1"),
                "purchase_requirement": .string("IN_APP_PURCHASE_OR_SUBSCRIPTION")
            ]
        ))

        #expect(create.isError != true)
        #expect(update.isError != true)
        let requests = await transport.recordedRequests()
        let createRequest = try #require(requests.first)
        let updateRequest = try #require(requests.last)
        #expect(try appEventsContractAttributes(createRequest)["purchaseRequirement"] as? String == "SUBSCRIPTION")
        #expect(try appEventsContractAttributes(updateRequest)["purchaseRequirement"] as? String == "IN_APP_PURCHASE_OR_SUBSCRIPTION")

        let manifest = try ASCOperationManifestBundle.loadBundled()
        for toolName in ["app_events_create", "app_events_update"] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let purchaseRequirement = try #require(mapping.fields.first { $0.toolField == "purchase_requirement" })
            #expect(purchaseRequirement.localRole?.contains("any non-null string") == true)
        }
    }

    @Test("localization update sends explicit null")
    func localizationExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {"data":{"type":"appEventLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":null}}}
            """)
        ])
        let worker = try await appEventsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_update_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "name": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let attributes = try appEventsContractAttributes(request)
        #expect(attributes["name"] is NSNull)
    }

    @Test("pagination continuation must preserve event filters")
    func paginationPreservesFilters() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await appEventsContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_events_list",
            arguments: [
                "app_id": .string("app-1"),
                "event_states": .string("DRAFT"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appEvents?cursor=next&limit=25")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private func appEventsContractWorker(transport: TestHTTPTransport) async throws -> AppEventsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppEventsWorker(httpClient: client)
}

private func appEventsContractQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func appEventsContractProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AppEventsContractTestError.expectedObject
    }
    return properties
}

private func appEventsContractAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(object["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func appEventsContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw AppEventsContractTestError.expectedObject
    }
    return object
}

private func appEventsContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw AppEventsContractTestError.expectedArray
    }
    return array
}

private func appEventsContractStrings(_ value: Value?) throws -> [String] {
    try appEventsContractArray(value).compactMap(\.stringValue)
}

private enum AppEventsContractTestError: Error {
    case expectedObject
    case expectedArray
}
