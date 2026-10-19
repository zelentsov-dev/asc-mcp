import Foundation
import MCP

extension AssetsWorker {
    func addReviewItemFromPreview(_ arguments: [String: Value]) async throws -> CallTool.Result {
        let previewID = try required("preview_id", arguments)
        let account = try await accountScope()
        let preview = try await store.inspectPreview(previewID, account: account, session: sessionID)
        let change = preview.operation.change
        let image = arguments["app_asset_library_image_id"]?.stringValue
        let video = arguments["app_asset_library_video_id"]?.stringValue
        guard change.action == .addReviewItem, (image != nil) != (video != nil),
              change.assetID == (image ?? video), change.kind == (image != nil ? .image : .video),
              change.submissionID == (try identifier("submission_id", arguments)) else {
            throw AssetLibraryError("Review item arguments do not match the prepared asset change")
        }
        return try await applyChange(previewID: previewID)
    }

    func reviewScope(_ change: AssetLibraryChange, uses: [AssetLibraryResource], asset: AssetLibraryResource, catalog: AssetLibraryResource) async throws -> [String: String] {
        guard let submissionID = change.submissionID, let kind = change.kind, let assetID = change.assetID else { throw AssetLibraryError("Incomplete review item change") }
        let submission = try await resource("reviewSubmissions", submissionID, include: "app")
        guard submission.related("app") == AssetLibraryResourceID(type: "apps", id: change.appID), submission.state == "READY_FOR_REVIEW",
              let platform = submission.attributes?["platform"]?.stringValue,
              ["IOS", "MAC_OS", "TV_OS", "VISION_OS"].contains(platform) else {
            throw AssetLibraryError("Asset review requires this app's editable submission with an explicit supported platform")
        }
        guard uses.allSatisfy({ !["PARENT_WAITING_FOR_REVIEW", "PARENT_IN_REVIEW"].contains($0.state ?? "") }) else {
            throw AssetLibraryError("Asset already participates in active parent review")
        }
        if kind == .video {
            guard asset.posterFrameState == "COMPLETE" else { throw AssetLibraryError("Video poster frame must finish processing before review") }
        }
        guard let specID = asset.attributes?["specId"]?.stringValue, let category = asset.attributes?["category"]?.stringValue else { throw AssetLibraryError("Asset review requires a processed specification and category") }
        let groups = (catalog.attributes?["placementTypes"]?.arrayValue ?? []).flatMap { value -> [String] in
            guard let type = value.objectValue, AssetMediaInspector.strings(type["acceptsAssetCategories"]).contains(category) else { return [] }
            return (type["specMappings"]?.arrayValue ?? []).compactMap { mapping in
                guard let object = mapping.objectValue, AssetMediaInspector.strings(object["specs"]).contains(specID) else { return nil }
                return object["placementGroupId"]?.stringValue
            }
        }
        guard groups.contains(where: { (try? validatePlatform(catalog, group: $0, platforms: platform)) != nil }) else {
            throw AssetLibraryError("Asset specification is not compatible with this review submission's platform")
        }
        let versions = try await all("/v1/apps/\(try ASCPathSegment.encode(change.appID))/appStoreVersions", query: ["filter[platform]": platform], type: "appStoreVersions")
        guard versions.contains(where: {
            $0.attributes?["appVersionState"]?.stringValue == "READY_FOR_DISTRIBUTION" ||
                ["READY_FOR_SALE", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION"].contains($0.attributes?["appStoreState"]?.stringValue ?? "")
        }) else { throw AssetLibraryError("Standalone asset review requires an already approved version on the selected platform") }
        let submissions = try await all("/v1/reviewSubmissions", query: ["filter[app]": change.appID], type: "reviewSubmissions")
        let relation = kind == .image ? "appAssetLibraryImage" : "appAssetLibraryVideo"
        var fingerprint: [String: String] = ["review_submission": try submission.fingerprint(), "review_platform": platform]
        fingerprint["approved_versions"] = try AssetLibraryJSON.fingerprint(try versions.sorted { $0.id < $1.id }.map { try $0.fingerprint() })
        for candidate in submissions where candidate.state != "COMPLETE" {
            guard let state = candidate.state, ASCReviewSubmissionState(rawValue: state) != nil else { throw AssetLibraryError("Unknown submission state prevents safe asset review preparation") }
            let items = try await reviewItems(candidate.id)
            guard !items.contains(where: { $0.related(relation) == AssetLibraryResourceID(type: kind.resourceType, id: assetID) && $0.state != "REMOVED" }) else {
                throw AssetLibraryError("Asset is already attached to an active review submission")
            }
            fingerprint["review_items:" + candidate.id] = try AssetLibraryJSON.fingerprint(try items.sorted { $0.id < $1.id }.map { try $0.fingerprint() })
        }
        return fingerprint
    }

    func reviewItems(_ submissionID: String) async throws -> [AssetLibraryResource] {
        try await all("/v1/reviewSubmissions/\(try ASCPathSegment.encode(try AssetLibraryJSON.identifier(submissionID, field: "submission_id")))/items",
                      query: ["include": "appAssetLibraryImage,appAssetLibraryVideo"], type: "reviewSubmissionItems")
    }
}
