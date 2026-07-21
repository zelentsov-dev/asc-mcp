import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Optional Input Contract Tests")
struct XcodeCloudOptionalInputContractTests {
    @Test("build-run builds encode all Apple filters and paging total")
    func buildRunBuildsEncodeFiltersAndTotal() async throws {
        let expectedQuery = [
            "limit": "2",
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
            "include": "betaGroups",
            "limit[betaGroups]": "2",
            "sort": "-uploadedDate,version"
        ]
        let transport = XcodeCloudOptionalInputTransport(
            body: xcodeCloudOptionalCollectionBody(
                path: "/v1/ciBuildRuns/run-1/builds",
                query: expectedQuery,
                total: 7
            )
        )
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "limit": .int(2),
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
                "include": .string("betaGroups"),
                "beta_groups_limit": .int(2),
                "sort": .array([.string("-uploadedDate"), .string("version")])
            ]
        ))

        #expect(result.isError == nil)
        let query = await transport.lastQueryItems()
        #expect(query == expectedQuery)
        guard case .object(let root)? = result.structuredContent else {
            Issue.record("Expected structured result")
            return
        }
        #expect(root["count"] == .int(0))
        #expect(root["total"] == .int(7))
    }

    @Test("invalid build filters fail before transport")
    func invalidBuildFiltersFailBeforeTransport() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: "{}")
        let worker = try await makeWorker(transport: transport)

        let invalidEnum = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "processing_state": .string("DONE")
            ]
        ))
        let emptyArray = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "version": .array([])
            ]
        ))
        let mixedArray = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "build_ids": .array([.string("build-1"), .int(2)])
            ]
        ))

        #expect(invalidEnum.isError == true)
        #expect(emptyArray.isError == true)
        #expect(mixedArray.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("boolean list filters reject duplicate values before transport")
    func duplicateBooleanFiltersFailBeforeTransport() async throws {
        for field in ["expired", "uses_non_exempt_encryption"] {
            let transport = XcodeCloudOptionalInputTransport(body: "{}")
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_build_run_builds_list",
                arguments: [
                    "build_run_id": .string("run-1"),
                    field: .array([.bool(true), .bool(true)])
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("product build runs accept scalar-or-array build filters")
    func productBuildRunsAcceptBuildFilters() async throws {
        let expectedQuery = [
            "limit": "25",
            "filter[builds]": "build-1,build-2",
            "sort": "-number,number"
        ]
        let transport = XcodeCloudOptionalInputTransport(
            body: xcodeCloudOptionalCollectionBody(
                path: "/v1/ciProducts/product-1/buildRuns",
                query: expectedQuery
            )
        )
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_build_runs_list",
            arguments: [
                "product_id": .string("product-1"),
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "sort": .array([.string("-number"), .string("number")])
            ]
        ))

        #expect(result.isError == nil)
        #expect(await transport.lastPath() == "/v1/ciProducts/product-1/buildRuns")
        let query = await transport.lastQueryItems()
        #expect(query == expectedQuery)
    }

    @Test("pagination preserves product build filters")
    func paginationPreservesProductBuildFilters() async throws {
        let scopeQuery = [
            "limit": "25",
            "filter[builds]": "build-1,build-2"
        ]
        let transport = XcodeCloudOptionalInputTransport(
            body: xcodeCloudOptionalContinuationBody(
                path: "/v1/ciProducts/product-1/buildRuns",
                scopeQuery: scopeQuery,
                currentCursor: "next",
                nextCursor: "after"
            )
        )
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_build_runs_list",
            arguments: [
                "product_id": .string("product-1"),
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "next_url": .string(xcodeCloudOptionalURL(
                    path: "/v1/ciProducts/product-1/buildRuns",
                    query: scopeQuery.merging(["cursor": "next"]) { _, new in new }
                ))
            ]
        ))
        let requestedQuery = scopeQuery.merging(["cursor": "next"]) { _, new in new }

        #expect(result.isError == nil)
        #expect(await transport.requestCount() == 1)
        #expect(await transport.lastPath() == "/v1/ciProducts/product-1/buildRuns")
        #expect(await transport.lastQueryItems() == requestedQuery)
    }

    @Test("pagination preserves build filters and sort")
    func paginationPreservesBuildFiltersAndSort() async throws {
        let scopeQuery = [
            "limit": "25",
            "filter[processingState]": "VALID",
            "sort": "-uploadedDate"
        ]
        let transport = XcodeCloudOptionalInputTransport(
            body: xcodeCloudOptionalContinuationBody(
                path: "/v1/ciBuildRuns/run-1/builds",
                scopeQuery: scopeQuery,
                currentCursor: "next",
                nextCursor: "after"
            )
        )
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "processing_state": .string("VALID"),
                "sort": .string("-uploadedDate"),
                "next_url": .string(xcodeCloudOptionalURL(
                    path: "/v1/ciBuildRuns/run-1/builds",
                    query: scopeQuery.merging(["cursor": "next"]) { _, new in new }
                ))
            ]
        ))
        let requestedQuery = scopeQuery.merging(["cursor": "next"]) { _, new in new }

        #expect(result.isError == nil)
        #expect(await transport.requestCount() == 1)
        #expect(await transport.lastPath() == "/v1/ciBuildRuns/run-1/builds")
        #expect(await transport.lastQueryItems() == requestedQuery)
    }

    @Test("product app repository and sort inputs accept scalar or array forms")
    func scalarOrArrayInputsReachAppleExactly() async throws {
        let cases: [(
            toolName: String,
            arguments: [String: Value],
            path: String,
            query: [String: String]
        )] = [
            (
                "xcode_cloud_products_list",
                ["product_type": .string("APP"), "app_id": .string("app-1")],
                "/v1/ciProducts",
                ["limit": "25", "filter[productType]": "APP", "filter[app]": "app-1"]
            ),
            (
                "xcode_cloud_products_list",
                [
                    "product_type": .array([.string("APP"), .string("FRAMEWORK")]),
                    "app_id": .array([.string("app-1"), .string("app-2")])
                ],
                "/v1/ciProducts",
                [
                    "limit": "25",
                    "filter[productType]": "APP,FRAMEWORK",
                    "filter[app]": "app-1,app-2"
                ]
            ),
            (
                "xcode_cloud_product_build_runs_list",
                [
                    "product_id": .string("product-1"),
                    "build_id": .string("build-1"),
                    "sort": .string("-number")
                ],
                "/v1/ciProducts/product-1/buildRuns",
                ["limit": "25", "filter[builds]": "build-1", "sort": "-number"]
            ),
            (
                "xcode_cloud_workflow_build_runs_list",
                [
                    "workflow_id": .string("workflow-1"),
                    "build_id": .array([.string("build-1"), .string("build-2")]),
                    "sort": .array([.string("number"), .string("-number")])
                ],
                "/v1/ciWorkflows/workflow-1/buildRuns",
                ["limit": "25", "filter[builds]": "build-1,build-2", "sort": "number,-number"]
            ),
            (
                "xcode_cloud_scm_repositories_list",
                ["repository_id": .string("repo-1")],
                "/v1/scmRepositories",
                ["limit": "25", "filter[id]": "repo-1"]
            ),
            (
                "xcode_cloud_scm_provider_repositories_list",
                [
                    "provider_id": .string("provider-1"),
                    "repository_id": .array([.string("repo-1"), .string("repo-2")])
                ],
                "/v1/scmProviders/provider-1/repositories",
                ["limit": "25", "filter[id]": "repo-1,repo-2"]
            )
        ]

        for testCase in cases {
            let transport = XcodeCloudOptionalInputTransport(
                body: xcodeCloudOptionalCollectionBody(path: testCase.path, query: testCase.query)
            )
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: testCase.toolName,
                arguments: testCase.arguments
            ))

            #expect(result.isError == nil, "Expected scalar-or-array input for \(testCase.toolName)")
            #expect(await transport.lastPath() == testCase.path)
            #expect(await transport.lastQueryItems() == testCase.query)
        }
    }

    @Test("single-resource relationship limits reach Apple exactly")
    func singleResourceRelationshipLimitsReachAppleExactly() async throws {
        let cases: [(
            toolName: String,
            arguments: [String: Value],
            path: String,
            query: [String: String],
            type: String,
            id: String
        )] = [
            (
                "xcode_cloud_products_get",
                [
                    "product_id": .string("product-1"),
                    "include": .string("primaryRepositories"),
                    "primary_repositories_limit": .int(2)
                ],
                "/v1/ciProducts/product-1",
                ["include": "primaryRepositories", "limit[primaryRepositories]": "2"],
                "ciProducts",
                "product-1"
            ),
            (
                "xcode_cloud_build_runs_get",
                [
                    "build_run_id": .string("run-1"),
                    "include": .string("builds"),
                    "builds_limit": .int(3)
                ],
                "/v1/ciBuildRuns/run-1",
                ["include": "builds", "limit[builds]": "3"],
                "ciBuildRuns",
                "run-1"
            ),
            (
                "xcode_cloud_xcode_versions_get",
                [
                    "xcode_version_id": .string("xcode-1"),
                    "include": .string("macOsVersions"),
                    "macos_versions_limit": .int(4)
                ],
                "/v1/ciXcodeVersions/xcode-1",
                ["include": "macOsVersions", "limit[macOsVersions]": "4"],
                "ciXcodeVersions",
                "xcode-1"
            ),
            (
                "xcode_cloud_macos_versions_get",
                [
                    "macos_version_id": .string("macos-1"),
                    "include": .string("xcodeVersions"),
                    "xcode_versions_limit": .int(5)
                ],
                "/v1/ciMacOsVersions/macos-1",
                ["include": "xcodeVersions", "limit[xcodeVersions]": "5"],
                "ciMacOsVersions",
                "macos-1"
            )
        ]

        for testCase in cases {
            let transport = XcodeCloudOptionalInputTransport(body: xcodeCloudOptionalSingleBody(
                path: testCase.path,
                query: testCase.query,
                type: testCase.type,
                id: testCase.id
            ))
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: testCase.toolName,
                arguments: testCase.arguments
            ))

            #expect(result.isError == nil, "Expected nested limit forwarding for \(testCase.toolName)")
            #expect(await transport.lastPath() == testCase.path)
            #expect(await transport.lastQueryItems() == testCase.query)
        }
    }

    @Test("public Apple list inputs expose scalar-or-array schemas")
    func scalarOrArraySchemasRemainPublic() async throws {
        let tools = await XcodeCloudWorker(httpClient: try await TestFactory.makeHTTPClient()).getTools()
        let expectedFields: [(toolName: String, field: String)] = [
            ("xcode_cloud_products_list", "product_type"),
            ("xcode_cloud_products_list", "app_id"),
            ("xcode_cloud_product_build_runs_list", "build_id"),
            ("xcode_cloud_product_build_runs_list", "sort"),
            ("xcode_cloud_workflow_build_runs_list", "build_id"),
            ("xcode_cloud_workflow_build_runs_list", "sort"),
            ("xcode_cloud_scm_provider_repositories_list", "repository_id"),
            ("xcode_cloud_scm_repositories_list", "repository_id")
        ]

        for expected in expectedFields {
            let tool = try #require(tools.first { $0.name == expected.toolName })
            guard case .object(let schema) = tool.inputSchema,
                  case .object(let properties)? = schema["properties"],
                  case .object(let fieldSchema)? = properties[expected.field],
                  case .array(let alternatives)? = fieldSchema["oneOf"] else {
                Issue.record("Expected scalar-or-array schema for \(expected.toolName).\(expected.field)")
                continue
            }
            #expect(alternatives.count == 2)
        }
    }

    @Test("invalid limits includes unknown keys and canonical IDs fail before transport")
    func invalidPublicInputsFailBeforeTransport() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: "{}")
        let worker = try await makeWorker(transport: transport)
        let invalidCalls: [(toolName: String, arguments: [String: Value])] = [
            ("xcode_cloud_products_list", ["limit": .int(0)]),
            ("xcode_cloud_products_list", ["limit": .int(201)]),
            ("xcode_cloud_products_list", ["limit": .string("25")]),
            ("xcode_cloud_products_list", ["include": .string("workflows")]),
            ("xcode_cloud_products_list", ["include": .array([])]),
            ("xcode_cloud_products_list", ["unknown": .bool(true)]),
            ("xcode_cloud_products_get", ["product_id": .string("product/1")]),
            ("xcode_cloud_products_list", ["app_id": .string("app%2F1")]),
            ("xcode_cloud_scm_repositories_list", ["repository_id": .string("..")]),
            (
                "xcode_cloud_product_build_runs_list",
                ["product_id": .string("product-1"), "sort": .string("createdDate")]
            )
        ]

        for invalidCall in invalidCalls {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: invalidCall.toolName,
                arguments: invalidCall.arguments
            ))
            #expect(result.isError == true, "Expected preflight rejection for \(invalidCall.toolName)")
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("requested nested limits bind core relationship linkage and metadata")
    func requestedNestedLimitsBindCoreResponses() async throws {
        let productsQuery = [
            "limit": "25",
            "include": "primaryRepositories",
            "limit[primaryRepositories]": "1"
        ]
        let buildRunQuery = [
            "include": "builds",
            "limit[builds]": "2"
        ]
        let cases: [(String, [String: Value], String)] = [
            (
                "xcode_cloud_products_list",
                [
                    "include": .string("primaryRepositories"),
                    "primary_repositories_limit": .int(1)
                ],
                """
                {
                  "data": [{
                    "type": "ciProducts",
                    "id": "product-1",
                    "relationships": {
                      "primaryRepositories": {
                        "data": [
                          { "type": "scmRepositories", "id": "repo-1" },
                          { "type": "scmRepositories", "id": "repo-2" }
                        ]
                      }
                    }
                  }],
                  "links": { "self": "\(xcodeCloudOptionalURL(path: "/v1/ciProducts", query: productsQuery))" },
                  "meta": { "paging": { "total": 1, "limit": 25 } }
                }
                """
            ),
            (
                "xcode_cloud_build_runs_get",
                [
                    "build_run_id": .string("run-1"),
                    "include": .string("builds"),
                    "builds_limit": .int(2)
                ],
                """
                {
                  "data": {
                    "type": "ciBuildRuns",
                    "id": "run-1",
                    "relationships": {
                      "builds": {
                        "data": [{ "type": "builds", "id": "build-1" }],
                        "meta": { "paging": { "total": 1, "limit": 3 } }
                      }
                    }
                  },
                  "links": { "self": "\(xcodeCloudOptionalURL(path: "/v1/ciBuildRuns/run-1", query: buildRunQuery))" }
                }
                """
            )
        ]

        for (toolName, arguments, body) in cases {
            let transport = XcodeCloudOptionalInputTransport(body: body)
            let worker = try await makeWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: toolName,
                arguments: arguments
            ))

            #expect(result.isError == true, "Expected nested-limit contract rejection for \(toolName)")
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("manifest binds public filters and classifies unsafe expansions")
    func manifestBindsAndClassifiesOptionalInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let builds = try #require(manifest.mapping(for: "xcode_cloud_build_run_builds_list"))
        let publicAppleNames = Set(builds.fields.compactMap { field in
            field.sourceKind == .parameter && field.location == "query" ? field.appleName : nil
        })
        #expect(publicAppleNames.isSuperset(of: Set([
            "filter[version]", "filter[expired]", "filter[processingState]",
            "filter[betaAppReviewSubmission.betaReviewState]", "filter[usesNonExemptEncryption]",
            "filter[preReleaseVersion.version]", "filter[preReleaseVersion.platform]",
            "filter[buildAudienceType]", "filter[preReleaseVersion]", "filter[app]",
            "filter[betaGroups]", "filter[appStoreVersion]", "filter[id]",
            "exists[usesNonExemptEncryption]", "sort", "include",
            "limit[individualTesters]", "limit[betaGroups]", "limit[betaBuildLocalizations]",
            "limit[icons]", "limit[buildBundles]"
        ])))
        #expect(builds.response.fields.contains { $0.outputField == "total" && $0.jsonPointer == "/meta/paging/total" })

        let buildClassifications = builds.operations.first?.optionalParameterClassifications
        #expect(buildClassifications?.isEmpty != false)

        let expectedRelatedLimits: [String: String] = [
            "xcode_cloud_build_runs_get": "limit[builds]",
            "xcode_cloud_product_build_runs_list": "limit[builds]",
            "xcode_cloud_workflow_build_runs_list": "limit[builds]",
            "xcode_cloud_products_get": "limit[primaryRepositories]",
            "xcode_cloud_products_list": "limit[primaryRepositories]",
            "xcode_cloud_macos_versions_get": "limit[xcodeVersions]",
            "xcode_cloud_macos_versions_list": "limit[xcodeVersions]",
            "xcode_cloud_xcode_versions_get": "limit[macOsVersions]",
            "xcode_cloud_xcode_versions_list": "limit[macOsVersions]"
        ]
        for (tool, appleName) in expectedRelatedLimits {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.fields.contains { $0.appleName == appleName })
            #expect(mapping.operations.first?.optionalParameterClassifications?.contains {
                $0.appleName == appleName
            } != true)
        }

        let productRuns = try #require(manifest.mapping(for: "xcode_cloud_product_build_runs_list"))
        #expect(productRuns.fields.contains {
            $0.toolField == "build_id" && $0.appleName == "filter[builds]"
        })
    }

    private func makeWorker(transport: XcodeCloudOptionalInputTransport) async throws -> XcodeCloudWorker {
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        return XcodeCloudWorker(httpClient: client)
    }
}

private func xcodeCloudOptionalCollectionBody(
    path: String,
    query: [String: String],
    total: Int = 0
) -> String {
    let selfURL = xcodeCloudOptionalURL(path: path, query: query)
    let limit = Int(query["limit"] ?? "") ?? 25
    return """
    {
      "data": [],
      "links": { "self": "\(selfURL)" },
      "meta": { "paging": { "total": \(total), "limit": \(limit) } }
    }
    """
}

private func xcodeCloudOptionalContinuationBody(
    path: String,
    scopeQuery: [String: String],
    currentCursor: String,
    nextCursor: String
) -> String {
    let selfURL = xcodeCloudOptionalURL(
        path: path,
        query: scopeQuery.merging(["cursor": currentCursor]) { _, new in new }
    )
    let nextURL = xcodeCloudOptionalURL(
        path: path,
        query: scopeQuery.merging(["cursor": nextCursor]) { _, new in new }
    )
    let limit = Int(scopeQuery["limit"] ?? "") ?? 25
    return """
    {
      "data": [],
      "links": { "self": "\(selfURL)", "next": "\(nextURL)" },
      "meta": { "paging": { "limit": \(limit), "nextCursor": "\(nextCursor)" } }
    }
    """
}

private func xcodeCloudOptionalSingleBody(
    path: String,
    query: [String: String],
    type: String,
    id: String
) -> String {
    let selfURL = xcodeCloudOptionalURL(path: path, query: query)
    let resourceURL = xcodeCloudOptionalURL(path: path, query: [:])
    return """
    {
      "data": {
        "type": "\(type)",
        "id": "\(id)",
        "links": { "self": "\(resourceURL)" }
      },
      "links": { "self": "\(selfURL)" }
    }
    """
}

private func xcodeCloudOptionalURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    if !query.isEmpty {
        components.queryItems = query.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct Xcode Cloud optional-input URL")
    }
    return url.absoluteString
}

private actor XcodeCloudOptionalInputTransport: HTTPTransport {
    private let body: String
    private var request: URLRequest?

    init(body: String) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }

    func lastPath() -> String? {
        request?.url?.path
    }

    func lastQueryItems() -> [String: String] {
        guard let url = request?.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    func requestCount() -> Int {
        request == nil ? 0 : 1
    }
}
