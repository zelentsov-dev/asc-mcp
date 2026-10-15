import Foundation

/// Aggregated performance overview returned with Apple's xcode-overview media type.
public struct ASCPerformanceOverview: Codable, Sendable {
    public let version: String?
    public let appMetadata: ASCPerformanceOverviewAppMetadata?
    public let insights: ASCMetricsInsights?
    public let categories: [ASCPerformanceOverviewCategory]?
    public let signatures: ASCPerformanceOverviewSignatures?
    public let telemetryIdentifier: String?

    var hasPerformanceData: Bool {
        if !(insights?.trendingUp ?? []).isEmpty || !(insights?.regressions ?? []).isEmpty {
            return true
        }
        if !(signatures?.topHangPoint ?? []).isEmpty || !(signatures?.topLaunchPoint ?? []).isEmpty
            || !(signatures?.topDiskWritePoint ?? []).isEmpty {
            return true
        }
        return (categories ?? []).contains { category in
            (category.sections ?? []).contains { section in
                (section.datasets ?? []).contains { !($0.points ?? []).isEmpty }
            }
        }
    }
}

public struct ASCPerformanceOverviewAppMetadata: Codable, Sendable {
    public let bundleId: String?
    public let appId: String?
    public let latestVersion: String?
    public let platform: String?
}

public struct ASCPerformanceOverviewCategory: Codable, Sendable {
    public let identifier: String?
    public let displayName: String?
    public let sections: [ASCPerformanceOverviewSection]?
}

public struct ASCPerformanceOverviewSection: Codable, Sendable {
    public let identifier: String?
    public let displayName: String?
    public let relevanceScore: Double?
    public let sortOrder: Int?
    public let unit: ASCMetricUnit?
    public let datasets: [ASCPerformanceOverviewDataset]?
}

public struct ASCPerformanceOverviewDataset: Codable, Sendable {
    public let filterCriteria: ASCFilterCriteria?
    public let points: [ASCPerformanceOverviewPoint]?
    public let recommendedMetricGoal: ASCRecommendedMetricGoal?
}

public struct ASCPerformanceOverviewPoint: Codable, Sendable {
    public let version: String?
    public let value: Double?
    public let errorMargin: Double?
    public let percentageBreakdown: ASCPercentageBreakdown?
}

public struct ASCPerformanceOverviewSignatures: Codable, Sendable {
    public let topHangPoint: [ASCPerformanceOverviewSignature]?
    public let topLaunchPoint: [ASCPerformanceOverviewSignature]?
    public let topDiskWritePoint: [ASCPerformanceOverviewSignature]?
}

public struct ASCPerformanceOverviewSignature: Codable, Sendable {
    public let signatureId: String?
    public let signature: String?
    public let count: Int?
    public let weight: Double?
    public let sourceFile: String?
    public let lineNumber: Int?
    public let trendInfo: String?
    public let metricsSummary: ASCPerformanceOverviewMetricsSummary?
}

public struct ASCPerformanceOverviewMetricsSummary: Codable, Sendable {
    public let referenceVersions: [ASCDiagnosticReferenceVersion]?
}
