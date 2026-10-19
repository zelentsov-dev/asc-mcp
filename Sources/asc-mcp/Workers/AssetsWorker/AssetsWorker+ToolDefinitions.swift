import MCP

extension AssetsWorker {
    func toolDefinitions() -> [Tool] {
        let app = field("App Store Connect app ID; all resource ownership is checked against this app")
        let asset = field("Exact Asset Library asset ID; legacy screenshot IDs are not interchangeable")
        let kind = enumeration(["image", "video"], "Asset media kind")
        let target = enumeration(AssetLibraryTarget.allCases.map(\.rawValue), "Exactly one localization resource type")
        let targetID = field("Exact localization resource ID")
        let pagination: [String: Value] = [
            "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(200)]),
            "next_url": field("Continuation returned by this exact collection and query")
        ]
        var tools = [
            definition("assets_get_library", "Get an application's reusable Asset Library", ["app_id": app], ["app_id"]),
            definition("assets_get_reference_data", "Read Apple's dynamic feature, placement and file specifications", [
                "reference_id": field("Optional exact reference-data resource ID"),
                "features": strings("Feature filters"), "placement_types": strings("Placement type filters"),
                "placement_groups": strings("Placement profile group filters"), "spec_ids": strings("Specification filters")
            ], []),
            definition("assets_get_image", "Read an image and processing/review state after checking app ownership", ["app_id": app, "asset_id": asset], ["app_id", "asset_id"]),
            definition("assets_get_video", "Read a video and its independent poster-frame processing state", ["app_id": app, "asset_id": asset], ["app_id", "asset_id"]),
            definition("assets_get_placement", "Read a placement after checking its parent application's ownership", ["app_id": app, "placement_id": field("Exact placement ID")], ["app_id", "placement_id"])
        ]
        for suffix in ["images", "videos"] {
            tools.append(definition("assets_list_\(suffix)", "List \(suffix) in this application's Asset Library", pagination.merging([
                "app_id": app, "categories": strings("Category filters"), "states": strings("Apple state filters"),
                "reference_names": strings("Exact reference-name filters"), "spec_ids": strings("Specification filters"), "asset_ids": strings("Asset ID filters")
            ]) { _, new in new }, ["app_id"]))
        }
        tools.append(definition("assets_list_placements", "List placements for exactly one asset or localization; preserve the same selector on pagination", pagination.merging([
            "app_id": app, "asset_kind": kind, "asset_id": asset, "target_type": target, "target_id": targetID,
            "placement_types": strings("Placement type filters"), "placement_groups": strings("Placement group filters")
        ]) { _, new in new }, ["app_id"]))
        tools.append(definition("assets_prepare_change", "Prepare a concrete asset change without writing to Apple. Returns a single-use preview valid for ten minutes. Review effects in the MCP client before applying. Uploads snapshot regular local files, up to 2 GiB; publication and review submission are separate actions.", [
            "app_id": app, "action": enumeration(AssetLibraryAction.allCases.map(\.rawValue), "Typed action; unsupported combinations are rejected"),
            "asset_kind": kind, "asset_id": asset, "file_path": field("Absolute path to a regular image/video file; symlinks are rejected"),
            "resume_operation_id": field("For upload actions only: resume a journaled reservation using the identical file; category and reference identity must match the original preview"),
            "category": enumeration(["CREATIVE_ASSETS", "APP_SCREENSHOTS_AND_PREVIEWS"], "Immutable asset category"),
            "reference_name": .object(["type": .array([.string("string"), .string("null")]), "description": .string("Reference name; explicit null clears it for update_reference_name")]),
            "preview_frame_time_code": field("Video poster timestamp in Apple's time-code format"),
            "target_type": target, "target_id": targetID, "placement_type": field("Placement type from live reference data"),
            "placement_group": field("Placement group from live reference data"), "placement_id": field("Existing placement for replacement or deletion"),
            "ordered_placement_ids": strings("Complete ordered list for exactly one group and localization"),
            "submission_id": field("Editable review submission receiving the image/video item")
        ], ["app_id", "action"]))
        tools.append(definition("assets_apply_change", "Apply exactly one unexpired prepared change. Rechecks app/account scope and remote state. Never replay an uncertain result; inspect operation_id instead. This tool can upload, alter placements, archive or delete explicitly previewed resources.", ["preview_id": field("Opaque single-use preview ID from assets_prepare_change")], ["preview_id"], mutation: true))
        tools.append(definition("assets_get_operation", "Read the private operation journal and reconcile known remote resources without writing to Apple", ["operation_id": field("Operation ID returned before execution")], ["operation_id"]))
        return tools
    }

    private func definition(_ name: String, _ description: String, _ properties: [String: Value], _ required: [String], mutation: Bool = false) -> Tool {
        Tool(name: name, description: description, inputSchema: .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(Value.string)), "additionalProperties": .bool(false)
        ]), annotations: .init(readOnlyHint: !mutation, destructiveHint: mutation, idempotentHint: !mutation && name != "assets_prepare_change", openWorldHint: true))
    }

    private func field(_ description: String) -> Value {
        .object(["type": .string("string"), "minLength": .int(1), "description": .string(description)])
    }

    private func enumeration(_ values: [String], _ description: String) -> Value {
        .object(["type": .string("string"), "enum": .array(values.map(Value.string)), "description": .string(description)])
    }

    private func strings(_ description: String) -> Value {
        .object(["type": .string("array"), "items": field("Nonempty value"), "minItems": .int(1), "maxItems": .int(200), "uniqueItems": .bool(true), "description": .string(description)])
    }
}
