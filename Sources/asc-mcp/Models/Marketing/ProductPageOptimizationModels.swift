import Foundation

enum ASCPPOPlatform: String, Codable, CaseIterable, Sendable {
    case iOS = "IOS"
    case macOS = "MAC_OS"
    case tvOS = "TV_OS"
    case visionOS = "VISION_OS"
}

enum ASCPPOExperimentState: String, Codable, CaseIterable, Sendable {
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case readyForReview = "READY_FOR_REVIEW"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case inReview = "IN_REVIEW"
    case accepted = "ACCEPTED"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case completed = "COMPLETED"
    case stopped = "STOPPED"
}

enum ASCPPOExperimentResourceType: String, Codable, Sendable {
    case experiment = "appStoreVersionExperiments"
}

enum ASCPPOTreatmentResourceType: String, Codable, Sendable {
    case treatment = "appStoreVersionExperimentTreatments"
}

enum ASCPPOLocalizationResourceType: String, Codable, Sendable {
    case localization = "appStoreVersionExperimentTreatmentLocalizations"
}

enum ASCPPONullable<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    case value(Value)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(Value.self))
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

struct ASCPPODocumentLinks: Codable, Sendable {
    let `self`: String
}

struct ASCPPOToOneRelationship: Codable, Sendable {
    let data: ASCResourceIdentifier?
}

struct ASCPPOManyRelationship: Codable, Sendable {
    let data: [ASCResourceIdentifier]?
}

struct ASCExperimentsResponse: Codable, Sendable {
    let data: [ASCExperiment]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCExperimentResponse: Codable, Sendable {
    let data: ASCExperiment
    let links: ASCPPODocumentLinks
}

struct ASCExperiment: Codable, Sendable {
    let type: ASCPPOExperimentResourceType
    let id: String
    let attributes: ExperimentAttributes?
    let relationships: ExperimentRelationships?
    let links: ASCResourceLinks?
}

struct ExperimentRelationships: Codable, Sendable {
    let app: ASCPPOToOneRelationship?
    let latestControlVersion: ASCPPOToOneRelationship?
    let controlVersions: ASCPPOManyRelationship?
}

struct ExperimentAttributes: Codable, Sendable {
    let name: String?
    let platform: ASCPPOPlatform?
    let trafficProportion: Int?
    let state: ASCPPOExperimentState?
    let reviewRequired: Bool?
    let startDate: String?
    let endDate: String?
    let hasName: Bool
    let hasPlatform: Bool
    let hasTrafficProportion: Bool
    let hasState: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case platform
        case trafficProportion
        case state
        case reviewRequired
        case startDate
        case endDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasName = container.contains(.name)
        hasPlatform = container.contains(.platform)
        hasTrafficProportion = container.contains(.trafficProportion)
        hasState = container.contains(.state)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        platform = try container.decodeIfPresent(ASCPPOPlatform.self, forKey: .platform)
        trafficProportion = try container.decodeIfPresent(Int.self, forKey: .trafficProportion)
        state = try container.decodeIfPresent(ASCPPOExperimentState.self, forKey: .state)
        reviewRequired = try container.decodeIfPresent(Bool.self, forKey: .reviewRequired)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasName { try container.encode(name, forKey: .name) }
        if hasPlatform { try container.encode(platform, forKey: .platform) }
        if hasTrafficProportion { try container.encode(trafficProportion, forKey: .trafficProportion) }
        if hasState { try container.encode(state, forKey: .state) }
        try container.encodeIfPresent(reviewRequired, forKey: .reviewRequired)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
    }
}

struct ASCTreatmentsResponse: Codable, Sendable {
    let data: [ASCTreatment]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCTreatmentResponse: Codable, Sendable {
    let data: ASCTreatment
    let links: ASCPPODocumentLinks
}

struct ASCTreatment: Codable, Sendable {
    let type: ASCPPOTreatmentResourceType
    let id: String
    let attributes: TreatmentAttributes?
    let relationships: TreatmentRelationships?
    let links: ASCResourceLinks?
}

struct TreatmentRelationships: Codable, Sendable {
    let appStoreVersionExperiment: ASCPPOToOneRelationship?
    let appStoreVersionExperimentV2: ASCPPOToOneRelationship?
    let appStoreVersionExperimentTreatmentLocalizations: ASCPPOManyRelationship?
}

struct TreatmentAttributes: Codable, Sendable {
    let name: String?
    let appIcon: ASCImageAsset?
    let appIconName: String?
    let promotedDate: String?
    let hasName: Bool
    let hasAppIconName: Bool

    private enum CodingKeys: String, CodingKey {
        case name
        case appIcon
        case appIconName
        case promotedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasName = container.contains(.name)
        hasAppIconName = container.contains(.appIconName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        appIcon = try container.decodeIfPresent(ASCImageAsset.self, forKey: .appIcon)
        appIconName = try container.decodeIfPresent(String.self, forKey: .appIconName)
        promotedDate = try container.decodeIfPresent(String.self, forKey: .promotedDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasName { try container.encode(name, forKey: .name) }
        try container.encodeIfPresent(appIcon, forKey: .appIcon)
        if hasAppIconName { try container.encode(appIconName, forKey: .appIconName) }
        try container.encodeIfPresent(promotedDate, forKey: .promotedDate)
    }
}

struct ASCTreatmentLocalizationsResponse: Codable, Sendable {
    let data: [ASCTreatmentLocalization]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCTreatmentLocalizationResponse: Codable, Sendable {
    let data: ASCTreatmentLocalization
    let links: ASCPPODocumentLinks
}

struct ASCTreatmentLocalization: Codable, Sendable {
    let type: ASCPPOLocalizationResourceType
    let id: String
    let attributes: TreatmentLocalizationAttributes?
    let relationships: TreatmentLocalizationRelationships?
    let links: ASCResourceLinks?
}

struct TreatmentLocalizationRelationships: Codable, Sendable {
    let appStoreVersionExperimentTreatment: ASCPPOToOneRelationship?
}

struct TreatmentLocalizationAttributes: Codable, Sendable {
    let locale: String?
    let hasLocale: Bool

    private enum CodingKeys: String, CodingKey {
        case locale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasLocale = container.contains(.locale)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if hasLocale { try container.encode(locale, forKey: .locale) }
    }
}

struct CreateExperimentRequest: Codable, Sendable {
    let data: CreateData

    struct CreateData: Codable, Sendable {
        var type: ASCPPOExperimentResourceType = .experiment
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let name: String
        let trafficProportion: Int
        let platform: ASCPPOPlatform
    }

    struct Relationships: Codable, Sendable {
        let app: AppRelationship
    }

    struct AppRelationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct UpdateExperimentRequest: Codable, Sendable {
    let data: UpdateData

    struct UpdateData: Codable, Sendable {
        var type: ASCPPOExperimentResourceType = .experiment
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let name: ASCPPONullable<String>?
        let trafficProportion: ASCPPONullable<Int>?
        let started: ASCPPONullable<Bool>?
    }
}

struct CreateTreatmentRequest: Codable, Sendable {
    let data: CreateData

    struct CreateData: Codable, Sendable {
        var type: ASCPPOTreatmentResourceType = .treatment
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let name: String
        let appIconName: ASCPPONullable<String>?
    }

    struct Relationships: Codable, Sendable {
        let appStoreVersionExperimentV2: ExperimentRelationship
    }

    struct ExperimentRelationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct UpdateTreatmentRequest: Codable, Sendable {
    let data: UpdateData

    struct UpdateData: Codable, Sendable {
        var type: ASCPPOTreatmentResourceType = .treatment
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let name: ASCPPONullable<String>?
        let appIconName: ASCPPONullable<String>?
    }
}

struct CreateTreatmentLocalizationRequest: Codable, Sendable {
    let data: CreateData

    struct CreateData: Codable, Sendable {
        var type: ASCPPOLocalizationResourceType = .localization
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let locale: String
    }

    struct Relationships: Codable, Sendable {
        let appStoreVersionExperimentTreatment: TreatmentRelationship
    }

    struct TreatmentRelationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}
