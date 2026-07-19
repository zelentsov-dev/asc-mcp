import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Users Update Contract Tests")
struct UsersUpdateContractTests {
    @Test("users_update exposes every Apple 4.4.1 writable field and current role enum")
    func exposesCurrentWritableFieldsAndRoles() async throws {
        let worker = try await usersUpdateWorker(transport: TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first { $0.name == "users_update" })
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let roles)? = properties["roles"],
              case .object(let roleItems)? = roles["items"],
              case .array(let roleValues)? = roleItems["enum"] else {
            Issue.record("Expected users_update schema properties")
            return
        }

        #expect(properties["all_apps_visible"] != nil)
        #expect(properties["provisioning_allowed"] != nil)
        #expect(properties["visible_app_ids"] != nil)
        let roleNames = Set(roleValues.compactMap(\.stringValue))
        #expect(roleNames == Set(UsersWorker.assignableRoles))
        #expect(roleNames.contains("ACCESS_TO_REPORTS"))
        #expect(roleNames.contains("TECHNICAL") == false)
    }

    @Test("users_update sends all writable fields with a limited-app developer role")
    func sendsAllWritableFields() async throws {
        let transport = TestHTTPTransport(responses: [usersUpdateResponse()])
        let worker = try await usersUpdateWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_update",
            arguments: [
                "user_id": .string("user-1"),
                "roles": .array([.string("DEVELOPER")]),
                "all_apps_visible": .bool(false),
                "provisioning_allowed": .bool(false),
                "visible_app_ids": .array([.string("app-1"), .string("app-2")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/users/user-1")

        let body = try usersUpdateBody(request)
        let data = try usersUpdateDictionary(body["data"])
        let attributes = try usersUpdateDictionary(data["attributes"])
        let relationships = try usersUpdateDictionary(data["relationships"])
        let visibleApps = try usersUpdateDictionary(relationships["visibleApps"])
        let appLinkages = try #require(visibleApps["data"] as? [[String: Any]])

        #expect(data["id"] as? String == "user-1")
        #expect(data["type"] as? String == "users")
        #expect(attributes["roles"] as? [String] == ["DEVELOPER"])
        #expect(attributes["allAppsVisible"] as? Bool == false)
        #expect(attributes["provisioningAllowed"] as? Bool == false)
        #expect(appLinkages.compactMap { $0["id"] as? String } == ["app-1", "app-2"])
        #expect(appLinkages.allSatisfy { $0["type"] as? String == "apps" })

        let structured = try usersUpdateObject(result.structuredContent)
        #expect(structured["warnings"] == nil)
    }

    @Test("users_update accepts deprecated access-to-reports separately and returns a warning")
    func warnsForDeprecatedAccessToReports() async throws {
        let transport = TestHTTPTransport(responses: [usersUpdateDeprecatedResponse()])
        let worker = try await usersUpdateWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_update",
            arguments: [
                "user_id": .string("user-1"),
                "roles": .array([.string("DEVELOPER"), .string("ACCESS_TO_REPORTS")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try usersUpdateBody(request)
        let data = try usersUpdateDictionary(body["data"])
        let attributes = try usersUpdateDictionary(data["attributes"])
        #expect(attributes["roles"] as? [String] == ["DEVELOPER", "ACCESS_TO_REPORTS"])
        #expect(attributes["allAppsVisible"] == nil)
        #expect(data["relationships"] == nil)

        let structured = try usersUpdateObject(result.structuredContent)
        guard case .array(let warnings)? = structured["warnings"] else {
            Issue.record("Expected a deprecation warning")
            return
        }
        #expect(warnings.compactMap(\.stringValue).first?.contains("deprecated by Apple") == true)
    }

    @Test("users_update accepts an empty visible app relationship without requiring roles")
    func clearsVisibleAppsWithoutRoles() async throws {
        let transport = TestHTTPTransport(responses: [usersUpdateResponse()])
        let worker = try await usersUpdateWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_update",
            arguments: [
                "user_id": .string("user-1"),
                "visible_app_ids": .array([])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try usersUpdateBody(request)
        let data = try usersUpdateDictionary(body["data"])
        let relationships = try usersUpdateDictionary(data["relationships"])
        let visibleApps = try usersUpdateDictionary(relationships["visibleApps"])
        #expect((visibleApps["data"] as? [Any])?.isEmpty == true)
    }

    @Test("users_update rejects TECHNICAL and unknown roles before the network")
    func rejectsUnsupportedRoles() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await usersUpdateWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_update",
            arguments: [
                "user_id": .string("user-1"),
                "roles": .array([.string("TECHNICAL"), .string("UNKNOWN")])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(usersUpdateText(result).contains("Unsupported role(s): TECHNICAL, UNKNOWN"))
    }

    @Test("users_update requires at least one update field")
    func requiresAChange() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await usersUpdateWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_update",
            arguments: ["user_id": .string("user-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(usersUpdateText(result).contains("Provide at least one update field"))
    }
}

private func usersUpdateWorker(transport: TestHTTPTransport) async throws -> UsersWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return UsersWorker(httpClient: client)
}

private func usersUpdateResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 200, body: """
    {
      "data": {
        "type": "users",
        "id": "user-1",
        "attributes": {
          "roles": ["DEVELOPER"],
          "allAppsVisible": false,
          "provisioningAllowed": false
        }
      }
    }
    """)
}

private func usersUpdateDeprecatedResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 200, body: """
    {
      "data": {
        "type": "users",
        "id": "user-1",
        "attributes": {
          "roles": ["DEVELOPER", "ACCESS_TO_REPORTS"],
          "allAppsVisible": true,
          "provisioningAllowed": true
        }
      }
    }
    """)
}

private func usersUpdateBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw UsersUpdateContractTestFailure.expectedDictionary
    }
    return object
}

private func usersUpdateDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw UsersUpdateContractTestFailure.expectedDictionary
    }
    return dictionary
}

private func usersUpdateObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw UsersUpdateContractTestFailure.expectedObject
    }
    return object
}

private func usersUpdateText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum UsersUpdateContractTestFailure: Error {
    case expectedDictionary
    case expectedObject
}
