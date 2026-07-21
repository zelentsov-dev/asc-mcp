import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("PPO V3.19 Contract Tests")
struct PPOV319ContractTests {
    @Test("PPO exposes only the current 15-tool surface with strict schemas")
    func ppoV319ToolSurface() async throws {
        let worker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(TestHTTPTransport(responses: []))
        )
        let tools = await worker.getTools()
        #expect(tools.count == 15)
        let expected: Set<String> = [
            "ppo_list_experiments",
            "ppo_list_version_experiments",
            "ppo_get_experiment",
            "ppo_create_experiment",
            "ppo_update_experiment",
            "ppo_delete_experiment",
            "ppo_list_treatments",
            "ppo_get_treatment",
            "ppo_create_treatment",
            "ppo_update_treatment",
            "ppo_delete_treatment",
            "ppo_list_treatment_localizations",
            "ppo_get_treatment_localization",
            "ppo_create_treatment_localization",
            "ppo_delete_treatment_localization"
        ]
        #expect(Set(tools.map(\.name)) == expected)
        for tool in tools {
            let schema = try ppoV319Object(tool.inputSchema)
            #expect(schema["additionalProperties"] == .bool(false))
            let properties = try ppoV319Object(schema["properties"])
            for (name, value) in properties where name.hasSuffix("_id") {
                #expect(try ppoV319Object(value)["pattern"] == .string(
                    #"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#
                ))
            }
            if let nextURL = properties["next_url"] {
                let nextURLSchema = try ppoV319Object(nextURL)
                #expect(nextURLSchema["format"] == .string("uri-reference"))
                #expect(nextURLSchema["minLength"] == .int(1))
                #expect(nextURLSchema["pattern"] == .string(
                    #"^(?!.*[\s\u0000-\u001F\u007F]).+$"#
                ))
            }
        }

        let update = try #require(tools.first { $0.name == "ppo_update_experiment" })
        let updateSchema = try ppoV319Object(update.inputSchema)
        let properties = try ppoV319Object(updateSchema["properties"])
        #expect(properties["confirm_experiment_id"] != nil)
        #expect(try ppoV319Array(try ppoV319Object(properties["name"])["type"]) == [
            .string("string"), .string("null")
        ])
        #expect(try ppoV319Array(try ppoV319Object(properties["traffic_proportion"])["type"]) == [
            .string("integer"), .string("null")
        ])
        #expect(updateSchema["anyOf"] != nil)
        #expect(updateSchema["allOf"] != nil)

        let delete = try #require(tools.first { $0.name == "ppo_delete_treatment" })
        #expect(try ppoV319StringSet(try ppoV319Object(delete.inputSchema)["required"]) == [
            "treatment_id", "confirm_treatment_id"
        ])
    }

    @Test("PPO rejects noncanonical IDs and malformed continuations before transport")
    func ppoV319CanonicalInputValidation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))

        for identifier in ["", ".", "..", "bad/id", "bad%2Fid", " spaced "] {
            let result = try await worker.handleTool(.init(
                name: "ppo_get_experiment",
                arguments: ["experiment_id": .string(identifier)]
            ))
            #expect(result.isError == true)
        }
        for continuation in [
            Value.string(""),
            .string(" "),
            .string(" https://api.example.test/v1/apps/app-1/appStoreVersionExperimentsV2?limit=25&cursor=next "),
            .string("not a URL"),
            .int(1)
        ] {
            let result = try await worker.handleTool(.init(
                name: "ppo_list_experiments",
                arguments: [
                    "app_id": .string("app-1"),
                    "next_url": continuation
                ]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("version-scoped list uses the V2 relationship endpoint and preserves continuation lineage")
    func ppoV319VersionScopedList() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: ppoV319ExperimentCollection(path: "/v1/appStoreVersions/version-1/appStoreVersionExperimentsV2"))
        ])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "ppo_list_version_experiments",
            arguments: [
                "version_id": .string("version-1"),
                "limit": .int(17),
                "states": .array([.string("APPROVED"), .string("STOPPED")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/appStoreVersions/version-1/appStoreVersionExperimentsV2")
        let requestURL = try #require(request.url)
        let query = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "limit" }?.value == "17")
        #expect(query.first { $0.name == "filter[state]" }?.value == "APPROVED,STOPPED")
        let root = try ppoV319Object(result.structuredContent)
        #expect(root["versionId"] == .string("version-1"))
        #expect(root["limit"] == .int(17))
    }

    @Test("PPO rejects hostile origins in required self and continuation links")
    func ppoV319RejectsHostileResponseLinks() async throws {
        let hostileSelfTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: ppoV319ExperimentResponse(
                    attributes: #"{"name":"Experiment","platform":"IOS","trafficProportion":50}"#,
                    selfLink: "https://evil.example/v2/appStoreVersionExperiments/experiment-1"
                )
            )
        ])
        let hostileSelfWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(hostileSelfTransport)
        )
        let hostileSelf = try await hostileSelfWorker.handleTool(.init(
            name: "ppo_get_experiment",
            arguments: ["experiment_id": .string("experiment-1")]
        ))
        #expect(hostileSelf.isError == true)

        let path = "/v1/appStoreVersions/version-1/appStoreVersionExperimentsV2"
        let hostileNextTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: """
                {
                  "data": [],
                  "links": {
                    "self": "https://api.example.test\(path)?filter%5Bstate%5D=APPROVED&limit=17",
                    "next": "https://evil.example\(path)?filter%5Bstate%5D=APPROVED&limit=17&cursor=next"
                  },
                  "meta": {"paging": {"total": 0, "limit": 17, "nextCursor": "next"}}
                }
                """
            )
        ])
        let hostileNextWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(hostileNextTransport)
        )
        let hostileNext = try await hostileNextWorker.handleTool(.init(
            name: "ppo_list_version_experiments",
            arguments: [
                "version_id": .string("version-1"),
                "limit": .int(17),
                "states": .string("APPROVED")
            ]
        ))
        #expect(hostileNext.isError == true)
    }

    @Test("experiment update preserves explicit null and rejects no-op and unknown keys")
    func ppoV319ExperimentNullAndNoOp() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: ppoV319ExperimentResponse(attributes: #"{"name":null,"platform":"IOS","trafficProportion":50}"#))
        ])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "name": .null
            ]
        ))
        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let attributes = try ppoV319RequestAttributes(request)
        #expect(attributes.keys.contains("name"))
        #expect(attributes["name"] is NSNull)
        #expect(attributes["trafficProportion"] == nil)
        #expect(attributes["started"] == nil)
        let resultRoot = try ppoV319Object(result.structuredContent)
        #expect(resultRoot["changed"] == .null)
        #expect(resultRoot["changeVerified"] == .bool(false))

        let missingNullTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: ppoV319ExperimentResponse(
                    attributes: #"{"platform":"IOS","trafficProportion":50}"#
                )
            )
        ])
        let missingNullWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(missingNullTransport)
        )
        let missingNull = try await missingNullWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "name": .null
            ]
        ))
        #expect(missingNull.isError == true)
        let missingNullRoot = try ppoV319Object(missingNull.structuredContent)
        #expect(missingNullRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(missingNullRoot["inspectionRequired"] == .bool(true))

        let noOp = try await worker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: ["experiment_id": .string("experiment-1")]
        ))
        let unknown = try await worker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "name": .string("Updated"),
                "legacy_state": .string("START")
            ]
        ))
        #expect(noOp.isError == true)
        #expect(unknown.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("START and STOP require exact experiment confirmation")
    func ppoV319LifecycleConfirmation() async throws {
        let validationTransport = TestHTTPTransport(responses: [])
        let validationWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(validationTransport)
        )

        let missing = try await validationWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "state": .string("START")
            ]
        ))
        let mismatch = try await validationWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "state": .string("STOP"),
                "confirm_experiment_id": .string("experiment-2")
            ]
        ))
        #expect(missing.isError == true)
        #expect(mismatch.isError == true)
        #expect(await validationTransport.requestCount() == 0)

        let startTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: ppoV319ExperimentResponse(
                    attributes: #"{"name":"Experiment","platform":"IOS","trafficProportion":50,"state":"APPROVED"}"#
                )
            )
        ])
        let startWorker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(startTransport))
        let start = try await startWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "state": .string("START"),
                "confirm_experiment_id": .string("experiment-1")
            ]
        ))
        #expect(start.isError == true)
        let startRequest = try #require(await startTransport.recordedRequests().first)
        #expect(try ppoV319RequestAttributes(startRequest)["started"] as? Bool == true)
        let startRoot = try ppoV319Object(start.structuredContent)
        #expect(startRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(startRoot["action"] == .string("START"))
        let startRecovery = try ppoV319Object(startRoot["recovery"])
        #expect(startRecovery["action"] == .string("START"))

        let stopTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: ppoV319ExperimentResponse(
                    attributes: #"{"name":"Experiment","platform":"IOS","trafficProportion":50,"state":"STOPPED"}"#
                )
            )
        ])
        let stopWorker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(stopTransport))
        let stop = try await stopWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "state": .string("STOP"),
                "confirm_experiment_id": .string("experiment-1")
            ]
        ))
        #expect(stop.isError != true)
        let stopRequest = try #require(await stopTransport.recordedRequests().first)
        #expect(try ppoV319RequestAttributes(stopRequest)["started"] as? Bool == false)
        let stopRoot = try ppoV319Object(stop.structuredContent)
        #expect(stopRoot["lifecycleAction"] == .string("STOP"))
        #expect(stopRoot["lifecycleConfirmationMatched"] == .bool(true))
        #expect(stopRoot["changed"] == .null)
        #expect(stopRoot["changeVerified"] == .bool(false))

        let unverifiedStopTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: ppoV319ExperimentResponse(
                    attributes: #"{"name":"Experiment","platform":"IOS","trafficProportion":50,"state":"APPROVED"}"#
                )
            )
        ])
        let unverifiedStopWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(unverifiedStopTransport)
        )
        let unverifiedStop = try await unverifiedStopWorker.handleTool(.init(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-1"),
                "state": .string("STOP"),
                "confirm_experiment_id": .string("experiment-1")
            ]
        ))
        #expect(unverifiedStop.isError == true)
        let unverifiedStopRoot = try ppoV319Object(unverifiedStop.structuredContent)
        #expect(unverifiedStopRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(unverifiedStopRoot["inspectionRequired"] == .bool(true))
    }

    @Test("treatment update preserves null and validates exact status and identity")
    func ppoV319TreatmentUpdate() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: ppoV319TreatmentResponse(attributes: #"{"name":"Variant","appIconName":null}"#))
        ])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "ppo_update_treatment",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "app_icon_name": .null
            ]
        ))
        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/appStoreVersionExperimentTreatments/treatment-1")
        let attributes = try ppoV319RequestAttributes(request)
        #expect(attributes["appIconName"] is NSNull)
        #expect(attributes["name"] == nil)
        let root = try ppoV319Object(result.structuredContent)
        #expect(root["changed"] == .null)
        #expect(root["changeVerified"] == .bool(false))

        let missingNullTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: ppoV319TreatmentResponse(attributes: #"{"name":"Variant"}"#))
        ])
        let missingNullWorker = ProductPageOptimizationWorker(
            httpClient: try await ppoV319Client(missingNullTransport)
        )
        let missingNull = try await missingNullWorker.handleTool(.init(
            name: "ppo_update_treatment",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "app_icon_name": .null
            ]
        ))
        #expect(missingNull.isError == true)
        let missingNullRoot = try ppoV319Object(missingNull.structuredContent)
        #expect(missingNullRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(missingNullRoot["inspectionRequired"] == .bool(true))
    }

    @Test("destructive operations require exact confirmation and exact 204")
    func ppoV319DeleteConfirmationAndStatus() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "{}"),
            .init(statusCode: 204, body: "")
        ])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))
        let missing = try await worker.handleTool(.init(
            name: "ppo_delete_treatment_localization",
            arguments: ["localization_id": .string("localization-1")]
        ))
        #expect(missing.isError == true)
        #expect(await transport.requestCount() == 0)

        let unexpected = try await worker.handleTool(.init(
            name: "ppo_delete_treatment_localization",
            arguments: [
                "localization_id": .string("localization-1"),
                "confirm_localization_id": .string("localization-1")
            ]
        ))
        #expect(unexpected.isError == true)
        let unexpectedRoot = try ppoV319Object(unexpected.structuredContent)
        #expect(unexpectedRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(unexpectedRoot["retrySafe"] == .bool(false))

        let success = try await worker.handleTool(.init(
            name: "ppo_delete_treatment_localization",
            arguments: [
                "localization_id": .string("localization-1"),
                "confirm_localization_id": .string("localization-1")
            ]
        ))
        #expect(success.isError != true)
        let successRoot = try ppoV319Object(success.structuredContent)
        #expect(successRoot["statusCode"] == .int(204))
        #expect(successRoot["confirmationMatched"] == .bool(true))
    }

    @Test("ambiguous mutation failures are fail-closed and include exact recovery")
    func ppoV319AmbiguousWriteRecovery() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 500, body: #"{"errors":[{"status":"500","detail":"temporary"}]}"#)
        ])
        let worker = ProductPageOptimizationWorker(httpClient: try await ppoV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "ppo_create_treatment_localization",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .string("en-US")
            ]
        ))
        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let root = try ppoV319Object(result.structuredContent)
        #expect(root["operationCommitState"] == .string("unknown"))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["inspectionRequired"] == .bool(true))
        let recovery = try ppoV319Object(root["recovery"])
        #expect(root["action"] == .string("CREATE"))
        let requestedValues = try ppoV319Object(root["requestedValues"])
        #expect(requestedValues["locale"] == .string("en-US"))
        #expect(recovery["action"] == .string("CREATE"))
        let recoveryRequestedValues = try ppoV319Object(recovery["requested_values"])
        #expect(recoveryRequestedValues["locale"] == .string("en-US"))
        let list = try ppoV319Object(recovery["list_candidates"])
        #expect(list["tool"] == .string("ppo_list_treatment_localizations"))
        let get = try ppoV319Object(recovery["get_candidate"])
        #expect(get["tool"] == .string("ppo_get_treatment_localization"))
    }

    @Test("PPO manifest maps every new public operation and keeps legacy experiment V1 closed")
    func ppoV319Manifest() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = source.appendingPathComponent(
            "Sources/asc-mcp/Resources/OperationManifest/tools/ppo.json"
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        let tools = try #require(root["tools"] as? [[String: Any]])
        #expect(tools.count == 15)
        let operations = Set(tools.flatMap { tool in
            (tool["operations"] as? [[String: Any]] ?? []).compactMap { $0["operationId"] as? String }
        })
        #expect(operations.contains("appStoreVersions_appStoreVersionExperimentsV2_getToManyRelated"))
        #expect(operations.contains("appStoreVersionExperimentTreatments_getInstance"))
        #expect(operations.contains("appStoreVersionExperimentTreatments_updateInstance"))
        #expect(operations.contains("appStoreVersionExperimentTreatments_deleteInstance"))
        #expect(operations.contains("appStoreVersionExperimentTreatmentLocalizations_getInstance"))
        #expect(operations.contains("appStoreVersionExperimentTreatmentLocalizations_deleteInstance"))
        #expect(!operations.contains("appStoreVersionExperiments_createInstance"))
        #expect(!operations.contains("appStoreVersionExperiments_updateInstance"))
        #expect(!operations.contains("appStoreVersionExperiments_deleteInstance"))
    }
}

private func ppoV319Client(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func ppoV319Object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object Value")
        throw PPOV319TestError.invalidValue
    }
    return object
}

private func ppoV319Array(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array Value")
        throw PPOV319TestError.invalidValue
    }
    return array
}

private func ppoV319StringSet(_ value: Value?) throws -> Set<String> {
    Set(try ppoV319Array(value).compactMap(\.stringValue))
}

private func ppoV319RequestAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(root["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func ppoV319ExperimentCollection(path: String) -> String {
    """
    {
      "data": [{
        "type": "appStoreVersionExperiments",
        "id": "experiment-1",
        "attributes": {
          "name": "Experiment",
          "platform": "IOS",
          "trafficProportion": 50,
          "state": "APPROVED"
        }
      }],
      "links": {"self": "\(path)?limit=17&filter%5Bstate%5D=APPROVED%2CSTOPPED"},
      "meta": {"paging": {"total": 1, "limit": 17}}
    }
    """
}

private func ppoV319ExperimentResponse(
    attributes: String,
    selfLink: String = "/v2/appStoreVersionExperiments/experiment-1"
) -> String {
    """
    {
      "data": {
        "type": "appStoreVersionExperiments",
        "id": "experiment-1",
        "attributes": \(attributes)
      },
      "links": {"self": "\(selfLink)"}
    }
    """
}

private func ppoV319TreatmentResponse(attributes: String) -> String {
    """
    {
      "data": {
        "type": "appStoreVersionExperimentTreatments",
        "id": "treatment-1",
        "attributes": \(attributes),
        "relationships": {
          "appStoreVersionExperimentV2": {
            "data": {"type": "appStoreVersionExperiments", "id": "experiment-1"}
          }
        }
      },
      "links": {"self": "/v1/appStoreVersionExperimentTreatments/treatment-1"}
    }
    """
}

private enum PPOV319TestError: Error {
    case invalidValue
}
