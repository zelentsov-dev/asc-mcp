import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Path-only Pagination Scope Tests")
struct PathOnlyPaginationScopeTests {
    @Test("all path-only lists preserve exact default and explicit queries")
    func preservesExactQueries() async throws {
        for fixture in pathOnlyPaginationCases() {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: fixture.responseBody)
            ])
            let firstPageResult = try await invokePathOnlyPaginationFixture(
                fixture,
                arguments: fixture.arguments,
                transport: firstPageTransport
            )

            #expect(firstPageResult.isError != true, "Expected first page for \(fixture.receiptName)")
            let firstPageRequest = try #require(await firstPageTransport.recordedRequests().first)
            #expect(firstPageRequest.url?.path == fixture.path)
            #expect(pathOnlyPaginationQuery(firstPageRequest) == fixture.requiredQuery)

            let continuationTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: fixture.responseBody)
            ])
            var continuationArguments = fixture.arguments
            var continuationQuery = fixture.requiredQuery
            continuationQuery["cursor"] = "next"
            continuationArguments["next_url"] = .string(pathOnlyPaginationURL(
                path: fixture.path,
                query: continuationQuery
            ))
            let continuationResult = try await invokePathOnlyPaginationFixture(
                fixture,
                arguments: continuationArguments,
                transport: continuationTransport
            )

            #expect(continuationResult.isError != true, "Expected continuation for \(fixture.receiptName)")
            let continuationRequest = try #require(await continuationTransport.recordedRequests().first)
            #expect(continuationRequest.url?.path == fixture.path)
            #expect(pathOnlyPaginationQuery(continuationRequest) == continuationQuery)
        }
    }

    @Test("all path-only continuations reject every missing or changed originating query value")
    func rejectsMissingAndChangedQueryValues() async throws {
        for fixture in pathOnlyPaginationCases() {
            for name in fixture.requiredQuery.keys {
                for mutation in PathOnlyQueryMutation.allCases {
                    let transport = TestHTTPTransport(responses: [])
                    var arguments = fixture.arguments
                    var query = fixture.requiredQuery
                    switch mutation {
                    case .missing:
                        query.removeValue(forKey: name)
                    case .changed:
                        query[name] = "drift"
                    }
                    query["cursor"] = "next"
                    arguments["next_url"] = .string(pathOnlyPaginationURL(
                        path: fixture.path,
                        query: query
                    ))

                    let result = try await invokePathOnlyPaginationFixture(
                        fixture,
                        arguments: arguments,
                        transport: transport
                    )

                    #expect(result.isError == true, "Expected \(mutation) \(name) rejection for \(fixture.receiptName)")
                    #expect(await transport.requestCount() == 0)
                }
            }
        }
    }

    @Test("all path-only continuations require a non-empty cursor")
    func rejectsMissingEmptyAndBlankCursors() async throws {
        for fixture in pathOnlyPaginationCases() {
            for cursor in [String?.none, .some(""), .some(" ")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(pathOnlyPaginationURL(
                    path: fixture.path,
                    query: query
                ))

                let result = try await invokePathOnlyPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor rejection for \(fixture.receiptName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("all path-only continuations reject query injection and duplicates")
    func rejectsInjectedAndDuplicateControls() async throws {
        for fixture in pathOnlyPaginationCases() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"

            for (name, value) in [("include", "app"), ("filter[unexpected]", "drift")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var injectedQuery = validQuery
                injectedQuery[name] = value
                arguments["next_url"] = .string(pathOnlyPaginationURL(
                    path: fixture.path,
                    query: injectedQuery
                ))

                let result = try await invokePathOnlyPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected \(name) injection rejection for \(fixture.receiptName)")
                #expect(await transport.requestCount() == 0)
            }

            let validURL = pathOnlyPaginationURL(path: fixture.path, query: validQuery)
            for name in ["limit", "cursor"] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(pathOnlyPaginationURL(
                    validURL,
                    appendingDuplicate: name,
                    value: "duplicate"
                ))

                let result = try await invokePathOnlyPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected duplicate \(name) rejection for \(fixture.receiptName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("all path-only continuations reject path origin port credentials and fragment changes")
    func rejectsPathAndOriginChanges() async throws {
        for fixture in pathOnlyPaginationCases() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            let invalidURLs = [
                pathOnlyPaginationURL(path: fixture.wrongPath, query: validQuery),
                pathOnlyPaginationURL(path: fixture.path, query: validQuery, host: "other.example.test"),
                pathOnlyPaginationURL(path: fixture.path, query: validQuery, scheme: "http"),
                pathOnlyPaginationURL(path: fixture.path, query: validQuery, port: 444),
                pathOnlyPaginationURL(
                    path: fixture.path,
                    query: validQuery,
                    user: "user",
                    password: "secret"
                ),
                pathOnlyPaginationURL(path: fixture.path, query: validQuery, fragment: "fragment")
            ]

            for nextURL in invalidURLs {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(nextURL)

                let result = try await invokePathOnlyPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected path or origin rejection for \(fixture.receiptName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }
}

private enum PathOnlyPaginationWorker {
    case accessibility
    case analytics
    case betaGroups
    case betaTesters
    case buildBetaDetails
    case preReleaseVersions
    case pricing
    case sandbox
    case users
}

private enum PathOnlyQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct PathOnlyPaginationFixture {
    let worker: PathOnlyPaginationWorker
    let toolName: String
    let controlName: String
    let arguments: [String: Value]
    let path: String
    let wrongPath: String
    let requiredQuery: [String: String]
    let defaultLimit: String
    let responseBody: String

    var receiptName: String {
        "\(toolName) [\(controlName)]"
    }
}

private func pathOnlyPaginationFixtures() -> [PathOnlyPaginationFixture] {
    let emptyResponse = #"{"data":[]}"#
    let appsResponse = #"{"data":[],"links":{"self":"https://api.example.test/v1/apps"}}"#

    return [
        PathOnlyPaginationFixture(
            worker: .accessibility,
            toolName: "accessibility_list_relationships",
            controlName: "explicit limit",
            arguments: ["app_id": .string("app-1"), "limit": .int(31)],
            path: "/v1/apps/app-1/relationships/accessibilityDeclarations",
            wrongPath: "/v1/apps/app-2/relationships/accessibilityDeclarations",
            requiredQuery: ["limit": "31"],
            defaultLimit: "25",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .analytics,
            toolName: "analytics_list_segments",
            controlName: "explicit limit",
            arguments: ["instance_id": .string("instance-1"), "limit": .int(32)],
            path: "/v1/analyticsReportInstances/instance-1/segments",
            wrongPath: "/v1/analyticsReportInstances/instance-2/segments",
            requiredQuery: ["limit": "32"],
            defaultLimit: "25",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .betaGroups,
            toolName: "beta_groups_list_testers",
            controlName: "explicit limit",
            arguments: ["group_id": .string("group-1"), "limit": .int(33)],
            path: "/v1/betaGroups/group-1/betaTesters",
            wrongPath: "/v1/betaGroups/group-2/betaTesters",
            requiredQuery: ["limit": "33"],
            defaultLimit: "25",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .betaTesters,
            toolName: "beta_testers_list_apps",
            controlName: "explicit limit",
            arguments: ["tester_id": .string("tester-1"), "limit": .int(34)],
            path: "/v1/betaTesters/tester-1/apps",
            wrongPath: "/v1/betaTesters/tester-2/apps",
            requiredQuery: ["limit": "34"],
            defaultLimit: "25",
            responseBody: appsResponse
        ),
        PathOnlyPaginationFixture(
            worker: .buildBetaDetails,
            toolName: "builds_list_beta_localizations",
            controlName: "explicit limit",
            arguments: ["build_id": .string("build-1"), "limit": .int(35)],
            path: "/v1/builds/build-1/betaBuildLocalizations",
            wrongPath: "/v1/builds/build-2/betaBuildLocalizations",
            requiredQuery: ["limit": "35"],
            defaultLimit: "50",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .buildBetaDetails,
            toolName: "builds_get_beta_testers",
            controlName: "explicit limit",
            arguments: ["build_id": .string("build-1"), "limit": .int(36)],
            path: "/v1/builds/build-1/individualTesters",
            wrongPath: "/v1/builds/build-2/individualTesters",
            requiredQuery: ["limit": "36"],
            defaultLimit: "50",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .buildBetaDetails,
            toolName: "builds_list_individual_testers",
            controlName: "explicit limit",
            arguments: ["build_id": .string("build-1"), "limit": .int(37)],
            path: "/v1/builds/build-1/individualTesters",
            wrongPath: "/v1/builds/build-2/individualTesters",
            requiredQuery: ["limit": "37"],
            defaultLimit: "50",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .preReleaseVersions,
            toolName: "pre_release_list_builds",
            controlName: "explicit limit",
            arguments: ["pre_release_version_id": .string("version-1"), "limit": .int(38)],
            path: "/v1/preReleaseVersions/version-1/builds",
            wrongPath: "/v1/preReleaseVersions/version-2/builds",
            requiredQuery: ["limit": "38"],
            defaultLimit: "25",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .pricing,
            toolName: "pricing_list_territories",
            controlName: "explicit limit",
            arguments: ["limit": .int(39)],
            path: "/v1/territories",
            wrongPath: "/v1/territories/other",
            requiredQuery: ["limit": "39"],
            defaultLimit: "200",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .sandbox,
            toolName: "sandbox_list",
            controlName: "explicit limit",
            arguments: ["limit": .int(40)],
            path: "/v2/sandboxTesters",
            wrongPath: "/v2/sandboxTesters/other",
            requiredQuery: ["limit": "40"],
            defaultLimit: "25",
            responseBody: emptyResponse
        ),
        PathOnlyPaginationFixture(
            worker: .users,
            toolName: "users_list_visible_apps",
            controlName: "explicit limit",
            arguments: ["user_id": .string("user-1"), "limit": .int(41)],
            path: "/v1/users/user-1/visibleApps",
            wrongPath: "/v1/users/user-2/visibleApps",
            requiredQuery: ["limit": "41"],
            defaultLimit: "25",
            responseBody: appsResponse
        )
    ]
}

private func pathOnlyPaginationCases() -> [PathOnlyPaginationFixture] {
    let explicitFixtures = pathOnlyPaginationFixtures()
    let defaultFixtures = explicitFixtures.map { fixture in
        var arguments = fixture.arguments
        arguments.removeValue(forKey: "limit")
        return PathOnlyPaginationFixture(
            worker: fixture.worker,
            toolName: fixture.toolName,
            controlName: "default limit",
            arguments: arguments,
            path: fixture.path,
            wrongPath: fixture.wrongPath,
            requiredQuery: ["limit": fixture.defaultLimit],
            defaultLimit: fixture.defaultLimit,
            responseBody: fixture.responseBody
        )
    }
    return explicitFixtures + defaultFixtures
}

private func invokePathOnlyPaginationFixture(
    _ fixture: PathOnlyPaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let parameters = CallTool.Parameters(name: fixture.toolName, arguments: arguments)

    switch fixture.worker {
    case .accessibility:
        return try await AccessibilityWorker(httpClient: client).handleTool(parameters)
    case .analytics:
        return try await AnalyticsWorker(httpClient: client).handleTool(parameters)
    case .betaGroups:
        return try await BetaGroupsWorker(httpClient: client).handleTool(parameters)
    case .betaTesters:
        return try await BetaTestersWorker(httpClient: client).handleTool(parameters)
    case .buildBetaDetails:
        return try await BuildBetaDetailsWorker(httpClient: client).handleTool(parameters)
    case .preReleaseVersions:
        return try await PreReleaseVersionsWorker(httpClient: client).handleTool(parameters)
    case .pricing:
        return try await PricingWorker(httpClient: client).handleTool(parameters)
    case .sandbox:
        return try await SandboxTestersWorker(httpClient: client).handleTool(parameters)
    case .users:
        return try await UsersWorker(httpClient: client).handleTool(parameters)
    }
}

private func pathOnlyPaginationURL(
    path: String,
    query: [String: String],
    host: String = "api.example.test",
    scheme: String = "https",
    port: Int? = nil,
    user: String? = nil,
    password: String? = nil,
    fragment: String? = nil
) -> String {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.user = user
    components.password = password
    components.path = path
    components.fragment = fragment
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct path-only pagination URL")
    }
    return url.absoluteString
}

private func pathOnlyPaginationURL(
    _ url: String,
    appendingDuplicate name: String,
    value: String
) -> String {
    guard var components = URLComponents(string: url) else {
        preconditionFailure("Unable to parse path-only pagination URL")
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    guard let duplicateURL = components.url else {
        preconditionFailure("Unable to construct duplicate path-only pagination URL")
    }
    return duplicateURL.absoluteString
}

private func pathOnlyPaginationQuery(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
