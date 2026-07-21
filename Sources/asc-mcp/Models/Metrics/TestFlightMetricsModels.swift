import Foundation

struct ASCBetaTesterUsageMetricsResponse: Decodable, Sendable {
    let data: [ASCBetaTesterUsageMetricGroup]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?
    let included: [ASCTestFlightIncludedBetaTester]?

    private enum CodingKeys: String, CodingKey {
        case data
        case links
        case meta
        case included
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["data", "links", "meta", "included"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ASCBetaTesterUsageMetricGroup].self, forKey: .data)
        links = try container.decode(ASCPagedDocumentLinks.self, forKey: .links)
        meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
        included = try container.decodeIfPresent([ASCTestFlightIncludedBetaTester].self, forKey: .included)
    }
}

struct ASCTesterUsageMetricsResponse: Decodable, Sendable {
    let data: [ASCTesterUsageMetricGroup]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?

    private enum CodingKeys: String, CodingKey {
        case data
        case links
        case meta
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["data", "links", "meta"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ASCTesterUsageMetricGroup].self, forKey: .data)
        links = try container.decode(ASCPagedDocumentLinks.self, forKey: .links)
        meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

struct ASCPublicLinkUsageMetricsResponse: Decodable, Sendable {
    let data: [ASCPublicLinkUsageMetricGroup]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?

    private enum CodingKeys: String, CodingKey {
        case data
        case links
        case meta
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["data", "links", "meta"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ASCPublicLinkUsageMetricGroup].self, forKey: .data)
        links = try container.decode(ASCPagedDocumentLinks.self, forKey: .links)
        meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

struct ASCBuildBetaUsageMetricsResponse: Decodable, Sendable {
    let data: [ASCBuildBetaUsageMetricGroup]
    let links: ASCPagedDocumentLinks
    let meta: ASCPagingInformation?

    private enum CodingKeys: String, CodingKey {
        case data
        case links
        case meta
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["data", "links", "meta"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ASCBuildBetaUsageMetricGroup].self, forKey: .data)
        links = try container.decode(ASCPagedDocumentLinks.self, forKey: .links)
        meta = try container.decodeIfPresent(ASCPagingInformation.self, forKey: .meta)
    }
}

struct ASCBetaTesterUsageMetricGroup: Decodable, Sendable {
    let dataPoints: [ASCBetaTesterUsageMetricDataPoint]?
    let dimensions: ASCBetaTesterUsageMetricDimensions?

    private enum CodingKeys: String, CodingKey {
        case dataPoints
        case dimensions
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["dataPoints", "dimensions"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataPoints = try container.decodeIfPresent([ASCBetaTesterUsageMetricDataPoint].self, forKey: .dataPoints)
        dimensions = try container.decodeIfPresent(ASCBetaTesterUsageMetricDimensions.self, forKey: .dimensions)
    }
}

struct ASCTesterUsageMetricGroup: Decodable, Sendable {
    let dataPoints: [ASCBetaTesterUsageMetricDataPoint]?
    let dimensions: ASCTesterUsageMetricDimensions?

    private enum CodingKeys: String, CodingKey {
        case dataPoints
        case dimensions
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["dataPoints", "dimensions"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataPoints = try container.decodeIfPresent([ASCBetaTesterUsageMetricDataPoint].self, forKey: .dataPoints)
        dimensions = try container.decodeIfPresent(ASCTesterUsageMetricDimensions.self, forKey: .dimensions)
    }
}

struct ASCPublicLinkUsageMetricGroup: Decodable, Sendable {
    let dataPoints: [ASCPublicLinkUsageMetricDataPoint]?

    private enum CodingKeys: String, CodingKey {
        case dataPoints
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["dataPoints"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataPoints = try container.decodeIfPresent([ASCPublicLinkUsageMetricDataPoint].self, forKey: .dataPoints)
    }
}

struct ASCBuildBetaUsageMetricGroup: Decodable, Sendable {
    let dataPoints: [ASCBuildBetaUsageMetricDataPoint]?

    private enum CodingKeys: String, CodingKey {
        case dataPoints
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["dataPoints"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataPoints = try container.decodeIfPresent([ASCBuildBetaUsageMetricDataPoint].self, forKey: .dataPoints)
    }
}

struct ASCBetaTesterUsageMetricDataPoint: Decodable, Sendable {
    let start: String?
    let end: String?
    let values: ASCBetaTesterUsageMetricValues?

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case values
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["start", "end", "values"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        values = try container.decodeIfPresent(ASCBetaTesterUsageMetricValues.self, forKey: .values)
    }
}

struct ASCPublicLinkUsageMetricDataPoint: Decodable, Sendable {
    let start: String?
    let end: String?
    let values: ASCPublicLinkUsageMetricValues?

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case values
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["start", "end", "values"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        values = try container.decodeIfPresent(ASCPublicLinkUsageMetricValues.self, forKey: .values)
    }
}

struct ASCBuildBetaUsageMetricDataPoint: Decodable, Sendable {
    let start: String?
    let end: String?
    let values: ASCBuildBetaUsageMetricValues?

    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case values
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["start", "end", "values"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end)
        values = try container.decodeIfPresent(ASCBuildBetaUsageMetricValues.self, forKey: .values)
    }
}

struct ASCBetaTesterUsageMetricValues: Decodable, Sendable {
    let crashCount: Int?
    let sessionCount: Int?
    let feedbackCount: Int?

    private enum CodingKeys: String, CodingKey {
        case crashCount
        case sessionCount
        case feedbackCount
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["crashCount", "sessionCount", "feedbackCount"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crashCount = try container.decodeIfPresent(Int.self, forKey: .crashCount)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount)
        feedbackCount = try container.decodeIfPresent(Int.self, forKey: .feedbackCount)
    }
}

struct ASCPublicLinkUsageMetricValues: Decodable, Sendable {
    let viewCount: Int?
    let acceptedCount: Int?
    let didNotAcceptCount: Int?
    let didNotMeetCriteriaCount: Int?
    let notRelevantRatio: Double?
    let notClearRatio: Double?
    let notInterestingRatio: Double?

    private enum CodingKeys: String, CodingKey {
        case viewCount
        case acceptedCount
        case didNotAcceptCount
        case didNotMeetCriteriaCount
        case notRelevantRatio
        case notClearRatio
        case notInterestingRatio
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(
            decoder,
            allowed: [
                "viewCount", "acceptedCount", "didNotAcceptCount", "didNotMeetCriteriaCount",
                "notRelevantRatio", "notClearRatio", "notInterestingRatio"
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        acceptedCount = try container.decodeIfPresent(Int.self, forKey: .acceptedCount)
        didNotAcceptCount = try container.decodeIfPresent(Int.self, forKey: .didNotAcceptCount)
        didNotMeetCriteriaCount = try container.decodeIfPresent(Int.self, forKey: .didNotMeetCriteriaCount)
        notRelevantRatio = try container.decodeIfPresent(Double.self, forKey: .notRelevantRatio)
        notClearRatio = try container.decodeIfPresent(Double.self, forKey: .notClearRatio)
        notInterestingRatio = try container.decodeIfPresent(Double.self, forKey: .notInterestingRatio)
    }
}

struct ASCBuildBetaUsageMetricValues: Decodable, Sendable {
    let crashCount: Int?
    let installCount: Int?
    let sessionCount: Int?
    let feedbackCount: Int?
    let inviteCount: Int?

    private enum CodingKeys: String, CodingKey {
        case crashCount
        case installCount
        case sessionCount
        case feedbackCount
        case inviteCount
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(
            decoder,
            allowed: ["crashCount", "installCount", "sessionCount", "feedbackCount", "inviteCount"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crashCount = try container.decodeIfPresent(Int.self, forKey: .crashCount)
        installCount = try container.decodeIfPresent(Int.self, forKey: .installCount)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount)
        feedbackCount = try container.decodeIfPresent(Int.self, forKey: .feedbackCount)
        inviteCount = try container.decodeIfPresent(Int.self, forKey: .inviteCount)
    }
}

struct ASCBetaTesterUsageMetricDimensions: Decodable, Sendable {
    let betaTesters: ASCTestFlightMetricDimension?

    private enum CodingKeys: String, CodingKey {
        case betaTesters
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["betaTesters"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        betaTesters = try container.decodeIfPresent(ASCTestFlightMetricDimension.self, forKey: .betaTesters)
    }
}

struct ASCTesterUsageMetricDimensions: Decodable, Sendable {
    let apps: ASCTestFlightMetricDimension?

    private enum CodingKeys: String, CodingKey {
        case apps
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["apps"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent(ASCTestFlightMetricDimension.self, forKey: .apps)
    }
}

struct ASCTestFlightMetricDimension: Decodable, Sendable {
    let links: ASCTestFlightMetricDimensionLinks?
    let data: String?

    private enum CodingKeys: String, CodingKey {
        case links
        case data
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["links", "data"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        links = try container.decodeIfPresent(ASCTestFlightMetricDimensionLinks.self, forKey: .links)
        data = try container.decodeIfPresent(String.self, forKey: .data)
    }
}

struct ASCTestFlightMetricDimensionLinks: Decodable, Sendable {
    let groupBy: String?
    let related: String?

    private enum CodingKeys: String, CodingKey {
        case groupBy
        case related
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["groupBy", "related"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupBy = try container.decodeIfPresent(String.self, forKey: .groupBy)
        related = try container.decodeIfPresent(String.self, forKey: .related)
    }
}

struct ASCTestFlightIncludedBetaTester: Decodable, Sendable {
    let type: ASCTestFlightIncludedBetaTesterType
    let id: String
    let attributes: BetaTesterAttributes?
    let relationships: BetaTesterRelationships?
    let links: ASCResourceLinks?

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case attributes
        case relationships
        case links
    }

    init(from decoder: Decoder) throws {
        try validateMetricKeys(decoder, allowed: ["type", "id", "attributes", "relationships", "links"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ASCTestFlightIncludedBetaTesterType.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        attributes = try container.decodeIfPresent(BetaTesterAttributes.self, forKey: .attributes)
        relationships = try container.decodeIfPresent(BetaTesterRelationships.self, forKey: .relationships)
        links = try container.decodeIfPresent(ASCResourceLinks.self, forKey: .links)
    }
}

enum ASCTestFlightIncludedBetaTesterType: String, Codable, Sendable {
    case betaTesters
}

private struct ASCMetricCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func validateMetricKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: ASCMetricCodingKey.self)
    let unsupported = Set(container.allKeys.map(\.stringValue)).subtracting(allowed).sorted()
    guard unsupported.isEmpty else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported TestFlight metric field(s): \(unsupported.joined(separator: ", "))"
            )
        )
    }
}
