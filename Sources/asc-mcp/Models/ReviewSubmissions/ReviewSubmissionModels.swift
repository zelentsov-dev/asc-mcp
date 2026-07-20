import Foundation

enum ASCReviewSubmissionPlatform: String, Codable, CaseIterable, Sendable {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"
}

enum ASCReviewSubmissionState: String, Codable, CaseIterable, Sendable {
    case readyForReview = "READY_FOR_REVIEW"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case inReview = "IN_REVIEW"
    case unresolvedIssues = "UNRESOLVED_ISSUES"
    case canceling = "CANCELING"
    case completing = "COMPLETING"
    case complete = "COMPLETE"
}

enum ASCReviewSubmissionItemState: String, Codable, CaseIterable, Sendable {
    case readyForReview = "READY_FOR_REVIEW"
    case accepted = "ACCEPTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case removed = "REMOVED"
}

enum ASCReviewSubmissionNullablePlatform: Codable, Equatable, Sendable {
    case value(ASCReviewSubmissionPlatform)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(ASCReviewSubmissionPlatform.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let platform):
            try container.encode(platform)
        case .null:
            try container.encodeNil()
        }
    }
}

enum ASCReviewSubmissionNullableBool: Codable, Equatable, Sendable {
    case value(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(Bool.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum ASCReviewSubmissionItemRelation: String, CaseIterable, Sendable {
    case appStoreVersion
    case appCustomProductPageVersion
    case appStoreVersionExperimentV2
    case appEvent
    case backgroundAssetVersion
    case inAppPurchaseVersion
    case subscriptionVersion
    case subscriptionGroupVersion

    var resourceType: String {
        switch self {
        case .appStoreVersion:
            "appStoreVersions"
        case .appCustomProductPageVersion:
            "appCustomProductPageVersions"
        case .appStoreVersionExperimentV2:
            "appStoreVersionExperiments"
        case .appEvent:
            "appEvents"
        case .backgroundAssetVersion:
            "backgroundAssetVersions"
        case .inAppPurchaseVersion:
            "inAppPurchaseVersions"
        case .subscriptionVersion:
            "subscriptionVersions"
        case .subscriptionGroupVersion:
            "subscriptionGroupVersions"
        }
    }
}

struct ASCReviewSubmissionCreateRequest: Codable, Sendable {
    let data: ResourceData

    init(
        appID: String,
        platform: ASCReviewSubmissionNullablePlatform?
    ) {
        data = ResourceData(
            attributes: platform.map { Attributes(platform: $0) },
            relationships: Relationships(
                app: ASCReviewSubmissionRequiredRelationship(
                    data: ASCResourceIdentifier(type: "apps", id: appID)
                )
            )
        )
    }

    struct ResourceData: Codable, Sendable {
        let type = "reviewSubmissions"
        let attributes: Attributes?
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let platform: ASCReviewSubmissionNullablePlatform
    }

    struct Relationships: Codable, Sendable {
        let app: ASCReviewSubmissionRequiredRelationship
    }
}

struct ASCReviewSubmissionUpdateRequest: Codable, Sendable {
    let data: ResourceData

    init(
        submissionID: String,
        platform: ASCReviewSubmissionNullablePlatform? = nil,
        submitted: ASCReviewSubmissionNullableBool? = nil,
        canceled: ASCReviewSubmissionNullableBool? = nil
    ) {
        data = ResourceData(
            id: submissionID,
            attributes: Attributes(
                platform: platform,
                submitted: submitted,
                canceled: canceled
            )
        )
    }

    struct ResourceData: Codable, Sendable {
        let type = "reviewSubmissions"
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let platform: ASCReviewSubmissionNullablePlatform?
        let submitted: ASCReviewSubmissionNullableBool?
        let canceled: ASCReviewSubmissionNullableBool?
    }
}

struct ASCReviewSubmissionItemCreateRequest: Codable, Sendable {
    let data: ResourceData

    init(
        submissionID: String,
        relation: ASCReviewSubmissionItemRelation,
        resourceID: String
    ) {
        data = ResourceData(
            relationships: Relationships(
                submissionID: submissionID,
                relation: relation,
                resourceID: resourceID
            )
        )
    }

    struct ResourceData: Codable, Sendable {
        let type = "reviewSubmissionItems"
        let relationships: Relationships
    }

    struct Relationships: Codable, Sendable {
        let reviewSubmission: ASCReviewSubmissionRequiredRelationship
        let appStoreVersion: ASCReviewSubmissionRequiredRelationship?
        let appCustomProductPageVersion: ASCReviewSubmissionRequiredRelationship?
        let appStoreVersionExperimentV2: ASCReviewSubmissionRequiredRelationship?
        let appEvent: ASCReviewSubmissionRequiredRelationship?
        let backgroundAssetVersion: ASCReviewSubmissionRequiredRelationship?
        let inAppPurchaseVersion: ASCReviewSubmissionRequiredRelationship?
        let subscriptionVersion: ASCReviewSubmissionRequiredRelationship?
        let subscriptionGroupVersion: ASCReviewSubmissionRequiredRelationship?

        init(
            submissionID: String,
            relation: ASCReviewSubmissionItemRelation,
            resourceID: String
        ) {
            reviewSubmission = ASCReviewSubmissionRequiredRelationship(
                data: ASCResourceIdentifier(
                    type: "reviewSubmissions",
                    id: submissionID
                )
            )
            let resource = ASCReviewSubmissionRequiredRelationship(
                data: ASCResourceIdentifier(
                    type: relation.resourceType,
                    id: resourceID
                )
            )
            appStoreVersion = relation == .appStoreVersion ? resource : nil
            appCustomProductPageVersion = relation == .appCustomProductPageVersion ? resource : nil
            appStoreVersionExperimentV2 = relation == .appStoreVersionExperimentV2 ? resource : nil
            appEvent = relation == .appEvent ? resource : nil
            backgroundAssetVersion = relation == .backgroundAssetVersion ? resource : nil
            inAppPurchaseVersion = relation == .inAppPurchaseVersion ? resource : nil
            subscriptionVersion = relation == .subscriptionVersion ? resource : nil
            subscriptionGroupVersion = relation == .subscriptionGroupVersion ? resource : nil
        }
    }
}

struct ASCReviewSubmissionItemUpdateRequest: Codable, Sendable {
    let data: ResourceData

    init(
        itemID: String,
        resolved: ASCReviewSubmissionNullableBool?,
        removed: ASCReviewSubmissionNullableBool?
    ) {
        data = ResourceData(
            id: itemID,
            attributes: Attributes(resolved: resolved, removed: removed)
        )
    }

    struct ResourceData: Codable, Sendable {
        let type = "reviewSubmissionItems"
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let resolved: ASCReviewSubmissionNullableBool?
        let removed: ASCReviewSubmissionNullableBool?
    }
}

struct ASCReviewSubmissionRequiredRelationship: Codable, Sendable {
    let data: ASCResourceIdentifier
}

struct ASCReviewSubmissionResponse: Codable, Sendable {
    let data: ASCReviewSubmission
    let included: [ASCReviewSubmissionIncludedResource]?
    let links: ASCReviewSubmissionDocumentLinks
}

struct ASCReviewSubmissionsResponse: Codable, Sendable {
    let data: [ASCReviewSubmission]
    let included: [ASCReviewSubmissionIncludedResource]?
    let links: ASCPagedDocumentLinks
    let meta: ASCReviewSubmissionPagingInformation?
}

struct ASCReviewSubmissionItemResponse: Codable, Sendable {
    let data: ASCReviewSubmissionItem
    let included: [ASCReviewSubmissionIncludedResource]?
    let links: ASCReviewSubmissionDocumentLinks
}

struct ASCReviewSubmissionItemsResponse: Codable, Sendable {
    let data: [ASCReviewSubmissionItem]
    let included: [ASCReviewSubmissionIncludedResource]?
    let links: ASCPagedDocumentLinks
    let meta: ASCReviewSubmissionPagingInformation?
}

struct ASCReviewSubmissionDocumentLinks: Codable, Sendable {
    let `self`: String
}

struct ASCReviewSubmissionPagingInformation: Codable, Sendable {
    let paging: Paging

    struct Paging: Codable, Sendable {
        let total: Int?
        let limit: Int
        let nextCursor: String?
    }
}

struct ASCReviewSubmission: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?
    let links: ASCResourceLinks?

    struct Attributes: Codable, Sendable {
        let platform: ASCReviewSubmissionPlatform?
        let submittedDate: String?
        let state: ASCReviewSubmissionState?
    }

    struct Relationships: Codable, Sendable {
        let app: ASCRelationship?
        let items: ASCReviewSubmissionPagedItemsRelationship?
        let appStoreVersionForReview: ASCRelationship?
        let submittedByActor: ASCRelationship?
        let lastUpdatedByActor: ASCRelationship?
    }
}

struct ASCReviewSubmissionPagedItemsRelationship: Codable, Sendable {
    let links: ASCRelationshipLinks?
    let meta: ASCReviewSubmissionPagingInformation?
    let data: [ASCResourceIdentifier]?
}

struct ASCReviewSubmissionItem: Codable, Sendable {
    let type: String
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?
    let links: ASCResourceLinks?

    struct Attributes: Codable, Sendable {
        let state: ASCReviewSubmissionItemState?
    }

    struct Relationships: Codable, Sendable {
        let appStoreVersion: ASCRelationship?
        let appCustomProductPageVersion: ASCRelationship?
        let appStoreVersionExperiment: ASCRelationship?
        let appStoreVersionExperimentV2: ASCRelationship?
        let appEvent: ASCRelationship?
        let backgroundAssetVersion: ASCRelationship?
        let gameCenterAchievementVersion: ASCRelationship?
        let gameCenterActivityVersion: ASCRelationship?
        let gameCenterChallengeVersion: ASCRelationship?
        let gameCenterLeaderboardSetVersion: ASCRelationship?
        let gameCenterLeaderboardVersion: ASCRelationship?
        let inAppPurchaseVersion: ASCRelationship?
        let subscriptionVersion: ASCRelationship?
        let subscriptionGroupVersion: ASCRelationship?
    }
}

struct ASCReviewSubmissionIncludedResource: Codable, Sendable {
    let type: String
    let id: String
    let attributes: JSONValue?
    let relationships: JSONValue?
    let links: JSONValue?
}
