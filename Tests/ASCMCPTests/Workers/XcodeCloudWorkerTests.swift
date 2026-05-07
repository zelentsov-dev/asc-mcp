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
              "startReason": "MANUAL"
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

        guard case .object(let root)? = result.structuredContent,
              case .object(let buildRun)? = root["buildRun"] else {
            Issue.record("Expected structured buildRun object")
            return
        }
        #expect(buildRun["id"] == .string("run-1"))
        #expect(buildRun["number"] == .int(42))
        #expect(buildRun["workflowId"] == .string("workflow-1"))
    }

    @Test("list products supports filters, include, and pagination result")
    func listProductsSupportsFiltersAndInclude() async throws {
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
              "primaryRepositories": { "data": [{ "type": "scmRepositories", "id": "repo-1" }] }
            }
          }],
          "links": {
            "self": "https://api.example.test/v1/ciProducts?limit=1",
            "next": "https://api.example.test/v1/ciProducts?cursor=abc&limit=1"
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
}
