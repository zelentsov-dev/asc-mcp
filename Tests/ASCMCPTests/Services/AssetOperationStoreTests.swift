import Foundation
import Testing
import os
@testable import asc_mcp

@Suite("Asset preview and journal safety")
struct AssetOperationStoreTests {
    private let account = String(repeating: "a", count: 64)

    @Test("Resource admission happens before snapshots and counts in-flight preparations")
    func reservations() async throws {
        let store = AssetOperationStore()
        let first = try await store.reservePreparation(upload: true)
        let second = try await store.reservePreparation(upload: true)
        await #expect(throws: AssetLibraryError.self) { try await store.reservePreparation(upload: true) }
        await store.releasePreparation(first)
        let replacement = try await store.reservePreparation(upload: true)
        await store.releasePreparation(second)
        await store.releasePreparation(replacement)
        for _ in 0..<8 { _ = try await store.reservePreparation(upload: false) }
        await #expect(throws: AssetLibraryError.self) { try await store.reservePreparation(upload: false) }
    }

    @Test("Preview expiry and wrong account/session never consume a valid preview")
    func expiryAndScope() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 100))
        let store = AssetOperationStore(root: root, now: { clock.withLock { $0 } })
        let session = UUID()
        let preview = try await prepare(store, session: session)
        await #expect(throws: AssetLibraryError.self) { try await store.consume(preview.previewID, account: String(repeating: "b", count: 64), session: session) }
        await #expect(throws: AssetLibraryError.self) { try await store.consume(preview.previewID, account: account, session: UUID()) }
        #expect(try await store.inspectPreview(preview.previewID, account: account, session: session).operation.id == preview.operation.id)
        clock.withLock { $0 = $0.addingTimeInterval(600) }
        await #expect(throws: AssetLibraryError.self) { try await store.consume(preview.previewID, account: account, session: session) }
        #expect(try await store.get(id: preview.operation.id, account: account).status == "expired")
    }

    @Test("Concurrent apply consumes exactly once and restart invalidates previews")
    func singleUse() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AssetOperationStore(root: root)
        let session = UUID()
        let preview = try await prepare(store, session: session)
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 {
                group.addTask { (try? await store.consume(preview.previewID, account: account, session: session)) != nil }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(outcomes.filter { $0 }.count == 1)
        let restarted = AssetOperationStore(root: root)
        await #expect(throws: AssetLibraryError.self) { try await restarted.consume(preview.previewID, account: account, session: session) }
        #expect(try await restarted.get(id: preview.operation.id, account: account).status == "running")
    }

    @Test("Retention preserves uncertain writes and full journal blocks admission")
    func retention() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 100))
        let store = AssetOperationStore(root: root, maximumRecords: 1, now: { clock.withLock { $0 } })
        let session = UUID()
        let preview = try await prepare(store, session: session)
        var record = try await store.consume(preview.previewID, account: account, session: session).operation
        record.status = "requires_reconciliation"
        try await store.finish(record)
        clock.withLock { $0 = $0.addingTimeInterval(8 * 86_400) }
        let token = try await store.reservePreparation(upload: false)
        await #expect(throws: AssetLibraryError.self) {
            try await store.prepare(account: account, session: UUID(), change: .init(action: .deleteAsset, appID: "app"), snapshot: nil, reservation: token)
        }
        await store.releasePreparation(token)
        #expect(try await store.get(id: record.id, account: account).unresolved)
    }

    @Test("Journal records use private permissions and reject symbolic links")
    func permissions() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AssetOperationStore(root: root)
        let preview = try await prepare(store, session: UUID())
        let file = root.appendingPathComponent(account).appendingPathComponent(preview.operation.id + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "/dev/null")
        await #expect(throws: AssetLibraryError.self) { try await store.get(id: preview.operation.id, account: account) }
    }

    @Test("Independent stores cannot execute or reconcile the same app concurrently")
    func crossStoreLease() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = AssetOperationStore(root: root)
        let second = AssetOperationStore(root: root)
        let session = UUID()
        let previewA = try await prepare(first, session: session)
        let previewB = try await prepare(second, session: session)
        var active = try await first.consume(previewA.previewID, account: account, session: session).operation
        #expect(try await second.beginInspection(active) == nil)
        await #expect(throws: AssetLibraryError.self) { try await second.consume(previewB.previewID, account: account, session: session) }
        active.status = "requires_reconciliation"
        try await first.finish(active)
        let inspection = try #require(try await second.beginInspection(active))
        await #expect(throws: AssetLibraryError.self) { try await second.consume(previewB.previewID, account: account, session: session) }
        await second.finishInspection(inspection)
        let consumed = try await second.consume(previewB.previewID, account: account, session: session)
        #expect(consumed.operation.id == previewB.operation.id)
        try await second.finish(consumed.operation)
    }

    private func prepare(_ store: AssetOperationStore, session: UUID) async throws -> AssetPreparedChange {
        let token = try await store.reservePreparation(upload: false)
        return try await store.prepare(account: account, session: session, change: .init(action: .updateReferenceName, appID: "app"), snapshot: nil, reservation: token)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("asc-asset-journal-test-" + UUID().uuidString)
    }
}
