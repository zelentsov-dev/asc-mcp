import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Product Page Optimization Contract Tests")
struct ProductPageOptimizationContractTests {
    @Test("create treatment binds the V2 experiment relationship")
    func createTreatmentUsesV2Relationship() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreVersionExperimentTreatments","id":"treatment-1","attributes":{"name":"Variant A"}},"links":{"self":"https://api.example.test/v1/appStoreVersionExperimentTreatments/treatment-1"}}"#)
        ])
        let worker = try await makePPOWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_create_treatment",
            arguments: [
                "experiment_id": .string("experiment-v2-1"),
                "name": .string("Variant A")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appStoreVersionExperimentTreatments")

        let root = try requestBody(request)
        let data = try #require(root["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let experiment = try #require(relationships["appStoreVersionExperimentV2"] as? [String: Any])
        let identifier = try #require(experiment["data"] as? [String: Any])
        #expect(identifier["type"] as? String == "appStoreVersionExperiments")
        #expect(identifier["id"] as? String == "experiment-v2-1")
        #expect(relationships["appStoreVersionExperiment"] == nil)
    }

    @Test("START maps to the V2 started boolean")
    func updateExperimentMapsStartToTrue() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: experimentUnverifiedStartResponseBody)
        ])
        let worker = try await makePPOWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-v2-1"),
                "state": .string("START"),
                "confirm_experiment_id": .string("experiment-v2-1")
            ]
        ))

        #expect(result.isError == true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v2/appStoreVersionExperiments/experiment-v2-1")
        let attributes = try updateAttributes(request)
        #expect(attributes["started"] as? Bool == true)
        #expect(attributes["state"] == nil)
        let root = try ppoContractObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["action"] == .string("START"))
    }

    @Test("STOP maps to the V2 started boolean")
    func updateExperimentMapsStopToFalse() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: experimentStoppedResponseBody)
        ])
        let worker = try await makePPOWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-v2-1"),
                "state": .string("STOP"),
                "confirm_experiment_id": .string("experiment-v2-1")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let attributes = try updateAttributes(request)
        #expect(attributes["started"] as? Bool == false)
        #expect(attributes["state"] == nil)
        let root = try ppoContractObject(result.structuredContent)
        #expect(root["lifecycleAction"] == .string("STOP"))
        #expect(root["changed"] == .null)
        #expect(root["changeVerified"] == .bool(false))
    }

    @Test("invalid lifecycle state is rejected before transport")
    func updateExperimentRejectsInvalidState() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePPOWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_update_experiment",
            arguments: [
                "experiment_id": .string("experiment-v2-1"),
                "state": .string("RUNNING")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private let experimentUnverifiedStartResponseBody = #"{"data":{"type":"appStoreVersionExperiments","id":"experiment-v2-1","attributes":{"name":"Experiment","trafficProportion":50,"state":"APPROVED"}},"links":{"self":"https://api.example.test/v2/appStoreVersionExperiments/experiment-v2-1"}}"#

private let experimentStoppedResponseBody = #"{"data":{"type":"appStoreVersionExperiments","id":"experiment-v2-1","attributes":{"name":"Experiment","trafficProportion":50,"state":"STOPPED"}},"links":{"self":"https://api.example.test/v2/appStoreVersionExperiments/experiment-v2-1"}}"#

private func makePPOWorker(transport: TestHTTPTransport) async throws -> ProductPageOptimizationWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ProductPageOptimizationWorker(httpClient: client)
}

private func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func updateAttributes(_ request: URLRequest) throws -> [String: Any] {
    let root = try requestBody(request)
    let data = try #require(root["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func ppoContractObject(_ value: Value?) throws -> [String: Value] {
    try #require(value?.objectValue)
}
