//
//  AnalyticsModels.swift
//  asc-mcp
//
//  Models for App Store Connect Analytics and Reports API
//

import Foundation

// MARK: - Analytics Report Request Models

/// Response containing a list of analytics report requests
public struct ASCAnalyticsReportRequestsResponse: Codable, Sendable {
    public let data: [ASCAnalyticsReportRequest]
    public let links: ASCPagedDocumentLinks?
}

/// Response containing a single analytics report request
public struct ASCAnalyticsReportRequestResponse: Codable, Sendable {
    public let data: ASCAnalyticsReportRequest
}

/// Analytics report request resource
public struct ASCAnalyticsReportRequest: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AnalyticsReportRequestAttributes?
}

/// Attributes for an analytics report request
public struct AnalyticsReportRequestAttributes: Codable, Sendable {
    public let accessType: String?
    public let stoppedDueToInactivity: Bool?
}

// MARK: - Create Analytics Report Request

/// Request body for creating an analytics report request
public struct CreateAnalyticsReportRequestRequest: Codable, Sendable {
    public let data: CreateAnalyticsReportRequestData

    public struct CreateAnalyticsReportRequestData: Codable, Sendable {
        public let type: String = "analyticsReportRequests"
        public let attributes: CreateAnalyticsReportRequestAttributes
        public let relationships: CreateAnalyticsReportRequestRelationships
    }

    public struct CreateAnalyticsReportRequestAttributes: Codable, Sendable {
        public let accessType: String
    }

    public struct CreateAnalyticsReportRequestRelationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Analytics Report Models

/// Response containing a list of analytics reports
public struct ASCAnalyticsReportsResponse: Codable, Sendable {
    public let data: [ASCAnalyticsReport]
    public let links: ASCPagedDocumentLinks?
}

/// Response containing a single analytics report
public struct ASCAnalyticsReportResponse: Codable, Sendable {
    public let data: ASCAnalyticsReport
}

/// Analytics report resource
public struct ASCAnalyticsReport: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AnalyticsReportAttributes?
}

/// Attributes for an analytics report
public struct AnalyticsReportAttributes: Codable, Sendable {
    public let category: String?
    public let name: String?
}

// MARK: - Analytics Report Instance Models

/// Response containing a list of analytics report instances
public struct ASCAnalyticsReportInstancesResponse: Codable, Sendable {
    public let data: [ASCAnalyticsReportInstance]
    public let links: ASCPagedDocumentLinks?
}

/// Response containing a single analytics report instance
public struct ASCAnalyticsReportInstanceResponse: Codable, Sendable {
    public let data: ASCAnalyticsReportInstance
}

/// Analytics report instance resource
public struct ASCAnalyticsReportInstance: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AnalyticsReportInstanceAttributes?
}

/// Attributes for an analytics report instance
public struct AnalyticsReportInstanceAttributes: Codable, Sendable {
    public let granularity: String?
    public let processingDate: String?
}

// MARK: - Analytics Report Segment Models

/// Response containing a list of analytics report segments
public struct ASCAnalyticsReportSegmentsResponse: Codable, Sendable {
    public let data: [ASCAnalyticsReportSegment]
    public let links: ASCPagedDocumentLinks?
}

/// Analytics report segment resource
public struct ASCAnalyticsReportSegment: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: AnalyticsReportSegmentAttributes?
}

/// Attributes for an analytics report segment
public struct AnalyticsReportSegmentAttributes: Codable, Sendable {
    public let checksum: String?
    public let sizeInBytes: Int?
    public let url: String?
}
