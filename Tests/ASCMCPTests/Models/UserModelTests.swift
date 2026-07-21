import Testing
import Foundation
@testable import asc_mcp

@Suite("User Model Tests")
struct UserModelTests {
    @Test func decodeUser() throws {
        let json = """
        {"type":"users","id":"u1","attributes":{"username":"john@test.com","firstName":"John","lastName":"Doe","roles":["ADMIN"],"allAppsVisible":true}}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(ASCUser.self, from: json)
        #expect(user.id == "u1")
        #expect(user.attributes?.username == "john@test.com")
        #expect(user.attributes?.roles == ["ADMIN"])
    }

    @Test func userInvitation() throws {
        let json = """
        {"type":"userInvitations","id":"inv-1","attributes":{"email":"new@test.com","firstName":"Jane","lastName":"Doe","roles":["DEVELOPER"]}}
        """.data(using: .utf8)!
        let inv = try JSONDecoder().decode(ASCUserInvitation.self, from: json)
        #expect(inv.attributes?.email == "new@test.com")
    }

    @Test func userResponse() throws {
        let json = """
        {"data":{"type":"users","id":"u1","attributes":{"username":"a@b.com"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCUserResponse.self, from: json)
        #expect(response.data.id == "u1")
    }

    @Test func usersResponse() throws {
        let json = """
        {"data":[{"type":"users","id":"u1","attributes":{"username":"a@b.com"}},{"type":"users","id":"u2","attributes":{"username":"c@d.com"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCUsersResponse.self, from: json)
        #expect(response.data.count == 2)
    }

    @Test func updateUserRequest() throws {
        let request = UpdateUserRequest(data: .init(id: "u1", attributes: .init(roles: ["ADMIN", "APP_MANAGER"], allAppsVisible: true)))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateUserRequest.self, from: data)
        #expect(decoded.data.id == "u1")
        #expect(decoded.data.attributes.roles == .value(["ADMIN", "APP_MANAGER"]))
    }

    @Test("user request models preserve omission explicit null and values")
    func nullableUserRequestAttributes() throws {
        let update = UpdateUserRequest(
            data: .init(
                id: "u1",
                attributes: .init(
                    nullableRoles: .null,
                    nullableAllAppsVisible: .value(false),
                    nullableProvisioningAllowed: .null
                )
            )
        )
        let invitation = CreateUserInvitationRequest(
            data: .init(
                attributes: .init(
                    email: "new@example.com",
                    firstName: "New",
                    lastName: "User",
                    roles: ["DEVELOPER"],
                    nullableAllAppsVisible: nil,
                    nullableProvisioningAllowed: .null
                ),
                relationships: nil
            )
        )

        let updateObject = try userModelObject(JSONEncoder().encode(update))
        let updateData = try userModelObject(updateObject["data"])
        let updateAttributes = try userModelObject(updateData["attributes"])
        #expect(updateAttributes["roles"] is NSNull)
        #expect(updateAttributes["allAppsVisible"] as? Bool == false)
        #expect(updateAttributes["provisioningAllowed"] is NSNull)

        let invitationObject = try userModelObject(JSONEncoder().encode(invitation))
        let invitationData = try userModelObject(invitationObject["data"])
        let invitationAttributes = try userModelObject(invitationData["attributes"])
        #expect(invitationAttributes.keys.contains("allAppsVisible") == false)
        #expect(invitationAttributes["provisioningAllowed"] is NSNull)
    }
}

private func userModelObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw UserModelTestFailure.expectedObject
    }
    return object
}

private func userModelObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw UserModelTestFailure.expectedObject
    }
    return object
}

private enum UserModelTestFailure: Error {
    case expectedObject
}
