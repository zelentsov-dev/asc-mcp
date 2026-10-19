import Foundation
import MCP

extension AssetsWorker {
    func getOperation(_ arguments: [String: Value]) async throws -> CallTool.Result {
        let id = try required("operation_id", arguments)
        var operation = try await store.get(id: id, account: accountScope())
        guard !(await store.isActive(id)) else { return operationResult(operation) }
        guard let lease = try await store.beginInspection(operation) else {
            operation.message = "Another process is executing or reconciling this app. No journal update or remote mutation was attempted."
            return operationResult(operation)
        }
        do {
            operation = try await store.get(id: id, account: operation.account)
            if let successor = operation.resourceIDs["resumed_by_operation_id"] {
                let resumed = try await store.get(id: successor, account: operation.account)
                if ["succeeded", "failed"].contains(resumed.status) {
                    operation.status = "superseded"
                    operation.updatedAt = Date()
                    try await store.checkpoint(operation)
                }
                operation.message = "This upload was resumed by operation \(successor). Inspect that operation for its outcome; do not resume this predecessor."
                await store.finishInspection(lease)
                return operationResult(operation)
            }
            if operation.unresolved {
                do { try await reconcile(&operation) }
                catch {
                    operation.status = "requires_reconciliation"
                    operation.message = Redactor.redact(error.localizedDescription)
                }
                operation.updatedAt = Date()
                try await store.checkpoint(operation)
            }
            await store.finishInspection(lease)
            return operationResult(operation)
        } catch {
            await store.finishInspection(lease)
            throw error
        }
    }

    func reconcile(_ operation: inout AssetLibraryOperation) async throws {
        let change = operation.change
        guard operation.pendingStep != nil || !operation.completedSteps.isEmpty else {
            operation.status = "failed"
            operation.message = "Execution stopped before a remote write was recorded. Prepare a new preview."
            return
        }
        operation.status = "requires_reconciliation"
        switch change.action {
        case .uploadImage, .uploadVideo:
            guard let kind = change.kind else { throw AssetLibraryError("Upload journal has no media kind") }
            guard let id = operation.resourceIDs["asset_id"] else {
                let library = try await library(appID: change.appID)
                let oldIDs = Set((change.baseline["upload_existing_ids"] ?? "").split(separator: ",").map(String.init))
                let assets = try await all("/v1/appAssetLibraries/\(try ASCPathSegment.encode(library.id))/\(try ASCPathSegment.encode(kind.collection))", type: kind.resourceType)
                let candidates = assets.filter { !oldIDs.contains($0.id) && (try? validateUploadIdentity($0, change: change)) != nil }
                if candidates.count == 1 { operation.resourceIDs["candidate_asset_id"] = candidates[0].id }
                operation.message = "Reservation response was lost. Candidate resources are diagnostic only; no creation or transfer was replayed. Inspect the candidate and library before preparing a separate action."
                return
            }
            let asset = try await ownedAsset(appID: change.appID, kind: kind, id: id)
            try validateUploadIdentity(asset, change: change)
            guard operation.completedSteps.contains("transfer_bytes"),
                  operation.completedSteps.contains("commit_upload") || operation.pendingStep == "commit_upload" else {
                operation.message = "The reservation is known, but upload/commit was not confirmed. Prepare a resume with this operation_id and the identical file; do not create a second reservation."
                return
            }
            if asset.state == "FAILED" {
                operation.status = "failed"
                operation.message = "Apple confirmed asset processing failure. Inspect the asset's stateDetails before a new preview."
                operation.pendingStep = nil
                return
            }
            try evaluateProcessing(asset, change: change, operation: &operation)
        case .deleteAsset:
            guard let kind = change.kind, let id = change.assetID else { throw AssetLibraryError("Missing deletion identity") }
            guard try await isAbsent(kind.resourceType, id: id) else { throw AssetLibraryError("Asset remains present; deletion is not confirmed and was not replayed") }
            operation.status = "succeeded"
        case .deletePlacement:
            guard let id = change.placementID, try await isAbsent("appAssetLibraryPlacements", id: id) else { throw AssetLibraryError("Placement deletion is not confirmed and was not replayed") }
            operation.status = "succeeded"
        case .archiveAsset, .unarchiveAsset, .updateReferenceName, .updateVideoPoster:
            guard let kind = change.kind, let id = change.assetID else { throw AssetLibraryError("Missing asset update identity") }
            let asset = try await ownedAsset(appID: change.appID, kind: kind, id: id)
            guard mutationMatches(asset, change: change) else { throw AssetLibraryError("Requested asset update is not visible; no mutation was replayed") }
            if change.action == .updateVideoPoster {
                let posterState = asset.posterFrameState
                guard posterState != "FAILED" else { throw AssetLibraryError("Poster-frame processing failed") }
                operation.status = posterState == "COMPLETE" ? "succeeded" : "processing_pending"
            } else {
                operation.status = "succeeded"
            }
        case .createPlacement, .replacePlacement, .reorderPlacements:
            guard let target = change.target, let targetID = change.targetID else { throw AssetLibraryError("Missing placement target") }
            _ = try await targetScope(appID: change.appID, target: target, id: targetID, requireEditable: false)
            let placements = try await targetPlacements(target: target, id: targetID)
            let group = placements.filter { $0.attributes?["placementGroup"]?.stringValue == change.placementGroup }.map(\.id)
            if change.action == .reorderPlacements {
                guard group == change.orderedPlacementIDs else { throw AssetLibraryError("The exact requested order is not confirmed; ordering was not replayed") }
            } else {
                guard let id = operation.resourceIDs["placement_id"] else {
                    let oldIDs = Set((change.baseline["target_placement_ids"] ?? "").split(separator: ",").map(String.init))
                    let candidates = placements.filter { !oldIDs.contains($0.id) && placementMatches($0, change: change) }
                    if candidates.count == 1 { operation.resourceIDs["candidate_placement_id"] = candidates[0].id }
                    throw AssetLibraryError("Placement creation response was lost. Inspect the target and candidate; no creation or deletion was replayed.")
                }
                guard placements.contains(where: { $0.id == id && placementMatches($0, change: change) }) else { throw AssetLibraryError("New placement is not confirmed in the intended localization") }
                if change.action == .replacePlacement {
                    guard !placements.contains(where: { $0.id == change.placementID }) else { throw AssetLibraryError("Old placement is still present; replacement is incomplete") }
                    if target != .appEventLocalization {
                        let expected = (change.orderedPlacementIDs ?? []).map { $0 == change.placementID ? id : $0 }
                        guard group == expected else { throw AssetLibraryError("Replacement exists but its requested order is incomplete. Prepare a separate reorder preview.") }
                    }
                }
            }
            operation.status = "succeeded"
        case .addReviewItem:
            guard let kind = change.kind, let assetID = change.assetID, let submissionID = change.submissionID else { throw AssetLibraryError("Missing review identity") }
            let submission = try await resource("reviewSubmissions", submissionID, include: "app")
            guard submission.related("app") == AssetLibraryResourceID(type: "apps", id: change.appID) else { throw AssetLibraryError("Review submission scope changed") }
            let relation = kind == .image ? "appAssetLibraryImage" : "appAssetLibraryVideo"
            let items = try await reviewItems(submissionID).filter { $0.related(relation) == AssetLibraryResourceID(type: kind.resourceType, id: assetID) && $0.state != "REMOVED" }
            guard items.count == 1, let item = items.first,
                  operation.resourceIDs["item_id"] == nil || operation.resourceIDs["item_id"] == item.id else {
                throw AssetLibraryError("Exactly one intended review item was not confirmed; adding it was not replayed")
            }
            operation.resourceIDs["item_id"] = item.id
            operation.status = "succeeded"
            operation.message = "Asset is attached to the review submission. Submission, approval and placement are separate states."
        }
        if operation.status == "succeeded" {
            operation.pendingStep = nil
            if !operation.completedSteps.contains("reconciled_readback") { operation.completedSteps.append("reconciled_readback") }
            operation.message = "Requested result was confirmed by reading Apple. No remote mutation was replayed."
        }
    }
}
