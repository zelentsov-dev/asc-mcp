import Foundation
import Testing
@testable import asc_mcp

@Suite("ASC Coverage Inventory Tests")
struct ASCCoverageInventoryTests {
    @Test("coverage inventory has unique documented areas")
    func coverageInventoryHasUniqueAreas() {
        let areas = ASCCoverageInventory.areas
        let names = Set(areas.map(\.name))

        #expect(ASCCoverageInventory.snapshotDate == "2026-05-05")
        #expect(areas.count == names.count)
        #expect(areas.count >= 10)

        for area in areas {
            #expect(area.appleDocumentationURL.hasPrefix("https://developer.apple.com/documentation/appstoreconnectapi"))
            #expect(area.coveredCapabilities.isEmpty == (area.status == .missing))
            #expect(area.missingCapabilities.isEmpty == (area.status == .covered))
        }
    }

    @Test("coverage inventory references only current worker keys")
    func coverageInventoryReferencesCurrentWorkerKeys() async throws {
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        let currentKeys = Set(snapshots.map(\.key))
        let referencedKeys = Set(ASCCoverageInventory.areas.flatMap(\.workerKeys))

        #expect(referencedKeys.isSubset(of: currentKeys))
    }

    @Test("high priority gaps include API 4 additions")
    func highPriorityGapsIncludeAPI4Additions() {
        let highPriorityNames = Set(ASCCoverageInventory.highPriorityGaps.map(\.name))

        #expect(highPriorityNames.contains("Webhook notification receiver resources"))
        #expect(highPriorityNames.contains("App Store app metadata and release operations"))
        #expect(highPriorityNames.contains("TestFlight builds, testers, groups, and beta app review"))
        #expect(highPriorityNames.contains("Xcode Cloud workflows and builds"))
    }

    @Test("markdown coverage matrix tracks every inventory area")
    func markdownCoverageMatrixTracksEveryInventoryArea() throws {
        let matrix = try String(
            contentsOfFile: "\(FileManager.default.currentDirectoryPath)/ASC-COVERAGE-MATRIX-2026-05-05.md",
            encoding: .utf8
        )

        for area in ASCCoverageInventory.areas {
            #expect(matrix.contains("| \(area.name) |"))
        }
    }
}
