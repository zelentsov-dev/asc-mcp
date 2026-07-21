import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Input Validation Contract Tests")
struct XcodeCloudInputValidationContractTests {
    @Test("every existing public schema is closed")
    func existingSchemasAreClosed() async throws {
        let worker = XcodeCloudWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()

        for tool in tools {
            guard case .object(let schema) = ToolMetadataPolicy.apply(to: tool).inputSchema else {
                Issue.record("Expected object schema for \(tool.name)")
                continue
            }
            #expect(schema["additionalProperties"] == .bool(false), "Open schema for \(tool.name)")
        }
    }

    @Test("unknown arguments fail before transport")
    func unknownArgumentsFailBeforeTransport() async throws {
        for invocation in [
            XcodeCloudValidationInvocation(tool: "xcode_cloud_products_list", arguments: [:]),
            XcodeCloudValidationInvocation(
                tool: "xcode_cloud_products_get",
                arguments: ["product_id": .string("product-1")]
            ),
            XcodeCloudValidationInvocation(
                tool: "xcode_cloud_build_runs_start",
                arguments: ["workflow_id": .string("workflow-1")]
            )
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport)
            var arguments = invocation.arguments
            arguments["typo_parameter"] = .string("ignored-before-hardening")

            let result = try await worker.handleTool(
                CallTool.Parameters(name: invocation.tool, arguments: arguments)
            )

            #expect(result.isError == true, "Unknown key was accepted by \(invocation.tool)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("all existing collection tools reject invalid limits before transport")
    func listLimitsAreStrict() async throws {
        let invocations = xcodeCloudListValidationInvocations()
        for invocation in invocations {
            for invalidLimit in [Value.int(0), .int(201), .string("25")] {
                let transport = TestHTTPTransport(responses: [])
                let worker = try await makeWorker(transport)
                var arguments = invocation.arguments
                arguments["limit"] = invalidLimit

                let result = try await worker.handleTool(
                    CallTool.Parameters(name: invocation.tool, arguments: arguments)
                )

                #expect(result.isError == true, "Invalid limit was accepted by \(invocation.tool)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("all existing path identifiers must be canonical")
    func pathIdentifiersAreCanonical() async throws {
        for invocation in xcodeCloudIDValidationInvocations() {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport)
            var arguments = invocation.arguments
            arguments[invocation.idField] = .string("bad/id")

            let result = try await worker.handleTool(
                CallTool.Parameters(name: invocation.tool, arguments: arguments)
            )

            #expect(result.isError == true, "Noncanonical ID was accepted by \(invocation.tool)")
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("include rejects mixed, duplicate, and unsupported values")
    func includeIsStrict() async throws {
        for include in [
            Value.array([.string("app"), .int(1)]),
            .array([.string("app"), .string("app")]),
            .string("unsupported")
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeWorker(transport)
            let result = try await worker.handleTool(
                CallTool.Parameters(
                    name: "xcode_cloud_products_list",
                    arguments: ["include": include]
                )
            )

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    private func makeWorker(_ transport: TestHTTPTransport) async throws -> XcodeCloudWorker {
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        return XcodeCloudWorker(httpClient: client)
    }
}

private struct XcodeCloudValidationInvocation {
    let tool: String
    let arguments: [String: Value]
}

private struct XcodeCloudIDValidationInvocation {
    let tool: String
    let idField: String
    let arguments: [String: Value]
}

private func xcodeCloudListValidationInvocations() -> [XcodeCloudValidationInvocation] {
    [
        .init(tool: "xcode_cloud_products_list", arguments: [:]),
        .init(tool: "xcode_cloud_product_workflows_list", arguments: ["product_id": .string("product-1")]),
        .init(tool: "xcode_cloud_product_build_runs_list", arguments: ["product_id": .string("product-1")]),
        .init(tool: "xcode_cloud_workflow_build_runs_list", arguments: ["workflow_id": .string("workflow-1")]),
        .init(tool: "xcode_cloud_build_run_actions_list", arguments: ["build_run_id": .string("run-1")]),
        .init(tool: "xcode_cloud_build_run_builds_list", arguments: ["build_run_id": .string("run-1")]),
        .init(tool: "xcode_cloud_action_artifacts_list", arguments: ["action_id": .string("action-1")]),
        .init(tool: "xcode_cloud_action_issues_list", arguments: ["action_id": .string("action-1")]),
        .init(tool: "xcode_cloud_action_test_results_list", arguments: ["action_id": .string("action-1")]),
        .init(tool: "xcode_cloud_xcode_versions_list", arguments: [:]),
        .init(tool: "xcode_cloud_macos_versions_list", arguments: [:]),
        .init(tool: "xcode_cloud_scm_providers_list", arguments: [:]),
        .init(tool: "xcode_cloud_scm_provider_repositories_list", arguments: ["provider_id": .string("provider-1")]),
        .init(tool: "xcode_cloud_scm_repositories_list", arguments: [:]),
        .init(tool: "xcode_cloud_scm_repository_git_references_list", arguments: ["repository_id": .string("repository-1")]),
        .init(tool: "xcode_cloud_scm_repository_pull_requests_list", arguments: ["repository_id": .string("repository-1")])
    ]
}

private func xcodeCloudIDValidationInvocations() -> [XcodeCloudIDValidationInvocation] {
    [
        .init(tool: "xcode_cloud_products_get", idField: "product_id", arguments: [:]),
        .init(tool: "xcode_cloud_product_workflows_list", idField: "product_id", arguments: [:]),
        .init(tool: "xcode_cloud_product_build_runs_list", idField: "product_id", arguments: [:]),
        .init(tool: "xcode_cloud_workflows_get", idField: "workflow_id", arguments: [:]),
        .init(tool: "xcode_cloud_workflow_build_runs_list", idField: "workflow_id", arguments: [:]),
        .init(tool: "xcode_cloud_build_runs_get", idField: "build_run_id", arguments: [:]),
        .init(tool: "xcode_cloud_build_runs_start", idField: "workflow_id", arguments: [:]),
        .init(tool: "xcode_cloud_build_run_actions_list", idField: "build_run_id", arguments: [:]),
        .init(tool: "xcode_cloud_build_run_builds_list", idField: "build_run_id", arguments: [:]),
        .init(tool: "xcode_cloud_actions_get", idField: "action_id", arguments: [:]),
        .init(tool: "xcode_cloud_action_artifacts_list", idField: "action_id", arguments: [:]),
        .init(tool: "xcode_cloud_action_issues_list", idField: "action_id", arguments: [:]),
        .init(tool: "xcode_cloud_action_test_results_list", idField: "action_id", arguments: [:]),
        .init(tool: "xcode_cloud_artifacts_get", idField: "artifact_id", arguments: [:]),
        .init(tool: "xcode_cloud_issues_get", idField: "issue_id", arguments: [:]),
        .init(tool: "xcode_cloud_test_results_get", idField: "test_result_id", arguments: [:]),
        .init(tool: "xcode_cloud_xcode_versions_get", idField: "xcode_version_id", arguments: [:]),
        .init(tool: "xcode_cloud_macos_versions_get", idField: "macos_version_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_providers_get", idField: "provider_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_provider_repositories_list", idField: "provider_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_repositories_get", idField: "repository_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_repository_git_references_list", idField: "repository_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_repository_pull_requests_list", idField: "repository_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_git_references_get", idField: "git_reference_id", arguments: [:]),
        .init(tool: "xcode_cloud_scm_pull_requests_get", idField: "pull_request_id", arguments: [:])
    ]
}
