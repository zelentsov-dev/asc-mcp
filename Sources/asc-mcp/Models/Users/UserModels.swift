import Foundation

// MARK: - User Models

/// Users list response
public struct ASCUsersResponse: Codable, Sendable {
    public let data: [ASCUser]
    public let links: ASCPagedDocumentLinks?
}

/// User single response
public struct ASCUserResponse: Codable, Sendable {
    public let data: ASCUser
}

/// User resource
public struct ASCUser: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: UserAttributes?
    public let relationships: UserRelationships?
}

/// User attributes
public struct UserAttributes: Codable, Sendable {
    public let username: String?
    public let firstName: String?
    public let lastName: String?
    public let roles: [String]?
    public let allAppsVisible: Bool?
    public let provisioningAllowed: Bool?
    public let expirationDate: String?
}

/// User relationships
public struct UserRelationships: Codable, Sendable {
    public let visibleApps: ASCRelationshipMultiple?
}

// MARK: - Update User Request

/// Request body for updating a user
public struct UpdateUserRequest: Codable, Sendable {
    public let data: UpdateUserData

    public struct UpdateUserData: Codable, Sendable {
        public let type: String = "users"
        public let id: String
        public let attributes: UpdateUserAttributes
    }

    public struct UpdateUserAttributes: Codable, Sendable {
        public let roles: [String]?
        public let allAppsVisible: Bool?
    }
}

// MARK: - User Invitation Models

/// User invitations list response
public struct ASCUserInvitationsResponse: Codable, Sendable {
    public let data: [ASCUserInvitation]
    public let links: ASCPagedDocumentLinks?
}

/// User invitation single response
public struct ASCUserInvitationResponse: Codable, Sendable {
    public let data: ASCUserInvitation
}

/// User invitation resource
public struct ASCUserInvitation: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: UserInvitationAttributes?
}

/// User invitation attributes
public struct UserInvitationAttributes: Codable, Sendable {
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let roles: [String]?
    public let allAppsVisible: Bool?
    public let provisioningAllowed: Bool?
    public let expirationDate: String?
}

// MARK: - Create User Invitation Request

/// Request body for creating a user invitation
public struct CreateUserInvitationRequest: Codable, Sendable {
    public let data: CreateUserInvitationData

    public struct CreateUserInvitationData: Codable, Sendable {
        public let type: String = "userInvitations"
        public let attributes: CreateUserInvitationAttributes
        public let relationships: CreateUserInvitationRelationships?
    }

    public struct CreateUserInvitationAttributes: Codable, Sendable {
        public let email: String
        public let firstName: String
        public let lastName: String
        public let roles: [String]
        public let allAppsVisible: Bool?
        public let provisioningAllowed: Bool?
    }

    public struct CreateUserInvitationRelationships: Codable, Sendable {
        public let visibleApps: VisibleAppsRelationship
    }

    public struct VisibleAppsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}
