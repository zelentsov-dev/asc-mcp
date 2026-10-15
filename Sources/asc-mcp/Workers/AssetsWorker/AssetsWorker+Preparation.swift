import Foundation
import MCP

extension AssetsWorker {
    func prepareChange(_ arguments: [String: Value]) async throws -> CallTool.Result {
        let change = try parseChange(arguments)
        if change.action.isUpload { try uploadService.validatePinnedTransportAvailability() }
        let reservation = try await store.reservePreparation(upload: change.action.isUpload)
        var snapshot: UploadFileSnapshot?
        var prepared = false
        defer { if !prepared { snapshot?.discard() } }
        do {
            var validated = try await inspectChange(change)
            if change.action.isUpload {
                let (file, sha) = try AssetMediaInspector.snapshot(path: required("file_path", arguments))
                snapshot = file
                let kind: AssetLibraryKind = change.action == .uploadImage ? .image : .video
                let facts = try await AssetMediaInspector.inspect(file, kind: kind)
                let catalog = try await referenceData()
                let specs = catalog.attributes?[kind.specs]?.arrayValue ?? []
                let matches = try AssetMediaInspector.matchingSpecs(snapshot: file, facts: facts, specs: specs)
                let allowed = try availableSpecs(catalog, category: change.category ?? "", target: change.target, placementType: change.placementType, group: change.placementGroup)
                validated.expectedSpecIDs = matches.filter { allowed.contains($0) }
                guard validated.expectedSpecIDs?.isEmpty == false else { throw AssetLibraryError("No matching file specification is available for this category and intended placement") }
                if let timeCode = change.previewFrameTimeCode { try validateTimeCode(timeCode, duration: facts.duration, fps: facts.framesPerSecond) }
                validated.fileSHA256 = sha
                validated.fileName = file.fileName
                validated.fileSize = file.fileSize
                if let resumeID = change.resumeOperationID {
                    let previous = try await resumableOperation(resumeID, change: validated)
                    guard sha == previous.change.fileSHA256, file.fileSize == previous.change.fileSize, file.fileName == previous.change.fileName else {
                        throw AssetLibraryError("Resume requires the identical file name, size and SHA-256 snapshot")
                    }
                }
            }
            try Task.checkCancellation()
            let preview = try await store.prepare(account: accountScope(), session: sessionID, change: validated, snapshot: snapshot, reservation: reservation)
            prepared = true
            return MCPResult.jsonObject([
                "success": true, "preview_id": preview.previewID, "operation_id": preview.operation.id,
                "expires_at": ISO8601DateFormatter().string(from: preview.expiresAt),
                "changes": try AssetLibraryJSON.value(validated).asAny,
                "writes_performed": false, "apply_tool": "assets_apply_change",
                "approval_note": "Review this change in your MCP client. A preview is not proof of human authorization."
            ])
        } catch {
            await store.releasePreparation(reservation)
            throw error
        }
    }

    func parseChange(_ arguments: [String: Value]) throws -> AssetLibraryChange {
        guard let action = AssetLibraryAction(rawValue: try required("action", arguments)) else { throw AssetLibraryError("Unsupported asset action") }
        var allowed: Set<String> = ["app_id", "action"]
        let assetFields: Set<String> = ["asset_kind", "asset_id"]
        let targetFields: Set<String> = ["target_type", "target_id", "placement_type", "placement_group"]
        switch action {
        case .uploadImage, .uploadVideo: allowed.formUnion(["file_path", "category", "reference_name", "resume_operation_id"]); allowed.formUnion(targetFields)
        case .updateReferenceName: allowed.formUnion(assetFields); allowed.insert("reference_name")
        case .updateVideoPoster: allowed.formUnion(assetFields); allowed.insert("preview_frame_time_code")
        case .createPlacement: allowed.formUnion(assetFields); allowed.formUnion(targetFields)
        case .replacePlacement: allowed.formUnion(assetFields); allowed.insert("placement_id")
        case .deletePlacement: allowed.insert("placement_id")
        case .reorderPlacements: allowed.formUnion(["target_type", "target_id", "placement_group", "ordered_placement_ids"])
        case .archiveAsset, .unarchiveAsset, .deleteAsset: allowed.formUnion(assetFields)
        case .addReviewItem: allowed.formUnion(assetFields); allowed.insert("submission_id")
        }
        if action == .uploadVideo { allowed.insert("preview_frame_time_code") }
        guard Set(arguments.keys).isSubset(of: allowed) else { throw AssetLibraryError("Parameters do not match the selected action") }
        var change = AssetLibraryChange(action: action, appID: try identifier("app_id", arguments))
        if action.isUpload {
            if arguments["resume_operation_id"] != nil { change.resumeOperationID = try required("resume_operation_id", arguments) }
            change.kind = action == .uploadImage ? .image : .video
            change.category = try required("category", arguments)
            guard ["CREATIVE_ASSETS", "APP_SCREENSHOTS_AND_PREVIEWS"].contains(change.category) else { throw AssetLibraryError("Invalid asset category") }
            _ = try required("file_path", arguments)
        } else if ![.deletePlacement, .reorderPlacements].contains(action) {
            guard let kind = AssetLibraryKind(rawValue: try required("asset_kind", arguments)) else { throw AssetLibraryError("Invalid asset_kind") }
            change.kind = kind
            change.assetID = try identifier("asset_id", arguments)
        }
        if action == .updateReferenceName || arguments["reference_name"] != nil {
            guard let value = arguments["reference_name"] else { throw AssetLibraryError("reference_name is required") }
            if case .null = value { change.referenceName = nil }
            else { change.referenceName = try required("reference_name", arguments) }
        }
        if action == .updateVideoPoster || arguments["preview_frame_time_code"] != nil {
            guard change.kind == .video else { throw AssetLibraryError("Poster changes require a video") }
            change.previewFrameTimeCode = try required("preview_frame_time_code", arguments)
            try validateTimeCode(change.previewFrameTimeCode ?? "", duration: nil, fps: nil)
        }
        if arguments["target_type"] != nil || arguments["target_id"] != nil || action == .createPlacement || action == .reorderPlacements {
            (change.target, change.targetID) = try targetArguments(arguments)
            change.placementGroup = try required("placement_group", arguments)
            if action != .reorderPlacements { change.placementType = try required("placement_type", arguments) }
        } else if arguments["placement_type"] != nil || arguments["placement_group"] != nil {
            throw AssetLibraryError("Placement constraints require an exact target localization")
        }
        if [.replacePlacement, .deletePlacement].contains(action) { change.placementID = try identifier("placement_id", arguments) }
        if action == .reorderPlacements {
            guard change.target != .appEventLocalization else { throw AssetLibraryError("Apple does not support ordering event placements") }
            change.orderedPlacementIDs = try stringList("ordered_placement_ids", arguments).map { try AssetLibraryJSON.identifier($0, field: "ordered_placement_ids") }
        }
        if action == .addReviewItem { change.submissionID = try identifier("submission_id", arguments) }
        if action.isUpload, change.referenceName == nil, change.resumeOperationID == nil { change.referenceName = "asc-mcp-" + UUID().uuidString }
        return change
    }

    func inspectChange(_ proposed: AssetLibraryChange) async throws -> AssetLibraryChange {
        var change = proposed
        change.baseline = [:]
        change.warnings = []
        let library = try await library(appID: change.appID)
        change.baseline["library"] = library.id
        let catalog = try await referenceData(refresh: true)
        change.baseline["reference_data"] = try catalog.fingerprint()
        if let resumeID = change.resumeOperationID {
            let previous = try await resumableOperation(resumeID, change: change)
            change.assetID = previous.resourceIDs["asset_id"]
            change.referenceName = previous.change.referenceName
            change.previewFrameTimeCode = previous.change.previewFrameTimeCode
            change.baseline["resume_operation"] = try AssetLibraryJSON.fingerprint(previous)
        }
        if let id = change.placementID {
            let placement = try await ownedPlacement(appID: change.appID, id: id, requireEditable: true)
            change.baseline["placement"] = try placement.fingerprint()
            guard let target = AssetLibraryTarget.allCases.first(where: { placement.related($0.rawValue) != nil }),
                  let targetID = placement.related(target.rawValue)?.id,
                  let group = placement.attributes?["placementGroup"]?.stringValue,
                  let type = placement.attributes?["placementType"]?.stringValue else { throw AssetLibraryError("Placement identity is incomplete") }
            change.target = target; change.targetID = targetID; change.placementGroup = group; change.placementType = type
            let assets = [AssetLibraryKind.image, .video].compactMap { kind -> (AssetLibraryKind, String)? in
                guard let asset = placement.related(kind.rawValue), asset.type == kind.resourceType else { return nil }
                return (kind, asset.id)
            }
            guard assets.count == 1, let (oldKind, oldAssetID) = assets.first else {
                throw AssetLibraryError("Existing placement must identify exactly one asset for explicit recovery")
            }
            change.previousPlacement = AssetPreviousPlacement(assetKind: oldKind, assetID: oldAssetID,
                target: target, targetID: targetID, placementType: type, placementGroup: group, orderedPlacementIDs: [])
            change.warnings.append("The existing placement is removed. Its asset is retained. Replacement is not atomic and may leave a temporary gap in this draft.")
        }
        var existing: [AssetLibraryResource] = []
        if let target = change.target, let targetID = change.targetID {
            change.baseline.merge(try await targetScope(appID: change.appID, target: target, id: targetID, requireEditable: true)) { _, new in new }
            if let group = change.placementGroup {
                try validatePlatform(catalog, group: group, platforms: change.baseline["target_platforms"] ?? "")
            }
            existing = try await targetPlacements(target: target, id: targetID)
            change.baseline["target_placement_ids"] = existing.map(\.id).sorted().joined(separator: ",")
            change.baseline["target_placements"] = try AssetLibraryJSON.fingerprint(try existing.map { try $0.fingerprint() })
            if let id = change.placementID {
                guard let member = existing.first(where: { $0.id == id }),
                      try member.fingerprint() == change.baseline["placement"] else {
                    throw AssetLibraryError("Existing placement is not consistently present in its target inventory")
                }
                change.previousPlacement?.orderedPlacementIDs = existing.filter {
                    $0.attributes?["placementGroup"]?.stringValue == change.placementGroup
                }.map(\.id)
            }
            if change.action == .reorderPlacements {
                let group = existing.filter { $0.attributes?["placementGroup"]?.stringValue == change.placementGroup }
                guard Set(group.map(\.id)) == Set(change.orderedPlacementIDs ?? []), group.count == change.orderedPlacementIDs?.count else { throw AssetLibraryError("Reorder must contain every placement in the exact group, once") }
            }
            if change.action == .replacePlacement {
                change.orderedPlacementIDs = existing.filter { $0.attributes?["placementGroup"]?.stringValue == change.placementGroup }.map(\.id)
            }
        }
        if let kind = change.kind, let assetID = change.assetID {
            let asset = try await ownedAsset(appID: change.appID, kind: kind, id: assetID)
            guard let state = asset.state, Self.knownAssetStates.contains(state) else { throw AssetLibraryError("Asset has an unknown state; reading is allowed but mutations are blocked") }
            change.baseline["asset"] = try asset.fingerprint()
            let uses = try await placements(kind: kind, id: assetID)
            change.baseline["asset_placements"] = try AssetLibraryJSON.fingerprint(try uses.sorted { $0.id < $1.id }.map { try $0.fingerprint() })
            if !uses.isEmpty { change.warnings.append("This reusable asset currently has \(uses.count) placement(s); binary deletion never cascades.") }
            switch change.action {
            case .uploadImage, .uploadVideo:
                guard change.resumeOperationID != nil, state == "AWAITING_UPLOAD" else { throw AssetLibraryError("Only a known reservation awaiting upload can be resumed") }
            case .deleteAsset:
                guard uses.isEmpty, ["AWAITING_UPLOAD", "FAILED", "PREPARE_FOR_SUBMISSION"].contains(state) else { throw AssetLibraryError("Delete requires an unused asset in AWAITING_UPLOAD, FAILED or PREPARE_FOR_SUBMISSION") }
            case .archiveAsset, .unarchiveAsset:
                guard state == (change.action == .archiveAsset ? "APPROVED" : "ARCHIVED") else { throw AssetLibraryError("Archive requires APPROVED; unarchive requires ARCHIVED") }
                for use in uses { _ = try await ownedPlacement(appID: change.appID, id: use.id, requireEditable: true) }
            case .updateVideoPoster:
                guard ["PREPARE_FOR_SUBMISSION", "COMPLETE", "REJECTED"].contains(state) else { throw AssetLibraryError("Poster updates are restricted to processed assets outside active or approved review") }
                for use in uses { _ = try await ownedPlacement(appID: change.appID, id: use.id, requireEditable: true) }
                change.warnings.append("Changing the poster affects every placement of this video; frame processing is asynchronous.")
            case .createPlacement, .replacePlacement:
                if kind == .video {
                    guard asset.attributes?["previewFrameImage"]?.objectValue?["state"]?.stringValue == "COMPLETE" else { throw AssetLibraryError("Video poster frame must finish processing before placement") }
                }
                guard Self.placeableStates.contains(state), let specID = asset.attributes?["specId"]?.stringValue,
                      let category = asset.attributes?["category"]?.stringValue else { throw AssetLibraryError("Asset must be processed with a known specification before placement") }
                let allowed = try availableSpecs(catalog, category: category, target: change.target, placementType: change.placementType, group: change.placementGroup)
                guard allowed.contains(specID) else { throw AssetLibraryError("Asset specification/category does not match the requested placement") }
                try validateCapacity(catalog, change: change, placements: existing)
            case .addReviewItem:
                guard ["PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED"].contains(state) else { throw AssetLibraryError("Asset is not ready for independent review") }
                change.baseline.merge(try await reviewScope(change, uses: uses, asset: asset, catalog: catalog)) { _, new in new }
            default: break
            }
        }
        if change.action.isUpload {
            _ = try availableSpecs(catalog, category: change.category ?? "", target: change.target, placementType: change.placementType, group: change.placementGroup)
            let kind: AssetLibraryKind = change.action == .uploadImage ? .image : .video
            let assets = try await all("/v1/appAssetLibraries/\(try ASCPathSegment.encode(library.id))/\(try ASCPathSegment.encode(kind.collection))", type: kind.resourceType)
            change.baseline["upload_existing_ids"] = assets.map(\.id).sorted().joined(separator: ",")
        }
        return change
    }

    func resumableOperation(_ id: String, change: AssetLibraryChange) async throws -> AssetLibraryOperation {
        let operation = try await store.get(id: id, account: accountScope())
        guard !(await store.isActive(id)), operation.change.action == change.action,
              operation.change.appID == change.appID, operation.change.kind == change.kind,
              operation.change.category == change.category, operation.resourceIDs["asset_id"] != nil,
              operation.resourceIDs["resumed_by_operation_id"] == nil,
              operation.completedSteps.contains("reserve_asset"), !operation.completedSteps.contains("commit_upload"),
              operation.pendingStep != "commit_upload", operation.status == "requires_reconciliation",
              change.referenceName == nil || change.referenceName == operation.change.referenceName,
              change.previewFrameTimeCode == nil || change.previewFrameTimeCode == operation.change.previewFrameTimeCode else {
            throw AssetLibraryError("Operation is not a confirmed resumable reservation in this account/app, or its file metadata differs")
        }
        return operation
    }

    static let knownAssetStates: Set<String> = ["AWAITING_UPLOAD", "UPLOAD_COMPLETE", "FAILED", "COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED", "REJECTED", "ARCHIVED"]
    static let placeableStates: Set<String> = ["COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "APPROVED", "REJECTED"]

    func validatePlatform(_ catalog: AssetLibraryResource, group: String, platforms: String) throws {
        guard let profile = catalog.attributes?["placementProfileGroups"]?.arrayValue?.first(where: {
            $0.objectValue?["placementProfileGroupId"]?.stringValue == group
        })?.objectValue, let platform = profile["platform"]?.stringValue else {
            throw AssetLibraryError("Placement group has no known platform")
        }
        if platform == "ANY" { return }
        let mapping = ["IPHONE_APP_STORE": "IOS", "IPAD_APP_STORE": "IOS", "WATCH_APP_STORE": "IOS",
                       "IMESSAGE_APP_STORE": "IOS", "VISION_PRO_APP_STORE": "VISION_OS", "MAC_APP_STORE": "MAC_OS", "TV_APP_STORE": "TV_OS"]
        guard let expected = mapping[platform], platforms.split(separator: ",").contains(Substring(expected)) else {
            throw AssetLibraryError("Placement group platform does not match the verified target application/platform")
        }
    }

    func availableSpecs(_ catalog: AssetLibraryResource, category: String, target: AssetLibraryTarget?, placementType: String?, group: String?) throws -> Set<String> {
        let features = catalog.attributes?["features"]?.arrayValue ?? []
        let selected = features.filter { target == nil || $0.objectValue?["featureId"]?.stringValue == target?.feature }
        guard !selected.isEmpty else { throw AssetLibraryError("Requested feature is unavailable in Apple's live catalog") }
        let policies = selected.flatMap { $0.objectValue?["placementPolicies"]?.arrayValue ?? [] }
        let policyTypes = Set(policies.compactMap { value -> String? in
            guard let policy = value.objectValue else { return nil }
            if let group {
                let limits = policy["groupLimits"]?.arrayValue ?? []
                guard limits.contains(where: {
                    AssetMediaInspector.strings($0.objectValue?["groupIds"]).contains(group)
                        && (AssetMediaInspector.number($0.objectValue?["maxCount"]) ?? 0) >= 1
                }) else { return nil }
            }
            return policy["placementType"]?.stringValue
        })
        if let group {
            guard (catalog.attributes?["placementProfileGroups"]?.arrayValue ?? []).contains(where: { $0.objectValue?["placementProfileGroupId"]?.stringValue == group }) else { throw AssetLibraryError("Unknown placement group after refreshing Apple's catalog") }
        }
        let types = catalog.attributes?["placementTypes"]?.arrayValue ?? []
        let specs = types.flatMap { value -> [String] in
            guard let type = value.objectValue, let name = type["placementTypeId"]?.stringValue,
                  policyTypes.contains(name), placementType == nil || placementType == name,
                  AssetMediaInspector.strings(type["acceptsAssetCategories"]).contains(category) else { return [] }
            return (type["specMappings"]?.arrayValue ?? []).flatMap { value -> [String] in
                guard let mapping = value.objectValue, group == nil || mapping["placementGroupId"]?.stringValue == group else { return [] }
                return AssetMediaInspector.strings(mapping["specs"])
            }
        }
        guard !specs.isEmpty else { throw AssetLibraryError("No specifications support the requested category, feature, type and group") }
        return Set(specs)
    }

    func validateCapacity(_ catalog: AssetLibraryResource, change: AssetLibraryChange, placements: [AssetLibraryResource]) throws {
        guard let target = change.target, let group = change.placementGroup, let type = change.placementType,
              let feature = catalog.attributes?["features"]?.arrayValue?.first(where: { $0.objectValue?["featureId"]?.stringValue == target.feature })?.objectValue,
              let policy = feature["placementPolicies"]?.arrayValue?.first(where: { $0.objectValue?["placementType"]?.stringValue == type })?.objectValue else {
            throw AssetLibraryError("Missing placement capacity policy")
        }
        let limits = (policy["groupLimits"]?.arrayValue ?? []).compactMap(\.objectValue).filter { AssetMediaInspector.strings($0["groupIds"]).contains(group) }
        guard !limits.isEmpty else { throw AssetLibraryError("No capacity policy exists for the placement group") }
        for limit in limits {
            let groups = AssetMediaInspector.strings(limit["groupIds"])
            guard let maxCount = AssetMediaInspector.number(limit["maxCount"]), maxCount >= 1 else { throw AssetLibraryError("Invalid placement capacity policy") }
            let count = placements.filter {
                $0.id != change.placementID && $0.attributes?["placementType"]?.stringValue == type && groups.contains($0.attributes?["placementGroup"]?.stringValue ?? "")
            }.count
            guard Double(count + 1) <= maxCount else { throw AssetLibraryError("Placement group is full") }
        }
    }

    func validateTimeCode(_ value: String, duration: Double?, fps: Double?) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }),
              let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]), let frame = Double(parts[3]), minutes < 60, seconds < 60 else {
            throw AssetLibraryError("preview_frame_time_code must use HH:MM:SS:FF")
        }
        if let fps, let duration {
            guard fps > 0, frame < fps, hours * 3_600 + minutes * 60 + seconds + frame / fps < duration else { throw AssetLibraryError("Poster timestamp is outside this video's duration/frame rate") }
        }
    }
}
