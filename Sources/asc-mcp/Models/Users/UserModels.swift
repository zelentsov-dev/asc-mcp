import Foundation

// MARK: - User Models

/// Users list response
public struct ASCUsersResponse: Codable, Sendable {
    public let data: [ASCUser]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// User single response
public struct ASCUserResponse: Codable, Sendable {
    public let data: ASCUser
    public let included: [JSONValue]?
    public let links: JSONValue?
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
        public var type: String = "users"
        public let id: String
        public let attributes: UpdateUserAttributes
        public let relationships: UpdateUserRelationships?

        public init(
            id: String,
            attributes: UpdateUserAttributes,
            relationships: UpdateUserRelationships? = nil
        ) {
            self.id = id
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct UpdateUserAttributes: Codable, Sendable {
        public let roles: ASCNullable<[String]>?
        public let allAppsVisible: ASCNullable<Bool>?
        public let provisioningAllowed: ASCNullable<Bool>?

        /// Creates user update attributes from ordinary optional values.
        public init(
            roles: [String]? = nil,
            allAppsVisible: Bool? = nil,
            provisioningAllowed: Bool? = nil
        ) {
            self.roles = roles.map { .value($0) }
            self.allAppsVisible = allAppsVisible.map { .value($0) }
            self.provisioningAllowed = provisioningAllowed.map { .value($0) }
        }

        /// Creates user update attributes while preserving omission and explicit null.
        public init(
            nullableRoles: ASCNullable<[String]>?,
            nullableAllAppsVisible: ASCNullable<Bool>?,
            nullableProvisioningAllowed: ASCNullable<Bool>?
        ) {
            self.roles = nullableRoles
            self.allAppsVisible = nullableAllAppsVisible
            self.provisioningAllowed = nullableProvisioningAllowed
        }

        enum CodingKeys: String, CodingKey {
            case roles
            case allAppsVisible
            case provisioningAllowed
        }

        /// Decodes user update attributes while preserving explicit null values.
        /// - Parameter decoder: Decoder containing the user update attributes.
        /// - Throws: A decoding error when a present attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roles = try container.decodeASCNullable([String].self, forKey: .roles)
            allAppsVisible = try container.decodeASCNullable(Bool.self, forKey: .allAppsVisible)
            provisioningAllowed = try container.decodeASCNullable(Bool.self, forKey: .provisioningAllowed)
        }
    }

    public struct UpdateUserRelationships: Codable, Sendable {
        public let visibleApps: VisibleAppsRelationship?

        public init(visibleApps: VisibleAppsRelationship? = nil) {
            self.visibleApps = visibleApps
        }
    }

    public struct VisibleAppsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]

        public init(data: [ASCResourceIdentifier]) {
            self.data = data
        }
    }
}

// MARK: - User Invitation Models

/// User invitations list response
public struct ASCUserInvitationsResponse: Codable, Sendable {
    public let data: [ASCUserInvitation]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// User invitation single response
public struct ASCUserInvitationResponse: Codable, Sendable {
    public let data: ASCUserInvitation
    public let included: [JSONValue]?
    public let links: JSONValue?
}

/// User invitation resource
public struct ASCUserInvitation: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: UserInvitationAttributes?
    public let relationships: UserRelationships?
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
        public var type: String = "userInvitations"
        public let attributes: CreateUserInvitationAttributes
        public let relationships: CreateUserInvitationRelationships?
    }

    public struct CreateUserInvitationAttributes: Codable, Sendable {
        public let email: String
        public let firstName: String
        public let lastName: String
        public let roles: [String]
        public let allAppsVisible: ASCNullable<Bool>?
        public let provisioningAllowed: ASCNullable<Bool>?

        /// Creates invitation attributes from ordinary optional access-control values.
        public init(
            email: String,
            firstName: String,
            lastName: String,
            roles: [String],
            allAppsVisible: Bool?,
            provisioningAllowed: Bool?
        ) {
            self.email = email
            self.firstName = firstName
            self.lastName = lastName
            self.roles = roles
            self.allAppsVisible = allAppsVisible.map { .value($0) }
            self.provisioningAllowed = provisioningAllowed.map { .value($0) }
        }

        /// Creates invitation attributes while preserving omission and explicit null.
        public init(
            email: String,
            firstName: String,
            lastName: String,
            roles: [String],
            nullableAllAppsVisible: ASCNullable<Bool>?,
            nullableProvisioningAllowed: ASCNullable<Bool>?
        ) {
            self.email = email
            self.firstName = firstName
            self.lastName = lastName
            self.roles = roles
            self.allAppsVisible = nullableAllAppsVisible
            self.provisioningAllowed = nullableProvisioningAllowed
        }

        enum CodingKeys: String, CodingKey {
            case email
            case firstName
            case lastName
            case roles
            case allAppsVisible
            case provisioningAllowed
        }

        /// Decodes invitation attributes while preserving explicit null values.
        /// - Parameter decoder: Decoder containing the invitation attributes.
        /// - Throws: A decoding error when a present attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            email = try container.decode(String.self, forKey: .email)
            firstName = try container.decode(String.self, forKey: .firstName)
            lastName = try container.decode(String.self, forKey: .lastName)
            roles = try container.decode([String].self, forKey: .roles)
            allAppsVisible = try container.decodeASCNullable(Bool.self, forKey: .allAppsVisible)
            provisioningAllowed = try container.decodeASCNullable(Bool.self, forKey: .provisioningAllowed)
        }
    }

    public struct CreateUserInvitationRelationships: Codable, Sendable {
        public let visibleApps: VisibleAppsRelationship
    }

    public struct VisibleAppsRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}
