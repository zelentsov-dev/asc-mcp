import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Pagination Scope Tests")
struct XcodeCloudPaginationScopeTests {
    @Test("all Xcode Cloud list continuations preserve their complete originating scope")
    func validContinuationsPreserveCompleteScope() async throws {
        for fixture in xcodeCloudPaginationFixtures() {
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            arguments["next_url"] = .string(xcodeCloudPaginationURL(path: fixture.path, query: query))
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: xcodeCloudPaginationResponseBody(
                        fixture: fixture,
                        currentCursor: "next",
                        nextCursor: "after"
                    )
                )
            ])

            let result = try await invokeXcodeCloudPaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError != true, "Expected valid continuation for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.url?.path == fixture.path)
            #expect(xcodeCloudPaginationQuery(request) == query)
            guard case .object(let root)? = result.structuredContent else {
                Issue.record("Expected structured pagination result for \(fixture.toolName)")
                continue
            }
            #expect(root["self_url"] == .string(xcodeCloudPaginationURL(path: fixture.path, query: query)))
            let responseNextQuery = fixture.requiredQuery.merging(["cursor": "after"]) { _, new in new }
            #expect(root["next_url"] == .string(
                xcodeCloudPaginationURL(path: fixture.path, query: responseNextQuery)
            ))
        }
    }

    @Test("all Xcode Cloud list responses reject self and next links outside the requested scope")
    func responseLinksPreserveRequestedScope() async throws {
        for fixture in xcodeCloudPaginationFixtures() {
            let validSelf = xcodeCloudPaginationURL(
                path: fixture.path,
                query: fixture.requiredQuery.merging(["cursor": "next"]) { _, new in new }
            )
            let validNext = xcodeCloudPaginationURL(
                path: fixture.path,
                query: fixture.requiredQuery.merging(["cursor": "after"]) { _, new in new }
            )
            let invalidLinks = [
                (
                    selfURL: xcodeCloudPaginationURL(
                        path: fixture.wrongParentPath,
                        query: fixture.requiredQuery.merging(["cursor": "next"]) { _, new in new }
                    ),
                    nextURL: validNext
                ),
                (
                    selfURL: validSelf,
                    nextURL: xcodeCloudPaginationURL(
                        path: fixture.wrongParentPath,
                        query: fixture.requiredQuery.merging(["cursor": "after"]) { _, new in new }
                    )
                )
            ]

            for invalidLink in invalidLinks {
                let limit = Int(fixture.requiredQuery["limit"] ?? "") ?? 25
                let response = """
                {
                  "data": [],
                  "links": { "self": "\(invalidLink.selfURL)", "next": "\(invalidLink.nextURL)" },
                  "meta": { "paging": { "limit": \(limit), "nextCursor": "after" } }
                }
                """
                let transport = TestHTTPTransport(responses: [
                    .init(statusCode: 200, body: response)
                ])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(validSelf)

                let result = try await invokeXcodeCloudPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected response-link rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 1)
            }
        }
    }

    @Test("all Xcode Cloud list continuations reject missing or changed originating controls")
    func rejectsMissingOrChangedOriginatingControls() async throws {
        for fixture in xcodeCloudPaginationFixtures() {
            for name in fixture.requiredQuery.keys {
                for mutation in XcodeCloudQueryMutation.allCases {
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
                    arguments["next_url"] = .string(xcodeCloudPaginationURL(path: fixture.path, query: query))

                    let result = try await invokeXcodeCloudPaginationFixture(
                        fixture,
                        arguments: arguments,
                        transport: transport
                    )

                    #expect(result.isError == true, "Expected \(mutation) \(name) rejection for \(fixture.toolName)")
                    #expect(await transport.requestCount() == 0)
                }
            }
        }
    }

    @Test("all Xcode Cloud list continuations require a non-empty cursor")
    func rejectsMissingAndEmptyCursors() async throws {
        for fixture in xcodeCloudPaginationFixtures() {
            for cursor in [nil, "", " "] as [String?] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(xcodeCloudPaginationURL(path: fixture.path, query: query))

                let result = try await invokeXcodeCloudPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("all Xcode Cloud list continuations reject path changes and query injection")
    func rejectsPathChangesAndQueryInjection() async throws {
        for fixture in xcodeCloudPaginationFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"

            let invalidURLs = [
                xcodeCloudPaginationURL(path: fixture.wrongParentPath, query: validQuery),
                xcodeCloudPaginationURL(
                    path: fixture.path,
                    query: validQuery.merging(["filter[unexpected]": "drift"]) { _, new in new }
                ),
                xcodeCloudPaginationURL(path: fixture.path, query: validQuery) + "&limit=1"
            ]

            for nextURL in invalidURLs {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(nextURL)

                let result = try await invokeXcodeCloudPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected scoped continuation rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }
}

private enum XcodeCloudQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct XcodeCloudPaginationFixture {
    let toolName: String
    let arguments: [String: Value]
    let path: String
    let wrongParentPath: String
    let requiredQuery: [String: String]
}

private func xcodeCloudPaginationFixtures() -> [XcodeCloudPaginationFixture] {
    [
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_products_list",
            arguments: [
                "product_type": .array([.string("APP"), .string("FRAMEWORK")]),
                "app_id": .array([.string("app-1"), .string("app-2")]),
                "include": .array([.string("app"), .string("primaryRepositories")]),
                "primary_repositories_limit": .int(2)
            ],
            path: "/v1/ciProducts",
            wrongParentPath: "/v1/ciProducts/other",
            requiredQuery: [
                "limit": "25",
                "filter[productType]": "APP,FRAMEWORK",
                "filter[app]": "app-1,app-2",
                "include": "app,primaryRepositories",
                "limit[primaryRepositories]": "2"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_product_workflows_list",
            arguments: [
                "product_id": .string("product-1"),
                "include": .string("product"),
                "limit": .int(26)
            ],
            path: "/v1/ciProducts/product-1/workflows",
            wrongParentPath: "/v1/ciProducts/product-2/workflows",
            requiredQuery: ["limit": "26", "include": "product"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_product_build_runs_list",
            arguments: [
                "product_id": .string("product-1"),
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "sort": .array([.string("-number"), .string("number")]),
                "include": .array([.string("builds"), .string("workflow")]),
                "builds_limit": .int(3),
                "limit": .int(27)
            ],
            path: "/v1/ciProducts/product-1/buildRuns",
            wrongParentPath: "/v1/ciProducts/product-2/buildRuns",
            requiredQuery: [
                "limit": "27",
                "filter[builds]": "build-1,build-2",
                "sort": "-number,number",
                "include": "builds,workflow",
                "limit[builds]": "3"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_workflow_build_runs_list",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "build_id": .string("build-3"),
                "sort": .string("number"),
                "include": .array([.string("builds"), .string("product")]),
                "builds_limit": .int(4),
                "limit": .int(28)
            ],
            path: "/v1/ciWorkflows/workflow-1/buildRuns",
            wrongParentPath: "/v1/ciWorkflows/workflow-2/buildRuns",
            requiredQuery: [
                "limit": "28",
                "filter[builds]": "build-3",
                "sort": "number",
                "include": "builds,product",
                "limit[builds]": "4"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_build_run_actions_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "include": .string("buildRun"),
                "limit": .int(29)
            ],
            path: "/v1/ciBuildRuns/run-1/actions",
            wrongParentPath: "/v1/ciBuildRuns/run-2/actions",
            requiredQuery: ["limit": "29", "include": "buildRun"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "limit": .int(30),
                "version": .array([.string("42"), .string("43")]),
                "expired": .array([.bool(false), .bool(true)]),
                "processing_state": .array([.string("PROCESSING"), .string("VALID")]),
                "beta_review_states": .array([.string("IN_REVIEW"), .string("APPROVED")]),
                "uses_non_exempt_encryption": .bool(true),
                "pre_release_versions": .array([.string("1.2"), .string("1.3")]),
                "pre_release_platforms": .array([.string("IOS"), .string("VISION_OS")]),
                "build_audience_types": .array([.string("INTERNAL_ONLY"), .string("APP_STORE_ELIGIBLE")]),
                "pre_release_version_ids": .array([.string("pre-1"), .string("pre-2")]),
                "app_ids": .array([.string("app-1"), .string("app-2")]),
                "beta_group_ids": .array([.string("group-1"), .string("group-2")]),
                "app_store_version_ids": .array([.string("version-1"), .string("version-2")]),
                "build_ids": .array([.string("build-1"), .string("build-2")]),
                "uses_non_exempt_encryption_set": .bool(false),
                "sort": .array([.string("-uploadedDate"), .string("version")])
            ],
            path: "/v1/ciBuildRuns/run-1/builds",
            wrongParentPath: "/v1/ciBuildRuns/run-2/builds",
            requiredQuery: [
                "limit": "30",
                "filter[version]": "42,43",
                "filter[expired]": "false,true",
                "filter[processingState]": "PROCESSING,VALID",
                "filter[betaAppReviewSubmission.betaReviewState]": "IN_REVIEW,APPROVED",
                "filter[usesNonExemptEncryption]": "true",
                "filter[preReleaseVersion.version]": "1.2,1.3",
                "filter[preReleaseVersion.platform]": "IOS,VISION_OS",
                "filter[buildAudienceType]": "INTERNAL_ONLY,APP_STORE_ELIGIBLE",
                "filter[preReleaseVersion]": "pre-1,pre-2",
                "filter[app]": "app-1,app-2",
                "filter[betaGroups]": "group-1,group-2",
                "filter[appStoreVersion]": "version-1,version-2",
                "filter[id]": "build-1,build-2",
                "exists[usesNonExemptEncryption]": "false",
                "sort": "-uploadedDate,version"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_action_artifacts_list",
            arguments: ["action_id": .string("action-1"), "limit": .int(31)],
            path: "/v1/ciBuildActions/action-1/artifacts",
            wrongParentPath: "/v1/ciBuildActions/action-2/artifacts",
            requiredQuery: ["limit": "31"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_action_issues_list",
            arguments: ["action_id": .string("action-1"), "limit": .int(32)],
            path: "/v1/ciBuildActions/action-1/issues",
            wrongParentPath: "/v1/ciBuildActions/action-2/issues",
            requiredQuery: ["limit": "32"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_action_test_results_list",
            arguments: ["action_id": .string("action-1"), "limit": .int(33)],
            path: "/v1/ciBuildActions/action-1/testResults",
            wrongParentPath: "/v1/ciBuildActions/action-2/testResults",
            requiredQuery: ["limit": "33"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_xcode_versions_list",
            arguments: [
                "include": .string("macOsVersions"),
                "macos_versions_limit": .int(5),
                "limit": .int(34)
            ],
            path: "/v1/ciXcodeVersions",
            wrongParentPath: "/v1/ciXcodeVersions/other",
            requiredQuery: [
                "limit": "34",
                "include": "macOsVersions",
                "limit[macOsVersions]": "5"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_macos_versions_list",
            arguments: [
                "include": .string("xcodeVersions"),
                "xcode_versions_limit": .int(6),
                "limit": .int(35)
            ],
            path: "/v1/ciMacOsVersions",
            wrongParentPath: "/v1/ciMacOsVersions/other",
            requiredQuery: [
                "limit": "35",
                "include": "xcodeVersions",
                "limit[xcodeVersions]": "6"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_scm_providers_list",
            arguments: ["limit": .int(36)],
            path: "/v1/scmProviders",
            wrongParentPath: "/v1/scmProviders/other",
            requiredQuery: ["limit": "36"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_scm_provider_repositories_list",
            arguments: [
                "provider_id": .string("provider-1"),
                "repository_id": .array([.string("repo-1"), .string("repo-2")]),
                "include": .array([.string("scmProvider"), .string("defaultBranch")]),
                "limit": .int(37)
            ],
            path: "/v1/scmProviders/provider-1/repositories",
            wrongParentPath: "/v1/scmProviders/provider-2/repositories",
            requiredQuery: [
                "limit": "37",
                "filter[id]": "repo-1,repo-2",
                "include": "scmProvider,defaultBranch"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_scm_repositories_list",
            arguments: [
                "repository_id": .string("repo-1"),
                "include": .string("defaultBranch"),
                "limit": .int(38)
            ],
            path: "/v1/scmRepositories",
            wrongParentPath: "/v1/scmRepositories/other",
            requiredQuery: [
                "limit": "38",
                "filter[id]": "repo-1",
                "include": "defaultBranch"
            ]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_scm_repository_git_references_list",
            arguments: [
                "repository_id": .string("repo-1"),
                "include": .string("repository"),
                "limit": .int(39)
            ],
            path: "/v1/scmRepositories/repo-1/gitReferences",
            wrongParentPath: "/v1/scmRepositories/repo-2/gitReferences",
            requiredQuery: ["limit": "39", "include": "repository"]
        ),
        XcodeCloudPaginationFixture(
            toolName: "xcode_cloud_scm_repository_pull_requests_list",
            arguments: [
                "repository_id": .string("repo-1"),
                "include": .string("repository"),
                "limit": .int(40)
            ],
            path: "/v1/scmRepositories/repo-1/pullRequests",
            wrongParentPath: "/v1/scmRepositories/repo-2/pullRequests",
            requiredQuery: ["limit": "40", "include": "repository"]
        )
    ]
}

private func invokeXcodeCloudPaginationFixture(
    _ fixture: XcodeCloudPaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return try await XcodeCloudWorker(httpClient: client).handleTool(.init(
        name: fixture.toolName,
        arguments: arguments
    ))
}

private func xcodeCloudPaginationURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct pagination URL")
    }
    return url.absoluteString
}

private func xcodeCloudPaginationResponseBody(
    fixture: XcodeCloudPaginationFixture,
    currentCursor: String,
    nextCursor: String
) -> String {
    let selfURL = xcodeCloudPaginationURL(
        path: fixture.path,
        query: fixture.requiredQuery.merging(["cursor": currentCursor]) { _, new in new }
    )
    let nextURL = xcodeCloudPaginationURL(
        path: fixture.path,
        query: fixture.requiredQuery.merging(["cursor": nextCursor]) { _, new in new }
    )
    let limit = Int(fixture.requiredQuery["limit"] ?? "") ?? 25
    return """
    {
      "data": [],
      "links": { "self": "\(selfURL)", "next": "\(nextURL)" },
      "meta": { "paging": { "limit": \(limit), "nextCursor": "\(nextCursor)" } }
    }
    """
}

private func xcodeCloudPaginationQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
