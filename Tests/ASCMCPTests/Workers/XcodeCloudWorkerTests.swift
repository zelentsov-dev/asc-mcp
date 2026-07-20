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
          "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1" }
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
            "id": "run-2",
            "relationships": {
              "buildRun": { "data": { "type": "ciBuildRuns", "id": "run-1" } }
            }
          }
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
        let nextURL =
            "https://api.example.test/v1/ciProducts?cursor=abc&limit=1" +
            "&filter%5BproductType%5D=APP&filter%5Bapp%5D=app-1" +
            "&include=app%2CprimaryRepositories"
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
            }
          }],
          "links": {
            "self": "https://api.example.test/v1/ciProducts?limit=1",
            "next": "\(nextURL)"
          },
          "meta": { "paging": { "total": 12, "limit": 1 } }
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
        #expect(queryItems["limit"] == "1")
        #expect(queryItems["filter[productType]"] == "APP")
        #expect(queryItems["filter[app]"] == "app-1")
        #expect(queryItems["include"] == "app,primaryRepositories")

        guard case .object(let root)? = result.structuredContent,
              case .array(let products)? = root["products"],
              case .object(let product)? = products.first else {
            Issue.record("Expected structured products array")
            return
        }
        #expect(root["count"] == .int(1))
        #expect(root["total"] == .int(12))
        #expect(product["id"] == .string("product-1"))
        #expect(product["appId"] == .string("app-1"))
        #expect(product["workflowIds"] == .null)
        #expect(product["workflowsUrl"] == .string("https://api.example.test/v1/ciProducts/product-1/workflows"))
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
          }
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
          }
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
          }
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
            }
          }
        }
        """.utf8)
        let provider = try JSONDecoder().decode(ASCScmProviderResponse.self, from: providerJSON)
        #expect(provider.data.attributes?.scmProviderType?.kind == "GITHUB_CLOUD")
        #expect(provider.data.attributes?.scmProviderType?.displayName == "GitHub")
        #expect(provider.data.attributes?.scmProviderType?.isOnPremise == false)
        #expect(provider.data.relationships?.repositories?.data == nil)
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
            }
          }
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
        #expect(provider["repositoryIds"] == .null)
        #expect(provider["repositoriesUrl"] == .string("https://api.example.test/v1/scmProviders/provider-1/repositories"))

        let testResultTransport = XcodeCloudMockTransport(body: """
        {
          "data": {
            "type": "ciTestResults",
            "id": "test-1",
            "attributes": {
              "name": "testExample",
              "fileSource": { "path": "Tests/AppTests.swift", "lineNumber": 17 },
              "destinationTestResults": [{
                "uuid": "destination-1",
                "deviceName": "iPhone 17 Pro",
                "osVersion": "26.0",
                "status": "PASSED",
                "duration": 1.25
              }]
            }
          }
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
        #expect(destination["uuid"] == .string("destination-1"))
        #expect(destination["message"] == nil)
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

private actor XcodeCloudMockTransport: HTTPTransport {
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
