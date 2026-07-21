import Foundation
import Testing
@testable import asc_mcp

@Suite("Metrics Model Tests")
struct MetricsModelTests {
    @Test("Xcode metrics fixture decodes the complete Apple 4.4.1 projection")
    func decodesXcodeMetricsFixture() throws {
        let response = try decodeFixture("metrics_xcode_metrics", as: ASCPerfPowerMetricsResponse.self)

        #expect(response.version == "1.0")
        let insight = try #require(response.insights?.trendingUp?.first)
        #expect(insight.metricCategory == "STORAGE")
        #expect(insight.populations?.first?.device == "iPhone15,2")

        let metric = try #require(response.productData?.first?.metricCategories?.first?.metrics?.first)
        let goalKey = try #require(metric.goalKeys?.first)
        #expect(goalKey.goalKey == "storageP90")
        #expect(goalKey.lowerBound == 0)
        #expect(goalKey.upperBound == 200)
        let dataset = try #require(metric.datasets?.first)
        let point = try #require(dataset.points?.first)
        #expect(point.errorMargin == 2.25)
        #expect(point.goal == "Less than 200 MB")
        #expect(dataset.recommendedMetricGoal?.value == 175.0)
        #expect(dataset.recommendedMetricGoal?.detail == "Keep the P90 value below 175 MB")
    }

    @Test("Diagnostic logs fixture decodes call stack arrays, metadata, insights, and string addresses")
    func decodesDiagnosticLogsFixture() throws {
        let response = try decodeFixture("metrics_diagnostic_logs", as: ASCDiagnosticLogsResponse.self)

        #expect(response.version == "1.0")
        let product = try #require(response.productData?.first)
        #expect(product.signatureId == "signature-1")
        #expect(product.diagnosticInsights?.first?.insightsCategory == "DISK_WRITES")

        let log = try #require(product.diagnosticLogs?.first)
        #expect(log.diagnosticMetaData?.bundleId == "com.example.app")
        #expect(log.diagnosticMetaData?.platformArchitecture == "arm64")
        let frame = try #require(log.callStackTree?.first?.callStacks?.first?.callStackRootFrames?.first)
        #expect(frame.sampleCount == 7)
        #expect(frame.isBlameFrame == true)
        #expect(frame.lineNumber == "87")
        #expect(frame.address == "0x0000000100001234")
        #expect(frame.offsetIntoBinaryTextSegment == "4660")
        #expect(frame.subFrames?.first?.symbolName == "Persistence.save()")
    }

    @Test("Diagnostic signature insight decodes direction and reference versions")
    func decodesDiagnosticSignatureInsight() throws {
        let data = Data(#"{"data":[{"type":"diagnosticSignatures","id":"signature-1","attributes":{"diagnosticType":"LAUNCHES","signature":"Slow launch","weight":0.75,"insight":{"insightType":"TREND","direction":"UP","referenceVersions":[{"version":"4.1.0","value":1.25}]}}}]}"#.utf8)

        let response = try JSONDecoder().decode(ASCDiagnosticSignaturesResponse.self, from: data)
        let attributes = try #require(response.data.first?.attributes)
        #expect(attributes.diagnosticType == "LAUNCHES")
        #expect(attributes.insight?.direction == "UP")
        #expect(attributes.insight?.referenceVersions?.first?.version == "4.1.0")
        #expect(attributes.insight?.referenceVersions?.first?.value == 1.25)
    }
}
