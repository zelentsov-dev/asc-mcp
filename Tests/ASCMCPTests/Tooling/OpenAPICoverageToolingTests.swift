import Foundation
import Testing
@testable import asc_mcp

@Suite("OpenAPI Coverage Tooling Tests")
struct OpenAPICoverageToolingTests {
    @Test("parser extracts spec metadata, paths, and operations")
    func parserExtractsSpecMetadataPathsAndOperations() throws {
        let data = try loadFixture("openapi_minimal.oas")
        let spec = try ASCOpenAPISpec.parse(data)

        #expect(spec.title == "App Store Connect API")
        #expect(spec.version == "4.3-test")
        #expect(spec.openAPIVersion == "3.0.1")
        #expect(spec.paths.count == 5)
        #expect(spec.operations.count == 8)
        #expect(spec.operations.contains { operation in
            operation.path == "/v1/apps" &&
            operation.method == "get" &&
            operation.operationID == "apps_getCollection"
        })
    }

    @Test("analyzer matches domain prefixes and surfaces high priority gaps")
    func analyzerMatchesDomainPrefixesAndSurfacesHighPriorityGaps() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let rules = [
            ASCOpenAPICoverageRule(
                domain: "Apps",
                priority: .p0,
                status: .partial,
                pathPrefixes: ["/v1/apps"],
                workerKeys: ["apps"],
                toolPrefixes: ["apps_"],
                notes: "Core app reads exist."
            ),
            ASCOpenAPICoverageRule(
                domain: "Game Center",
                priority: .p2,
                status: .missing,
                pathPrefixes: ["/v1/gameCenter"],
                workerKeys: [],
                toolPrefixes: [],
                notes: "No worker yet."
            )
        ]

        let report = ASCOpenAPICoverageAnalyzer(rules: rules).analyze(
            spec: spec,
            generatedAt: "2026-05-07"
        )

        let apps = try #require(report.domains.first { $0.rule.domain == "Apps" })
        let gameCenter = try #require(report.domains.first { $0.rule.domain == "Game Center" })

        #expect(apps.pathCount == 2)
        #expect(apps.operationCount == 3)
        #expect(gameCenter.pathCount == 2)
        #expect(report.highPriorityAppleGaps.map(\.rule.domain) == ["Apps"])
        #expect(report.missingAppleDomains.map(\.rule.domain) == ["Game Center"])
        #expect(report.unclassifiedPaths == ["/v1/actors"])
    }

    @Test("markdown renderer includes summary, gaps, and examples")
    func markdownRendererIncludesSummaryGapsAndExamples() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let rules = [
            ASCOpenAPICoverageRule(
                domain: "Apps",
                priority: .p0,
                status: .partial,
                pathPrefixes: ["/v1/apps"],
                workerKeys: ["apps"],
                toolPrefixes: ["apps_"],
                notes: "Core app reads exist."
            )
        ]
        let report = ASCOpenAPICoverageAnalyzer(rules: rules).analyze(
            spec: spec,
            generatedAt: "2026-05-07"
        )

        let markdown = ASCOpenAPICoverageMarkdownRenderer.render(report)

        #expect(markdown.contains("# App Store Connect OpenAPI Coverage"))
        #expect(markdown.contains("Spec: App Store Connect API 4.3-test"))
        #expect(markdown.contains("Apple paths: 5"))
        #expect(markdown.contains("| Apps | Partial | P0 | 2 | 3 | `apps` | Core app reads exist. |"))
        #expect(markdown.contains("## Unclassified Apple Paths"))
        #expect(markdown.contains("`/v1/actors`"))
    }

    @Test("default OpenAPI coverage rules track every inventory area")
    func defaultRulesTrackEveryInventoryArea() {
        let ruleDomains = Set(ASCOpenAPICoverageRules.defaultRules.map(\.domain))

        for area in ASCCoverageInventory.areas {
            #expect(ruleDomains.contains(area.name), "Missing OpenAPI coverage rule for \(area.name)")
        }
    }
}
