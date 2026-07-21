import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Related Resource Contract Tests")
struct XcodeCloudRelatedResourceContractTests {
    @Test("all related-resource handlers use exact Apple routes and queries")
    func handlersUseExactRoutesAndQueries() async throws {
        for fixture in relatedResourceRouteFixtures() {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: relatedResourceResponseBody(fixture))
            ])
            let worker = try await relatedResourceWorker(transport: transport)

            let result = try await invokeRelatedResourceTool(
                fixture.toolName,
                arguments: fixture.arguments,
                worker: worker
            )

            #expect(result.isError != true, "Expected success for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == fixture.path)
            #expect(relatedResourceQuery(request) == fixture.query)
            guard case .object(let root)? = result.structuredContent else {
                Issue.record("Expected structured result for \(fixture.toolName)")
                continue
            }
            #expect(root["self_url"] == .string(relatedResourceURL(path: fixture.path, query: fixture.query)))
        }
    }

    @Test("related-resource collection pagination remains bound to the original query")
    func paginationPreservesScope() async throws {
        let path = "/v1/ciProducts/product-1/primaryRepositories"
        let query = [
            "limit": "40",
            "filter[id]": "repo-1,repo-2",
            "include": "scmProvider",
            "cursor": "next-page"
        ]
        let nextURL = relatedResourceURL(path: path, query: query)
        var firstQuery = query
        firstQuery.removeValue(forKey: "cursor")
        let firstURL = relatedResourceURL(path: path, query: firstQuery)
        let response = """
        {
          "data": [{
            "type": "scmRepositories",
            "id": "repo-1",
            "attributes": { "ownerName": "Example", "repositoryName": "App" },
            "relationships": {
              "scmProvider": {
                "data": { "type": "scmProviders", "id": "provider-1" }
              }
            },
            "links": { "self": "https://api.example.test/v1/scmRepositories/repo-1" }
          }],
          "links": { "self": "\(nextURL)", "first": "\(firstURL)" },
          "meta": { "paging": { "total": 2, "limit": 40 } }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: response)])
        let worker = try await relatedResourceWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_primary_repositories_list",
            arguments: [
                "product_id": .string("product-1"),
                "repository_id": .array([.string("repo-1"), .string("repo-2")]),
                "include": .string("scmProvider"),
                "limit": .int(40),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == path)
        #expect(relatedResourceQuery(request) == query)
        guard case .object(let root)? = result.structuredContent else {
            Issue.record("Expected structured pagination result")
            return
        }
        #expect(root["self_url"] == .string(nextURL))
        #expect(root["first_url"] == .string(firstURL))
    }

    @Test("invalid related-resource inputs perform zero requests")
    func invalidInputsPerformZeroRequests() async throws {
        let cases: [(String, [String: Value])] = [
            ("xcode_cloud_app_product_get", [:]),
            ("xcode_cloud_app_product_get", ["app_id": .string(" app-1")]),
            ("xcode_cloud_action_build_run_get", ["action_id": .string("action/1")]),
            ("xcode_cloud_product_app_get", ["product_id": .string("product%2D1")]),
            ("xcode_cloud_workflow_repository_get", [
                "workflow_id": .string("workflow-1"),
                "include": .string("unknown")
            ]),
            ("xcode_cloud_macos_version_xcode_versions_list", [
                "macos_version_id": .string("macos-1"),
                "limit": .int(0)
            ]),
            ("xcode_cloud_xcode_version_macos_versions_list", [
                "xcode_version_id": .string("xcode-1"),
                "xcode_versions_limit": .int(51)
            ]),
            ("xcode_cloud_action_build_run_get", [
                "action_id": .string("action-1"),
                "builds_limit": .int(2)
            ]),
            ("xcode_cloud_app_product_get", [
                "app_id": .string("app-1"),
                "primary_repositories_limit": .int(2)
            ]),
            ("xcode_cloud_macos_version_xcode_versions_list", [
                "macos_version_id": .string("macos-1"),
                "macos_versions_limit": .int(2)
            ]),
            ("xcode_cloud_xcode_version_macos_versions_list", [
                "xcode_version_id": .string("xcode-1"),
                "xcode_versions_limit": .int(2)
            ]),
            ("xcode_cloud_product_primary_repositories_list", [
                "product_id": .string("product-1"),
                "repository_id": .array([.string("repo-1"), .string("repo-1")])
            ]),
            ("xcode_cloud_product_additional_repositories_list", [
                "product_id": .string("product-1"),
                "next_url": .string("https://evil.example/v1/ciProducts/product-1/additionalRepositories?limit=25&cursor=next")
            ]),
            ("xcode_cloud_product_app_get", [
                "product_id": .string("product-1"),
                "unexpected": .bool(true)
            ])
        ]

        for (toolName, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await relatedResourceWorker(transport: transport)
            let result = try await invokeRelatedResourceTool(toolName, arguments: arguments, worker: worker)

            #expect(result.isError == true, "Expected validation error for \(toolName)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("response type identity document links and exact GET status are enforced")
    func invalidResponsesAreRejected() async throws {
        let invalidResponses: [(Int, String)] = [
            (201, "{}"),
            (200, """
            {
              "data": { "type": "ciWorkflows", "id": "product-1" },
              "links": { "self": "https://api.example.test/v1/apps/app-1/ciProduct" }
            }
            """),
            (200, """
            {
              "data": { "type": "ciProducts", "id": "bad/id" },
              "links": { "self": "https://api.example.test/v1/apps/app-1/ciProduct" }
            }
            """),
            (200, """
            {
              "data": {
                "type": "ciProducts",
                "id": "product-1",
                "relationships": {
                  "app": { "data": { "type": "ciProducts", "id": "app-1" } }
                }
              },
              "links": { "self": "https://api.example.test/v1/apps/app-1/ciProduct" }
            }
            """),
            (200, """
            {
              "data": { "type": "ciProducts", "id": "product-1" },
              "links": { "self": "https://api.example.test/v1/apps/other/ciProduct" }
            }
            """)
        ]

        for (statusCode, body) in invalidResponses {
            let transport = TestHTTPTransport(responses: [.init(statusCode: statusCode, body: body)])
            let worker = try await relatedResourceWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_app_product_get",
                arguments: ["app_id": .string("app-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("compact product app rejects the included member even when it is empty")
    func compactProductAppRejectsIncludedMember() async throws {
        let body = """
        {
          "data": \(relatedAppJSON()),
          "included": [],
          "links": { "self": "https://api.example.test/v1/ciProducts/product-1/app" }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await relatedResourceWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_app_get",
            arguments: ["product_id": .string("product-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("requested nested limits bind related-resource linkage and metadata")
    func requestedNestedLimitsBindRelatedResponses() async throws {
        let productPath = "/v1/apps/app-1/ciProduct"
        let productQuery = [
            "include": "primaryRepositories",
            "limit[primaryRepositories]": "1"
        ]
        let versionsPath = "/v1/ciMacOsVersions/macos-1/xcodeVersions"
        let versionsQuery = [
            "limit": "25",
            "include": "macOsVersions",
            "limit[macOsVersions]": "2"
        ]
        let cases: [(String, [String: Value], String)] = [
            (
                "xcode_cloud_app_product_get",
                [
                    "app_id": .string("app-1"),
                    "include": .string("primaryRepositories"),
                    "primary_repositories_limit": .int(1)
                ],
                """
                {
                  "data": {
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
                  },
                  "links": { "self": "\(relatedResourceURL(path: productPath, query: productQuery))" }
                }
                """
            ),
            (
                "xcode_cloud_macos_version_xcode_versions_list",
                [
                    "macos_version_id": .string("macos-1"),
                    "include": .string("macOsVersions"),
                    "macos_versions_limit": .int(2)
                ],
                """
                {
                  "data": [{
                    "type": "ciXcodeVersions",
                    "id": "xcode-1",
                    "relationships": {
                      "macOsVersions": {
                        "data": [{ "type": "ciMacOsVersions", "id": "macos-1" }],
                        "meta": { "paging": { "total": 1, "limit": 3 } }
                      }
                    }
                  }],
                  "links": { "self": "\(relatedResourceURL(path: versionsPath, query: versionsQuery))" },
                  "meta": { "paging": { "total": 1, "limit": 25 } }
                }
                """
            )
        ]

        for (toolName, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await relatedResourceWorker(transport: transport)
            let result = try await invokeRelatedResourceTool(
                toolName,
                arguments: arguments,
                worker: worker
            )

            #expect(result.isError == true, "Expected nested-limit contract rejection for \(toolName)")
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("repository filters reject resources outside the requested ID set")
    func repositoryFilterRejectsOutOfScopeResource() async throws {
        let path = "/v1/ciProducts/product-1/primaryRepositories"
        let query = ["limit": "25", "filter[id]": "repo-1"]
        let body = """
        {
          "data": [{
            "type": "scmRepositories",
            "id": "repo-3",
            "attributes": { "ownerName": "Other", "repositoryName": "Unexpected" },
            "links": { "self": "https://api.example.test/v1/scmRepositories/repo-3" }
          }],
          "links": { "self": "\(relatedResourceURL(path: path, query: query))" },
          "meta": { "paging": { "total": 1, "limit": 25 } }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await relatedResourceWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_primary_repositories_list",
            arguments: [
                "product_id": .string("product-1"),
                "repository_id": .string("repo-1")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("collection page metadata and cursor links must match the requested page")
    func collectionPageContractDriftIsRejected() async throws {
        let path = "/v1/ciMacOsVersions/macos-1/xcodeVersions"
        let baseQuery = ["limit": "25"]
        let selfURL = relatedResourceURL(path: path, query: baseQuery)
        let invalidBodies = [
            """
            {
              "data": [],
              "links": { "self": "\(selfURL)" },
              "meta": {}
            }
            """,
            """
            {
              "data": [],
              "links": { "self": "\(selfURL)" },
              "meta": { "paging": { "limit": 24, "total": 0 } }
            }
            """,
            """
            {
              "data": [],
              "links": {
                "self": "\(selfURL)",
                "first": "\(relatedResourceURL(path: path, query: ["limit": "25", "cursor": "not-first"]))"
              },
              "meta": { "paging": { "limit": 25, "total": 0 } }
            }
            """
        ]

        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await relatedResourceWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "xcode_cloud_macos_version_xcode_versions_list",
                arguments: ["macos_version_id": .string("macos-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("links.next remains valid when optional meta nextCursor is absent")
    func optionalMetaNextCursorMayBeAbsent() async throws {
        let path = "/v1/ciMacOsVersions/macos-1/xcodeVersions"
        let query = ["limit": "25"]
        let nextURL = relatedResourceURL(path: path, query: ["limit": "25", "cursor": "next"])
        let body = """
        {
          "data": [],
          "links": {
            "self": "\(relatedResourceURL(path: path, query: query))",
            "next": "\(nextURL)"
          },
          "meta": { "paging": { "limit": 25, "total": 0 } }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await relatedResourceWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_macos_version_xcode_versions_list",
            arguments: ["macos_version_id": .string("macos-1")]
        ))

        #expect(result.isError != true)
        guard case .object(let root)? = result.structuredContent else {
            Issue.record("Expected structured collection result")
            return
        }
        #expect(root["next_url"] == .string(nextURL))
    }

    @Test("included resources are validated and preserved only for requested includes")
    func includedResourcesRequireExplicitInclude() async throws {
        let included = """
        [{
          "type": "scmProviders",
          "id": "provider-1",
          "attributes": { "url": "https://git.example.test" },
          "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
        }]
        """
        let body = """
        {
          "data": {
            "type": "scmRepositories",
            "id": "repo-1",
            "attributes": { "ownerName": "Example", "repositoryName": "App" },
            "relationships": {
              "scmProvider": {
                "data": { "type": "scmProviders", "id": "provider-1" }
              }
            },
            "links": { "self": "https://api.example.test/v1/scmRepositories/repo-1" }
          },
          "included": \(included),
          "links": {
            "self": "https://api.example.test/v1/ciWorkflows/workflow-1/repository?include=scmProvider"
          }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await relatedResourceWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_workflow_repository_get",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "include": .string("scmProvider")
            ]
        ))

        #expect(result.isError != true)
        guard case .object(let root)? = result.structuredContent,
              case .array(let resources)? = root["included"] else {
            Issue.record("Expected preserved included resources")
            return
        }
        #expect(resources.count == 1)
    }

    @Test("related included resources reject a same-type identity outside relationship lineage")
    func relatedIncludedResourcesRejectWrongLineage() async throws {
        let body = """
        {
          "data": {
            "type": "scmRepositories",
            "id": "repo-1",
            "relationships": {
              "scmProvider": {
                "data": { "type": "scmProviders", "id": "provider-2" }
              }
            },
            "links": { "self": "https://api.example.test/v1/scmRepositories/repo-1" }
          },
          "included": [{
            "type": "scmProviders",
            "id": "provider-1",
            "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
          }],
          "links": {
            "self": "https://api.example.test/v1/ciWorkflows/workflow-1/repository?include=scmProvider"
          }
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await relatedResourceWorker(transport: transport)
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_workflow_repository_get",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "include": .string("scmProvider")
            ]
        ))

        #expect(result.isError == true)
    }

    @Test("related endpoints preserve the established resource projections")
    func relatedEndpointsPreserveEstablishedProjections() async throws {
        for fixture in relatedProjectionParityFixtures() {
            let existingTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: fixture.existingResponse)
            ])
            let existingWorker = try await relatedResourceWorker(transport: existingTransport)
            let existingResult = try await existingWorker.handleTool(CallTool.Parameters(
                name: fixture.existingTool,
                arguments: fixture.existingArguments
            ))

            let relatedTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: fixture.relatedResponse)
            ])
            let relatedWorker = try await relatedResourceWorker(transport: relatedTransport)
            let relatedResult = try await relatedWorker.handleTool(CallTool.Parameters(
                name: fixture.relatedTool,
                arguments: fixture.relatedArguments
            ))

            #expect(existingResult.isError != true)
            #expect(relatedResult.isError != true)
            let existingProjection = try relatedProjection(
                existingResult,
                key: fixture.existingProjectionKey,
                collection: false
            )
            let relatedProjectionValue = try relatedProjection(
                relatedResult,
                key: fixture.relatedProjectionKey,
                collection: fixture.relatedCollection
            )
            #expect(
                existingProjection == relatedProjectionValue,
                "Projection drift for \(fixture.relatedTool)"
            )
        }
    }

    @Test("all related-resource schemas are strict and expose bounded controls")
    func schemasAreStrictAndBounded() async throws {
        let worker = try await relatedResourceWorker(transport: TestHTTPTransport(responses: []))
        let expectedNames: Set<String> = [
            "xcode_cloud_app_product_get",
            "xcode_cloud_action_build_run_get",
            "xcode_cloud_macos_version_xcode_versions_list",
            "xcode_cloud_product_additional_repositories_list",
            "xcode_cloud_product_app_get",
            "xcode_cloud_product_primary_repositories_list",
            "xcode_cloud_workflow_repository_get",
            "xcode_cloud_xcode_version_macos_versions_list"
        ]
        let tools = (await worker.getTools()).filter { expectedNames.contains($0.name) }

        #expect(Set(tools.map(\.name)) == expectedNames)
        for tool in tools {
            guard case .object(let schema) = tool.inputSchema,
                  case .object(let properties)? = schema["properties"] else {
                Issue.record("Expected object schema for \(tool.name)")
                continue
            }
            #expect(schema["additionalProperties"] == .bool(false))
            if let limit = properties["limit"] {
                guard case .object(let limitSchema) = limit else {
                    Issue.record("Expected integer limit schema")
                    continue
                }
                #expect(limitSchema["minimum"] == .int(1))
                #expect(limitSchema["maximum"] == .int(200))
            }
            if let nextURL = properties["next_url"] {
                guard case .object(let nextURLSchema) = nextURL else {
                    Issue.record("Expected next_url schema")
                    continue
                }
                #expect(nextURLSchema["format"] == .string("uri-reference"))
            }
            for (name, property) in properties where name.hasSuffix("_id") && name != "repository_id" {
                guard case .object(let identifierSchema) = property else {
                    Issue.record("Expected identifier schema for \(name)")
                    continue
                }
                #expect(identifierSchema["minLength"] == .int(1))
                #expect(identifierSchema["pattern"] != nil)
            }
        }

        let repositoryTool = try #require(tools.first {
            $0.name == "xcode_cloud_product_primary_repositories_list"
        })
        guard case .object(let repositorySchema) = repositoryTool.inputSchema,
              case .object(let repositoryProperties)? = repositorySchema["properties"],
              case .object(let repositoryIDSchema)? = repositoryProperties["repository_id"],
              case .array(let repositoryAlternatives)? = repositoryIDSchema["oneOf"] else {
            Issue.record("Expected scalar-or-array repository_id schema")
            return
        }
        #expect(repositoryAlternatives.count == 2)

        let actionTool = try #require(tools.first { $0.name == "xcode_cloud_action_build_run_get" })
        guard case .object(let actionSchema) = actionTool.inputSchema,
              case .object(let actionProperties)? = actionSchema["properties"],
              case .object(let includeSchema)? = actionProperties["include"],
              case .array(let includeAlternatives)? = includeSchema["oneOf"],
              case .object(let nestedLimit)? = actionProperties["builds_limit"] else {
            Issue.record("Expected scalar-or-array include and nested limit schemas")
            return
        }
        #expect(includeAlternatives.count == 2)
        #expect(nestedLimit["minimum"] == .int(1))
        #expect(nestedLimit["maximum"] == .int(50))
    }
}

private struct XcodeCloudRelatedProjectionParityFixture {
    let existingTool: String
    let existingArguments: [String: Value]
    let existingResponse: String
    let relatedTool: String
    let relatedArguments: [String: Value]
    let relatedResponse: String
    let existingProjectionKey: String
    let relatedProjectionKey: String
    let relatedCollection: Bool
}

private func relatedProjectionParityFixtures() -> [XcodeCloudRelatedProjectionParityFixture] {
    let product = relatedProductJSON()
    let buildRun = relatedBuildRunJSON()
    let xcodeVersion = relatedXcodeVersionJSON()
    let macOSVersion = relatedMacOSVersionJSON()
    let repository = relatedRepositoryJSON()
    return [
        .init(
            existingTool: "xcode_cloud_products_get",
            existingArguments: ["product_id": .string("product-1")],
            existingResponse: relatedSingleResponse(
                dataJSON: product,
                selfURL: "https://api.example.test/v1/ciProducts/product-1"
            ),
            relatedTool: "xcode_cloud_app_product_get",
            relatedArguments: ["app_id": .string("app-1")],
            relatedResponse: relatedSingleResponse(
                dataJSON: product,
                selfURL: "https://api.example.test/v1/apps/app-1/ciProduct"
            ),
            existingProjectionKey: "product",
            relatedProjectionKey: "product",
            relatedCollection: false
        ),
        .init(
            existingTool: "xcode_cloud_build_runs_get",
            existingArguments: ["build_run_id": .string("run-1")],
            existingResponse: relatedSingleResponse(
                dataJSON: buildRun,
                selfURL: "https://api.example.test/v1/ciBuildRuns/run-1"
            ),
            relatedTool: "xcode_cloud_action_build_run_get",
            relatedArguments: ["action_id": .string("action-1")],
            relatedResponse: relatedSingleResponse(
                dataJSON: buildRun,
                selfURL: "https://api.example.test/v1/ciBuildActions/action-1/buildRun"
            ),
            existingProjectionKey: "buildRun",
            relatedProjectionKey: "buildRun",
            relatedCollection: false
        ),
        .init(
            existingTool: "xcode_cloud_xcode_versions_get",
            existingArguments: ["xcode_version_id": .string("xcode-1")],
            existingResponse: relatedSingleResponse(
                dataJSON: xcodeVersion,
                selfURL: "https://api.example.test/v1/ciXcodeVersions/xcode-1"
            ),
            relatedTool: "xcode_cloud_macos_version_xcode_versions_list",
            relatedArguments: ["macos_version_id": .string("macos-1")],
            relatedResponse: relatedCollectionResponse(
                dataJSON: xcodeVersion,
                selfURL: "https://api.example.test/v1/ciMacOsVersions/macos-1/xcodeVersions?limit=25"
            ),
            existingProjectionKey: "xcodeVersion",
            relatedProjectionKey: "xcodeVersions",
            relatedCollection: true
        ),
        .init(
            existingTool: "xcode_cloud_macos_versions_get",
            existingArguments: ["macos_version_id": .string("macos-1")],
            existingResponse: relatedSingleResponse(
                dataJSON: macOSVersion,
                selfURL: "https://api.example.test/v1/ciMacOsVersions/macos-1"
            ),
            relatedTool: "xcode_cloud_xcode_version_macos_versions_list",
            relatedArguments: ["xcode_version_id": .string("xcode-1")],
            relatedResponse: relatedCollectionResponse(
                dataJSON: macOSVersion,
                selfURL: "https://api.example.test/v1/ciXcodeVersions/xcode-1/macOsVersions?limit=25"
            ),
            existingProjectionKey: "macOSVersion",
            relatedProjectionKey: "macOSVersions",
            relatedCollection: true
        ),
        .init(
            existingTool: "xcode_cloud_scm_repositories_get",
            existingArguments: ["repository_id": .string("repo-1")],
            existingResponse: relatedSingleResponse(
                dataJSON: repository,
                selfURL: "https://api.example.test/v1/scmRepositories/repo-1"
            ),
            relatedTool: "xcode_cloud_workflow_repository_get",
            relatedArguments: ["workflow_id": .string("workflow-1")],
            relatedResponse: relatedSingleResponse(
                dataJSON: repository,
                selfURL: "https://api.example.test/v1/ciWorkflows/workflow-1/repository"
            ),
            existingProjectionKey: "repository",
            relatedProjectionKey: "repository",
            relatedCollection: false
        )
    ]
}

private func relatedSingleResponse(dataJSON: String, selfURL: String) -> String {
    """
    {
      "data": \(dataJSON),
      "links": { "self": "\(selfURL)" }
    }
    """
}

private func relatedCollectionResponse(dataJSON: String, selfURL: String) -> String {
    """
    {
      "data": [\(dataJSON)],
      "links": { "self": "\(selfURL)" },
      "meta": { "paging": { "total": 1, "limit": 25 } }
    }
    """
}

private func relatedProjection(
    _ result: CallTool.Result,
    key: String,
    collection: Bool
) throws -> Value {
    guard case .object(let root)? = result.structuredContent,
          let value = root[key] else {
        throw XcodeCloudRelatedProjectionTestError.missingProjection(key)
    }
    if collection {
        guard case .array(let values) = value, let first = values.first else {
            throw XcodeCloudRelatedProjectionTestError.missingProjection(key)
        }
        return first
    }
    return value
}

private enum XcodeCloudRelatedProjectionTestError: Error {
    case missingProjection(String)
}

private struct XcodeCloudRelatedResourceRouteFixture {
    let toolName: String
    let arguments: [String: Value]
    let path: String
    let query: [String: String]
    let dataJSON: String
    let collection: Bool
}

private func relatedResourceRouteFixtures() -> [XcodeCloudRelatedResourceRouteFixture] {
    [
        .init(
            toolName: "xcode_cloud_app_product_get",
            arguments: [
                "app_id": .string("app-1"),
                "include": .array([.string("app"), .string("primaryRepositories")]),
                "primary_repositories_limit": .int(2)
            ],
            path: "/v1/apps/app-1/ciProduct",
            query: ["include": "app,primaryRepositories", "limit[primaryRepositories]": "2"],
            dataJSON: relatedProductJSON(),
            collection: false
        ),
        .init(
            toolName: "xcode_cloud_action_build_run_get",
            arguments: [
                "action_id": .string("action-1"),
                "include": .array([.string("builds"), .string("workflow")]),
                "builds_limit": .int(3)
            ],
            path: "/v1/ciBuildActions/action-1/buildRun",
            query: ["include": "builds,workflow", "limit[builds]": "3"],
            dataJSON: relatedBuildRunJSON(),
            collection: false
        ),
        .init(
            toolName: "xcode_cloud_macos_version_xcode_versions_list",
            arguments: [
                "macos_version_id": .string("macos-1"),
                "limit": .int(30),
                "include": .string("macOsVersions"),
                "macos_versions_limit": .int(4)
            ],
            path: "/v1/ciMacOsVersions/macos-1/xcodeVersions",
            query: ["limit": "30", "include": "macOsVersions", "limit[macOsVersions]": "4"],
            dataJSON: relatedXcodeVersionJSON(),
            collection: true
        ),
        .init(
            toolName: "xcode_cloud_product_additional_repositories_list",
            arguments: [
                "product_id": .string("product-1"),
                "repository_id": .array([.string("repo-1"), .string("repo-2")]),
                "limit": .int(31),
                "include": .string("defaultBranch")
            ],
            path: "/v1/ciProducts/product-1/additionalRepositories",
            query: ["limit": "31", "filter[id]": "repo-1,repo-2", "include": "defaultBranch"],
            dataJSON: relatedRepositoryJSON(),
            collection: true
        ),
        .init(
            toolName: "xcode_cloud_product_app_get",
            arguments: ["product_id": .string("product-1")],
            path: "/v1/ciProducts/product-1/app",
            query: [:],
            dataJSON: relatedAppJSON(),
            collection: false
        ),
        .init(
            toolName: "xcode_cloud_product_primary_repositories_list",
            arguments: [
                "product_id": .string("product-1"),
                "repository_id": .string("repo-1"),
                "limit": .int(32),
                "include": .string("scmProvider")
            ],
            path: "/v1/ciProducts/product-1/primaryRepositories",
            query: ["limit": "32", "filter[id]": "repo-1", "include": "scmProvider"],
            dataJSON: relatedRepositoryJSON(),
            collection: true
        ),
        .init(
            toolName: "xcode_cloud_workflow_repository_get",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "include": .array([.string("scmProvider"), .string("defaultBranch")])
            ],
            path: "/v1/ciWorkflows/workflow-1/repository",
            query: ["include": "scmProvider,defaultBranch"],
            dataJSON: relatedRepositoryJSON(),
            collection: false
        ),
        .init(
            toolName: "xcode_cloud_xcode_version_macos_versions_list",
            arguments: [
                "xcode_version_id": .string("xcode-1"),
                "limit": .int(33),
                "include": .string("xcodeVersions"),
                "xcode_versions_limit": .int(5)
            ],
            path: "/v1/ciXcodeVersions/xcode-1/macOsVersions",
            query: ["limit": "33", "include": "xcodeVersions", "limit[xcodeVersions]": "5"],
            dataJSON: relatedMacOSVersionJSON(),
            collection: true
        )
    ]
}

private func relatedResourceResponseBody(_ fixture: XcodeCloudRelatedResourceRouteFixture) -> String {
    let selfURL = relatedResourceURL(path: fixture.path, query: fixture.query)
    let data = fixture.collection ? "[\(fixture.dataJSON)]" : fixture.dataJSON
    return """
    {
      "data": \(data),
      "links": { "self": "\(selfURL)" },
      "meta": { "paging": { "total": 1, "limit": \(fixture.query["limit"] ?? "1") } }
    }
    """
}

private func relatedProductJSON() -> String {
    """
    {
      "type": "ciProducts",
      "id": "product-1",
      "attributes": { "name": "App", "productType": "APP" },
      "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
    }
    """
}

private func relatedBuildRunJSON() -> String {
    """
    {
      "type": "ciBuildRuns",
      "id": "run-1",
      "attributes": { "number": 42, "executionProgress": "RUNNING" },
      "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
    }
    """
}

private func relatedXcodeVersionJSON() -> String {
    """
    {
      "type": "ciXcodeVersions",
      "id": "xcode-1",
      "attributes": { "version": "26.0", "name": "Xcode 26" },
      "links": { "self": "https://api.example.test/v1/ciXcodeVersions/xcode-1" }
    }
    """
}

private func relatedMacOSVersionJSON() -> String {
    """
    {
      "type": "ciMacOsVersions",
      "id": "macos-1",
      "attributes": { "version": "26.0", "name": "macOS 26" },
      "links": { "self": "https://api.example.test/v1/ciMacOsVersions/macos-1" }
    }
    """
}

private func relatedRepositoryJSON() -> String {
    """
    {
      "type": "scmRepositories",
      "id": "repo-1",
      "attributes": { "ownerName": "Example", "repositoryName": "App" },
      "links": { "self": "https://api.example.test/v1/scmRepositories/repo-1" }
    }
    """
}

private func relatedAppJSON() -> String {
    """
    {
      "type": "apps",
      "id": "app-1",
      "attributes": {
        "name": "App",
        "bundleId": "com.example.app",
        "sku": "APP",
        "primaryLocale": "en-US"
      },
      "links": { "self": "https://api.example.test/v1/apps/app-1" }
    }
    """
}

private func relatedResourceURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    if !query.isEmpty {
        components.queryItems = query.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
    }
    return components.url!.absoluteString
}

private func relatedResourceQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func relatedResourceWorker(transport: TestHTTPTransport) async throws -> XcodeCloudWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return XcodeCloudWorker(httpClient: client)
}

private func invokeRelatedResourceTool(
    _ name: String,
    arguments: [String: Value],
    worker: XcodeCloudWorker
) async throws -> CallTool.Result {
    try await worker.handleTool(CallTool.Parameters(name: name, arguments: arguments))
}
