import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Mutation Contract Tests")
struct XcodeCloudMutationContractTests {
    @Test("mutation schemas are strict through nested Apple request objects")
    func strictMutationSchemas() async throws {
        let worker = XcodeCloudWorker(httpClient: try await TestFactory.makeHTTPClient())
        let create = try xcSchemaObject(worker.workflowsCreateTool().inputSchema)
        #expect(create["additionalProperties"] == .bool(false))
        let properties = try xcSchemaObject(create["properties"])
        let actions = try xcSchemaObject(properties["actions"])
        let action = try xcSchemaObject(actions["items"])
        #expect(action["additionalProperties"] == .bool(false))
        let actionProperties = try xcSchemaObject(action["properties"])
        let configuration = try xcSchemaObject(actionProperties["test_configuration"])
        #expect(configuration["additionalProperties"] == .bool(false))
        let branch = try xcSchemaObject(properties["branch_start_condition"])
        #expect(branch["additionalProperties"] == .bool(false))
        let branchProperties = try xcSchemaObject(branch["properties"])
        let source = try xcSchemaObject(branchProperties["source"])
        #expect(source["additionalProperties"] == .bool(false))

        let update = try xcSchemaObject(worker.workflowsUpdateTool().inputSchema)
        let updateProperties = try xcSchemaObject(update["properties"])
        let description = try xcSchemaObject(updateProperties["description"])
        #expect(description["type"] == .array([.string("string"), .string("null")]))
        let updateActions = try xcSchemaObject(updateProperties["actions"])
        #expect(updateActions["type"] == .array([.string("array"), .string("null")]))
    }

    @Test("create rejects unknown nested input without making a request")
    func createUnknownNestedFieldIsZeroRequest() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [])
        let worker = try await makeWorker(transport)
        var arguments = Self.createArguments
        arguments["actions"] = .array([.object([
            "action_type": .string("ARCHIVE"),
            "unknown": .bool(true)
        ])])

        let result = try await worker.createWorkflow(.init(
            name: "xcode_cloud_workflows_create",
            arguments: arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requests().isEmpty)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("not_attempted"))
        #expect(root["retrySafe"] == .bool(false))
    }

    @Test("create treats a wrong accepted 2xx status as committed unverified")
    func createWrongStatusIsCommittedUnverified() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.createdWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.createWorkflow(.init(
            name: "xcode_cloud_workflows_create",
            arguments: Self.createArguments
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["retrySafe"] == .bool(false))
        #expect(await transport.requests().map(\.method) == ["POST"])
    }

    @Test("create commits only an exact HTTP 201 response")
    func createExactResponseCommits() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 201, body: Self.createdWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.createWorkflow(.init(
            name: "xcode_cloud_workflows_create",
            arguments: Self.createArguments
        ))

        #expect(result.isError != true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["statusCode"] == .int(201))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["self_url"] == .string("https://api.example.test/v1/ciWorkflows/workflow-1"))
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["POST"])
        #expect(requests[0].path == "/v1/ciWorkflows")
        let body = try xcJSONObject(requests[0].body)
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["type"] as? String == "ciWorkflows")
        #expect(data["id"] == nil)
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.keys.sorted() == [
            "actions", "clean", "containerFilePath", "description", "isEnabled", "name"
        ])
        #expect(attributes["name"] as? String == "Release")
        #expect(attributes["description"] as? String == "Release workflow")
        #expect((attributes["actions"] as? [Any])?.isEmpty == true)
        #expect(attributes["isEnabled"] as? Bool == true)
        #expect(attributes["clean"] as? Bool == true)
        #expect(attributes["containerFilePath"] as? String == "App.xcodeproj")
        let relationships = try #require(data["relationships"] as? [String: Any])
        #expect(relationships.keys.sorted() == ["macOsVersion", "product", "repository", "xcodeVersion"])
        let product = try xcRelationshipTypeAndID(relationships["product"])
        let repository = try xcRelationshipTypeAndID(relationships["repository"])
        let xcodeVersion = try xcRelationshipTypeAndID(relationships["xcodeVersion"])
        let macOSVersion = try xcRelationshipTypeAndID(relationships["macOsVersion"])
        #expect(product.type == "ciProducts" && product.id == "product-1")
        #expect(repository.type == "scmRepositories" && repository.id == "repository-1")
        #expect(xcodeVersion.type == "ciXcodeVersions" && xcodeVersion.id == "xcode-1")
        #expect(macOSVersion.type == "ciMacOsVersions" && macOSVersion.id == "macos-1")
    }

    @Test("ambiguous create remains unknown and performs no follow-up read")
    func ambiguousCreateRemainsUnknown() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [.network("connection lost")])
        let worker = try await makeWorker(transport)

        let result = try await worker.createWorkflow(.init(
            name: "xcode_cloud_workflows_create",
            arguments: Self.createArguments
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("unknown"))
        #expect(root["retrySafe"] == .bool(false))
        guard case .object(let identifiers)? = root["identifiers"] else {
            Issue.record("Expected public create identifiers")
            return
        }
        #expect(identifiers.keys.sorted() == [
            "macos_version_id", "product_id", "repository_id", "xcode_version_id"
        ])
        #expect(identifiers["product_id"] == .string("product-1"))
        #expect(identifiers["repository_id"] == .string("repository-1"))
        #expect(identifiers["xcode_version_id"] == .string("xcode-1"))
        #expect(identifiers["macos_version_id"] == .string("macos-1"))
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["POST"])
        #expect(requests[0].path == "/v1/ciWorkflows")
    }

    @Test("update preserves explicit null but rejects null in Apple's non-null response fields")
    func updatePreservesExplicitNull() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.nullUpdatedWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "description": .null,
                "tag_start_condition": .null,
                "is_enabled": .bool(false)
            ]
        ))

        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["PATCH"])
        #expect(requests[0].path == "/v1/ciWorkflows/workflow-1")
        let body = try xcJSONObject(requests[0].body)
        let data = try #require(body["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.keys.sorted() == ["description", "isEnabled", "tagStartCondition"])
        #expect(attributes["description"] is NSNull)
        #expect(attributes["tagStartCondition"] is NSNull)
        #expect(attributes["isEnabled"] as? Bool == false)
        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["operationCommitted"] == .bool(true))
    }

    @Test("empty update is rejected before transport")
    func emptyUpdateIsZeroRequest() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: ["workflow_id": .string("workflow-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requests().isEmpty)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("not_attempted"))
    }

    @Test("malformed accepted update identity or links is committed unverified")
    func malformedUpdateResponseIsCommittedUnverified() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.wrongLinkedWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "is_enabled": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(await transport.requests().map(\.method) == ["PATCH"])
    }

    @Test("PATCH nested response extras cannot verify a partial composite request")
    func updateNestedResponseExtrasAreCommittedUnverified() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.expandedBranchConditionWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "branch_start_condition": .object([:])
            ]
        ))

        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["PATCH"])
        let body = try xcJSONObject(requests[0].body)
        let data = try #require(body["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        let requestedCondition = try #require(attributes["branchStartCondition"] as? [String: Any])
        #expect(requestedCondition.isEmpty)
        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["retrySafe"] == .bool(false))
    }

    @Test("accepted update rejects a wrong type in an unrequested relationship")
    func updateValidatesUnrequestedRelationshipTypes() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.wrongRelationshipWorkflow)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "is_enabled": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(await transport.requests().map(\.method) == ["PATCH"])
    }

    @Test("accepted update recursively validates unrequested workflow attributes")
    func updateValidatesUnrequestedNestedAttributes() async throws {
        let cases: [(String, String)] = [
            (
                "malformed action",
                Self.updatedWorkflowResponse(attributeSuffix: #","actions":[42]"#)
            ),
            (
                "malformed condition",
                Self.updatedWorkflowResponse(
                    attributeSuffix: #","branchStartCondition":{"autoCancel":"yes"}"#
                )
            )
        ]
        for (label, body) in cases {
            let transport = XcodeCloudMutationContractTransport(steps: [
                .response(status: 200, body: body)
            ])
            let worker = try await makeWorker(transport)

            let result = try await worker.updateWorkflow(.init(
                name: "xcode_cloud_workflows_update",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "is_enabled": .bool(false)
                ]
            ))

            #expect(result.isError == true, "Expected \(label) to fail response validation")
            let root = try xcResultObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            let requests = await transport.requests()
            #expect(requests.map(\.method) == ["PATCH"])
            #expect(requests[0].path == "/v1/ciWorkflows/workflow-1")
        }
    }

    @Test("accepted update validates workflow relationship link shape and scope")
    func updateValidatesRelationshipLinks() async throws {
        let cases: [(String, String)] = [
            (
                "non-object links",
                Self.updatedWorkflowResponse(dataSuffix: #","relationships":{"repository":{"links":42}}"#)
            ),
            (
                "wrong-origin links",
                Self.updatedWorkflowResponse(
                    dataSuffix: #","relationships":{"repository":{"links":{"self":"https://evil.example/v1/ciWorkflows/workflow-1/relationships/repository"}}}"#
                )
            ),
            (
                "unsupported product links",
                Self.updatedWorkflowResponse(
                    dataSuffix: #","relationships":{"product":{"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/relationships/product"}}}"#
                )
            )
        ]
        for (label, body) in cases {
            let transport = XcodeCloudMutationContractTransport(steps: [
                .response(status: 200, body: body)
            ])
            let worker = try await makeWorker(transport)

            let result = try await worker.updateWorkflow(.init(
                name: "xcode_cloud_workflows_update",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "is_enabled": .bool(false)
                ]
            ))

            #expect(result.isError == true, "Expected \(label) to fail response validation")
            let root = try xcResultObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(await transport.requests().map(\.method) == ["PATCH"])
        }
    }

    @Test("valid workflow included union is preserved with document self URL")
    func updatePreservesValidIncludedResources() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(
                status: 200,
                body: Self.updatedWorkflowResponse(included: Self.validWorkflowIncluded)
            )
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "is_enabled": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["self_url"] == .string("https://api.example.test/v1/ciWorkflows/workflow-1"))
        guard case .array(let included)? = root["included"] else {
            Issue.record("Expected preserved included resources")
            return
        }
        #expect(included.count == 4)
        let types = included.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let type)? = object["type"] else { return nil }
            return type
        }
        #expect(types == ["ciMacOsVersions", "ciProducts", "ciXcodeVersions", "scmRepositories"])
        guard case .object(let repository) = included[3],
              case .object(let futureField)? = repository["futureField"] else {
            Issue.record("Expected additive included fields to be preserved")
            return
        }
        #expect(futureField["preserved"] == .bool(true))
        #expect(await transport.requests().map(\.method) == ["PATCH"])
    }

    @Test("present empty workflow included array is preserved")
    func updatePreservesEmptyIncludedArray() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .response(status: 200, body: Self.updatedWorkflowResponse(included: "[]"))
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.updateWorkflow(.init(
            name: "xcode_cloud_workflows_update",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "is_enabled": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["included"] == .array([]))
    }

    @Test("malformed workflow included resources are committed unverified")
    func updateRejectsMalformedIncludedResources() async throws {
        let cases: [(String, String)] = [
            ("explicit null", "null"),
            ("wrong union type", #"[{"type":"ciWorkflows","id":"workflow-included"}]"#),
            (
                "duplicate identity",
                #"[{"type":"ciProducts","id":"product-included"},{"type":"ciProducts","id":"product-included"}]"#
            ),
            (
                "malformed known attribute",
                #"[{"type":"ciProducts","id":"product-included","attributes":{"productType":"TOOL"}}]"#
            ),
            (
                "hostile relationship link",
                #"[{"type":"ciXcodeVersions","id":"xcode-included","relationships":{"macOsVersions":{"links":{"self":"https://evil.example/v1/ciXcodeVersions/xcode-included/relationships/macOsVersions"}}}}]"#
            ),
            (
                "duplicate to-many identifier",
                #"[{"type":"ciMacOsVersions","id":"macos-included","relationships":{"xcodeVersions":{"data":[{"type":"ciXcodeVersions","id":"xcode-1"},{"type":"ciXcodeVersions","id":"xcode-1"}]}}}]"#
            ),
            (
                "page exceeds relationship limit",
                #"[{"type":"ciMacOsVersions","id":"macos-included","relationships":{"xcodeVersions":{"data":[{"type":"ciXcodeVersions","id":"xcode-1"},{"type":"ciXcodeVersions","id":"xcode-2"}],"meta":{"paging":{"total":2,"limit":1}}}}}]"#
            ),
            (
                "blank relationship cursor",
                #"[{"type":"ciMacOsVersions","id":"macos-included","relationships":{"xcodeVersions":{"meta":{"paging":{"limit":1,"nextCursor":"   "}}}}}]"#
            )
        ]
        for (label, included) in cases {
            let transport = XcodeCloudMutationContractTransport(steps: [
                .response(
                    status: 200,
                    body: Self.updatedWorkflowResponse(included: included)
                )
            ])
            let worker = try await makeWorker(transport)

            let result = try await worker.updateWorkflow(.init(
                name: "xcode_cloud_workflows_update",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "is_enabled": .bool(false)
                ]
            ))

            #expect(result.isError == true, "Expected \(label) to fail response validation")
            let root = try xcResultObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(await transport.requests().map(\.method) == ["PATCH"])
        }
    }

    @Test("accepted response rejects explicit null resource containers")
    func updateRejectsExplicitNullResourceContainers() async throws {
        let cases: [(String, String)] = [
            ("relationships", Self.updatedWorkflowResponse(dataSuffix: #","relationships":null"#)),
            ("links", Self.updatedWorkflowResponse(dataSuffix: #","links":null"#)),
            ("resource links self", Self.updatedWorkflowResponse(dataSuffix: #","links":{"self":null}"#))
        ]
        for (label, body) in cases {
            let transport = XcodeCloudMutationContractTransport(steps: [
                .response(status: 200, body: body)
            ])
            let worker = try await makeWorker(transport)

            let result = try await worker.updateWorkflow(.init(
                name: "xcode_cloud_workflows_update",
                arguments: [
                    "workflow_id": .string("workflow-1"),
                    "is_enabled": .bool(false)
                ]
            ))

            #expect(result.isError == true, "Expected explicit null \(label) to fail response validation")
            let root = try xcResultObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("committed_unverified"))
            #expect(await transport.requests().map(\.method) == ["PATCH"])
        }
    }

    @Test("workflow deletion confirmation mismatch never sends DELETE")
    func workflowDeletionMismatchIsZeroDelete() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns)
        ])
        let worker = try await makeWorker(transport)

        let result = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string("stale"),
                "expected_workflow_name": .string("Release"),
                "expected_build_run_count": .int(0)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requests().map(\.method) == ["GET", "GET"])
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("not_attempted"))
    }

    @Test("deterministic workflow DELETE rejection remains rejected")
    func workflowDeleteRejectionRemainsRejected() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .response(status: 403, body: Self.forbidden)
        ])
        let worker = try await makeWorker(transport)
        let preview = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let confirmation = try xcConfirmation(preview)

        let result = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string(confirmation.receipt),
                "expected_workflow_name": .string("Release"),
                "expected_build_run_count": .int(0)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("rejected"))
        #expect(root["retrySafe"] == .bool(false))
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["GET", "GET", "GET", "GET", "DELETE"])
        #expect(requests[4].path == "/v1/ciWorkflows/workflow-1")
    }

    @Test("valid workflow confirmation and empty HTTP 204 commit deletion")
    func workflowDeleteExact204Commits() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .response(status: 204, body: "")
        ])
        let worker = try await makeWorker(transport)
        let preview = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let confirmation = try xcConfirmation(preview)

        let result = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string(confirmation.receipt),
                "expected_workflow_name": .string(confirmation.name),
                "expected_build_run_count": .int(confirmation.count)
            ]
        ))

        #expect(result.isError != true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["write_outcome"] == .string("committed"))
        #expect(root["statusCode"] == .int(204))
        #expect(root["deleted"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(await transport.requests().map(\.method) == ["GET", "GET", "GET", "GET", "DELETE"])
    }

    @Test("nonempty HTTP 204 deletion response is committed unverified")
    func workflowDeleteNonempty204IsCommittedUnverified() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .json(Self.workflow),
            .json(Self.emptyWorkflowBuildRuns),
            .response(status: 204, body: #"{"unexpected":true}"#)
        ])
        let worker = try await makeWorker(transport)
        let preview = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let confirmation = try xcConfirmation(preview)

        let result = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string(confirmation.receipt),
                "expected_workflow_name": .string(confirmation.name),
                "expected_build_run_count": .int(confirmation.count)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["write_outcome"] == .string("committed_unverified"))
        #expect(root["retrySafe"] == .bool(false))
        #expect(await transport.requests().map(\.method) == ["GET", "GET", "GET", "GET", "DELETE"])
    }

    @Test("two-page workflow deletion preflight accumulates exact count and receipt")
    func workflowDeleteTwoPagePreflight() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.workflowBuildRunsFirstPage),
            .json(Self.workflowBuildRunsSecondPage)
        ])
        let worker = try await makeWorker(transport)

        let preview = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: ["workflow_id": .string("workflow-1")]
        ))

        #expect(preview.isError != true)
        let root = try xcResultObject(preview.structuredContent)
        #expect(root["buildRunCount"] == .int(2))
        let confirmation = try xcConfirmation(preview)
        #expect(confirmation.count == 2)
        #expect(confirmation.receipt.hasPrefix("xcode-cloud-delete-v1:"))
        #expect(confirmation.receipt.count > "xcode-cloud-delete-v1:".count)
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["GET", "GET", "GET"])
        #expect(requests[1].query == [
            "limit": "200",
            "fields[ciBuildRuns]": "number"
        ])
        #expect(requests[2].query == [
            "limit": "200",
            "fields[ciBuildRuns]": "number",
            "cursor": "page-2"
        ])
    }

    @Test("two-page deletion preflight rejects duplicate IDs and total drift")
    func workflowDeleteTwoPageAdversarialCounts() async throws {
        let cases: [(String, String)] = [
            ("duplicate", Self.workflowBuildRunsDuplicateSecondPage),
            ("total drift", Self.workflowBuildRunsDriftedSecondPage)
        ]
        for (label, secondPage) in cases {
            let transport = XcodeCloudMutationContractTransport(steps: [
                .json(Self.workflow),
                .json(Self.workflowBuildRunsFirstPage),
                .json(secondPage)
            ])
            let worker = try await makeWorker(transport)

            let result = try await worker.deleteWorkflow(.init(
                name: "xcode_cloud_workflows_delete",
                arguments: ["workflow_id": .string("workflow-1")]
            ))

            #expect(result.isError == true, "Expected \(label) to fail closed")
            let root = try xcResultObject(result.structuredContent)
            #expect(root["operationCommitState"] == .string("not_attempted"))
            #expect(await transport.requests().map(\.method) == ["GET", "GET", "GET"])
        }
    }

    @Test("same count with different build-run IDs invalidates a stale deletion receipt")
    func workflowDeleteReceiptBindsExactInventory() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.workflow),
            .json(Self.singleWorkflowBuildRunA),
            .json(Self.workflow),
            .json(Self.singleWorkflowBuildRunB)
        ])
        let worker = try await makeWorker(transport)
        let preview = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: ["workflow_id": .string("workflow-1")]
        ))
        let staleConfirmation = try xcConfirmation(preview)
        #expect(staleConfirmation.count == 1)

        let result = try await worker.deleteWorkflow(.init(
            name: "xcode_cloud_workflows_delete",
            arguments: [
                "workflow_id": .string("workflow-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string(staleConfirmation.receipt),
                "expected_workflow_name": .string(staleConfirmation.name),
                "expected_build_run_count": .int(staleConfirmation.count)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("not_attempted"))
        guard case .object(let latestPreview)? = root["latestPreview"],
              case .string(let freshReceipt)? = latestPreview["confirmationReceipt"] else {
            Issue.record("Expected a fresh deletion receipt")
            return
        }
        #expect(freshReceipt != staleConfirmation.receipt)
        #expect(await transport.requests().map(\.method) == ["GET", "GET", "GET", "GET"])
    }

    @Test("ambiguous product DELETE remains unknown without reconciliation")
    func productDeleteAmbiguityRemainsUnknown() async throws {
        let transport = XcodeCloudMutationContractTransport(steps: [
            .json(Self.product),
            .json(Self.emptyProductWorkflows),
            .json(Self.emptyProductBuildRuns),
            .json(Self.product),
            .json(Self.emptyProductWorkflows),
            .json(Self.emptyProductBuildRuns),
            .network("connection lost during delete")
        ])
        let worker = try await makeWorker(transport)
        let preview = try await worker.deleteProduct(.init(
            name: "xcode_cloud_products_delete",
            arguments: ["product_id": .string("product-1")]
        ))
        let confirmation = try xcProductConfirmation(preview)

        let result = try await worker.deleteProduct(.init(
            name: "xcode_cloud_products_delete",
            arguments: [
                "product_id": .string("product-1"),
                "confirm_permanent_deletion": .bool(true),
                "confirmation_receipt": .string(confirmation.receipt),
                "expected_product_name": .string("App"),
                "expected_workflow_count": .int(0),
                "expected_build_run_count": .int(0)
            ]
        ))

        #expect(result.isError == true)
        let root = try xcResultObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("unknown"))
        #expect(root["retrySafe"] == .bool(false))
        let requests = await transport.requests()
        #expect(requests.last?.method == "DELETE")
        #expect(requests.last?.path == "/v1/ciProducts/product-1")
        #expect(requests[1].query == [
            "limit": "200",
            "fields[ciWorkflows]": "name"
        ])
        #expect(requests[2].query == [
            "limit": "200",
            "fields[ciBuildRuns]": "number"
        ])
        #expect(requests[4].query == requests[1].query)
        #expect(requests[5].query == requests[2].query)
    }

    private func makeWorker(
        _ transport: XcodeCloudMutationContractTransport
    ) async throws -> XcodeCloudWorker {
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        return XcodeCloudWorker(httpClient: client)
    }

    private static let createArguments: [String: Value] = [
        "product_id": .string("product-1"),
        "repository_id": .string("repository-1"),
        "xcode_version_id": .string("xcode-1"),
        "macos_version_id": .string("macos-1"),
        "name": .string("Release"),
        "description": .string("Release workflow"),
        "actions": .array([]),
        "is_enabled": .bool(true),
        "clean": .bool(true),
        "container_file_path": .string("App.xcodeproj")
    ]

    private static func updatedWorkflowResponse(
        attributeSuffix: String = "",
        dataSuffix: String = "",
        included: String? = nil
    ) -> String {
        let includedMember = included.map { #","included":"# + $0 } ?? ""
        return #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"isEnabled":false"#
            + attributeSuffix
            + "}"
            + dataSuffix
            + #"},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}"#
            + includedMember
            + "}"
    }

    private static let validWorkflowIncluded = #"[{"type":"ciMacOsVersions","id":"macos-included","attributes":{"version":"15.0","name":"macOS 15"},"links":{"self":"https://api.example.test/v1/ciMacOsVersions/macos-included"}},{"type":"ciProducts","id":"product-included","attributes":{"name":"App","productType":"APP"},"links":{"self":"https://api.example.test/v1/ciProducts/product-included"}},{"type":"ciXcodeVersions","id":"xcode-included","attributes":{"version":"16.0","name":"Xcode 16","testDestinations":[{"deviceTypeName":"iPhone","deviceTypeIdentifier":"iPhone","kind":"SIMULATOR","availableRuntimes":[{"runtimeName":"iOS 18","runtimeIdentifier":"iOS-18"}]}]},"links":{"self":"https://api.example.test/v1/ciXcodeVersions/xcode-included"}},{"type":"scmRepositories","id":"repository-included","attributes":{"ownerName":"Owner","repositoryName":"Repo","httpCloneUrl":"https://example.test/Owner/Repo.git"},"links":{"self":"https://api.example.test/v1/scmRepositories/repository-included"},"futureField":{"preserved":true}}]"#

    private static let createdWorkflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"name":"Release","description":"Release workflow","actions":[],"isEnabled":true,"clean":true,"containerFilePath":"App.xcodeproj"},"relationships":{"product":{"data":{"type":"ciProducts","id":"product-1"}},"repository":{"data":{"type":"scmRepositories","id":"repository-1"}},"xcodeVersion":{"data":{"type":"ciXcodeVersions","id":"xcode-1"}},"macOsVersion":{"data":{"type":"ciMacOsVersions","id":"macos-1"}}}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}}"#
    private static let nullUpdatedWorkflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"description":null,"tagStartCondition":null,"isEnabled":false,"lastModifiedDate":null}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}}"#
    private static let wrongLinkedWorkflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"isEnabled":false}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-2"}}"#
    private static let expandedBranchConditionWorkflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"branchStartCondition":{"autoCancel":true}}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}}"#
    private static let wrongRelationshipWorkflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"isEnabled":false},"relationships":{"product":{"data":{"type":"ciWorkflows","id":"product-1"}}}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}}"#
    private static let workflow = #"{"data":{"type":"ciWorkflows","id":"workflow-1","attributes":{"name":"Release"}},"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1"}}"#
    private static let product = #"{"data":{"type":"ciProducts","id":"product-1","attributes":{"name":"App"}},"links":{"self":"https://api.example.test/v1/ciProducts/product-1"}}"#
    private static let emptyWorkflowBuildRuns = #"{"data":[],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":0,"limit":200}}}"#
    private static let workflowBuildRunsFirstPage = #"{"data":[{"type":"ciBuildRuns","id":"build-run-1"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number","next":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number&cursor=page-2"},"meta":{"paging":{"total":2,"limit":200,"nextCursor":"page-2"}}}"#
    private static let workflowBuildRunsSecondPage = #"{"data":[{"type":"ciBuildRuns","id":"build-run-2"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number&cursor=page-2","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":2,"limit":200}}}"#
    private static let workflowBuildRunsDuplicateSecondPage = #"{"data":[{"type":"ciBuildRuns","id":"build-run-1"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number&cursor=page-2","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":2,"limit":200}}}"#
    private static let workflowBuildRunsDriftedSecondPage = #"{"data":[{"type":"ciBuildRuns","id":"build-run-2"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number&cursor=page-2","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":3,"limit":200}}}"#
    private static let singleWorkflowBuildRunA = #"{"data":[{"type":"ciBuildRuns","id":"build-run-a"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":1,"limit":200}}}"#
    private static let singleWorkflowBuildRunB = #"{"data":[{"type":"ciBuildRuns","id":"build-run-b"}],"links":{"self":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number","first":"https://api.example.test/v1/ciWorkflows/workflow-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":1,"limit":200}}}"#
    private static let emptyProductWorkflows = #"{"data":[],"links":{"self":"https://api.example.test/v1/ciProducts/product-1/workflows?limit=200&fields%5BciWorkflows%5D=name"},"meta":{"paging":{"total":0,"limit":200}}}"#
    private static let emptyProductBuildRuns = #"{"data":[],"links":{"self":"https://api.example.test/v1/ciProducts/product-1/buildRuns?limit=200&fields%5BciBuildRuns%5D=number"},"meta":{"paging":{"total":0,"limit":200}}}"#
    private static let forbidden = #"{"errors":[{"status":"403","detail":"Forbidden"}]}"#
}

private enum XcodeCloudMutationContractStep: Sendable {
    case response(status: Int, body: String)
    case network(String)

    static func json(_ body: String) -> XcodeCloudMutationContractStep {
        .response(status: 200, body: body)
    }
}

private struct XcodeCloudMutationContractRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data
}

private struct XcodeCloudMutationContractError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor XcodeCloudMutationContractTransport: HTTPTransport {
    private var steps: [XcodeCloudMutationContractStep]
    private var captured: [XcodeCloudMutationContractRequest] = []

    init(steps: [XcodeCloudMutationContractStep]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        captured.append(.init(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            query: Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            }),
            body: request.httpBody ?? Data()
        ))
        guard !steps.isEmpty else {
            throw XcodeCloudMutationContractError(message: "Unexpected request")
        }
        switch steps.removeFirst() {
        case .network(let message):
            throw XcodeCloudMutationContractError(message: message)
        case .response(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (Data(body.utf8), response)
        }
    }

    func requests() -> [XcodeCloudMutationContractRequest] {
        captured
    }
}

private func xcJSONObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func xcRelationshipTypeAndID(_ value: Any?) throws -> (type: String, id: String) {
    let relationship = try #require(value as? [String: Any])
    let data = try #require(relationship["data"] as? [String: Any])
    return (
        type: try #require(data["type"] as? String),
        id: try #require(data["id"] as? String)
    )
}

private func xcResultObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        Issue.record("Expected structured object")
        return [:]
    }
    return object
}

private func xcSchemaObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        Issue.record("Expected schema object")
        return [:]
    }
    return object
}

private func xcConfirmation(_ result: CallTool.Result) throws -> (receipt: String, name: String, count: Int) {
    let root = try xcResultObject(result.structuredContent)
    guard case .object(let confirmation)? = root["confirmation"],
          case .string(let receipt)? = confirmation["confirmationReceipt"],
          case .string(let name)? = confirmation["expectedWorkflowName"],
          case .int(let count)? = confirmation["expectedBuildRunCount"] else {
        Issue.record("Expected workflow confirmation")
        return ("", "", -1)
    }
    return (receipt, name, count)
}

private func xcProductConfirmation(
    _ result: CallTool.Result
) throws -> (receipt: String, name: String, workflowCount: Int, buildRunCount: Int) {
    let root = try xcResultObject(result.structuredContent)
    guard case .object(let confirmation)? = root["confirmation"],
          case .string(let receipt)? = confirmation["confirmationReceipt"],
          case .string(let name)? = confirmation["expectedProductName"],
          case .int(let workflowCount)? = confirmation["expectedWorkflowCount"],
          case .int(let buildRunCount)? = confirmation["expectedBuildRunCount"] else {
        Issue.record("Expected product confirmation")
        return ("", "", -1, -1)
    }
    return (receipt, name, workflowCount, buildRunCount)
}
