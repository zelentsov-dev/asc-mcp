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
