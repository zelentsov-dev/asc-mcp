import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Users Apple Contract Tests")
struct UsersAppleContractTests {
    @Test("Users tools expose Apple 4.4.1 collection controls and invitation provisioning")
    func exposesCurrentInputs() async throws {
        let worker = try await usersContractWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let usersList = try usersContractProperties(
            try #require(tools.first { $0.name == "users_list" })
        )
        #expect(usersList["filter_username"] != nil)
        #expect(usersList["filter_roles"] != nil)
        #expect(usersList["filter_visible_apps"] != nil)
        #expect(usersList["sort"] != nil)
        #expect(usersList["include"] != nil)
        #expect(usersList["limit_visible_apps"] != nil)

        let usersGet = try usersContractProperties(
            try #require(tools.first { $0.name == "users_get" })
        )
        #expect(usersGet["include"] != nil)
        #expect(usersGet["limit_visible_apps"] != nil)

        let invitations = try usersContractProperties(
            try #require(tools.first { $0.name == "users_list_invitations" })
        )
        #expect(invitations["filter_email"] != nil)
        #expect(invitations["filter_roles"] != nil)
        #expect(invitations["filter_visible_apps"] != nil)
        #expect(invitations["sort"] != nil)
        #expect(invitations["include"] != nil)
        #expect(invitations["limit_visible_apps"] != nil)

        let invite = try usersContractProperties(
            try #require(tools.first { $0.name == "users_invite" })
        )
        #expect(invite["provisioning_allowed"] != nil)
    }

    @Test("users_list sends all current controls and preserves included apps and relationship IDs")
    func listsUsersWithCurrentContract() async throws {
        let transport = TestHTTPTransport(responses: [usersListContractResponse()])
        let worker = try await usersContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_list",
            arguments: [
                "limit": .int(40),
                "filter_username": .array([.string("a@example.com"), .string("b@example.com")]),
                "filter_roles": .string("ADMIN,DEVELOPER"),
                "filter_visible_apps": .array([.string("app-1"), .string("app-2")]),
                "sort": .array([.string("username"), .string("-lastName")]),
                "include": .string("visibleApps"),
                "limit_visible_apps": .int(2)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try usersContractQuery(request)
        #expect(query["limit"] == "40")
        #expect(query["filter[username]"] == "a@example.com,b@example.com")
        #expect(query["filter[roles]"] == "ADMIN,DEVELOPER")
        #expect(query["filter[visibleApps]"] == "app-1,app-2")
        #expect(query["sort"] == "username,-lastName")
        #expect(query["include"] == "visibleApps")
        #expect(query["limit[visibleApps]"] == "2")

        let payload = try usersContractObject(result.structuredContent)
        #expect(payload["total"]?.intValue == 2)
        let users = try usersContractArray(payload["users"])
        let user = try usersContractObject(try #require(users.first))
        #expect(try usersContractStrings(user["visibleAppIds"]) == ["app-1", "app-2"])
        #expect(user["expirationDate"] == nil)
        let included = try usersContractArray(payload["included"])
        let app = try usersContractObject(try #require(included.first))
        #expect(app["id"]?.stringValue == "app-1")
        #expect(try usersContractObject(app["attributes"])["name"]?.stringValue == "Example")
    }

    @Test("users_get sends the nested include limit and returns included resources")
    func getsUserWithIncludedApps() async throws {
        let transport = TestHTTPTransport(responses: [usersGetContractResponse()])
        let worker = try await usersContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_get",
            arguments: [
                "user_id": .string("user:1"),
                "include": .array([.string("visibleApps")]),
                "limit_visible_apps": .int(1)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let components = try #require(URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        ))
        #expect(components.percentEncodedPath == "/v1/users/user%3A1")
        let query = try usersContractQuery(request)
        #expect(query["include"] == "visibleApps")
        #expect(query["limit[visibleApps]"] == "1")

        let payload = try usersContractObject(result.structuredContent)
        let user = try usersContractObject(payload["user"])
        #expect(try usersContractStrings(user["visibleAppIds"]) == ["app-1"])
        #expect(try usersContractArray(payload["included"]).count == 1)
    }

    @Test("users_list_invitations sends all current controls and returns current invitation data")
    func listsInvitationsWithCurrentContract() async throws {
        let transport = TestHTTPTransport(responses: [usersInvitationsContractResponse()])
        let worker = try await usersContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_list_invitations",
            arguments: [
                "filter_email": .string("new@example.com"),
                "filter_roles": .array([.string("DEVELOPER")]),
                "filter_visible_apps": .string("app-9"),
                "sort": .string("-email,lastName"),
                "include": .string("visibleApps"),
                "limit_visible_apps": .int(3)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try usersContractQuery(request)
        #expect(query["filter[email]"] == "new@example.com")
        #expect(query["filter[roles]"] == "DEVELOPER")
        #expect(query["filter[visibleApps]"] == "app-9")
        #expect(query["sort"] == "-email,lastName")
        #expect(query["include"] == "visibleApps")
        #expect(query["limit[visibleApps]"] == "3")

        let payload = try usersContractObject(result.structuredContent)
        #expect(payload["total"]?.intValue == 1)
        let invitations = try usersContractArray(payload["invitations"])
        let invitation = try usersContractObject(try #require(invitations.first))
        #expect(invitation["provisioningAllowed"]?.boolValue == true)
        #expect(invitation["expirationDate"]?.stringValue == "2026-08-01T00:00:00Z")
        #expect(try usersContractStrings(invitation["visibleAppIds"]) == ["app-9"])
        #expect(try usersContractArray(payload["included"]).count == 1)
    }

    @Test("users_invite sends provisioning access and validated relationships")
    func invitesWithCurrentAttributes() async throws {
        let transport = TestHTTPTransport(responses: [usersInviteContractResponse()])
        let worker = try await usersContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "users_invite",
            arguments: [
                "email": .string("new@example.com"),
                "first_name": .string("New"),
                "last_name": .string("User"),
                "roles": .array([.string("DEVELOPER")]),
                "all_apps_visible": .bool(false),
                "provisioning_allowed": .bool(true),
                "visible_app_ids": .array([.string("app-9")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try usersContractBody(request)
        let data = try usersContractDictionary(body["data"])
        let attributes = try usersContractDictionary(data["attributes"])
        let relationships = try usersContractDictionary(data["relationships"])
        let visibleApps = try usersContractDictionary(relationships["visibleApps"])
        let linkages = try #require(visibleApps["data"] as? [[String: Any]])
        #expect(attributes["provisioningAllowed"] as? Bool == true)
        #expect(linkages.compactMap { $0["id"] as? String } == ["app-9"])

        let payload = try usersContractObject(result.structuredContent)
        let invitation = try usersContractObject(payload["invitation"])
        #expect(invitation["provisioningAllowed"]?.boolValue == true)
        #expect(try usersContractStrings(invitation["visibleAppIds"]) == ["app-9"])
    }

    @Test("User write tools reject malformed role and app ID arrays before the network")
    func rejectsMalformedArraysBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await usersContractWorker(transport: transport)
        let invalidCalls: [CallTool.Parameters] = [
            CallTool.Parameters(
                name: "users_invite",
                arguments: usersInviteArguments(roles: [.string("DEVELOPER"), .int(1)])
            ),
            CallTool.Parameters(
                name: "users_invite",
                arguments: usersInviteArguments(roles: [.string("DEVELOPER"), .string("DEVELOPER")])
            ),
            CallTool.Parameters(
                name: "users_invite",
                arguments: usersInviteArguments(roles: [.string("TECHNICAL")])
            ),
            CallTool.Parameters(
                name: "users_invite",
                arguments: usersInviteArguments(
                    roles: [.string("DEVELOPER")],
                    visibleAppIds: [.string(" ")]
                )
            ),
            CallTool.Parameters(
                name: "users_update",
                arguments: [
                    "user_id": .string("user-1"),
                    "visible_app_ids": .array([.string("app-1"), .string("app-1")])
                ]
            ),
            CallTool.Parameters(
                name: "users_add_visible_apps",
                arguments: [
                    "user_id": .string("user-1"),
                    "app_ids": .array([.string("app-1"), .int(1)])
                ]
            ),
            CallTool.Parameters(
                name: "users_remove_visible_apps",
                arguments: [
                    "user_id": .string("user-1"),
                    "app_ids": .array([.string("app-1"), .string("app-1")])
                ]
            )
        ]

        for call in invalidCalls {
            let result = try await worker.handleTool(call)
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }
}

private func usersContractWorker(transport: TestHTTPTransport) async throws -> UsersWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return UsersWorker(httpClient: client)
}

private func usersContractProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw UsersAppleContractTestFailure.expectedObject
    }
    return properties
}

private func usersContractQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func usersContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw UsersAppleContractTestFailure.expectedObject
    }
    return object
}

private func usersContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw UsersAppleContractTestFailure.expectedArray
    }
    return array
}

private func usersContractStrings(_ value: Value?) throws -> [String] {
    try usersContractArray(value).compactMap(\.stringValue)
}

private func usersContractBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw UsersAppleContractTestFailure.expectedDictionary
    }
    return object
}

private func usersContractDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw UsersAppleContractTestFailure.expectedDictionary
    }
    return dictionary
}

private func usersInviteArguments(
    roles: [Value],
    visibleAppIds: [Value]? = nil
) -> [String: Value] {
    var arguments: [String: Value] = [
        "email": .string("new@example.com"),
        "first_name": .string("New"),
        "last_name": .string("User"),
        "roles": .array(roles)
    ]
    if let visibleAppIds {
        arguments["visible_app_ids"] = .array(visibleAppIds)
    }
    return arguments
}

private func usersListContractResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 200, body: """
    {
      "data": [{
        "type": "users",
        "id": "user-1",
        "attributes": {
          "username": "a@example.com",
          "roles": ["ADMIN"],
          "allAppsVisible": false,
          "provisioningAllowed": true
        },
        "relationships": {
          "visibleApps": {
            "data": [
              {"type": "apps", "id": "app-1"},
              {"type": "apps", "id": "app-2"}
            ]
          }
        }
      }],
      "included": [{
        "type": "apps",
        "id": "app-1",
        "attributes": {"name": "Example", "bundleId": "com.example.app"}
      }],
      "links": {"self": "https://api.example.test/v1/users"},
      "meta": {"paging": {"total": 2, "limit": 40}}
    }
    """)
}

private func usersGetContractResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 200, body: """
    {
      "data": {
        "type": "users",
        "id": "user-1",
        "attributes": {"username": "a@example.com"},
        "relationships": {
          "visibleApps": {"data": [{"type": "apps", "id": "app-1"}]}
        }
      },
      "included": [{"type": "apps", "id": "app-1", "attributes": {"name": "Example"}}],
      "links": {"self": "https://api.example.test/v1/users/user-1"}
    }
    """)
}

private func usersInvitationsContractResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 200, body: """
    {
      "data": [{
        "type": "userInvitations",
        "id": "invitation-1",
        "attributes": {
          "email": "new@example.com",
          "roles": ["DEVELOPER"],
          "allAppsVisible": false,
          "provisioningAllowed": true,
          "expirationDate": "2026-08-01T00:00:00Z"
        },
        "relationships": {
          "visibleApps": {"data": [{"type": "apps", "id": "app-9"}]}
        }
      }],
      "included": [{"type": "apps", "id": "app-9", "attributes": {"name": "Nine"}}],
      "links": {"self": "https://api.example.test/v1/userInvitations"},
      "meta": {"paging": {"total": 1, "limit": 25}}
    }
    """)
}

private func usersInviteContractResponse() -> TestHTTPTransport.Response {
    .init(statusCode: 201, body: """
    {
      "data": {
        "type": "userInvitations",
        "id": "invitation-1",
        "attributes": {
          "email": "new@example.com",
          "roles": ["DEVELOPER"],
          "allAppsVisible": false,
          "provisioningAllowed": true
        },
        "relationships": {
          "visibleApps": {"data": [{"type": "apps", "id": "app-9"}]}
        }
      },
      "links": {"self": "https://api.example.test/v1/userInvitations/invitation-1"}
    }
    """)
}

private enum UsersAppleContractTestFailure: Error {
    case expectedObject
    case expectedArray
    case expectedDictionary
}
