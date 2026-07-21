import Foundation
import Testing
@testable import asc_mcp

@Suite("README Worker Count Tests")
struct READMEWorkerCountsTests {
    @Test("README worker table matches current tool counts")
    func workerTableMatchesCurrentCounts() async throws {
        let readme = try String(
            contentsOfFile: "\(FileManager.default.currentDirectoryPath)/README.md",
            encoding: .utf8
        )
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        let totalTools = snapshots.reduce(0) { $0 + $1.count }

        #expect(totalTools == 502)
        #expect(snapshots.count == 35)
        #expect(readme.contains("**\(totalTools) tools**"))
        #expect(readme.contains("33 App Store tool domains + 2 core domains"))
        #expect(readme.contains("35 `--workers` filter keys"))
        #expect(readme.contains("39 Swift worker classes"))
        #expect(!readme.contains("@v2.4.0"))
        #expect(!readme.contains("builds_wait_for_processing"))

        let lines = readme.components(separatedBy: .newlines)
        for snapshot in snapshots {
            let row = try #require(lines.first { $0.hasPrefix("| `\(snapshot.key)` |") })
            #expect(row.contains("| \(snapshot.count) |"))

            let summary = "<summary><strong>\(snapshot.readmeName)</strong> — \(snapshot.count) tools</summary>"
            #expect(readme.contains(summary))
        }

        let counts = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key, $0.count) })
        func subsetCount(_ keys: [String]) throws -> Int {
            try keys.reduce(into: 0) { total, key in
                total += try #require(counts[key])
            }
        }

        let releasePreparation = try subsetCount([
            "company", "auth", "apps", "accessibility", "builds", "build_processing",
            "build_beta", "export_compliance", "versions", "app_info", "screenshots"
        ])
        let testFlightReviewHelpers = try subsetCount([
            "company", "auth", "apps", "builds", "build_processing", "build_beta",
            "beta_app", "pre_release"
        ])
        let releaseWorkflow = try subsetCount([
            "company", "auth", "apps", "builds", "build_processing", "build_beta",
            "export_compliance", "versions", "reviews"
        ])
        let monetization = try subsetCount([
            "company", "auth", "apps", "iap", "subscriptions", "pricing"
        ])
        let testFlight = try subsetCount([
            "company", "auth", "apps", "builds", "build_processing", "build_beta",
            "beta_groups", "beta_testers"
        ])
        let marketing = try subsetCount([
            "company", "auth", "apps", "screenshots", "custom_pages", "ppo", "promoted"
        ])
        let appsOnly = try subsetCount(["company", "auth", "apps"])

        #expect(releasePreparation == 99)
        #expect(readme.contains("release preparation subset (\(releasePreparation) tools"))
        #expect(testFlightReviewHelpers == 49)
        #expect(readme.contains("TestFlight review helpers can be loaded separately (\(testFlightReviewHelpers) tools)"))
        #expect(readme.contains("| Release workflow: `apps,builds,export_compliance,versions,reviews` | ~\(releaseWorkflow) |"))
        #expect(readme.contains("| Monetization: `apps,iap,subscriptions,pricing` | \(monetization) |"))
        #expect(readme.contains("| TestFlight: `apps,builds,beta_groups,beta_testers` | ~\(testFlight) |"))
        #expect(readme.contains("| Marketing: `apps,screenshots,custom_pages,ppo,promoted` | ~\(marketing) |"))
        #expect(readme.contains("| `--workers apps` | \(appsOnly) |"))
    }
}
