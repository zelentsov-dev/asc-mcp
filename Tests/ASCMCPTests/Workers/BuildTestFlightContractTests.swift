import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Build and TestFlight Contract Tests")
struct BuildTestFlightContractTests {
    @Test("encryption update patches the build resource")
    func encryptionUpdatePatchesBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"builds","id":"build-1","attributes":{"usesNonExemptEncryption":true}}}"#)
        ])
        let worker = try await makeBuildProcessingWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_update_encryption",
            arguments: [
                "build_id": .string("build-1"),
                "uses_non_exempt_encryption": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/builds/build-1")

        let body = try buildContractJSONBody(request)
        let data = try buildContractDictionary(body["data"])
        let attributes = try buildContractDictionary(data["attributes"])
        #expect(data["type"] as? String == "builds")
        #expect(data["id"] as? String == "build-1")
        #expect(attributes["usesNonExemptEncryption"] as? Bool == true)
        #expect(attributes["usesEncryption"] == nil)
        #expect(Set(attributes.keys) == ["usesNonExemptEncryption"])

        let payload = try buildContractObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["buildId"] == .string("build-1"))
        #expect(payload["usesNonExemptEncryption"] == .bool(true))
    }

    @Test("beta notification uses the current resource path and type")
    func betaNotificationUsesCurrentResource() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"buildBetaNotifications","id":"notification-1"}}"#)
        ])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_send_beta_notification",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/buildBetaNotifications")

        let body = try buildContractJSONBody(request)
        let data = try buildContractDictionary(body["data"])
        let relationships = try buildContractDictionary(data["relationships"])
        let build = try buildContractDictionary(relationships["build"])
        let linkage = try buildContractDictionary(build["data"])
        #expect(data["type"] as? String == "buildBetaNotifications")
        #expect(linkage["type"] as? String == "builds")
        #expect(linkage["id"] as? String == "build-1")
    }

    @Test("beta localization create sends only supported attributes")
    func betaLocalizationCreateSendsSupportedAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"betaBuildLocalizations","id":"localization-1","attributes":{"locale":"en-US","whatsNew":"Ready to test"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}}"#)
        ])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_set_beta_localization",
            arguments: [
                "build_id": .string("build-1"),
                "locale": .string("en-US"),
                "whats_new": .string("Ready to test")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "POST"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/betaBuildLocalizations",
            "/v1/betaBuildLocalizations"
        ])
        let query = buildContractQueryItems(requests[0])
        #expect(query["filter[build]"] == "build-1")
        #expect(query["filter[locale]"] == "en-US")
        #expect(query["limit"] == "1")

        let body = try buildContractJSONBody(requests[1])
        let data = try buildContractDictionary(body["data"])
        let attributes = try buildContractDictionary(data["attributes"])
        #expect(attributes["locale"] as? String == "en-US")
        #expect(attributes["whatsNew"] as? String == "Ready to test")
        #expect(Set(attributes.keys) == ["locale", "whatsNew"])

        let payload = try buildContractObject(result.structuredContent)
        #expect(payload["action"] == .string("created"))
        let localization = try buildContractObject(payload["localization"])
        #expect(Set(localization.keys) == ["id", "type", "locale", "whatsNew", "build"])
        let build = try buildContractObject(localization["build"])
        #expect(build == ["type": .string("builds"), "id": .string("build-1")])
    }

    @Test("filtered beta localization lookup updates an existing resource without posting")
    func betaLocalizationLookupUpdatesWithoutPost() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"betaBuildLocalizations","id":"localization-1","attributes":{"locale":"en-US","whatsNew":"Old"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}]}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"betaBuildLocalizations","id":"localization-1","attributes":{"locale":"en-US","whatsNew":"New"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}}"#)
        ])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_set_beta_localization",
            arguments: [
                "build_id": .string("build-1"),
                "locale": .string("en-US"),
                "whats_new": .string("New")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "PATCH"])
        #expect(!requests.contains { $0.httpMethod == "POST" })
        #expect(requests[0].url?.path == "/v1/betaBuildLocalizations")
        #expect(requests[1].url?.path == "/v1/betaBuildLocalizations/localization-1")
        let query = buildContractQueryItems(requests[0])
        #expect(query["filter[build]"] == "build-1")
        #expect(query["filter[locale]"] == "en-US")
        #expect(query["limit"] == "1")

        let body = try buildContractJSONBody(requests[1])
        let data = try buildContractDictionary(body["data"])
        let attributes = try buildContractDictionary(data["attributes"])
        #expect(data["type"] as? String == "betaBuildLocalizations")
        #expect(data["id"] as? String == "localization-1")
        #expect(attributes["whatsNew"] as? String == "New")
        #expect(Set(attributes.keys) == ["whatsNew"])

        let payload = try buildContractObject(result.structuredContent)
        #expect(payload["action"] == .string("updated"))
        let localization = try buildContractObject(payload["localization"])
        #expect(Set(localization.keys) == ["id", "type", "locale", "whatsNew", "build"])
    }

    @Test("beta localization rejects app-level attributes before network")
    func betaLocalizationRejectsAppLevelAttributes() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_set_beta_localization",
            arguments: [
                "build_id": .string("build-1"),
                "locale": .string("en-US"),
                "marketing_url": .string("https://example.com")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(buildContractText(result).contains("beta_app_create_localization"))
    }

    @Test("beta detail update sends only auto notify")
    func betaDetailUpdateSendsOnlyAutoNotify() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"buildBetaDetails","id":"detail-1","attributes":{"autoNotifyEnabled":true,"internalBuildState":"READY_FOR_BETA_TESTING","externalBuildState":"READY_FOR_BETA_TESTING"}}}"#)
        ])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_update_beta_detail",
            arguments: [
                "beta_detail_id": .string("detail-1"),
                "auto_notify": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/buildBetaDetails/detail-1")

        let body = try buildContractJSONBody(request)
        let data = try buildContractDictionary(body["data"])
        let attributes = try buildContractDictionary(data["attributes"])
        #expect(data["type"] as? String == "buildBetaDetails")
        #expect(data["id"] as? String == "detail-1")
        #expect(attributes["autoNotifyEnabled"] as? Bool == true)
        #expect(Set(attributes.keys) == ["autoNotifyEnabled"])
    }

    @Test("beta detail rejects read-only states before network")
    func betaDetailRejectsReadOnlyStates() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeBuildBetaDetailsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_update_beta_detail",
            arguments: [
                "beta_detail_id": .string("detail-1"),
                "internal_build_state": .string("READY_FOR_BETA_TESTING")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(buildContractText(result).contains("read-only"))
    }

    @Test("legacy unsupported inputs remain discoverable as deprecated")
    func legacyUnsupportedInputsAreDeprecated() async throws {
        let worker = try await makeBuildBetaDetailsWorker(
            transport: TestHTTPTransport(responses: [])
        )
        let tools = await worker.getTools()
        let betaDetail = try #require(tools.first { $0.name == "builds_update_beta_detail" })
        let localization = try #require(tools.first { $0.name == "builds_set_beta_localization" })

        for field in ["internal_build_state", "external_build_state"] {
            #expect(try buildContractProperty(field, in: betaDetail)["deprecated"] == .bool(true))
        }
        for field in ["feedback_email", "marketing_url", "privacy_policy_url", "tv_os_privacy_policy"] {
            #expect(try buildContractProperty(field, in: localization)["deprecated"] == .bool(true))
        }
    }
}

private func makeBuildProcessingWorker(transport: TestHTTPTransport) async throws -> BuildProcessingWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return BuildProcessingWorker(httpClient: client)
}

private func makeBuildBetaDetailsWorker(transport: TestHTTPTransport) async throws -> BuildBetaDetailsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return BuildBetaDetailsWorker(httpClient: client)
}

private func buildContractJSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw BuildTestFlightContractFailure.expectedDictionary
    }
    return object
}

private func buildContractQueryItems(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func buildContractDictionary(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
        throw BuildTestFlightContractFailure.expectedDictionary
    }
    return value
}

private func buildContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw BuildTestFlightContractFailure.expectedObject
    }
    return object
}

private func buildContractProperty(_ name: String, in tool: Tool) throws -> [String: Value] {
    guard case .object(let root) = tool.inputSchema,
          case .object(let properties)? = root["properties"],
          case .object(let property)? = properties[name] else {
        throw BuildTestFlightContractFailure.expectedProperty(name)
    }
    return property
}

private func buildContractText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum BuildTestFlightContractFailure: Error {
    case expectedDictionary
    case expectedObject
    case expectedProperty(String)
}
