import Foundation

public enum ASCWebhookEventTypes {
    public static let all: [String] = [
        "ALTERNATIVE_DISTRIBUTION_PACKAGE_AVAILABLE_UPDATED",
        "ALTERNATIVE_DISTRIBUTION_PACKAGE_VERSION_CREATED",
        "ALTERNATIVE_DISTRIBUTION_TERRITORY_AVAILABILITY_UPDATED",
        "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED",
        "BACKGROUND_ASSET_VERSION_APP_STORE_RELEASE_STATE_UPDATED",
        "BACKGROUND_ASSET_VERSION_EXTERNAL_BETA_RELEASE_STATE_UPDATED",
        "BACKGROUND_ASSET_VERSION_INTERNAL_BETA_RELEASE_CREATED",
        "BACKGROUND_ASSET_VERSION_STATE_UPDATED",
        "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED",
        "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED",
        "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED",
        "BUILD_UPLOAD_STATE_UPDATED"
    ]
}

public struct ASCWebhooksResponse: Codable, Sendable {
    public let data: [ASCWebhook]
    public let included: [JSONValue]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCWebhookResponse: Codable, Sendable {
    public let data: ASCWebhook
    public let included: [JSONValue]?
    let links: JSONValue?
}

public struct ASCWebhook: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let enabled: Bool?
        public let eventTypes: [String]?
        public let name: String?
        public let url: String?
    }

    public struct Relationships: Codable, Sendable {
        public let app: ASCRelationship?
        public let deliveries: ASCRelationshipMultiple?
    }
}

public struct ASCWebhookDeliveriesResponse: Codable, Sendable {
    public let data: [ASCWebhookDelivery]
    public let included: [ASCWebhookEvent]?
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCWebhookDeliveryResponse: Codable, Sendable {
    public let data: ASCWebhookDelivery
    public let included: [ASCWebhookEvent]?
    let links: JSONValue?
}

public struct ASCWebhookDelivery: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let createdDate: String?
        public let deliveryState: String?
        public let errorMessage: String?
        public let redelivery: Bool?
        public let sentDate: String?
        public let request: Request?
        public let response: Response?

        public struct Request: Codable, Sendable {
            public let url: String?
        }

        public struct Response: Codable, Sendable {
            public let httpStatusCode: Int?
            public let body: String?
        }
    }

    public struct Relationships: Codable, Sendable {
        public let event: ASCRelationship?
    }
}

public struct ASCWebhookEvent: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let eventType: String?
        public let payload: String?
        public let ping: Bool?
        public let createdDate: String?
    }
}

public struct ASCWebhookPingResponse: Codable, Sendable {
    public let data: ASCWebhookPing
    let links: JSONValue?
}

public struct ASCWebhookPing: Codable, Sendable {
    public let type: String
    public let id: String
    public let links: ASCResourceLinks?
}

public struct ASCResourceLinks: Codable, Sendable {
    public let `self`: String?
}

public struct ASCPagingInformation: Codable, Sendable {
    public let paging: Paging?

    public struct Paging: Codable, Sendable {
        public let total: Int?
        public let limit: Int?
    }
}

public struct ASCWebhookCreateRequest: Codable, Sendable {
    public let data: ResourceData

    public init(appID: String, name: String, url: String, secret: String, eventTypes: [String], enabled: Bool) {
        self.data = ResourceData(
            attributes: Attributes(
                enabled: enabled,
                eventTypes: eventTypes,
                name: name,
                secret: secret,
                url: url
            ),
            relationships: Relationships(
                app: Relationship(data: ASCResourceIdentifier(type: "apps", id: appID))
            )
        )
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships

        public init(attributes: Attributes, relationships: Relationships) {
            self.type = "webhooks"
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let enabled: Bool
        public let eventTypes: [String]
        public let name: String
        public let secret: String
        public let url: String
    }

    public struct Relationships: Codable, Sendable {
        public let app: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

public struct ASCWebhookUpdateRequest: Codable, Sendable {
    public let data: ResourceData

    public init(webhookID: String, attributes: Attributes) {
        self.data = ResourceData(id: webhookID, attributes: attributes)
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes

        public init(id: String, attributes: Attributes) {
            self.type = "webhooks"
            self.id = id
            self.attributes = attributes
        }
    }

    public struct Attributes: Codable, Sendable {
        public let enabled: Bool?
        public let eventTypes: [String]?
        public let name: String?
        public let secret: String?
        public let url: String?

        public var hasChanges: Bool {
            enabled != nil || eventTypes != nil || name != nil || secret != nil || url != nil
        }
    }
}

public struct ASCWebhookDeliveryCreateRequest: Codable, Sendable {
    public let data: ResourceData

    public init(templateDeliveryID: String) {
        self.data = ResourceData(
            relationships: Relationships(
                template: Relationship(
                    data: ASCResourceIdentifier(type: "webhookDeliveries", id: templateDeliveryID)
                )
            )
        )
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let relationships: Relationships

        public init(relationships: Relationships) {
            self.type = "webhookDeliveries"
            self.relationships = relationships
        }
    }

    public struct Relationships: Codable, Sendable {
        public let template: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

public struct ASCWebhookPingCreateRequest: Codable, Sendable {
    public let data: ResourceData

    public init(webhookID: String) {
        self.data = ResourceData(
            relationships: Relationships(
                webhook: Relationship(
                    data: ASCResourceIdentifier(type: "webhooks", id: webhookID)
                )
            )
        )
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let relationships: Relationships

        public init(relationships: Relationships) {
            self.type = "webhookPings"
            self.relationships = relationships
        }
    }

    public struct Relationships: Codable, Sendable {
        public let webhook: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
