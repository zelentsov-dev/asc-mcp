import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("AppLifecycle Reliability Tests")
struct AppLifecycleReliabilityTests {
    @Test("lifecycle manifest records fixed query controls")
    func lifecycleManifestRecordsFixedQueries() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        #expect(try lifecycleReliabilityFixedQuery(
            manifest,
            tool: "app_versions_submit_for_review",
            operationID: "appStoreVersions_getInstance",
            appleName: "fields[appStoreVersions]"
        ) == .array([
            .string("app"), .string("platform"), .string("versionString"), .string("appVersionState")
        ]))
        #expect(try lifecycleReliabilityFixedQuery(
            manifest,
            tool: "app_versions_list",
            operationID: "apps_appStoreVersions_getToManyRelated",
            appleName: "include"
        ) == .array([
            .string("build"), .string("appStoreVersionPhasedRelease")
        ]))
        #expect(try lifecycleReliabilityFixedQuery(
            manifest,
            tool: "app_versions_get",
            operationID: "appStoreVersions_getInstance",
            appleName: "include"
        ) == .array([
            .string("build"), .string("appStoreVersionPhasedRelease")
        ]))
        #expect(try lifecycleReliabilityFixedQuery(
            manifest,
            tool: "app_versions_release",
            operationID: "appStoreVersions_getInstance",
            appleName: "fields[appStoreVersions]"
        ) == .array([
            .string("platform"), .string("versionString"), .string("appVersionState")
        ]))
    }

    @Test("schemas expose current lifecycle fields and phased release delete")
    func schemasExposeCurrentFields() async throws {
        let worker = try await makeLifecycleReliabilityWorker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let list = try lifecycleReliabilityProperties(try #require(tools.first { $0.name == "app_versions_list" }))
        let create = try lifecycleReliabilityProperties(try #require(tools.first { $0.name == "app_versions_create" }))
        let update = try lifecycleReliabilityProperties(try #require(tools.first { $0.name == "app_versions_update" }))
        let age = try lifecycleReliabilityProperties(try #require(tools.first { $0.name == "app_versions_update_age_rating" }))
        let updatePhased = try #require(tools.first { $0.name == "app_versions_update_phased_release" })
        let deletePhased = try #require(tools.first { $0.name == "app_versions_delete_phased_release" })
        let deleteVersion = try #require(tools.first { $0.name == "app_versions_delete" })

        #expect(list["states"] != nil)
        #expect(list["states"]?.objectValue?["deprecated"]?.boolValue == true)
        #expect(list["states"]?.objectValue?["minItems"]?.intValue == 1)
        #expect(list["states"]?.objectValue?["uniqueItems"]?.boolValue == true)
        #expect(list["app_version_states"] != nil)
        #expect(list["app_version_states"]?.objectValue?["minItems"]?.intValue == 1)
        #expect(list["app_version_states"]?.objectValue?["uniqueItems"]?.boolValue == true)
        #expect(list["platform"]?.objectValue?["deprecated"]?.boolValue == true)
        #expect(list["platforms"]?.objectValue?["type"]?.stringValue == "array")
        #expect(list["limit"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(list["limit"]?.objectValue?["maximum"]?.intValue == 200)
        #expect(list["limit"]?.objectValue?["default"]?.intValue == 25)
        #expect(create["copyright"] != nil)
        #expect(create["review_type"] != nil)
        #expect(update["review_type"]?.objectValue?["type"]?.arrayValue?.compactMap(\.stringValue) == ["string", "null"])
        #expect(update["downloadable"]?.objectValue?["type"]?.arrayValue?.compactMap(\.stringValue) == ["boolean", "null"])
        #expect(age["kids_age_band"]?.objectValue?["type"]?.arrayValue?.compactMap(\.stringValue) == ["string", "null"])
        #expect(tools.contains { $0.name == "app_versions_delete_phased_release" })
        #expect(Set(deletePhased.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) == [
            "phased_release_id", "confirm_phased_release_id"
        ])
        #expect(updatePhased.inputSchema.objectValue?["allOf"]?.arrayValue?.isEmpty == false)
        #expect(Set(deleteVersion.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []) == [
            "version_id", "confirm_version_id"
        ])
    }

    @Test("version filters preserve deprecated and current state semantics")
    func versionFiltersMapToDistinctAppleParameters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/appStoreVersions"}}"#)
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_list",
            arguments: [
                "app_id": .string("app-1"),
                "states": .array([.string("READY_FOR_SALE")]),
                "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first(where: { $0.name == "include" })?.value == "build,appStoreVersionPhasedRelease")
        #expect(query.first(where: { $0.name == "filter[appStoreState]" })?.value == "READY_FOR_SALE")
        #expect(query.first(where: { $0.name == "filter[appVersionState]" })?.value == "READY_FOR_DISTRIBUTION")
        #expect(query.first(where: { $0.name == "limit" })?.value == "25")
    }

    @Test("create version sends copyright and review type")
    func createVersionSendsCurrentAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersions","id":"ver-1"}}"#)
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_create",
            arguments: [
                "app_id": .string("app-1"),
                "platform": .string("IOS"),
                "version_string": .string("2.0"),
                "copyright": .string("2026 Example"),
                "review_type": .string("APP_STORE")
            ]
        ))

        #expect(result.isError != true)
        let attributes = try lifecycleReliabilityRequestAttributes(try #require(await transport.recordedBodyStrings().first))
        #expect(attributes["copyright"] as? String == "2026 Example")
        #expect(attributes["reviewType"] as? String == "APP_STORE")
    }

    @Test("update version preserves nullable tri-state and exposes current state")
    func updateVersionPreservesTriStateAndStateOutput() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {"data":{"type":"appStoreVersions","id":"ver-1","attributes":{"platform":"IOS","versionString":"2.0","appVersionState":"READY_FOR_DISTRIBUTION","appStoreState":"READY_FOR_SALE","copyright":"2026 Example","earliestReleaseDate":"2026-08-01T00:00:00Z","reviewType":"NOTARIZATION","downloadable":false}}}
            """)
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_update",
            arguments: [
                "version_id": .string("ver-1"),
                "copyright": .null,
                "review_type": .string("NOTARIZATION"),
                "downloadable": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let attributes = try lifecycleReliabilityRequestAttributes(try #require(await transport.recordedBodyStrings().first))
        #expect(attributes.count == 3)
        #expect(attributes["copyright"] is NSNull)
        #expect(attributes["reviewType"] as? String == "NOTARIZATION")
        #expect(attributes["downloadable"] as? Bool == false)
        let payload = try lifecycleReliabilityObject(result)
        let version = try #require(payload["version"] as? [String: Any])
        #expect(version["platform"] as? String == "IOS")
        #expect(version["state"] as? String == "READY_FOR_DISTRIBUTION")
        #expect(version["appVersionState"] as? String == "READY_FOR_DISTRIBUTION")
        #expect(version["appStoreState"] as? String == "READY_FOR_SALE")
        #expect(version["app_version_state"] as? String == "READY_FOR_DISTRIBUTION")
        #expect(version["app_store_state"] as? String == "READY_FOR_SALE")
        #expect(version["copyright"] as? String == "2026 Example")
        #expect(version["earliest_release_date"] as? String == "2026-08-01T00:00:00Z")
    }

    @Test("kids age band preserves explicit null")
    func kidsAgeBandPreservesNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1","attributes":{"kidsAgeBand":null}}}"#)
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_update_age_rating",
            arguments: ["app_info_id": .string("info-1"), "kids_age_band": .null]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 2)
        let attributes = try lifecycleReliabilityRequestAttributes(try #require(await transport.recordedBodyStrings().last))
        #expect(attributes.count == 1)
        #expect(attributes["kidsAgeBand"] is NSNull)
    }

    @Test("phased release delete uses Apple delete endpoint")
    func phasedReleaseDelete() async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 204, body: "")])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_delete_phased_release",
            arguments: [
                "phased_release_id": .string("phase-1"),
                "confirm_phased_release_id": .string("phase-1")
            ]
        ))

        #expect(result.isError != true)
        let payload = try lifecycleReliabilityStructuredObject(result)
        #expect(payload["deletionState"] == .string("confirmed"))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/appStoreVersionPhasedReleases/phase-1")
    }

    @Test("version delete requires an exact canonical confirmation before network access")
    func versionDeleteRequiresExactConfirmation() async throws {
        let invalidArguments: [[String: Value]] = [
            ["version_id": .string("ver-1")],
            ["version_id": .string("ver-1"), "confirm_version_id": .string("ver-2")],
            ["version_id": .string(" ver-1 "), "confirm_version_id": .string(" ver-1 ")]
        ]

        for arguments in invalidArguments {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeLifecycleReliabilityWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "app_versions_delete",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("version delete sends one confirmed request")
    func versionDeleteUsesOneConfirmedRequest() async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 204, body: "")])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_delete",
            arguments: [
                "version_id": .string("ver-1"),
                "confirm_version_id": .string("ver-1")
            ]
        ))

        #expect(result.isError != true)
        let payload = try lifecycleReliabilityStructuredObject(result)
        #expect(payload["version_id"] == .string("ver-1"))
        #expect(payload["deletionState"] == .string("confirmed"))
        #expect(payload["retrySafe"] == .bool(false))
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "DELETE")
        #expect(requests.first?.url?.path == "/v1/appStoreVersions/ver-1")
    }

    @Test("ambiguous delete statuses stay commit unknown after one attempt")
    func ambiguousDeleteStatusesStayUnknown() async throws {
        let cases: [(String, [String: Value])] = [
            (
                "app_versions_delete",
                ["version_id": .string("ver-1"), "confirm_version_id": .string("ver-1")]
            ),
            (
                "app_versions_delete_phased_release",
                ["phased_release_id": .string("phase-1"), "confirm_phased_release_id": .string("phase-1")]
            )
        ]

        for (tool, arguments) in cases {
            for statusCode in [408, 500, 502, 503, 504] {
                let transport = TestHTTPTransport(responses: [
                    .init(statusCode: statusCode, body: lifecycleReliabilityAPIError(statusCode))
                ])
                let worker = try await makeLifecycleReliabilityWorker(transport)
                let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

                #expect(result.isError == true)
                let details = try lifecycleReliabilityErrorDetails(result)
                #expect(details["deletionState"] == .string("commit_unknown"))
                #expect(details["operationCommitState"] == .string("unknown"))
                #expect(details["outcomeUnknown"] == .bool(true))
                #expect(details["retrySafe"] == .bool(false))
                let requests = await transport.recordedRequests()
                #expect(requests.count == 1)
                #expect(requests.first?.httpMethod == "DELETE")
            }
        }
    }

    @Test("network delete failures stay commit unknown after one attempt")
    func networkDeleteFailuresStayUnknown() async throws {
        let cases: [(String, [String: Value])] = [
            (
                "app_versions_delete",
                ["version_id": .string("ver-1"), "confirm_version_id": .string("ver-1")]
            ),
            (
                "app_versions_delete_phased_release",
                ["phased_release_id": .string("phase-1"), "confirm_phased_release_id": .string("phase-1")]
            )
        ]

        for (tool, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeLifecycleReliabilityWorker(transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

            #expect(result.isError == true)
            let details = try lifecycleReliabilityErrorDetails(result)
            #expect(details["deletionState"] == .string("commit_unknown"))
            #expect(details["outcomeUnknown"] == .bool(true))
            #expect(details["retrySafe"] == .bool(false))
            let requests = await transport.recordedRequests()
            #expect(requests.count == 1)
            #expect(requests.first?.httpMethod == "DELETE")
        }
    }

    @Test("definite delete rejection remains retry safe and preserves Apple error")
    func definiteDeleteRejection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 403, body: lifecycleReliabilityAPIError(403))
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_delete",
            arguments: [
                "version_id": .string("ver-1"),
                "confirm_version_id": .string("ver-1")
            ]
        ))

        #expect(result.isError == true)
        let details = try lifecycleReliabilityErrorDetails(result)
        #expect(details["deletionState"] == .string("rejected"))
        #expect(details["operationCommitState"] == .string("rejected"))
        #expect(details["outcomeUnknown"] == .bool(false))
        #expect(details["retrySafe"] == .bool(true))
        let cause = try lifecycleReliabilityValueObject(details["cause"])
        #expect(cause["type"] == .string("api"))
        #expect(cause["statusCode"] == .int(403))
        #expect(await transport.requestCount() == 1)
    }

    @Test("submit rejects mismatched app ownership before creating a submission")
    func submitRejectsMismatchedOwnership() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersions","id":"ver-1","attributes":{"platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":"actual-app"}}}}}"#)
        ])
        let worker = try await makeLifecycleReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_submit_for_review",
            arguments: ["version_id": .string("ver-1"), "app_id": .string("wrong-app")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first(where: { $0.name == "fields[appStoreVersions]" })?.value == "app,platform,versionString,appVersionState")
    }
}

private func makeLifecycleReliabilityWorker(_ transport: TestHTTPTransport) async throws -> AppLifecycleWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppLifecycleWorker(httpClient: client)
}

private func lifecycleReliabilityRequestAttributes(_ body: String) throws -> [String: Any] {
    let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    let data = try #require(object["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func lifecycleReliabilityText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content { return text }
        return nil
    }.joined(separator: "\n")
}

private func lifecycleReliabilityObject(_ result: CallTool.Result) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(lifecycleReliabilityText(result).utf8)) as? [String: Any])
}

private func lifecycleReliabilityStructuredObject(_ result: CallTool.Result) throws -> [String: Value] {
    try lifecycleReliabilityValueObject(result.structuredContent)
}

private func lifecycleReliabilityErrorDetails(_ result: CallTool.Result) throws -> [String: Value] {
    let root = try lifecycleReliabilityStructuredObject(result)
    return try lifecycleReliabilityValueObject(root["details"])
}

private func lifecycleReliabilityValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        throw LifecycleReliabilityTestError.expectedObject
    }
    return object
}

private func lifecycleReliabilityAPIError(_ statusCode: Int) -> String {
    #"{"errors":[{"status":"\#(statusCode)","detail":"request rejected"}]}"#
}

private func lifecycleReliabilityProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw LifecycleReliabilityTestError.expectedProperties
    }
    return properties
}

private func lifecycleReliabilityFixedQuery(
    _ manifest: ASCOperationManifestBundle,
    tool: String,
    operationID: String,
    appleName: String
) throws -> ASCJSONValue {
    let mapping = try #require(manifest.mapping(for: tool))
    let operation = try #require(mapping.operations.first { $0.operationID == operationID })
    let input = try #require(operation.inputs?.first {
        $0.sourceKind == .fixed && $0.location == "query" && $0.appleName == appleName
    })
    return try #require(input.fixedValue)
}

private enum LifecycleReliabilityTestError: Error {
    case expectedProperties
    case expectedObject
}
