import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Worker Tests")
struct XcodeCloudWorkerTests {
    @Test("missing required parameters return isError")
    func missingRequiredParametersReturnErrors() async throws {
        let worker = XcodeCloudWorker(httpClient: try await TestFactory.makeHTTPClient())

        let getProduct = try await worker.handleTool(CallTool.Parameters(name: "xcode_cloud_products_get", arguments: nil))
        let listWorkflows = try await worker.handleTool(CallTool.Parameters(name: "xcode_cloud_product_workflows_list", arguments: nil))
        let getBuildRun = try await worker.handleTool(CallTool.Parameters(name: "xcode_cloud_build_runs_get", arguments: nil))
        let listActions = try await worker.handleTool(CallTool.Parameters(name: "xcode_cloud_build_run_actions_list", arguments: nil))
        let getRepository = try await worker.handleTool(CallTool.Parameters(name: "xcode_cloud_scm_repositories_get", arguments: nil))

        #expect(getProduct.isError == true)
        #expect(listWorkflows.isError == true)
        #expect(getBuildRun.isError == true)
        #expect(listActions.isError == true)
        #expect(getRepository.isError == true)
    }

    @Test("start build validates required source relationships")
    func startBuildValidatesRelationships() async throws {
        let worker = XcodeCloudWorker(httpClient: try await TestFactory.makeHTTPClient())

        let missing = try await worker.handleTool(
            CallTool.Parameters(name: "xcode_cloud_build_runs_start", arguments: [:])
        )
        let conflicting = try await worker.handleTool(
            CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "source_branch_or_tag_id": .string("branch-1"),
                    "pull_request_id": .string("pr-1")
                ]
            )
        )

        #expect(missing.isError == true)
        #expect(conflicting.isError == true)
    }

    @Test("start build enforces exactly one run selector at runtime")
    func startBuildRequiresExactlyOneRunSelector() async throws {
        let transport = XcodeCloudMockTransport(body: "{}")
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)
        let tools = await worker.getTools()
        let tool = ToolMetadataPolicy.apply(
            to: try #require(tools.first { $0.name == "xcode_cloud_build_runs_start" })
        )

        guard case .object(let schema) = tool.inputSchema else {
            Issue.record("Expected object input schema")
            return
        }
        #expect(schema["if"] == nil)
        #expect(schema["then"] == nil)
        #expect(schema["else"] == nil)
        #expect(schema["not"] == nil)

        let neither = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: [:]
        ))
        let both = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "build_run_id": .string("run-1")
            ]
        ))
        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["workflow_id": .string("   ")]
        ))

        #expect(neither.isError == true)
        #expect(both.isError == true)
        #expect(empty.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("start build sends workflow relationship and returns structured build run")
    func startBuildSendsWorkflowRelationship() async throws {
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciBuildRuns",
            "id": "run-1",
            "attributes": {
              "number": 42,
              "executionProgress": "PENDING",
              "startReason": "MANUAL",
              "sourceCommit": {
                "commitSha": "abc123",
                "author": {
                  "displayName": "A. Developer",
                  "avatarUrl": "https://example.test/avatar.png"
                }
              }
            },
            "relationships": {
              "workflow": { "data": { "type": "ciWorkflows", "id": "workflow-1" } }
            }
          },
          "links": { "self": "https://api.example.test/v1/ciBuildRuns" }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "xcode_cloud_build_runs_start",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "clean": .bool(true)
                ]
            )
        )

        #expect(result.isError == nil)
        #expect(await transport.lastMethod() == "POST")
        #expect(await transport.lastPath() == "/v1/ciBuildRuns")
        let body = await transport.lastBodyString()
        #expect(body.contains("\"workflow\""))
        #expect(body.contains("\"ciWorkflows\""))
        #expect(body.contains("\"clean\":true"))
        #expect(!body.contains("\"buildRun\""))

        guard case .object(let root)? = result.structuredContent,
              case .object(let buildRun)? = root["buildRun"] else {
            Issue.record("Expected structured buildRun object")
            return
        }
        #expect(buildRun["id"] == .string("run-1"))
        #expect(buildRun["number"] == .int(42))
        #expect(buildRun["workflowId"] == .string("workflow-1"))
        guard case .object(let sourceCommit)? = buildRun["sourceCommit"],
              case .object(let author)? = sourceCommit["author"] else {
            Issue.record("Expected projected source commit author")
            return
        }
        #expect(author["avatarUrl"] == .string("https://example.test/avatar.png"))
        #expect(author["email"] == nil)
        #expect(buildRun["destinationCommit"] == .null)
        #expect(buildRun["issueCounts"] == .null)
    }

    @Test("start build sends only the build run relationship for rebuilds")
    func startBuildSendsBuildRunRelationship() async throws {
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciBuildRuns",
            "id": "run-2"
          },
          "links": { "self": "https://api.example.test/v1/ciBuildRuns" }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_runs_start",
            arguments: ["build_run_id": .string("run-1")]
        ))

        #expect(result.isError == nil)
        let bodyString = await transport.lastBodyString()
        let body = Data(bodyString.utf8)
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let buildRun = try #require(relationships["buildRun"] as? [String: Any])
        let linkage = try #require(buildRun["data"] as? [String: Any])
        #expect(linkage["type"] as? String == "ciBuildRuns")
        #expect(linkage["id"] as? String == "run-1")
        #expect(relationships["workflow"] == nil)
    }

    @Test("list products supports filters, include, and pagination result")
    func listProductsSupportsFiltersAndInclude() async throws {
        let query = [
            "limit": "1",
            "filter[productType]": "APP",
            "filter[app]": "app-1",
            "include": "app,primaryRepositories"
        ]
        let selfURL = xcodeCloudWorkerURL(path: "/v1/ciProducts", query: query)
        let nextURL = xcodeCloudWorkerURL(
            path: "/v1/ciProducts",
            query: query.merging(["cursor": "abc"]) { _, new in new }
        )
        let followingURL = xcodeCloudWorkerURL(
            path: "/v1/ciProducts",
            query: query.merging(["cursor": "def"]) { _, new in new }
        )
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": [{
            "type": "ciProducts",
            "id": "product-1",
            "attributes": {
              "name": "Main App",
              "createdDate": "2026-05-07T08:00:00Z",
              "productType": "APP"
            },
            "relationships": {
              "app": { "data": { "type": "apps", "id": "app-1" } },
              "workflows": {
                "links": { "related": "https://api.example.test/v1/ciProducts/product-1/workflows" }
              },
              "primaryRepositories": { "data": [] }
            },
            "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
          }],
          "links": {
            "self": "\(selfURL)",
            "next": "\(nextURL)"
          },
          "meta": { "paging": { "total": 12, "limit": 1 } }
        }
        """, continuationBody: """
        {
          "data": [],
          "links": {
            "self": "\(nextURL)",
            "next": "\(followingURL)"
          },
          "meta": { "paging": { "total": 12, "limit": 1, "nextCursor": "def" } }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "xcode_cloud_products_list",
                arguments: [
                    "limit": .int(1),
                    "product_type": .string("APP"),
                    "app_id": .string("app-1"),
                    "include": .array([.string("app"), .string("primaryRepositories")])
                ]
            )
        )

        #expect(result.isError == nil)
        let queryItems = await transport.lastQueryItems()
        #expect(queryItems == query)

        guard case .object(let root)? = result.structuredContent,
              case .array(let products)? = root["products"],
              case .object(let product)? = products.first else {
            Issue.record("Expected structured products array")
            return
        }
        #expect(root["count"] == .int(1))
        #expect(root["total"] == .int(12))
        #expect(root["self_url"] == .string(selfURL))
        #expect(product["id"] == .string("product-1"))
        #expect(product["selfUrl"] == .string("https://api.example.test/v1/ciProducts/product-1"))
        #expect(product["appId"] == .string("app-1"))
        #expect(product["workflowIds"] == .null)
        #expect(product["additionalRepositoryIds"] == .null)
        #expect(product["buildRunIds"] == .null)
        #expect(product["workflowsUrl"] == .string("https://api.example.test/v1/ciProducts/product-1/workflows"))
        #expect(product["workflowsRelationshipUrl"] == .null)
        #expect(product["primaryRepositoryIds"] == .array([]))
        #expect(root["next_url"] == .string(nextURL))

        let continuation = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_products_list",
            arguments: [
                "limit": .int(1),
                "product_type": .string("APP"),
                "app_id": .string("app-1"),
                "include": .array([.string("app"), .string("primaryRepositories")]),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(continuation.isError == nil)
        let continuationQuery = await transport.lastQueryItems()
        #expect(continuationQuery["cursor"] == "abc")
        #expect(continuationQuery["limit"] == "1")
        #expect(continuationQuery["filter[productType]"] == "APP")
        #expect(continuationQuery["filter[app]"] == "app-1")
        #expect(continuationQuery["include"] == "app,primaryRepositories")
        guard case .object(let continuationRoot)? = continuation.structuredContent else {
            Issue.record("Expected structured continuation result")
            return
        }
        #expect(continuationRoot["self_url"] == .string(nextURL))
        #expect(continuationRoot["next_url"] == .string(followingURL))
    }

    @Test("workflow pagination rejects another product parent before transport")
    func workflowPaginationRejectsAnotherProduct() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_workflows_list",
            arguments: [
                "product_id": .string("product-1"),
                "next_url": .string(
                    "https://api.example.test/v1/ciProducts/product-2/workflows?cursor=next"
                )
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("present non-string pagination value fails before transport")
    func productPaginationRejectsNonStringValue() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = XcodeCloudWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_products_list",
            arguments: ["next_url": .int(1)]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("models decode workflow, build run, and SCM repository")
    func modelDecoding() throws {
        let workflowJSON = Data("""
        {
          "data": {
            "type": "ciWorkflows",
            "id": "workflow-1",
            "attributes": {
              "name": "Release",
              "isEnabled": true,
              "actions": [{ "name": "Archive", "actionType": "ARCHIVE" }]
            },
            "relationships": {
              "repository": { "data": { "type": "scmRepositories", "id": "repo-1" } },
              "xcodeVersion": { "data": { "type": "ciXcodeVersions", "id": "xcode-1" } }
            }
          },
          "links": { "self": "https://api.example.test/v1/ciWorkflows/workflow-1" }
        }
        """.utf8)
        let workflow = try JSONDecoder().decode(ASCCIWorkflowResponse.self, from: workflowJSON)
        #expect(workflow.data.attributes?.name == "Release")
        #expect(workflow.data.relationships?.repository?.data?.id == "repo-1")
        #expect(workflow.data.attributes?.actions?.count == 1)

        let runJSON = Data("""
        {
          "data": {
            "type": "ciBuildRuns",
            "id": "run-1",
            "attributes": {
              "number": 7,
              "issueCounts": { "errors": 1, "warnings": 2 },
              "completionStatus": "FAILED"
            }
          },
          "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
        }
        """.utf8)
        let run = try JSONDecoder().decode(ASCCIBuildRunResponse.self, from: runJSON)
        #expect(run.data.attributes?.issueCounts?.errors == 1)
        #expect(run.data.attributes?.completionStatus == "FAILED")

        let repositoryJSON = Data("""
        {
          "data": {
            "type": "scmRepositories",
            "id": "repo-1",
            "attributes": {
              "ownerName": "develotex",
              "repositoryName": "ios-app",
              "httpCloneUrl": "https://example.com/repo.git"
            }
          },
          "links": { "self": "https://api.example.test/v1/scmRepositories/repo-1" }
        }
        """.utf8)
        let repository = try JSONDecoder().decode(ASCScmRepositoryResponse.self, from: repositoryJSON)
        #expect(repository.data.attributes?.ownerName == "develotex")
        #expect(repository.data.attributes?.repositoryName == "ios-app")

        let providerJSON = Data("""
        {
          "data": {
            "type": "scmProviders",
            "id": "provider-1",
            "attributes": {
              "scmProviderType": {
                "kind": "GITHUB_CLOUD",
                "displayName": "GitHub",
                "isOnPremise": false
              },
              "url": "https://github.com"
            },
            "relationships": {
              "repositories": {
                "links": { "related": "https://api.example.test/v1/scmProviders/provider-1/repositories" }
              }
            },
            "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
          },
          "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
        }
        """.utf8)
        let provider = try JSONDecoder().decode(ASCScmProviderResponse.self, from: providerJSON)
        #expect(provider.data.attributes?.scmProviderType?.kind == "GITHUB_CLOUD")
        #expect(provider.data.attributes?.scmProviderType?.displayName == "GitHub")
        #expect(provider.data.attributes?.scmProviderType?.isOnPremise == false)
        #expect(provider.data.relationships?.repositories?.links?.related == "https://api.example.test/v1/scmProviders/provider-1/repositories")
    }

    @Test("provider and test result projections follow Apple 4.4.1")
    func providerAndTestResultProjections() async throws {
        let providerTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "scmProviders",
            "id": "provider-1",
            "attributes": {
              "scmProviderType": {
                "kind": "GITHUB_ENTERPRISE",
                "displayName": "GitHub Enterprise",
                "isOnPremise": true
              },
              "url": "https://git.example.test"
            },
            "relationships": {
              "repositories": {
                "links": { "related": "https://api.example.test/v1/scmProviders/provider-1/repositories" }
              }
            },
            "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
          },
          "links": { "self": "https://api.example.test/v1/scmProviders/provider-1" }
        }
        """)
        let providerClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: providerTransport,
            maxRetries: 1
        )
        let providerResult = try await XcodeCloudWorker(httpClient: providerClient).handleTool(
            CallTool.Parameters(
                name: "xcode_cloud_scm_providers_get",
                arguments: ["provider_id": .string("provider-1")]
            )
        )
        guard case .object(let providerRoot)? = providerResult.structuredContent,
              case .object(let provider)? = providerRoot["provider"] else {
            Issue.record("Expected structured provider object")
            return
        }
        #expect(provider["scmProviderType"] == .string("GITHUB_ENTERPRISE"))
        #expect(provider["scmProviderDisplayName"] == .string("GitHub Enterprise"))
        #expect(provider["isOnPremise"] == .bool(true))
        #expect(providerRoot["self_url"] == .string("https://api.example.test/v1/scmProviders/provider-1"))
        #expect(provider["selfUrl"] == .string("https://api.example.test/v1/scmProviders/provider-1"))
        #expect(provider["repositoryIds"] == .null)
        #expect(provider["repositoriesUrl"] == .string("https://api.example.test/v1/scmProviders/provider-1/repositories"))
        #expect(provider["repositoriesRelationshipUrl"] == .null)

        let testResultTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciTestResults",
            "id": "test-1",
            "attributes": {
              "name": "testExample",
              "status": "SUCCESS",
              "fileSource": { "path": "Tests/AppTests.swift", "lineNumber": 17 },
              "destinationTestResults": [{
                "uuid": "destination-1",
                "deviceName": "iPhone 17 Pro",
                "osVersion": "26.0",
                "status": "SUCCESS",
                "duration": 1.25
              }]
            },
            "links": { "self": "https://api.example.test/v1/ciTestResults/test-1" }
          },
          "links": { "self": "https://api.example.test/v1/ciTestResults/test-1" }
        }
        """)
        let testResultClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: testResultTransport,
            maxRetries: 1
        )
        let testResult = try await XcodeCloudWorker(httpClient: testResultClient).handleTool(
            CallTool.Parameters(
                name: "xcode_cloud_test_results_get",
                arguments: ["test_result_id": .string("test-1")]
            )
        )
        guard case .object(let resultRoot)? = testResult.structuredContent,
              case .object(let result)? = resultRoot["testResult"],
              case .object(let fileSource)? = result["fileSource"],
              case .array(let destinations)? = result["destinationTestResults"],
              case .object(let destination)? = destinations.first else {
            Issue.record("Expected structured test result object")
            return
        }
        #expect(fileSource["path"] == .string("Tests/AppTests.swift"))
        #expect(fileSource["fileName"] == nil)
        #expect(resultRoot["self_url"] == .string("https://api.example.test/v1/ciTestResults/test-1"))
        #expect(result["selfUrl"] == .string("https://api.example.test/v1/ciTestResults/test-1"))
        #expect(result["status"] == .string("SUCCESS"))
        #expect(result["destinationTestResultsPresent"] == .bool(true))
        #expect(destination["uuid"] == .string("destination-1"))
        #expect(destination["status"] == .string("SUCCESS"))
        #expect(destination["message"] == nil)
    }

    @Test("read projections preserve legacy arrays and relationship page completeness")
    func readProjectionNullabilityAndRelationshipPaging() async throws {
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciWorkflows",
            "id": "workflow-1",
            "attributes": { "name": "Release" },
            "relationships": {
              "buildRuns": {
                "links": {
                  "self": "https://api.example.test/v1/ciWorkflows/workflow-1/relationships/buildRuns",
                  "related": "https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns"
                }
              }
            },
            "links": { "self": "https://api.example.test/v1/ciWorkflows/workflow-1" }
          },
          "links": { "self": "https://api.example.test/v1/ciWorkflows/workflow-1" }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let result = try await XcodeCloudWorker(httpClient: client).handleTool(.init(
            name: "xcode_cloud_workflows_get",
            arguments: ["workflow_id": .string("workflow-1")]
        ))

        #expect(result.isError == nil)
        guard case .object(let root)? = result.structuredContent,
              case .object(let workflow)? = root["workflow"] else {
            Issue.record("Expected workflow projection")
            return
        }
        #expect(workflow["actions"] == .array([]))
        #expect(workflow["actionsPresent"] == .bool(false))
        #expect(workflow["buildRunIds"] == .null)
        #expect(workflow["buildRunIdsMeta"] == nil)
        #expect(workflow["buildRunsUrl"] == .string("https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns"))
        #expect(workflow["buildRunsRelationshipUrl"] == .string("https://api.example.test/v1/ciWorkflows/workflow-1/relationships/buildRuns"))

        let productTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciProducts",
            "id": "product-1",
            "relationships": {
              "primaryRepositories": {
                "data": [{ "type": "scmRepositories", "id": "repository-1" }],
                "meta": { "paging": { "total": 2, "limit": 1, "nextCursor": "next" } },
                "links": {
                  "self": "https://api.example.test/v1/ciProducts/product-1/relationships/primaryRepositories",
                  "related": "https://api.example.test/v1/ciProducts/product-1/primaryRepositories"
                }
              }
            },
            "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
          },
          "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
        }
        """)
        let productClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: productTransport,
            maxRetries: 1
        )
        let productResult = try await XcodeCloudWorker(httpClient: productClient).handleTool(.init(
            name: "xcode_cloud_products_get",
            arguments: ["product_id": .string("product-1")]
        ))
        guard case .object(let productRoot)? = productResult.structuredContent,
              case .object(let product)? = productRoot["product"],
              case .object(let metadata)? = product["primaryRepositoryIdsMeta"] else {
            Issue.record("Expected primary-repository relationship metadata")
            return
        }
        #expect(metadata["returnedCount"] == .int(1))
        #expect(metadata["total"] == .int(2))
        #expect(metadata["nextCursor"] == .string("next"))
        #expect(metadata["isComplete"] == .bool(false))
        #expect(product["primaryRepositoriesUrl"] == .string("https://api.example.test/v1/ciProducts/product-1/primaryRepositories"))
        #expect(product["primaryRepositoriesRelationshipUrl"] == .string("https://api.example.test/v1/ciProducts/product-1/relationships/primaryRepositories"))
    }

    @Test("links-only relationships project only parent-scoped URLs")
    func linksOnlyRelationshipProjection() async throws {
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciBuildRuns",
            "id": "run-1",
            "relationships": {
              "actions": {
                "links": {
                  "self": "https://api.example.test/v1/ciBuildRuns/run-1/relationships/actions",
                  "related": "https://api.example.test/v1/ciBuildRuns/run-1/actions"
                }
              }
            },
            "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
          },
          "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let result = try await XcodeCloudWorker(httpClient: client).handleTool(.init(
            name: "xcode_cloud_build_runs_get",
            arguments: ["build_run_id": .string("run-1")]
        ))

        #expect(result.isError == nil)
        guard case .object(let root)? = result.structuredContent,
              case .object(let buildRun)? = root["buildRun"] else {
            Issue.record("Expected build-run projection")
            return
        }
        #expect(buildRun["actionIds"] == .null)
        #expect(buildRun["actionIdsMeta"] == nil)
        #expect(buildRun["actionsUrl"] == .string("https://api.example.test/v1/ciBuildRuns/run-1/actions"))
        #expect(buildRun["actionsRelationshipUrl"] == .string("https://api.example.test/v1/ciBuildRuns/run-1/relationships/actions"))
    }

    @Test("legacy projection keys remain stable with explicit presence metadata")
    func legacyProjectionCompatibility() async throws {
        let actionTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciBuildActions",
            "id": "action-1",
            "relationships": {
              "artifacts": { "links": {
                "self": "https://api.example.test/v1/ciBuildActions/action-1/relationships/artifacts",
                "related": "https://api.example.test/v1/ciBuildActions/action-1/artifacts"
              } },
              "issues": { "links": {
                "self": "https://api.example.test/v1/ciBuildActions/action-1/relationships/issues",
                "related": "https://api.example.test/v1/ciBuildActions/action-1/issues"
              } },
              "testResults": { "links": {
                "self": "https://api.example.test/v1/ciBuildActions/action-1/relationships/testResults",
                "related": "https://api.example.test/v1/ciBuildActions/action-1/testResults"
              } }
            },
            "links": { "self": "https://api.example.test/v1/ciBuildActions/action-1" }
          },
          "links": { "self": "https://api.example.test/v1/ciBuildActions/action-1" }
        }
        """)
        let actionClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: actionTransport,
            maxRetries: 1
        )
        let actionResult = try await XcodeCloudWorker(httpClient: actionClient).handleTool(.init(
            name: "xcode_cloud_actions_get",
            arguments: ["action_id": .string("action-1")]
        ))
        guard case .object(let actionRoot)? = actionResult.structuredContent,
              case .object(let action)? = actionRoot["action"] else {
            Issue.record("Expected action projection")
            return
        }
        #expect(action["artifactIds"] == .null)
        #expect(action["issueIds"] == .null)
        #expect(action["testResultIds"] == .null)

        let repositoryTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "scmRepositories",
            "id": "repository-1",
            "relationships": {
              "gitReferences": { "links": {
                "self": "https://api.example.test/v1/scmRepositories/repository-1/relationships/gitReferences",
                "related": "https://api.example.test/v1/scmRepositories/repository-1/gitReferences"
              } },
              "pullRequests": { "links": {
                "self": "https://api.example.test/v1/scmRepositories/repository-1/relationships/pullRequests",
                "related": "https://api.example.test/v1/scmRepositories/repository-1/pullRequests"
              } }
            },
            "links": { "self": "https://api.example.test/v1/scmRepositories/repository-1" }
          },
          "links": { "self": "https://api.example.test/v1/scmRepositories/repository-1" }
        }
        """)
        let repositoryClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: repositoryTransport,
            maxRetries: 1
        )
        let repositoryResult = try await XcodeCloudWorker(httpClient: repositoryClient).handleTool(.init(
            name: "xcode_cloud_scm_repositories_get",
            arguments: ["repository_id": .string("repository-1")]
        ))
        guard case .object(let repositoryRoot)? = repositoryResult.structuredContent,
              case .object(let repository)? = repositoryRoot["repository"] else {
            Issue.record("Expected repository projection")
            return
        }
        #expect(repository["gitReferenceIds"] == .null)
        #expect(repository["pullRequestIds"] == .null)

        let versionsTransport = XcodeCloudMockTransport(body: """
        {
          "data": [
            {
              "type": "ciXcodeVersions",
              "id": "xcode-1",
              "attributes": { "name": "Xcode One" },
              "links": { "self": "https://api.example.test/v1/ciXcodeVersions/xcode-1" }
            },
            {
              "type": "ciXcodeVersions",
              "id": "xcode-2",
              "attributes": {
                "name": "Xcode Two",
                "testDestinations": [{ "deviceTypeName": "iPhone" }]
              },
              "links": { "self": "https://api.example.test/v1/ciXcodeVersions/xcode-2" }
            }
          ],
          "links": { "self": "https://api.example.test/v1/ciXcodeVersions?limit=25" }
        }
        """)
        let versionsClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: versionsTransport,
            maxRetries: 1
        )
        let versionsResult = try await XcodeCloudWorker(httpClient: versionsClient).handleTool(.init(
            name: "xcode_cloud_xcode_versions_list",
            arguments: [:]
        ))
        guard case .object(let versionsRoot)? = versionsResult.structuredContent,
              case .array(let versions)? = versionsRoot["xcodeVersions"],
              versions.count == 2,
              case .object(let firstVersion) = versions[0],
              case .object(let secondVersion) = versions[1],
              case .array(let destinations)? = secondVersion["testDestinations"],
              case .object(let destination)? = destinations.first else {
            Issue.record("Expected Xcode-version projections")
            return
        }
        #expect(firstVersion["testDestinations"] == .array([]))
        #expect(firstVersion["testDestinationsPresent"] == .bool(false))
        #expect(secondVersion["testDestinationsPresent"] == .bool(true))
        #expect(destination["availableRuntimes"] == .array([]))
        #expect(destination["availableRuntimesPresent"] == .bool(false))
    }

    @Test("included resources stay within the exact requested relationship lineage")
    func includedResourcesStayWithinRequestedLineage() async throws {
        let productQuery = ["include": "app"]
        let productSelfURL = xcodeCloudWorkerURL(
            path: "/v1/ciProducts/product-1",
            query: productQuery
        )

        for (includedID, expectsError) in [("app-1", false), ("app-2", true)] {
            let transport = XcodeCloudMockTransport(body: """
            {
              "data": {
                "type": "ciProducts",
                "id": "product-1",
                "relationships": {
                  "app": { "data": { "type": "apps", "id": "app-1" } }
                },
                "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
              },
              "included": [{
                "type": "apps",
                "id": "\(includedID)",
                "links": { "self": "https://api.example.test/v1/apps/\(includedID)" }
              }],
              "links": { "self": "\(productSelfURL)" }
            }
            """)
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 1
            )
            let result = try await XcodeCloudWorker(httpClient: client).handleTool(.init(
                name: "xcode_cloud_products_get",
                arguments: [
                    "product_id": .string("product-1"),
                    "include": .string("app")
                ]
            ))

            #expect((result.isError == true) == expectsError)
        }

        let buildRunQuery = ["include": "sourceBranchOrTag"]
        let buildRunSelfURL = xcodeCloudWorkerURL(
            path: "/v1/ciBuildRuns/run-1",
            query: buildRunQuery
        )
        let buildRunTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciBuildRuns",
            "id": "run-1",
            "relationships": {
              "sourceBranchOrTag": {
                "data": { "type": "scmGitReferences", "id": "branch-1" }
              },
              "destinationBranch": {
                "data": { "type": "scmGitReferences", "id": "branch-2" }
              }
            },
            "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
          },
          "included": [{
            "type": "scmGitReferences",
            "id": "branch-2",
            "links": { "self": "https://api.example.test/v1/scmGitReferences/branch-2" }
          }],
          "links": { "self": "\(buildRunSelfURL)" }
        }
        """)
        let buildRunClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: buildRunTransport,
            maxRetries: 1
        )
        let buildRunResult = try await XcodeCloudWorker(httpClient: buildRunClient).handleTool(.init(
            name: "xcode_cloud_build_runs_get",
            arguments: [
                "build_run_id": .string("run-1"),
                "include": .string("sourceBranchOrTag")
            ]
        ))

        #expect(buildRunResult.isError == true)
    }

    @Test("relationship links reject wrong origins parents and schema-absent links")
    func relationshipLinksRemainParentScoped() async throws {
        let relationships = [
            """
            "workflows": {
              "links": {
                "self": "https://api.example.test/v1/ciProducts/product-2/relationships/workflows",
                "related": "https://api.example.test/v1/ciProducts/product-1/workflows"
              }
            }
            """,
            """
            "workflows": {
              "links": {
                "self": "https://api.example.test/v1/ciProducts/product-1/relationships/workflows",
                "related": "https://evil.example/v1/ciProducts/product-1/workflows"
              }
            }
            """,
            """
            "bundleId": {
              "data": { "type": "bundleIds", "id": "bundle-1" },
              "links": { "related": "https://api.example.test/v1/ciProducts/product-1/bundleId" }
            }
            """
        ]

        for relationship in relationships {
            let transport = XcodeCloudMockTransport(body: """
            {
              "data": {
                "type": "ciProducts",
                "id": "product-1",
                "relationships": { \(relationship) },
                "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
              },
              "links": { "self": "https://api.example.test/v1/ciProducts/product-1" }
            }
            """)
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 1
            )
            let result = try await XcodeCloudWorker(httpClient: client).handleTool(.init(
                name: "xcode_cloud_products_get",
                arguments: ["product_id": .string("product-1")]
            ))

            #expect(result.isError == true)
        }
    }

    @Test("list handlers reject duplicate data identities")
    func listHandlersRejectDuplicateDataIdentities() async throws {
        let selfURL = xcodeCloudWorkerURL(path: "/v1/ciProducts", query: ["limit": "25"])
        let transport = XcodeCloudMockTransport(body: """
        {
          "data": [
            { "type": "ciProducts", "id": "product-1" },
            { "type": "ciProducts", "id": "product-1" }
          ],
          "links": { "self": "\(selfURL)" },
          "meta": { "paging": { "total": 2, "limit": 25 } }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let result = try await XcodeCloudWorker(httpClient: client).handleTool(.init(
            name: "xcode_cloud_products_list",
            arguments: [:]
        ))

        #expect(result.isError == true)
    }

    @Test("Xcode Cloud manifest records conditional build start branches")
    func buildStartManifestConditions() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mapping = try #require(manifest.mapping(for: "xcode_cloud_build_runs_start"))
        let inputs = try #require(mapping.operations.first?.inputs)
        let byPointer = Dictionary(uniqueKeysWithValues: inputs.compactMap { input in
            input.jsonPointer.map { ($0, input.localRole ?? "") }
        })

        #expect(byPointer["/data/relationships/workflow/data/type"] == "presentOnlyWithWorkflowId")
        #expect(byPointer["/data/relationships/buildRun/data/type"] == "presentOnlyWithBuildRunId")
        #expect(byPointer["/data/relationships/sourceBranchOrTag/data/type"] == "presentOnlyWithSourceBranchOrTagId")
        #expect(byPointer["/data/relationships/pullRequest/data/type"] == "presentOnlyWithPullRequestId")
        let fieldRoles = Dictionary(uniqueKeysWithValues: mapping.fields.map {
            ($0.toolField, $0.localRole ?? "")
        })
        #expect(fieldRoles["workflow_id"] == "exactlyOneRunSelector")
        #expect(fieldRoles["build_run_id"] == "exactlyOneRunSelector")
        #expect(fieldRoles["source_branch_or_tag_id"] == "atMostOneSourceSelector")
        #expect(fieldRoles["pull_request_id"] == "atMostOneSourceSelector")
        #expect(mapping.note?.contains("exactly one of workflow_id and build_run_id") == true)
    }
}

private func xcodeCloudWorkerURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct Xcode Cloud test URL")
    }
    return url.absoluteString
}

private actor XcodeCloudMockTransport: HTTPTransport {
    private let body: String
    private let continuationBody: String?
    private var request: URLRequest?

    init(body: String, continuationBody: String? = nil) {
        self.body = body
        self.continuationBody = continuationBody
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: request.httpMethod == "POST" ? 201 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        let hasCursor = URLComponents(
            url: request.url ?? URL(string: "https://api.example.test")!,
            resolvingAgainstBaseURL: false
        )?.queryItems?.contains { $0.name == "cursor" } == true
        let responseBody = hasCursor ? continuationBody ?? body : body
        return (Data(responseBody.utf8), response)
    }

    func lastMethod() -> String? {
        request?.httpMethod
    }

    func lastPath() -> String? {
        request?.url?.path
    }

    func lastBodyString() -> String {
        request?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
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
