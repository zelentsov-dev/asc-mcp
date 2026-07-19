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

        #expect(totalTools == 389)
        #expect(snapshots.count == 32)
        #expect(readme.contains("**\(totalTools) tools**"))
        #expect(readme.contains("30 App Store tool domains + 2 core domains"))
        #expect(readme.contains("32 `--workers` filter keys"))
        #expect(readme.contains("36 Swift worker classes"))
        #expect(!readme.contains("@v2.4.0"))
        #expect(!readme.contains("builds_wait_for_processing"))

        let lines = readme.components(separatedBy: .newlines)
        for snapshot in snapshots {
            let row = try #require(lines.first { $0.hasPrefix("| `\(snapshot.key)` |") })
            #expect(row.contains("| \(snapshot.count) |"))

            let summary = "<summary><strong>\(snapshot.readmeName)</strong> — \(snapshot.count) tools</summary>"
            #expect(readme.contains(summary))
        }
    }
}
