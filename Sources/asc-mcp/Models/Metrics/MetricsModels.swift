//
//  MetricsModels.swift
//  asc-mcp
//
//  Models for App Store Connect Performance Metrics and Diagnostics API
//

import Foundation

// MARK: - Performance Power Metrics

/// perfPowerMetrics returns a non-standard format (array of metric categories)
public struct ASCPerfPowerMetricsResponse: Codable, Sendable {
    public let productData: [ASCProductData]?
}

public struct ASCProductData: Codable, Sendable {
    public let platform: String?
    public let metricCategories: [ASCMetricCategory]?
}

public struct ASCMetricCategory: Codable, Sendable {
    public let identifier: String?
    public let metrics: [ASCMetric]?
}

public struct ASCMetric: Codable, Sendable {
    public let identifier: String?
    public let unit: ASCMetricUnit?
    public let datasets: [ASCMetricDataset]?
}

public struct ASCMetricUnit: Codable, Sendable {
    public let identifier: String?
    public let displayName: String?
}

public struct ASCMetricDataset: Codable, Sendable {
    public let filterCriteria: ASCFilterCriteria?
    public let points: [ASCMetricPoint]?
}

public struct ASCFilterCriteria: Codable, Sendable {
    public let device: String?
    public let deviceMarketingName: String?
    public let percentile: String?
}

public struct ASCMetricPoint: Codable, Sendable {
    public let version: String?
    public let value: Double?
    public let goal: Double?
    public let percentageBreakdown: ASCPercentageBreakdown?
}

public struct ASCPercentageBreakdown: Codable, Sendable {
    public let value: Double?
    public let subSystemLabel: String?
}

// MARK: - Diagnostic Signatures

public struct ASCDiagnosticSignaturesResponse: Codable, Sendable {
    public let data: [ASCDiagnosticSignature]
    public let links: ASCPagedDocumentLinks?
}

public struct ASCDiagnosticSignature: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: DiagnosticSignatureAttributes?
}

public struct DiagnosticSignatureAttributes: Codable, Sendable {
    public let diagnosticType: String?
    public let signature: String?
    public let weight: Double?
    public let insight: ASCDiagnosticInsight?
}

public struct ASCDiagnosticInsight: Codable, Sendable {
    public let insightType: String?
    public let referenceURL: String?
}

// MARK: - Diagnostic Logs

public struct ASCDiagnosticLogsResponse: Codable, Sendable {
    public let productData: [ASCDiagnosticLogProductData]?
}

public struct ASCDiagnosticLogProductData: Codable, Sendable {
    public let signatureId: String?
    public let diagnosticLogs: [ASCDiagnosticLog]?
}

public struct ASCDiagnosticLog: Codable, Sendable {
    public let callStackTree: ASCCallStackTree?
}

public struct ASCCallStackTree: Codable, Sendable {
    public let callStacks: [ASCCallStack]?
    public let callStackPerThread: Bool?
}

public struct ASCCallStack: Codable, Sendable {
    public let threadAttributed: Bool?
    public let callStackRootFrames: [ASCCallStackFrame]?
}

public struct ASCCallStackFrame: Codable, Sendable {
    public let binaryName: String?
    public let address: Int?
    public let offsetIntoBinaryTextSegment: Int?
    public let rawFrame: String?
    public let subFrames: [ASCCallStackFrame]?
}
