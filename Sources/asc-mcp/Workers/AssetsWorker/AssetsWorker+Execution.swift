import Foundation
import MCP

extension AssetsWorker {
    func applyChange(previewID: String) async throws -> CallTool.Result {
        let account = try await accountScope()
        let preview = try await store.consume(previewID, account: account, session: sessionID)
        defer { preview.snapshot?.discard() }
        var operation = preview.operation
        do {
            let current = try await inspectChange(operation.change)
            guard current.baseline == operation.change.baseline else { throw AssetLibraryError("Remote state changed since preview; no write was attempted. Prepare a new change.") }
            try Task.checkCancellation()
            if operation.change.action.isUpload {
                guard let snapshot = preview.snapshot, try AssetMediaInspector.sha256(snapshot) == operation.change.fileSHA256 else {
                    throw AssetLibraryError("Prepared upload snapshot is missing or changed")
                }
                try await executeUpload(snapshot, operation: &operation)
            } else {
                try await executeMutation(operation: &operation)
            }
            if operation.status == "running" { operation.status = "succeeded" }
        } catch {
            operation.message = Redactor.redact(error.localizedDescription)
            if operation.pendingStep == nil && operation.completedSteps.isEmpty {
                operation.status = "failed"
            } else {
                operation.status = "requires_reconciliation"
                do { try await reconcile(&operation) }
                catch {
                    operation.status = "requires_reconciliation"
                    operation.message = Redactor.redact(error.localizedDescription)
                }
            }
        }
        operation.updatedAt = Date()
        do { try await store.finish(operation) }
        catch {
            operation.status = "requires_reconciliation"
            operation.message = "The private journal could not be finalized. Inspect operation_id before any further write."
        }
        return operationResult(operation)
    }

    func executeUpload(_ snapshot: UploadFileSnapshot, operation: inout AssetLibraryOperation) async throws {
        let change = operation.change
        guard let kind = change.kind, let libraryID = change.baseline["library"], let category = change.category else { throw AssetLibraryError("Incomplete upload preview") }
        var attributes: [String: JSONValue] = ["fileName": .string(snapshot.fileName), "fileSize": .int(snapshot.fileSize), "category": .string(category)]
        if let reference = change.referenceName { attributes["referenceName"] = .string(reference) }
        if let timeCode = change.previewFrameTimeCode { attributes["previewFrameTimeCode"] = .string(timeCode) }
        let body = try AssetLibraryJSON.body(type: kind.resourceType, attributes: attributes,
                                             relationships: ["assetLibrary": AssetLibraryResourceID(type: "appAssetLibraries", id: libraryID).relationship])
        let reserved: AssetLibraryResource
        if let resumeID = change.resumeOperationID, let assetID = change.assetID {
            var previous = try await resumableOperation(resumeID, change: change)
            reserved = try await ownedAsset(appID: change.appID, kind: kind, id: assetID)
            try validateUploadIdentity(reserved, change: change)
            guard reserved.state == "AWAITING_UPLOAD" else { throw AssetLibraryError("Existing reservation is no longer awaiting upload") }
            previous.resourceIDs["resumed_by_operation_id"] = operation.id
            previous.updatedAt = Date()
            try await store.checkpoint(previous)
            operation.resourceIDs["asset_id"] = assetID
            try await complete("reserve_asset", operation: &operation)
        } else {
            reserved = try await create("/v1/\(try ASCPathSegment.encode(kind.resourceType))", body: body, type: kind.resourceType, step: "reserve_asset", operation: &operation)
        }
        operation.resourceIDs["asset_id"] = reserved.id
        try validateUploadIdentity(reserved, change: change)
        guard reserved.state == "AWAITING_UPLOAD", let values = reserved.attributes?["uploadOperations"] else { throw AssetLibraryError("Reservation did not return a fresh upload resource") }
        try await store.checkpoint(operation)
        let transfers = try JSONDecoder().decode([ASCUploadOperation].self, from: AssetLibraryJSON.encode(values))
        let destinations = try await validateUploadDestinations(transfers)
        try await begin("transfer_bytes", operation: &operation)
        _ = try await uploadService.withPinnedDestinations(destinations).uploadFile(snapshot: snapshot, uploadOperations: transfers)
        guard try AssetMediaInspector.sha256(snapshot) == change.fileSHA256 else { throw AssetLibraryError("Snapshot changed during upload") }
        try await complete("transfer_bytes", operation: &operation)
        try await begin("commit_upload", operation: &operation)
        _ = try await httpClient.patch("/v1/\(try ASCPathSegment.encode(kind.resourceType))/\(try ASCPathSegment.encode(reserved.id))", body: AssetLibraryJSON.body(type: kind.resourceType, id: reserved.id, attributes: ["uploaded": .bool(true)]))
        try await complete("commit_upload", operation: &operation)
        var processed = try await resource(kind.resourceType, reserved.id)
        for _ in 0..<10 where ["AWAITING_UPLOAD", "UPLOAD_COMPLETE"].contains(processed.state ?? "") {
            try await Task.sleep(for: .seconds(1))
            processed = try await resource(kind.resourceType, reserved.id)
        }
        try validateUploadIdentity(processed, change: change)
        try evaluateProcessing(processed, change: change, operation: &operation)
    }

    func executeMutation(operation: inout AssetLibraryOperation) async throws {
        let change = operation.change
        switch change.action {
        case .createPlacement, .replacePlacement:
            if change.action == .replacePlacement {
                guard let id = change.placementID else { throw AssetLibraryError("Missing old placement") }
                try await delete("appAssetLibraryPlacements", id: id, step: "remove_old_placement", operation: &operation)
                guard let target = change.target, let targetID = change.targetID else { throw AssetLibraryError("Missing placement target") }
                let remaining = try await targetPlacements(target: target, id: targetID)
                let actual = remaining.filter { $0.attributes?["placementGroup"]?.stringValue == change.placementGroup }.map(\.id)
                guard actual == (change.orderedPlacementIDs ?? []).filter({ $0 != id }) else { throw AssetLibraryError("Placement group changed after removal; inspect the partial replacement") }
            }
            let placement = try await createPlacement(change, operation: &operation)
            operation.resourceIDs["placement_id"] = placement.id
            try await store.checkpoint(operation)
            if change.action == .replacePlacement, change.target != .appEventLocalization {
                let order = (change.orderedPlacementIDs ?? []).map { $0 == change.placementID ? placement.id : $0 }
                try await reorder(change, ids: order, operation: &operation)
            }
        case .deletePlacement:
            guard let id = change.placementID else { throw AssetLibraryError("Missing placement ID") }
            try await delete("appAssetLibraryPlacements", id: id, step: "delete_placement", operation: &operation)
        case .reorderPlacements:
            try await reorder(change, ids: change.orderedPlacementIDs ?? [], operation: &operation)
        case .deleteAsset:
            guard let kind = change.kind, let id = change.assetID else { throw AssetLibraryError("Missing asset identity") }
            try await delete(kind.resourceType, id: id, step: "delete_asset", operation: &operation)
        case .archiveAsset, .unarchiveAsset, .updateReferenceName, .updateVideoPoster:
            guard let kind = change.kind, let id = change.assetID else { throw AssetLibraryError("Missing asset identity") }
            let attributes: [String: JSONValue]
            switch change.action {
            case .archiveAsset: attributes = ["archived": .bool(true)]
            case .unarchiveAsset: attributes = ["archived": .bool(false)]
            case .updateVideoPoster: attributes = ["previewFrameTimeCode": .string(change.previewFrameTimeCode ?? "")]
            default: attributes = ["referenceName": change.referenceName.map(JSONValue.string) ?? .null]
            }
            try await begin(change.action.rawValue, operation: &operation)
            _ = try await httpClient.patch("/v1/\(try ASCPathSegment.encode(kind.resourceType))/\(try ASCPathSegment.encode(id))", body: AssetLibraryJSON.body(type: kind.resourceType, id: id, attributes: attributes))
            let updated = try await resource(kind.resourceType, id)
            guard mutationMatches(updated, change: change) else { throw AssetLibraryError("Apple accepted the update but read-back did not confirm its effect") }
            operation.resourceIDs["asset_id"] = id
            try await complete(change.action.rawValue, operation: &operation)
            if change.action == .updateVideoPoster, updated.posterFrameState != "COMPLETE" {
                guard updated.posterFrameState != "FAILED" else { throw AssetLibraryError("Poster timestamp changed but its frame processing failed") }
                operation.status = "processing_pending"
                operation.message = "Poster timestamp was updated; frame processing must be inspected separately."
            }
        case .addReviewItem:
            guard let kind = change.kind, let id = change.assetID, let submissionID = change.submissionID else { throw AssetLibraryError("Missing review identity") }
            let relationship = kind == .image ? "appAssetLibraryImage" : "appAssetLibraryVideo"
            let body = try AssetLibraryJSON.body(type: "reviewSubmissionItems", relationships: [
                "reviewSubmission": AssetLibraryResourceID(type: "reviewSubmissions", id: submissionID).relationship,
                relationship: AssetLibraryResourceID(type: kind.resourceType, id: id).relationship
            ])
            let item = try await create("/v1/reviewSubmissionItems", body: body, type: "reviewSubmissionItems", step: "add_review_item", operation: &operation)
            operation.resourceIDs["item_id"] = item.id
            let items = try await reviewItems(submissionID)
            guard items.contains(where: { $0.id == item.id && $0.related(relationship) == AssetLibraryResourceID(type: kind.resourceType, id: id) }) else { throw AssetLibraryError("Review item was not confirmed in the intended submission") }
        case .uploadImage, .uploadVideo: throw AssetLibraryError("Upload execution requires its protected snapshot")
        }
    }

    func createPlacement(_ change: AssetLibraryChange, operation: inout AssetLibraryOperation) async throws -> AssetLibraryResource {
        guard let kind = change.kind, let assetID = change.assetID, let target = change.target, let targetID = change.targetID,
              let type = change.placementType, let group = change.placementGroup else { throw AssetLibraryError("Incomplete placement identity") }
        let body = try AssetLibraryJSON.body(type: "appAssetLibraryPlacements", attributes: ["placementType": .string(type), "placementGroup": .string(group)], relationships: [
            kind.rawValue: AssetLibraryResourceID(type: kind.resourceType, id: assetID).relationship,
            target.rawValue: AssetLibraryResourceID(type: target.resourceType, id: targetID).relationship
        ])
        let created = try await create("/v1/appAssetLibraryPlacements", body: body, type: "appAssetLibraryPlacements", step: "create_placement", operation: &operation)
        operation.resourceIDs["placement_id"] = created.id
        try await store.checkpoint(operation)
        let verified = try await resource("appAssetLibraryPlacements", created.id, include: Self.placementIncludes)
        guard placementMatches(verified, change: change) else { throw AssetLibraryError("Created placement does not match the preview") }
        let list = try await targetPlacements(target: target, id: targetID)
        guard list.contains(where: { $0.id == created.id && placementMatches($0, change: change) }) else { throw AssetLibraryError("Created placement is absent from the intended localization") }
        return verified
    }

    func reorder(_ change: AssetLibraryChange, ids: [String], operation: inout AssetLibraryOperation) async throws {
        guard let target = change.target, target != .appEventLocalization, let targetID = change.targetID, let group = change.placementGroup else { throw AssetLibraryError("Unsupported ordering target") }
        let before = try await targetPlacements(target: target, id: targetID).filter { $0.attributes?["placementGroup"]?.stringValue == group }
        guard ids.count == before.count, Set(ids) == Set(before.map(\.id)) else { throw AssetLibraryError("Ordering membership changed before mutation") }
        let ordered: [JSONValue] = ids.map { .object(["type": .string("appAssetLibraryPlacements"), "id": .string($0)]) }
        let body = try AssetLibraryJSON.body(type: "appAssetLibraryPlacementOrderingRequests", attributes: ["placementGroup": .string(group)], relationships: [
            target.rawValue: AssetLibraryResourceID(type: target.resourceType, id: targetID).relationship,
            "orderedPlacements": .object(["data": .array(ordered)])
        ])
        let request = try await create("/v1/appAssetLibraryPlacementOrderingRequests", body: body, type: "appAssetLibraryPlacementOrderingRequests", step: "reorder_placements", operation: &operation)
        operation.resourceIDs["ordering_request_id"] = request.id
        let after = try await targetPlacements(target: target, id: targetID).filter { $0.attributes?["placementGroup"]?.stringValue == group }
        guard after.map(\.id) == ids else { throw AssetLibraryError("Apple did not confirm the exact requested placement order") }
    }

    func create(_ path: String, body: Data, type: String, step: String, operation: inout AssetLibraryOperation) async throws -> AssetLibraryResource {
        try await begin(step, operation: &operation)
        let data = try await httpClient.post(path, body: body)
        let resource = try JSONDecoder().decode(AssetLibraryDocument.self, from: data).data
        guard resource.type == type else { throw AssetLibraryError("Apple create returned an unexpected resource type") }
        _ = try AssetLibraryJSON.identifier(resource.id, field: "created_id")
        let key: String
        switch type {
        case "appAssetLibraryImages", "appAssetLibraryVideos": key = "asset_id"
        case "appAssetLibraryPlacements": key = "placement_id"
        case "reviewSubmissionItems": key = "item_id"
        case "appAssetLibraryPlacementOrderingRequests": key = "ordering_request_id"
        default: throw AssetLibraryError("Unsupported journal resource type")
        }
        operation.resourceIDs[key] = resource.id
        try await complete(step, operation: &operation)
        return resource
    }

    func delete(_ type: String, id: String, step: String, operation: inout AssetLibraryOperation) async throws {
        try await begin(step, operation: &operation)
        _ = try await httpClient.delete("/v1/\(try ASCPathSegment.encode(type))/\(try ASCPathSegment.encode(try AssetLibraryJSON.identifier(id, field: "delete_id")))")
        guard try await isAbsent(type, id: id) else { throw AssetLibraryError("Deleted resource is still visible; inspect before any retry") }
        try await complete(step, operation: &operation)
    }

    func isAbsent(_ type: String, id: String) async throws -> Bool {
        do { _ = try await resource(type, id); return false }
        catch let error as ASCError {
            switch error {
            case .api(_, 404), .apiResponse(_, 404): return true
            default: throw error
            }
        }
    }

    func begin(_ step: String, operation: inout AssetLibraryOperation) async throws {
        try Task.checkCancellation()
        operation.pendingStep = step
        operation.updatedAt = Date()
        try await store.checkpoint(operation)
    }

    func complete(_ step: String, operation: inout AssetLibraryOperation) async throws {
        operation.pendingStep = nil
        operation.completedSteps.append(step)
        operation.updatedAt = Date()
        try await store.checkpoint(operation)
    }

    func validateUploadIdentity(_ resource: AssetLibraryResource, change: AssetLibraryChange) throws {
        guard resource.type == change.kind?.resourceType,
              resource.attributes?["fileName"]?.stringValue == change.fileName,
              AssetMediaInspector.number(resource.attributes?["fileSize"]) == change.fileSize.map(Double.init),
              resource.attributes?["category"]?.stringValue == change.category,
              resource.attributes?["referenceName"]?.stringValue == change.referenceName else {
            throw AssetLibraryError("Upload response does not match the reserved file identity")
        }
    }

    func evaluateProcessing(_ resource: AssetLibraryResource, change: AssetLibraryChange, operation: inout AssetLibraryOperation) throws {
        if resource.state == "FAILED" { throw AssetLibraryError("Apple asset processing failed; inspect stateDetails before preparing a replacement") }
        if Self.placeableStates.contains(resource.state ?? "") {
            guard let spec = resource.attributes?["specId"]?.stringValue, change.expectedSpecIDs?.contains(spec) == true else { throw AssetLibraryError("Apple's assigned specId does not match the prepared file requirements") }
            if change.kind == .video, resource.posterFrameState != "COMPLETE" {
                guard resource.posterFrameState != "FAILED" else {
                    throw AssetLibraryError("Video was processed but its poster frame failed; inspect the asset before preparing a poster change")
                }
                operation.status = "processing_pending"
                operation.message = "Video processing is complete; poster-frame processing is pending."
            } else {
                operation.status = "succeeded"
                operation.message = "File processing was verified. Placement, review and publication are separate actions."
            }
        } else {
            guard ["AWAITING_UPLOAD", "UPLOAD_COMPLETE"].contains(resource.state ?? "") else { throw AssetLibraryError("Unknown or unexpected processing state; inspect without retrying the upload") }
            operation.status = "processing_pending"
            operation.message = "Apple processing is pending. Inspect operation_id and the asset instead of creating another upload."
        }
    }

    func placementMatches(_ resource: AssetLibraryResource, change: AssetLibraryChange) -> Bool {
        guard let kind = change.kind, let id = change.assetID, let target = change.target, let targetID = change.targetID else { return false }
        return resource.type == "appAssetLibraryPlacements" && resource.related(kind.rawValue) == AssetLibraryResourceID(type: kind.resourceType, id: id)
            && resource.related(target.rawValue) == AssetLibraryResourceID(type: target.resourceType, id: targetID)
            && resource.attributes?["placementType"]?.stringValue == change.placementType
            && resource.attributes?["placementGroup"]?.stringValue == change.placementGroup
    }

    func mutationMatches(_ resource: AssetLibraryResource, change: AssetLibraryChange) -> Bool {
        switch change.action {
        case .archiveAsset: resource.state == "ARCHIVED"
        case .unarchiveAsset: resource.state == "APPROVED"
        case .updateReferenceName: resource.attributes?["referenceName"]?.stringValue == change.referenceName
        case .updateVideoPoster: resource.attributes?["previewFrameTimeCode"]?.stringValue == change.previewFrameTimeCode
        default: false
        }
    }

    func operationResult(_ operation: AssetLibraryOperation) -> CallTool.Result {
        let failed = ["failed", "outcome_unknown", "requires_reconciliation"].contains(operation.status)
        var result: [String: Any] = ["success": !failed, "operation": (try? AssetLibraryJSON.value(operation).asAny) ?? [:],
                                   "retry_safe": false, "inspect_tool": "assets_get_operation"]
        if failed { result["error"] = operation.message ?? "The operation requires inspection before another write" }
        return MCPResult.jsonObject(result, isError: failed)
    }
}
