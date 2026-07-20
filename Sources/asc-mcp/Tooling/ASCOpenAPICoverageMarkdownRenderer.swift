import Foundation

enum ASCOpenAPICoverageMarkdownRenderer {
    /// Render the OpenAPI coverage report as stable markdown for reviews and CI artifacts.
    /// - Parameters:
    ///   - report: Coverage report from `ASCOpenAPICoverageAnalyzer`.
    ///   - maxUnclassifiedExamples: Maximum number of unclassified paths to list.
    /// - Returns: Markdown report text.
    static func render(
        _ report: ASCOpenAPICoverageReport,
        maxUnclassifiedExamples: Int = 80
    ) -> String {
        var lines: [String] = []

        lines.append("# App Store Connect OpenAPI Coverage")
        lines.append("")
        lines.append("Generated: \(report.generatedAt)")
        lines.append("")
        lines.append("Sources:")
        lines.append("- Apple App Store Connect API overview: https://developer.apple.com/app-store-connect/api/")
        lines.append("- Apple App Store Connect API documentation: https://developer.apple.com/documentation/appstoreconnectapi")
        lines.append("- Apple OpenAPI specification download: https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip")
        lines.append("")
        lines.append("Spec: \(report.spec.title) \(report.spec.version) (OpenAPI \(report.spec.openAPIVersion))")
        lines.append("Apple paths: \(report.spec.paths.count)")
        lines.append("Apple operations: \(report.spec.operations.count)")
        lines.append("Classified paths: \(report.coveredPathCount)")
        lines.append("Unclassified paths: \(report.unclassifiedPathCount)")
        lines.append("")
        lines.append("## Priority Gaps")
        lines.append("")

        if report.highPriorityAppleGaps.isEmpty {
            lines.append("No P0/P1 Apple-path domains are currently marked as missing or partial.")
        } else {
            for domain in report.highPriorityAppleGaps {
                lines.append("- \(domain.rule.priority.rawValue) \(domain.rule.domain): \(domain.rule.status.displayName), \(domain.pathCount) Apple paths, \(domain.operationCount) operations.")
            }
        }

        lines.append("")
        lines.append("## Domain Matrix")
        lines.append("")
        lines.append("| Domain | Status | Priority | Apple paths | Operations | Workers | Notes |")
        lines.append("|---|---|---:|---:|---:|---|---|")

        for domain in report.domains {
            lines.append(
                "| \(domain.rule.domain) | \(domain.rule.status.displayName) | \(domain.rule.priority.rawValue) | \(domain.pathCount) | \(domain.operationCount) | \(markdownCodeList(domain.rule.workerKeys)) | \(escapeTableText(domain.rule.notes)) |"
            )
        }

        lines.append("")
        lines.append("## Missing Apple Domains")
        lines.append("")

        if report.missingAppleDomains.isEmpty {
            lines.append("No matched Apple domains are marked as fully missing.")
        } else {
            for domain in report.missingAppleDomains {
                lines.append("- \(domain.rule.domain): \(domain.pathCount) paths, \(domain.operationCount) operations.")
            }
        }

        lines.append("")
        lines.append("## Unclassified Apple Paths")
        lines.append("")

        if report.unclassifiedPaths.isEmpty {
            lines.append("All Apple paths matched at least one maintained coverage rule.")
        } else {
            lines.append("These paths did not match any maintained rule. They are the first drift triage queue, not proof that every endpoint is missing.")
            lines.append("")
            for path in report.unclassifiedPaths.prefix(maxUnclassifiedExamples) {
                lines.append("- `\(path)`")
            }
            let remaining = report.unclassifiedPaths.count - min(report.unclassifiedPaths.count, maxUnclassifiedExamples)
            if remaining > 0 {
                lines.append("- ...and \(remaining) more.")
            }
        }

        lines.append("")
        lines.append("## How To Regenerate")
        lines.append("")
        lines.append("```bash")
        lines.append("rm -rf /tmp/asc-openapi")
        lines.append("mkdir -p /tmp/asc-openapi")
        lines.append("curl -L --fail -o /tmp/asc-openapi/spec.zip https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip")
        lines.append("unzip -q /tmp/asc-openapi/spec.zip -d /tmp/asc-openapi")
        lines.append("swift run asc-mcp openapi-coverage --spec /tmp/asc-openapi/openapi.oas.json --output ASC-OPENAPI-COVERAGE-GENERATED.md")
        lines.append("```")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func markdownCodeList(_ values: [String]) -> String {
        guard !values.isEmpty else {
            return "none"
        }
        return values.map { "`\($0)`" }.joined(separator: ", ")
    }

    private static func escapeTableText(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

extension ASCCoverageStatus {
    var displayName: String {
        switch self {
        case .covered:
            "Covered"
        case .partial:
            "Partial"
        case .missing:
            "Missing"
        }
    }
}
