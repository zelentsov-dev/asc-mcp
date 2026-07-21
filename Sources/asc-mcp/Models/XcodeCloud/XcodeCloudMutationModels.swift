import Foundation

enum XcodeCloudMutationPresence: Sendable {
    case omitted
    case null
    case value(JSONValue)

    var jsonValue: JSONValue? {
        switch self {
        case .omitted:
            nil
        case .null:
            .null
        case .value(let value):
            value
        }
    }
}

struct XcodeCloudMutationResourceDocument: Decodable, Sendable {
    let data: XcodeCloudMutationResource
    let included: [JSONValue]?
    let links: XcodeCloudMutationDocumentLinks

    private enum CodingKeys: String, CodingKey {
        case data
        case included
        case links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(XcodeCloudMutationResource.self, forKey: .data)
        links = try container.decode(XcodeCloudMutationDocumentLinks.self, forKey: .links)
        included = container.contains(.included)
            ? try container.decode([JSONValue].self, forKey: .included)
            : nil
    }
}

struct XcodeCloudMutationResource: Decodable, Sendable {
    let type: String
    let id: String
    let attributes: [String: JSONValue]?
    let relationships: [String: JSONValue]?
    let links: XcodeCloudMutationResourceLinks?

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case attributes
        case relationships
        case links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        attributes = container.contains(.attributes)
            ? try container.decode([String: JSONValue].self, forKey: .attributes)
            : nil
        relationships = container.contains(.relationships)
            ? try container.decode([String: JSONValue].self, forKey: .relationships)
            : nil
        links = container.contains(.links)
            ? try container.decode(XcodeCloudMutationResourceLinks.self, forKey: .links)
            : nil
    }
}

struct XcodeCloudMutationDocumentLinks: Decodable, Sendable {
    let `self`: String
}

struct XcodeCloudMutationResourceLinks: Decodable, Sendable {
    let `self`: String?

    private enum CodingKeys: String, CodingKey {
        case `self`
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.`self` = container.contains(CodingKeys.`self`)
            ? try container.decode(String.self, forKey: CodingKeys.`self`)
            : nil
    }
}

struct XcodeCloudMutationCollectionDocument: Decodable, Sendable {
    let data: [XcodeCloudMutationResourceIdentifier]
    let links: XcodeCloudMutationPagedDocumentLinks
    let meta: XcodeCloudMutationPagingInformation?
}

struct XcodeCloudMutationResourceIdentifier: Decodable, Sendable {
    let type: String
    let id: String
}

struct XcodeCloudMutationPagedDocumentLinks: Decodable, Sendable {
    let `self`: String
    let first: String?
    let next: String?
}

struct XcodeCloudMutationPagingInformation: Decodable, Sendable {
    let paging: Paging

    struct Paging: Decodable, Sendable {
        let total: Int?
        let limit: Int
        let nextCursor: String?
    }
}

struct XcodeCloudWorkflowMutationRequestPlan: Sendable {
    let body: Data
    let attributes: [String: XcodeCloudMutationPresence]
    let relationships: [String: XcodeCloudMutationResourceIdentifier]
}
