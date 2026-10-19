import Foundation
import Testing
@testable import asc_mcp

@Suite("Assets Manifest Contract Tests")
struct AssetsManifestContractTests {
    @Test("all asset tools and 24 new operations have exact bindings")
    func catalogAndOperations() async throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(manifest.workers.first { $0.workerKey == "assets" })
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        let snapshot = try #require(snapshots.first { $0.key == "assets" })

        #expect(worker.tools.count == 11)
        #expect(Set(worker.tools.map(\.tool)) == Set(snapshot.tools.map(\.name)))
        for mapping in worker.tools {
            let tool = try #require(snapshot.tools.first { $0.name == mapping.tool })
            let properties = tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
            #expect(Set(mapping.fields.map(\.toolField)) == Set(properties.keys))
            #expect(mapping.implementationState == .asBuilt)
            #expect(mapping.operations.filter { $0.role == .primary }.count == 1)
        }

        let operationIDs = Set(worker.tools.flatMap(\.operations).map(\.operationID))
        let assetOperationIDs = operationIDs.filter {
            $0.hasPrefix("appAssetLibrar") ||
                $0.hasSuffix("_placements_getToManyRelated") ||
                $0 == "apps_assetLibrary_getToOneRelated"
        }
        #expect(assetOperationIDs.count == 24)
        #expect(operationIDs.count == 40)
        #expect(operationIDs.contains("reviewSubmissionItems_createInstance"))
        #expect(!worker.tools.flatMap(\.operations).contains { $0.path.contains("/relationships/") })
        #expect(manifest.index.waivers.allSatisfy {
            $0.operationID.map { !assetOperationIDs.contains($0) } ?? true
        })
    }

    @Test("asset input and response mappings match the pinned Apple contract")
    func pinnedContract() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("OpenAPI/app-store-connect-4.5.1.oas.json")
        let spec = try ASCOpenAPISpec.parse(Data(contentsOf: fixture))
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let diagnostics = ASCOperationToolAnalyzer().analyze(spec: spec, manifest: manifest)
        let assetDiagnostics = diagnostics.filter { $0.tool?.hasPrefix("assets_") == true }
        let uncovered: Set<ASCContractDiagnosticCode> = [
            .parameterUnexposed, .requestBodyUnmodeled, .requestBodyOptionalPropertyUnbound
        ]

        #expect(assetDiagnostics.filter { $0.severity == .error || uncovered.contains($0.code) }.isEmpty)
        let worker = try #require(manifest.workers.first { $0.workerKey == "assets" })
        #expect(worker.tools.flatMap(\.operations).flatMap {
            $0.optionalParameterClassifications ?? []
        }.allSatisfy { $0.reviewAtSpec == "4.5.1" && !$0.reason.isEmpty })
    }

    @Test("only preview application may call mutating Apple operations")
    func previewBoundary() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(manifest.workers.first { $0.workerKey == "assets" })
        for mapping in worker.tools where mapping.tool != "assets_apply_change" {
            #expect(mapping.operations.allSatisfy { $0.method == "get" })
            #expect(mapping.effect == .read || mapping.effect == .local)
        }

        let prepare = try #require(manifest.mapping(for: "assets_prepare_change"))
        #expect(prepare.effect == .local)
        for field in ["file_path", "resume_operation_id", "action", "reference_name", "category"] {
            #expect(prepare.fields.contains { $0.toolField == field && $0.sourceKind == .local })
        }
        #expect(prepare.response.fields.contains { $0.outputField == "writes_performed" })

        let apply = try #require(manifest.mapping(for: "assets_apply_change"))
        #expect(apply.effect == .destructive)
        #expect(apply.fields.count == 1)
        #expect(apply.fields.first?.toolField == "preview_id")
        #expect(apply.fields.first?.sourceKind == .local)
        for operation in apply.operations where operation.method != "get" {
            #expect(operation.inputs?.allSatisfy {
                $0.sourceKind == .fixed ||
                    ($0.sourceKind == .derived && $0.derivedFrom?.contains("preview_id") == true)
            } == true)
        }
        #expect(Set(worker.tools.flatMap(\.fields).map(\.toolField)).isDisjoint(with: [
            "url", "upload_url", "headers", "method", "request_body"
        ]))
    }

    @Test("uploads ordering and recovery preserve their safety boundaries")
    func workflowBoundaries() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let apply = try #require(manifest.mapping(for: "assets_apply_change"))
        let patches = apply.operations.filter { $0.method == "patch" }
        #expect(patches.count == 9)
        #expect(Set(patches.compactMap(\.invocationID)).count == patches.count)
        for patch in patches {
            let attributes = patch.inputs?.filter {
                $0.jsonPointer?.hasPrefix("/data/attributes/") == true
            } ?? []
            #expect(attributes.count == 1)
            #expect(patch.optionalParameterClassifications?.allSatisfy {
                $0.location == "body" && $0.disposition == .intentionallyOmitted
            } == true)
        }
        for resource in ["appAssetLibraryImages", "appAssetLibraryVideos"] {
            let reservation = try #require(apply.operations.first {
                $0.operationID == resource + "_createInstance"
            })
            #expect(reservation.condition?.contains("Never called when resuming") == true)
            #expect(reservation.optionalParameterClassifications?.contains {
                $0.location == "body" && $0.appleName == "/data/relationships/placements" &&
                    $0.disposition == .intentionallyOmitted
            } == true)

            let update = try #require(apply.operations.first {
                $0.operationID == resource + "_updateInstance"
            })
            #expect(update.inputs?.contains {
                $0.jsonPointer == "/data/attributes/uploaded" &&
                    $0.sourceKind == .fixed && $0.fixedValue == .boolean(true)
            } == true)
            #expect(update.inputs?.allSatisfy { $0.jsonPointer?.contains("Checksum") != true } == true)
        }

        let ordering = try #require(apply.operations.first {
            $0.operationID == "appAssetLibraryPlacementOrderingRequests_createInstance"
        })
        #expect(ordering.inputs?.contains {
            $0.jsonPointer == "/data/relationships/orderedPlacements/data" && $0.sourceKind == .derived
        } == true)
        #expect(ordering.inputs?.allSatisfy {
            $0.jsonPointer?.contains("appEventLocalization") != true
        } == true)

        let recover = try #require(manifest.mapping(for: "assets_get_operation"))
        #expect(recover.effect == .local)
        #expect(recover.operations.allSatisfy { $0.method == "get" })
        #expect(recover.fields.count == 1 && recover.fields.first?.toolField == "operation_id")
        #expect(recover.response.fields.contains { $0.outputField == "retry_safe" })
        #expect(recover.note?.contains("never attribute ownership") == true)
    }
}
