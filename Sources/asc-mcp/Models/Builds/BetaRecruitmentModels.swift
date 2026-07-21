import Foundation

enum ASCDeviceFamily: String, Codable, Equatable, Sendable {
    case iPhone = "IPHONE"
    case iPad = "IPAD"
    case appleTV = "APPLE_TV"
    case appleWatch = "APPLE_WATCH"
    case mac = "MAC"
    case vision = "VISION"
}

struct ASCBetaRecruitmentDocumentLinks: Codable, Sendable {
    let `self`: String
}

struct ASCBetaRecruitmentParentResponse: Codable, Sendable {
    let data: ASCResourceIdentifier
    let links: ASCBetaRecruitmentDocumentLinks
}

struct ASCBetaRecruitmentCriterionResponse: Codable, Sendable {
    let data: ASCBetaRecruitmentCriterion
    let links: ASCBetaRecruitmentDocumentLinks
}

struct ASCBetaRecruitmentCriterion: Codable, Sendable {
    let type: ASCBetaRecruitmentCriterionType
    let id: String
    let attributes: ASCBetaRecruitmentCriterionAttributes?
    let links: ASCResourceLinks?
}

enum ASCBetaRecruitmentCriterionType: String, Codable, Sendable {
    case betaRecruitmentCriteria
}

struct ASCBetaRecruitmentCriterionAttributes: Codable, Sendable {
    let lastModifiedDate: String?
    let deviceFamilyOsVersionFilters: [ASCDeviceFamilyOsVersionFilter]?
    let hasDeviceFamilyOsVersionFilters: Bool

    private enum CodingKeys: String, CodingKey {
        case lastModifiedDate
        case deviceFamilyOsVersionFilters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastModifiedDate = try container.decodeIfPresent(String.self, forKey: .lastModifiedDate)
        hasDeviceFamilyOsVersionFilters = container.contains(.deviceFamilyOsVersionFilters)
        deviceFamilyOsVersionFilters = try container.decodeIfPresent(
            [ASCDeviceFamilyOsVersionFilter].self,
            forKey: .deviceFamilyOsVersionFilters
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastModifiedDate, forKey: .lastModifiedDate)
        if hasDeviceFamilyOsVersionFilters {
            if let deviceFamilyOsVersionFilters {
                try container.encode(deviceFamilyOsVersionFilters, forKey: .deviceFamilyOsVersionFilters)
            } else {
                try container.encodeNil(forKey: .deviceFamilyOsVersionFilters)
            }
        }
    }
}

struct ASCDeviceFamilyOsVersionFilter: Codable, Equatable, Sendable {
    let deviceFamily: ASCDeviceFamily?
    let minimumOsInclusive: String?
    let maximumOsInclusive: String?
}

struct ASCBetaRecruitmentCriterionOptionsResponse: Codable, Sendable {
    let data: [ASCBetaRecruitmentCriterionOption]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
}

struct ASCBetaRecruitmentCriterionOption: Codable, Sendable {
    let type: ASCBetaRecruitmentCriterionOptionType
    let id: String
    let attributes: ASCBetaRecruitmentCriterionOptionAttributes?
    let links: ASCResourceLinks?
}

enum ASCBetaRecruitmentCriterionOptionType: String, Codable, Sendable {
    case betaRecruitmentCriterionOptions
}

struct ASCBetaRecruitmentCriterionOptionAttributes: Codable, Sendable {
    let deviceFamilyOsVersions: [ASCDeviceFamilyOsVersions]?
}

struct ASCDeviceFamilyOsVersions: Codable, Sendable {
    let deviceFamily: ASCDeviceFamily?
    let osVersions: [String]?
}

struct ASCBetaRecruitmentCompatibilityResponse: Codable, Sendable {
    let data: ASCBetaRecruitmentCompatibility
    let links: ASCBetaRecruitmentDocumentLinks
}

struct ASCBetaRecruitmentCompatibility: Codable, Sendable {
    let type: ASCBetaRecruitmentCompatibilityType
    let id: String
    let attributes: ASCBetaRecruitmentCompatibilityAttributes?
    let links: ASCResourceLinks?
}

enum ASCBetaRecruitmentCompatibilityType: String, Codable, Sendable {
    case betaRecruitmentCriterionCompatibleBuildChecks
}

struct ASCBetaRecruitmentCompatibilityAttributes: Codable, Sendable {
    let hasCompatibleBuild: Bool?
}

struct CreateBetaRecruitmentCriterionRequest: Codable, Sendable {
    let data: DataPayload

    struct DataPayload: Codable, Sendable {
        var type = "betaRecruitmentCriteria"
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Codable, Sendable {
        let deviceFamilyOsVersionFilters: [ASCDeviceFamilyOsVersionFilter]
    }

    struct Relationships: Codable, Sendable {
        let betaGroup: BetaGroupRelationship
    }

    struct BetaGroupRelationship: Codable, Sendable {
        let data: ASCResourceIdentifier
    }
}

struct UpdateBetaRecruitmentCriterionRequest: Codable, Sendable {
    let data: DataPayload

    struct DataPayload: Codable, Sendable {
        var type = "betaRecruitmentCriteria"
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable, Sendable {
        let deviceFamilyOsVersionFilters: ASCNullableDeviceFamilyOsVersionFilters
    }
}

enum ASCNullableDeviceFamilyOsVersionFilters: Codable, Sendable {
    case value([ASCDeviceFamilyOsVersionFilter])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let filters):
            try container.encode(filters)
        case .null:
            try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode([ASCDeviceFamilyOsVersionFilter].self))
        }
    }
}
