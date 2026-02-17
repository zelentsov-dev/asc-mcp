import Foundation

// MARK: - Shared Relationship Helper

/// Shared relationship data structure for API requests
struct RelationshipData: Codable, Sendable {
    let data: ResourceRef
    struct ResourceRef: Codable, Sendable {
        let type: String
        let id: String
    }
}

// MARK: - App Store Version Requests

/// Request to create a new app store version
struct CreateAppStoreVersionRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Codable, Sendable {
            let platform: String
            let versionString: String
            let releaseType: String?
            let earliestReleaseDate: String?
        }
        struct Relationships: Codable, Sendable {
            let app: RelationshipData
        }
    }

    init(platform: String, versionString: String, releaseType: String?, earliestReleaseDate: String?, appId: String) {
        self.data = Data(
            type: "appStoreVersions",
            attributes: Data.Attributes(
                platform: platform,
                versionString: versionString,
                releaseType: releaseType,
                earliestReleaseDate: earliestReleaseDate
            ),
            relationships: Data.Relationships(
                app: RelationshipData(data: .init(type: "apps", id: appId))
            )
        )
    }
}

/// Request to update an app store version
struct UpdateAppStoreVersionRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        struct Attributes: Codable, Sendable {
            let releaseType: String?
            let earliestReleaseDate: String?
            let copyright: String?
            let versionString: String?
        }
    }

    init(id: String, releaseType: String? = nil, earliestReleaseDate: String? = nil, copyright: String? = nil, versionString: String? = nil) {
        self.data = Data(
            type: "appStoreVersions",
            id: id,
            attributes: Data.Attributes(
                releaseType: releaseType,
                earliestReleaseDate: earliestReleaseDate,
                copyright: copyright,
                versionString: versionString
            )
        )
    }
}

/// Request to attach/detach a build to a version (PATCH relationship)
struct AttachBuildRequest: Codable, Sendable {
    let data: ResourceRef
    struct ResourceRef: Codable, Sendable {
        let type: String
        let id: String
    }

    init(buildId: String) {
        self.data = ResourceRef(type: "builds", id: buildId)
    }
}

// MARK: - Review Submission Requests

/// Request to create a review submission
struct CreateReviewSubmissionRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Codable, Sendable {
            let platform: String
        }
        struct Relationships: Codable, Sendable {
            let app: RelationshipData
        }
    }

    init(platform: String, appId: String) {
        self.data = Data(
            type: "reviewSubmissions",
            attributes: Data.Attributes(platform: platform),
            relationships: Data.Relationships(
                app: RelationshipData(data: .init(type: "apps", id: appId))
            )
        )
    }
}

/// Request to add an item to a review submission
struct CreateReviewSubmissionItemRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let relationships: Relationships
        struct Relationships: Codable, Sendable {
            let reviewSubmission: RelationshipData
            let appStoreVersion: RelationshipData
        }
    }

    init(submissionId: String, versionId: String) {
        self.data = Data(
            type: "reviewSubmissionItems",
            relationships: Data.Relationships(
                reviewSubmission: RelationshipData(data: .init(type: "reviewSubmissions", id: submissionId)),
                appStoreVersion: RelationshipData(data: .init(type: "appStoreVersions", id: versionId))
            )
        )
    }
}

/// Request to confirm a review submission
struct ConfirmReviewSubmissionRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        struct Attributes: Codable, Sendable {
            let submitted: Bool
        }
    }

    init(submissionId: String) {
        self.data = Data(
            type: "reviewSubmissions",
            id: submissionId,
            attributes: Data.Attributes(submitted: true)
        )
    }
}

/// Request to cancel a review submission
struct CancelReviewSubmissionRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        struct Attributes: Codable, Sendable {
            let canceled: Bool
        }
    }

    init(submissionId: String) {
        self.data = Data(
            type: "reviewSubmissions",
            id: submissionId,
            attributes: Data.Attributes(canceled: true)
        )
    }
}

// MARK: - Phased Release Requests

/// Request to create a phased release for a version
struct CreatePhasedReleaseRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Codable, Sendable {
            let phasedReleaseState: String
        }
        struct Relationships: Codable, Sendable {
            let appStoreVersion: RelationshipData
        }
    }

    init(versionId: String, state: String) {
        self.data = Data(
            type: "appStoreVersionPhasedReleases",
            attributes: Data.Attributes(phasedReleaseState: state),
            relationships: Data.Relationships(
                appStoreVersion: RelationshipData(data: .init(type: "appStoreVersions", id: versionId))
            )
        )
    }
}

/// Request to update a phased release state
struct UpdatePhasedReleaseRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        struct Attributes: Codable, Sendable {
            let phasedReleaseState: String
        }
    }

    init(phasedReleaseId: String, state: String) {
        self.data = Data(
            type: "appStoreVersionPhasedReleases",
            id: phasedReleaseId,
            attributes: Data.Attributes(phasedReleaseState: state)
        )
    }
}

// MARK: - Release Request

/// Request to release an approved version immediately
struct CreateReleaseRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let relationships: Relationships
        struct Relationships: Codable, Sendable {
            let appStoreVersion: RelationshipData
        }
    }

    init(versionId: String) {
        self.data = Data(
            type: "appStoreVersionReleaseRequests",
            relationships: Data.Relationships(
                appStoreVersion: RelationshipData(data: .init(type: "appStoreVersions", id: versionId))
            )
        )
    }
}

// MARK: - Review Details Requests

/// Request to create review details for a version
struct CreateAppStoreReviewDetailRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Codable, Sendable {
            let contactFirstName: String?
            let contactLastName: String?
            let contactPhone: String?
            let contactEmail: String?
            let demoAccountName: String?
            let demoAccountPassword: String?
            let demoAccountRequired: Bool?
            let notes: String?
            let attachmentAssetId: String?
        }
        struct Relationships: Codable, Sendable {
            let appStoreVersion: RelationshipData
        }
    }

    init(versionId: String, attributes: Data.Attributes) {
        self.data = Data(
            type: "appStoreReviewDetails",
            attributes: attributes,
            relationships: Data.Relationships(
                appStoreVersion: RelationshipData(data: .init(type: "appStoreVersions", id: versionId))
            )
        )
    }
}

/// Request to update review details
struct UpdateAppStoreReviewDetailRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        struct Attributes: Codable, Sendable {
            let contactFirstName: String?
            let contactLastName: String?
            let contactPhone: String?
            let contactEmail: String?
            let demoAccountName: String?
            let demoAccountPassword: String?
            let demoAccountRequired: Bool?
            let notes: String?
            let attachmentAssetId: String?
        }
    }

    init(reviewDetailId: String, attributes: Data.Attributes) {
        self.data = Data(
            type: "appStoreReviewDetails",
            id: reviewDetailId,
            attributes: attributes
        )
    }
}

// MARK: - Age Rating Requests

/// Request to update age rating declaration
struct UpdateAgeRatingDeclarationRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let id: String
        let attributes: [String: AgeRatingValue]
    }

    init(ageRatingId: String, attributes: [String: AgeRatingValue]) {
        self.data = Data(
            type: "ageRatingDeclarations",
            id: ageRatingId,
            attributes: attributes
        )
    }
}

/// Request to create age rating declaration
struct CreateAgeRatingDeclarationRequest: Codable, Sendable {
    let data: Data
    struct Data: Codable, Sendable {
        let type: String
        let attributes: [String: AgeRatingValue]
        let relationships: Relationships
        struct Relationships: Codable, Sendable {
            let appStoreVersion: RelationshipData
        }
    }

    init(versionId: String, attributes: [String: AgeRatingValue]) {
        self.data = Data(
            type: "ageRatingDeclarations",
            attributes: attributes,
            relationships: Data.Relationships(
                appStoreVersion: RelationshipData(data: .init(type: "appStoreVersions", id: versionId))
            )
        )
    }
}

/// Type-erased value for age rating attributes (string or bool)
enum AgeRatingValue: Codable, Sendable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String or Bool")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

// MARK: - Lightweight Response Wrappers

/// Lightweight wrapper for passthrough API responses
struct PassthroughAPIResponse: Codable, Sendable {
    let data: JSONValue
    let included: [JSONValue]?
    let links: JSONValue?
}

/// Wrapper for single-resource response where we need to extract the ID
struct SingleResourceResponse: Codable, Sendable {
    let data: ResourceData
    struct ResourceData: Codable, Sendable {
        let id: String
        let type: String
        let attributes: JSONValue?
        let relationships: JSONValue?
    }
}

/// Type-erased JSON value for passthrough responses
enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Convert to Any for JSONFormatter
    var asAny: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .object(let v): return v.mapValues { $0.asAny }
        case .array(let v): return v.map { $0.asAny }
        case .null: return NSNull()
        }
    }
}
