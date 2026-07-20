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
    public let version: String?
    public let insights: ASCMetricsInsights?
    public let productData: [ASCProductData]?
}

public struct ASCMetricsInsights: Codable, Sendable {
    public let trendingUp: [ASCMetricsInsight]?
    public let regressions: [ASCMetricsInsight]?
}

public struct ASCMetricsInsight: Codable, Sendable {
    public let metricCategory: String?
    public let latestVersion: String?
    public let metric: String?
    public let summaryString: String?
    public let referenceVersions: String?
    public let maxLatestVersionValue: Double?
    public let subSystemLabel: String?
    public let highImpact: Bool?
    public let populations: [ASCMetricsInsightPopulation]?
}

public struct ASCMetricsInsightPopulation: Codable, Sendable {
    public let deltaPercentage: Double?
    public let percentile: String?
    public let summaryString: String?
    public let referenceAverageValue: Double?
    public let latestVersionValue: Double?
    public let device: String?
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
    public let recommendedMetricGoal: ASCRecommendedMetricGoal?
}

public struct ASCRecommendedMetricGoal: Codable, Sendable {
    public let value: Double?
    public let detail: String?
}

public struct ASCFilterCriteria: Codable, Sendable {
    public let device: String?
    public let deviceMarketingName: String?
    public let percentile: String?
}

public struct ASCMetricPoint: Codable, Sendable {
    public let version: String?
    public let value: Double?
    public let errorMargin: Double?
    public let goal: String?
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
    public let direction: String?
    public let referenceVersions: [ASCDiagnosticReferenceVersion]?
}

public struct ASCDiagnosticReferenceVersion: Codable, Sendable {
    public let version: String?
    public let value: Double?
}

// MARK: - Diagnostic Logs

public struct ASCDiagnosticLogsResponse: Codable, Sendable {
    public let version: String?
    public let productData: [ASCDiagnosticLogProductData]?
}

public struct ASCDiagnosticLogProductData: Codable, Sendable {
    public let signatureId: String?
    public let diagnosticInsights: [ASCDiagnosticLogInsight]?
    public let diagnosticLogs: [ASCDiagnosticLog]?
}

public struct ASCDiagnosticLogInsight: Codable, Sendable {
    public let insightsURL: String?
    public let insightsCategory: String?
    public let insightsString: String?
}

public struct ASCDiagnosticLog: Codable, Sendable {
    public let callStackTree: [ASCCallStackTree]?
    public let diagnosticMetaData: ASCDiagnosticMetaData?
}

public struct ASCDiagnosticMetaData: Codable, Sendable {
    public let bundleId: String?
    public let event: String?
    public let osVersion: String?
    public let appVersion: String?
    public let writesCaused: String?
    public let deviceType: String?
    public let platformArchitecture: String?
    public let eventDetail: String?
    public let buildVersion: String?
}

public struct ASCCallStackTree: Codable, Sendable {
    public let callStacks: [ASCCallStack]?
    public let callStackPerThread: Bool?
}

public struct ASCCallStack: Codable, Sendable {
    public let callStackRootFrames: [ASCCallStackFrame]?
}

public struct ASCCallStackFrame: Codable, Sendable {
    public let sampleCount: Int?
    public let isBlameFrame: Bool?
    public let symbolName: String?
    public let insightsCategory: String?
    public let offsetIntoSymbol: String?
    public let binaryName: String?
    public let fileName: String?
    public let binaryUUID: String?
    public let lineNumber: String?
    public let address: String?
    public let offsetIntoBinaryTextSegment: String?
    public let rawFrame: String?
    public let subFrames: [ASCCallStackFrame]?
}
