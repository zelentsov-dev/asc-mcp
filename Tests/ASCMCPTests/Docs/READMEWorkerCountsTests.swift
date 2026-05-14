import Foundation
import Testing

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

        #expect(totalTools == 348)
        #expect(snapshots.count == 36)
        #expect(readme.contains("**\(totalTools) tools**"))
        #expect(readme.contains("36 worker domains"))

        let lines = readme.components(separatedBy: .newlines)
        for snapshot in snapshots {
            let row = try #require(lines.first { $0.hasPrefix("| `\(snapshot.key)` |") })
            #expect(row.contains("| \(snapshot.count) |"))

            let summary = "<summary><strong>\(snapshot.readmeName)</strong> — \(snapshot.count) tools</summary>"
            #expect(readme.contains(summary))
        }
    }
}
