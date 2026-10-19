import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Asset Library registration and execution gates")
struct AssetsRegistrationTests {
    private static let names: Set<String> = [
        "assets_get_library", "assets_get_reference_data", "assets_get_image", "assets_get_video",
        "assets_list_images", "assets_list_videos", "assets_get_placement", "assets_list_placements",
        "assets_prepare_change", "assets_apply_change", "assets_get_operation"
    ]

    @Test("Asset Library extends the registry without removing legacy media tools")
    func catalog() async throws {
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        #expect(snapshots.count == 36)
        #expect(WorkerManager.validWorkerFilterKeys.count == 36)
        #expect(snapshots.reduce(0) { $0 + $1.count } == 514)
        let assets = try #require(snapshots.first { $0.key == "assets" })
        #expect(assets.readmeName == "App Asset Library")
        #expect(Set(assets.tools.map(\.name)) == Self.names)
        #expect(snapshots.first { $0.key == "screenshots" }?.tools.count == 19)
        #expect(snapshots.first { $0.key == "metrics" }?.tools.count == 10)
    }

    @Test("All eleven asset effects are explicit and unknown asset names fail closed")
    func effects() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets"])
        let worker = await manager.getAssetsWorker()
        let tools = await worker.getTools()
        for raw in tools {
            let tool = ToolMetadataPolicy.apply(to: raw)
            let read = tool.name != "assets_apply_change"
            #expect(ToolMetadataPolicy.isReadOnly(tool.name) == read)
            #expect(tool.annotations.readOnlyHint == read)
            #expect(tool.annotations.destructiveHint == !read)
        }
        #expect(!ToolMetadataPolicy.isReadOnly("assets_get_and_delete"))
        #expect(!ToolMetadataPolicy.isReadOnly("assets_future_read"))
    }

    @Test("Asset and screenshot filters are independent and disabled tools cannot bypass routing")
    func filters() async throws {
        let legacy = try await TestFactory.makeWorkerManager(enabledWorkers: ["screenshots"])
        let legacySnapshots = await legacy.collectWorkerToolSnapshots()
        #expect(legacySnapshots.contains { $0.key == "screenshots" })
        #expect(!legacySnapshots.contains { $0.key == "assets" })
        for name in Self.names {
            let result = try await legacy.routeTool(.init(name: name, arguments: nil))
            #expect(result.isError == true)
            #expect(result.structuredContent?.objectValue?["error"]?.stringValue?.contains("Worker 'assets' is disabled") == true)
        }
        let assets = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets"])
        let assetSnapshots = await assets.collectWorkerToolSnapshots()
        #expect(assetSnapshots.contains { $0.key == "assets" })
        #expect(!assetSnapshots.contains { $0.key == "screenshots" })
        let blockedLegacy = try await assets.routeTool(.init(name: "screenshots_get", arguments: nil))
        #expect(blockedLegacy.structuredContent?.objectValue?["error"]?.stringValue?.contains("Worker 'screenshots' is disabled") == true)
    }

    @Test("Read-only blocks apply and review aliases before reaching handlers")
    func readOnlyBlocksWrites() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets", "review_submissions"], readOnlyMode: true)
        for name in ["assets_apply_change", "review_submissions_add_item"] {
            let result = try await manager.routeTool(.init(name: name, arguments: ["preview_id": .string("not-a-live-preview")]))
            #expect(result.isError == true)
            #expect(result._meta?.fields["asc/readOnlyMode"] == .bool(true))
            #expect(result._meta?.fields["asc/blockedTool"] == .string(name))
        }
    }

    @Test("Read-only allows inspection and local preparation to reach input validation")
    func readOnlyAllowsPreparation() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets"], readOnlyMode: true)
        for name in Self.names.subtracting(["assets_apply_change"]) {
            let arguments: [String: Value]? = name == "assets_get_reference_data" ? ["unsupported": .bool(true)] : nil
            let result = try await manager.routeTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true)
            #expect(result._meta?.fields["asc/blockedTool"] == nil)
            #expect(result.structuredContent?.objectValue?["error"]?.stringValue?.contains("is disabled") != true)
        }
    }

    @Test("Review routing receives the shared asset coordinator")
    func reviewCoordinatorInjected() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets", "review_submissions"])
        let result = try await manager.routeTool(.init(name: "review_submissions_add_item", arguments: [
            "submission_id": .string("submission-1"),
            "app_asset_library_image_id": .string("image-1"),
            "preview_id": .string("nonexistent-preview")
        ]))
        #expect(result.isError == true)
        let error = try #require(result.structuredContent?.objectValue?["error"]?.stringValue)
        #expect(error.contains("Preview is unavailable"))
        #expect(!error.contains("require the shared assets worker"))
    }

    @Test("Account reinitialization replaces the preview coordinator session")
    func reinitializationReplacesCoordinator() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets"])
        let original = await manager.getAssetsWorker()
        try await manager.reinitializeWorkers(for: TestFactory.makeCompany(id: "company-2"))
        let replacement = await manager.getAssetsWorker()
        #expect(original !== replacement)
        #expect(original.sessionID != replacement.sessionID)
    }

    @Test("Asset routing rejects unknown tools")
    func unknownTool() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["assets"])
        let worker = await manager.getAssetsWorker()
        do {
            _ = try await worker.handleTool(.init(name: "assets_nonexistent", arguments: nil))
            Issue.record("Expected methodNotFound")
        } catch let error as MCPError {
            guard case .methodNotFound = error else {
                Issue.record("Expected methodNotFound, received \(error)")
                return
            }
        }
    }
}
