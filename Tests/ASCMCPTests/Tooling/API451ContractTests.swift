import CryptoKit
import Foundation
import Testing
@testable import asc_mcp

@Suite("API 4.5.1 Contract Tests")
struct API451ContractTests {
    @Test("pinned Apple snapshot is exact and agrees with the manifest")
    func pinnedSnapshotIsExact() throws {
        let raw = try Data(contentsOf: fixtureURL("OpenAPI/app-store-connect-4.5.1.oas.json"))
        let sha256 = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let info = try #require(object["info"] as? [String: Any])
        let paths = try #require(object["paths"] as? [String: [String: Any]])
        let operationCount = paths.values.reduce(0) { count, item in
            count + item.values.filter { ($0 as? [String: Any])?["operationId"] != nil }.count
        }
        let manifest = try ASCOperationManifestBundle.loadBundled()

        #expect(sha256 == "7518d3a94a8bd701ac25c1c601b95b8f53aad92091affb15a2a9d331713dac1a")
        #expect(info["version"] as? String == "4.5.1")
        #expect(paths.count == 1001)
        #expect(operationCount == 1303)
        #expect(manifest.index.specPin == ASCSpecPin(
            version: "4.5.1", sha256: sha256, pathCount: paths.count, operationCount: operationCount
        ))
    }

    @Test("4.1.6 public tool names and worker filters remain available")
    func preservesBaselineCatalog() async throws {
        let data = try Data(contentsOf: fixtureURL("public-catalog-4.1.6.json"))
        let baseline = try JSONDecoder().decode(BaselineCatalog.self, from: data)
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()

        #expect(baseline.sourceCommit == "4c26a15e24b9f5deeec686c9419140102467b500")
        #expect(baseline.workers.count == 35)
        #expect(baseline.workers.flatMap(\.tools).count == 502)
        #expect(baseline.workerFilterKeys.count == 35)
        #expect(Set(baseline.workerFilterKeys).isSubset(of: WorkerManager.validWorkerFilterKeys))
        for worker in baseline.workers {
            let current = try #require(snapshots.first { $0.key == worker.key })
            let missing = Set(worker.tools).subtracting(current.tools.map(\.name))
            #expect(missing.isEmpty, "Missing baseline tools from \(worker.key): \(missing.sorted())")
        }
    }

    @Test("every new 4.5.1 operation has its approved implementation or scope decision")
    func newOperationsAreExplicitlyAccountedFor() throws {
        let data = try Data(contentsOf: fixtureURL("OpenAPI/api-4.5.1-operation-decisions.json"))
        let decisions = try JSONDecoder().decode(OperationDecisions.self, from: data).operations
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let implemented = Set(manifest.tools.filter {
            $0.implementationState == .asBuilt && $0.status != .unresolved
        }.flatMap(\.operations).map(\.operationID))

        #expect(decisions.count == 40)
        #expect(decisions.filter { $0.decision == "requiredMapping" }.count == 25)
        #expect(decisions.filter { $0.decision == "unsupported" }.count == 9)
        #expect(decisions.filter { $0.decision == "outOfScope" }.count == 6)
        for decision in decisions {
            switch decision.decision {
            case "requiredMapping":
                #expect(implemented.contains(decision.operationId), "Missing implementation mapping: \(decision.operationId)")
                #expect(!manifest.index.waivers.contains { $0.operationID == decision.operationId })
            case "unsupported":
                #expect(decision.path.contains("/relationships/"))
                #expect(manifest.index.waivers.contains {
                    $0.operationID == decision.operationId && $0.disposition == .unsupported && $0.reviewAtSpec == "4.5.1"
                })
                #expect(!implemented.contains(decision.operationId))
            case "outOfScope":
                #expect(manifest.index.scopeRules.contains {
                    decision.path.hasPrefix($0.pathPrefix) && $0.disposition == .outOfScope && $0.reviewAtSpec == "4.5.1"
                })
            default:
                Issue.record("Unrecognized operation decision: \(decision.decision)")
            }
        }
    }

    @Test("release-note deprecations remain visible when OpenAPI omits the flag")
    func semanticDeprecationWithoutOpenAPIFlag() throws {
        let spec = try ASCOpenAPISpec.parse(Data(contentsOf: fixtureURL("openapi_minimal.oas.json")))
        let operation = try #require(spec.operations.first { $0.operationID == "apps_getCollection" })
        #expect(!operation.deprecated)
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec, manifest: try fixtureManifest(deprecations: [deprecation(review: spec.version)])
        )
        #expect(diagnostics.contains {
            $0.code == .operationSemanticDeprecation && $0.severity == .warning &&
                $0.operationID == "apps_getCollection" && $0.tool == "apps_list"
        })
        #expect(!diagnostics.contains {
            $0.code == .semanticDeprecationInvalid || $0.code == .semanticDeprecationTargetMissing ||
                $0.code == .semanticDeprecationExpired
        })
    }

    @Test("semantic overlays reject stale reviews, missing targets, and non-Apple sources")
    func rejectsInvalidSemanticDeprecations() throws {
        let spec = try ASCOpenAPISpec.parse(Data(contentsOf: fixtureURL("openapi_minimal.oas.json")))
        let stale = deprecation(review: "4.0")
        let invalid = ASCSemanticDeprecation(
            id: "invalid", operationIDs: ["missing_operation"], parameterNames: nil,
            reason: "Fixture", sourceURL: "https://example.com/docs", owner: "tests", reviewAtSpec: spec.version
        )
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec, manifest: try fixtureManifest(deprecations: [stale, invalid])
        )
        #expect(diagnostics.contains { $0.code == .semanticDeprecationExpired && $0.severity == .error })
        #expect(diagnostics.contains { $0.code == .semanticDeprecationInvalid && $0.severity == .error })
        #expect(diagnostics.contains { $0.code == .semanticDeprecationTargetMissing && $0.severity == .error })
    }

    @Test("parameter deprecations cannot silently reference removed parameters")
    func validatesSemanticParameterTargets() throws {
        let spec = try ASCOpenAPISpec.parse(Data(contentsOf: fixtureURL("openapi_minimal.oas.json")))
        let entry = ASCSemanticDeprecation(
            id: "parameter", operationIDs: ["apps_getCollection"], parameterNames: ["missing_parameter"],
            reason: "Fixture parameter deprecation.", sourceURL: deprecation(review: spec.version).sourceURL,
            owner: "tests", reviewAtSpec: spec.version
        )
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec, manifest: try fixtureManifest(deprecations: [entry])
        )
        #expect(diagnostics.contains {
            $0.code == .semanticDeprecationTargetMissing && $0.field == "missing_parameter"
        })
    }

    private func deprecation(review: String) -> ASCSemanticDeprecation {
        ASCSemanticDeprecation(
            id: "fixture", operationIDs: ["apps_getCollection"], parameterNames: nil,
            reason: "Fixture release-note deprecation.",
            sourceURL: "https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-1-release-notes",
            owner: "tests", reviewAtSpec: review
        )
    }

    private func fixtureManifest(deprecations: [ASCSemanticDeprecation]) throws -> ASCOperationManifestBundle {
        let manifest = try ASCOperationManifestBundle.load(from: fixtureURL("operation_manifest_valid"))
        return ASCOperationManifestBundle(index: ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers,
            semanticDeprecations: deprecations
        ), workers: manifest.workers)
    }

    private func fixtureURL(_ path: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent(path)
    }
}

private struct BaselineCatalog: Decodable {
    let sourceCommit: String
    let workerFilterKeys: [String]
    let workers: [Worker]

    struct Worker: Decodable {
        let key: String
        let tools: [String]
    }
}

private struct OperationDecisions: Decodable {
    let operations: [Decision]

    struct Decision: Decodable {
        let operationId: String
        let path: String
        let decision: String
    }
}
