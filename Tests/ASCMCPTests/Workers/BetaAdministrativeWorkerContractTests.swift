import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Beta Administrative Worker Contract Tests")
struct BetaAdministrativeWorkerContractTests {
    @Test("beta license list accepts Apple array filter and preserves app linkage")
    func betaLicenseListAcceptsArrayFilterAndPreservesAppLinkage() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "betaLicenseAgreements",
                  "id": "agreement-1",
                  "relationships": {
                    "app": {
                      "data": {"type": "apps", "id": "app-1"},
                      "links": {"related": "https://api.appstoreconnect.apple.com/v1/betaLicenseAgreements/agreement-1/app"}
                    }
                  }
                }
              ],
              "meta": {"paging": {"total": 8, "limit": 25}}
            }
            """)
        ])
        let worker = BetaLicenseAgreementsWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_license_list",
            arguments: ["app_id": .array([.string("app-1"), .string("app-2")])]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(betaAdministrativeQuery(request)["filter[app]"] == "app-1,app-2")
        let root = try betaAdministrativeObject(result.structuredContent)
        #expect(root["total"] == .int(8))
        let agreements = try betaAdministrativeArray(root["beta_license_agreements"])
        let agreement = try betaAdministrativeObject(agreements.first)
        #expect(agreement["appId"] == .string("app-1"))
        #expect(agreement["agreementText"] == .null)
    }

    @Test("beta license get requires only its resource ID")
    func betaLicenseGetRequiresOnlyResourceID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"betaLicenseAgreements","id":"agreement-1","attributes":{"agreementText":"Terms"}}}"#)
        ])
        let worker = BetaLicenseAgreementsWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_license_get",
            arguments: ["beta_license_agreement_id": .string("agreement-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/betaLicenseAgreements/agreement-1")
    }

    @Test("beta license update preserves explicit null")
    func betaLicenseUpdatePreservesExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "betaLicenseAgreements",
                "id": "agreement-1",
                "attributes": {"agreementText": null},
                "relationships": {"app": {"data": {"type": "apps", "id": "app-1"}}}
              }
            }
            """)
        ])
        let worker = BetaLicenseAgreementsWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_license_update",
            arguments: [
                "beta_license_agreement_id": .string("agreement-1"),
                "agreement_text": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/betaLicenseAgreements/agreement-1")
        let attributes = try betaAdministrativeRequestAttributes(request)
        #expect(Set(attributes.keys) == ["agreementText"])
        #expect(attributes["agreementText"] is NSNull)
    }

    @Test("beta license update rejects empty and malformed patches")
    func betaLicenseUpdateRejectsEmptyAndMalformedPatches() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaLicenseAgreementsWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "beta_license_update",
            arguments: ["beta_license_agreement_id": .string("agreement-1")]
        ))
        let malformed = try await worker.handleTool(CallTool.Parameters(
            name: "beta_license_update",
            arguments: [
                "beta_license_agreement_id": .string("agreement-1"),
                "agreement_text": .int(1)
            ]
        ))

        #expect(empty.isError == true)
        #expect(malformed.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("sandbox update preserves nulls and accepts sparse response")
    func sandboxUpdatePreservesNullsAndAcceptsSparseResponse() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"sandboxTesters","id":"tester-1"}}"#)
        ])
        let worker = SandboxTestersWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_update",
            arguments: [
                "sandbox_tester_id": .string("tester-1"),
                "territory": .null,
                "interrupt_purchases": .null,
                "subscription_renewal_rate": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let attributes = try betaAdministrativeRequestAttributes(request)
        #expect(Set(attributes.keys) == ["territory", "interruptPurchases", "subscriptionRenewalRate"])
        #expect(attributes.values.allSatisfy { $0 is NSNull })
        let root = try betaAdministrativeObject(result.structuredContent)
        let tester = try betaAdministrativeObject(root["sandbox_tester"])
        #expect(tester["id"] == .string("tester-1"))
        #expect(tester["territory"] == .null)
    }

    @Test("sandbox update rejects empty and malformed patches")
    func sandboxUpdateRejectsEmptyAndMalformedPatches() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = SandboxTestersWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_update",
            arguments: ["sandbox_tester_id": .string("tester-1")]
        ))
        let malformed = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_update",
            arguments: [
                "sandbox_tester_id": .string("tester-1"),
                "interrupt_purchases": .string("yes")
            ]
        ))
        let invalidTerritory = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_update",
            arguments: [
                "sandbox_tester_id": .string("tester-1"),
                "territory": .string("INVALID")
            ]
        ))

        #expect(empty.isError == true)
        #expect(malformed.isError == true)
        #expect(invalidTerritory.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("sandbox clear history validates all IDs and returns Apple request ID")
    func sandboxClearHistoryValidatesAllIDsAndReturnsRequestID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: """
            {
              "data": {"type": "sandboxTestersClearPurchaseHistoryRequest", "id": "clear-1"},
              "links": {"self": "https://api.appstoreconnect.apple.com/v2/sandboxTestersClearPurchaseHistoryRequest/clear-1"}
            }
            """)
        ])
        let worker = SandboxTestersWorker(httpClient: try await makeBetaAdministrativeClient(transport))

        let invalid = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_clear_purchase_history",
            arguments: ["sandbox_tester_ids": .array([.string("tester-1"), .int(2)])]
        ))
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 0)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "sandbox_clear_purchase_history",
            arguments: ["sandbox_tester_ids": .array([.string("tester-1"), .string("tester-2")])]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v2/sandboxTestersClearPurchaseHistoryRequest")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let sandboxTesters = try #require(relationships["sandboxTesters"] as? [String: Any])
        let linkage = try #require(sandboxTesters["data"] as? [[String: Any]])
        #expect(linkage.compactMap { $0["id"] as? String } == ["tester-1", "tester-2"])
        #expect(linkage.allSatisfy { $0["type"] as? String == "sandboxTesters" })
        let root = try betaAdministrativeObject(result.structuredContent)
        #expect(root["request_id"] == .string("clear-1"))
    }

    @Test("sandbox mutations preserve committed-unverified state")
    func sandboxMutationsPreserveCommittedUnverifiedState() async throws {
        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: "")
        ])
        let updateWorker = SandboxTestersWorker(
            httpClient: try await makeBetaAdministrativeClient(updateTransport)
        )
        let update = try await updateWorker.handleTool(CallTool.Parameters(
            name: "sandbox_update",
            arguments: [
                "sandbox_tester_id": .string("tester-1"),
                "interrupt_purchases": .bool(true)
            ]
        ))
        let updatePayload = try betaAdministrativeObject(update.structuredContent)
        #expect(update.isError == true)
        #expect(updatePayload["operationCommitState"] == .string("committed_unverified"))
        #expect(updatePayload["operationCommitted"] == .bool(true))
        #expect(updatePayload["retrySafe"] == .bool(false))

        let clearTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"sandboxTestersClearPurchaseHistoryRequest","id":"clear-1"}}"#)
        ])
        let clearWorker = SandboxTestersWorker(
            httpClient: try await makeBetaAdministrativeClient(clearTransport)
        )
        let clear = try await clearWorker.handleTool(CallTool.Parameters(
            name: "sandbox_clear_purchase_history",
            arguments: ["sandbox_tester_ids": .array([.string("tester-1")])]
        ))
        let clearPayload = try betaAdministrativeObject(clear.structuredContent)
        #expect(clear.isError == true)
        #expect(clearPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(clearPayload["operationCommitted"] == .bool(true))
        #expect(clearPayload["retrySafe"] == .bool(false))
    }

    @Test("beta administrative schemas expose nullable writes and collection bounds")
    func betaAdministrativeSchemasExposeContracts() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let licenseTools = await BetaLicenseAgreementsWorker(httpClient: client).getTools()
        let sandboxTools = await SandboxTestersWorker(httpClient: client).getTools()
        let licenseUpdate = try #require(licenseTools.first { $0.name == "beta_license_update" })
        let sandboxUpdate = try #require(sandboxTools.first { $0.name == "sandbox_update" })
        let clearHistory = try #require(sandboxTools.first { $0.name == "sandbox_clear_purchase_history" })

        let licenseProperties = try betaAdministrativeProperties(licenseUpdate)
        #expect(try betaAdministrativeArray(try betaAdministrativeObject(licenseProperties["agreement_text"])["type"]) == [.string("string"), .string("null")])
        let sandboxProperties = try betaAdministrativeProperties(sandboxUpdate)
        #expect(try betaAdministrativeArray(try betaAdministrativeObject(sandboxProperties["interrupt_purchases"])["type"]) == [.string("boolean"), .string("null")])
        #expect(try betaAdministrativeObject(sandboxUpdate.inputSchema)["minProperties"] == .int(2))
        let territories = try betaAdministrativeArray(try betaAdministrativeObject(sandboxProperties["territory"])["enum"])
        #expect(territories.contains(.string("USA")))
        #expect(territories.contains(.null))
        let clearProperties = try betaAdministrativeProperties(clearHistory)
        let ids = try betaAdministrativeObject(clearProperties["sandbox_tester_ids"])
        #expect(ids["minItems"] == .int(1))
        #expect(ids["uniqueItems"] == .bool(true))
    }
}

private func makeBetaAdministrativeClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func betaAdministrativeQuery(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func betaAdministrativeRequestAttributes(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let data = try #require(json["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func betaAdministrativeProperties(_ tool: Tool) throws -> [String: Value] {
    let schema = try betaAdministrativeObject(tool.inputSchema)
    return try betaAdministrativeObject(schema["properties"])
}

private func betaAdministrativeObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw BetaAdministrativeTestError.expectedObject
    }
    return object
}

private func betaAdministrativeArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw BetaAdministrativeTestError.expectedArray
    }
    return array
}

private enum BetaAdministrativeTestError: Error {
    case expectedObject
    case expectedArray
}
