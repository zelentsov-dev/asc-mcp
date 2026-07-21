import Foundation
import Testing
@testable import asc_mcp

@Suite("ASC Coverage Inventory Tests")
struct ASCCoverageInventoryTests {
    @Test("coverage inventory has unique documented areas")
    func coverageInventoryHasUniqueAreas() {
        let areas = ASCCoverageInventory.areas
        let names = Set(areas.map(\.name))

        #expect(ASCCoverageInventory.snapshotDate == "2026-07-21")
        #expect(ASCCoverageInventory.appleAPIVersionBaseline == "4.4.1")
        #expect(areas.count == names.count)
        #expect(areas.count >= 10)

        for area in areas {
            #expect(area.appleDocumentationURL.hasPrefix("https://developer.apple.com/documentation/appstoreconnectapi"))
            #expect(area.coveredCapabilities.isEmpty == (area.status == .missing))
            #expect(area.missingCapabilities.isEmpty == (area.status == .covered))
        }
    }

    @Test("commerce coverage tracks App Store Connect 4.4.1 capabilities and remaining gaps")
    func commerceCoverageDisclosesCurrentGaps() throws {
        let commerce = try #require(
            ASCCoverageInventory.areas.first {
                $0.name == "In-app purchases, subscriptions, and offers"
            }
        )

        #expect(commerce.status == .partial)
        #expect(commerce.coveredCapabilities.contains {
            $0.contains("plan-type-aware availability")
        })
        #expect(commerce.coveredCapabilities.contains {
            $0.contains("paginated plural version-owned IAP review images")
        })
        #expect(commerce.missingCapabilities.contains("authoritative fully paginated subscription inventory"))
    }

    @Test("TestFlight coverage tracks recruitment app-device context and usage metrics")
    func testFlightCoverageTracksNewCapabilities() throws {
        let testFlight = try #require(
            ASCCoverageInventory.areas.first {
                $0.name == "TestFlight builds, testers, groups, and beta app review"
            }
        )
        let reporting = try #require(
            ASCCoverageInventory.areas.first {
                $0.name == "Reporting, analytics, metrics, and diagnostics"
            }
        )

        #expect(testFlight.coveredCapabilities.contains(
            "beta recruitment criteria, option discovery, and compatible-build checks"
        ))
        #expect(testFlight.coveredCapabilities.contains("beta tester app-device context"))
        #expect(testFlight.coveredCapabilities.contains(
            "app, group, tester, build, and public-link TestFlight usage metrics"
        ))
        #expect(reporting.coveredCapabilities.contains(
            "TestFlight tester, build, and public-link usage metrics"
        ))
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

    @Test("coverage documents track build upload and export compliance workers")
    func coverageDocumentsTrackBuildUploadWorkers() throws {
        let root = FileManager.default.currentDirectoryPath
        let matrix = try String(
            contentsOfFile: "\(root)/ASC-COVERAGE-MATRIX-2026-05-05.md",
            encoding: .utf8
        )
        let generated = try String(
            contentsOfFile: "\(root)/ASC-OPENAPI-COVERAGE-GENERATED.md",
            encoding: .utf8
        )
        let matrixTestFlight = try #require(
            matrix.split(separator: "\n").first {
                $0.hasPrefix("| TestFlight builds, testers, groups, and beta app review |")
            }
        )
        let matrixAppStore = try #require(
            matrix.split(separator: "\n").first {
                $0.hasPrefix("| App Store app metadata and release operations |")
            }
        )
        let generatedTestFlight = try #require(
            generated.split(separator: "\n").first {
                $0.hasPrefix("| TestFlight builds, testers, groups, and beta app review |")
            }
        )

        #expect(matrixTestFlight.contains("`build_uploads`"))
        #expect(matrixTestFlight.contains("`export_compliance`"))
        #expect(matrixAppStore.contains("`export_compliance`"))
        #expect(generatedTestFlight.contains("`build_uploads`"))
        #expect(generatedTestFlight.contains("`export_compliance`"))
    }
}
