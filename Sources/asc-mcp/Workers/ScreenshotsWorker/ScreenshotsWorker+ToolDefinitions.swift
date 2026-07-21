import Foundation
import MCP

// MARK: - Tool Definitions
extension ScreenshotsWorker {

    func listScreenshotSetsTool() -> Tool {
        return Tool(
            name: "screenshots_list_sets",
            description: "List screenshot sets for exactly one App Store version, custom product page, or PPO treatment localization.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "localization_id": canonicalIdentifierSchema("Legacy alias for app_store_version_localization_id"),
                    "app_store_version_localization_id": canonicalIdentifierSchema("App Store version localization ID"),
                    "custom_product_page_localization_id": canonicalIdentifierSchema("Custom product page localization ID"),
                    "treatment_localization_id": canonicalIdentifierSchema("Product page optimization treatment localization ID"),
                    "display_types": stringArraySchema(
                        description: "Screenshot display types to include",
                        allowedValues: Self.screenshotDisplayTypes
                    ),
                    "app_store_version_localization_ids": stringArraySchema(
                        description: "App Store version localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "custom_product_page_localization_ids": stringArraySchema(
                        description: "Custom product page localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "treatment_localization_ids": stringArraySchema(
                        description: "Product page optimization treatment localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": nextURLSchema()
                ]),
                "oneOf": localizationParentSchemas()
            ])
        )
    }

    func getScreenshotSetTool() -> Tool {
        Tool(
            name: "screenshots_get_set",
            description: "Get one screenshot set by its exact App Store Connect ID.",
            inputSchema: identifierOnlySchema(
                field: "set_id",
                description: "Screenshot set ID"
            )
        )
    }

    func createScreenshotSetTool() -> Tool {
        return Tool(
            name: "screenshots_create_set",
            description: "Create a screenshot set for exactly one App Store, custom product page, or PPO treatment localization. Display types: APP_IPHONE_67, APP_IPAD_PRO_3GEN_129, APP_DESKTOP, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "minProperties": .int(2),
                "maxProperties": .int(2),
                "properties": .object([
                    "localization_id": canonicalIdentifierSchema("Legacy alias for app_store_version_localization_id"),
                    "app_store_version_localization_id": canonicalIdentifierSchema("App Store version localization ID"),
                    "custom_product_page_localization_id": canonicalIdentifierSchema("Custom product page localization ID"),
                    "treatment_localization_id": canonicalIdentifierSchema("Product page optimization treatment localization ID"),
                    "display_type": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot display type (e.g. APP_IPHONE_67, APP_IPAD_PRO_3GEN_129, APP_DESKTOP)"),
                        "enum": .array(Self.screenshotDisplayTypes.map(Value.string))
                    ])
                ]),
                "required": .array([.string("display_type")]),
                "oneOf": localizationParentSchemas()
            ])
        )
    }

    func deleteScreenshotSetTool() -> Tool {
        return Tool(
            name: "screenshots_delete_set",
            description: "Delete a screenshot set and all its screenshots after exact ID confirmation.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Screenshot set ID to delete"),
                    "confirm_set_id": canonicalIdentifierSchema("Must exactly match set_id because deleting a set cascades to all screenshots")
                ]),
                "required": .array([.string("set_id"), .string("confirm_set_id")])
            ])
        )
    }

    func listScreenshotsTool() -> Tool {
        return Tool(
            name: "screenshots_list",
            description: "List screenshots in a screenshot set. Returns file info, upload status, image asset details, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Screenshot set ID"),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": nextURLSchema()
                ]),
                "required": .array([.string("set_id")])
            ])
        )
    }

    func uploadScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_upload",
            description: "Upload a screenshot from an immutable snapshot, then reserve, transfer, commit, and verify Apple processing. Pre-commit failures roll back the reservation; uncertain commits are retained and reconciled. A confirmed commit can return success with deliveryPending=true while Apple continues asynchronous processing; inspect that resource instead of retrying.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Screenshot set ID"),
                    "file_path": absoluteFilePathSchema("Absolute path to the screenshot file on disk (e.g. /path/to/screenshot.png)")
                ]),
                "required": .array([.string("set_id"), .string("file_path")])
            ])
        )
    }

    func getScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_get",
            description: "Get details of a specific screenshot. Returns file info, image asset, delivery state, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: identifierOnlySchema(field: "screenshot_id", description: "Screenshot ID")
        )
    }

    func deleteScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_delete",
            description: "Delete a screenshot from a screenshot set",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "screenshot_id": canonicalIdentifierSchema("Screenshot ID to delete"),
                    "confirm_screenshot_id": canonicalIdentifierSchema("Must exactly match screenshot_id to confirm deletion")
                ]),
                "required": .array([.string("screenshot_id"), .string("confirm_screenshot_id")])
            ])
        )
    }

    func reorderScreenshotsTool() -> Tool {
        return Tool(
            name: "screenshots_reorder",
            description: "Replace the screenshot-set relationship order after verifying the array is the complete current membership.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Screenshot set ID"),
                    "screenshot_ids": .object([
                        "type": .string("array"),
                        "minItems": .int(1),
                        "maxItems": .int(Self.maximumReorderCount),
                        "uniqueItems": .bool(true),
                        "description": .string("Complete ordered array of screenshot IDs currently in the set"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1),
                            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                        ])
                    ])
                ]),
                "required": .array([.string("set_id"), .string("screenshot_ids")])
            ])
        )
    }

    func listPreviewSetsTool() -> Tool {
        return Tool(
            name: "screenshots_list_preview_sets",
            description: "List app preview sets for exactly one App Store version, custom product page, or PPO treatment localization.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "localization_id": canonicalIdentifierSchema("Legacy alias for app_store_version_localization_id"),
                    "app_store_version_localization_id": canonicalIdentifierSchema("App Store version localization ID"),
                    "custom_product_page_localization_id": canonicalIdentifierSchema("Custom product page localization ID"),
                    "treatment_localization_id": canonicalIdentifierSchema("Product page optimization treatment localization ID"),
                    "preview_types": stringArraySchema(
                        description: "App preview display types to include",
                        allowedValues: Self.previewTypes
                    ),
                    "app_store_version_localization_ids": stringArraySchema(
                        description: "App Store version localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "custom_product_page_localization_ids": stringArraySchema(
                        description: "Custom product page localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "treatment_localization_ids": stringArraySchema(
                        description: "Product page optimization treatment localization IDs to match when the selected parent supports this filter",
                        canonicalIdentifiers: true
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": nextURLSchema()
                ]),
                "oneOf": localizationParentSchemas()
            ])
        )
    }

    func getPreviewSetTool() -> Tool {
        Tool(
            name: "screenshots_get_preview_set",
            description: "Get one app preview set by its exact App Store Connect ID.",
            inputSchema: identifierOnlySchema(
                field: "set_id",
                description: "App preview set ID"
            )
        )
    }

    func createPreviewSetTool() -> Tool {
        return Tool(
            name: "screenshots_create_preview_set",
            description: "Create an app preview set for exactly one App Store, custom product page, or PPO treatment localization. Preview types: IPHONE_67, IPAD_PRO_3GEN_129, DESKTOP, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "minProperties": .int(2),
                "maxProperties": .int(2),
                "properties": .object([
                    "localization_id": canonicalIdentifierSchema("Legacy alias for app_store_version_localization_id"),
                    "app_store_version_localization_id": canonicalIdentifierSchema("App Store version localization ID"),
                    "custom_product_page_localization_id": canonicalIdentifierSchema("Custom product page localization ID"),
                    "treatment_localization_id": canonicalIdentifierSchema("Product page optimization treatment localization ID"),
                    "preview_type": .object([
                        "type": .string("string"),
                        "description": .string("Preview type (e.g. IPHONE_67, IPAD_PRO_3GEN_129, DESKTOP)"),
                        "enum": .array(Self.previewTypes.map(Value.string))
                    ])
                ]),
                "required": .array([.string("preview_type")]),
                "oneOf": localizationParentSchemas()
            ])
        )
    }

    func deletePreviewSetTool() -> Tool {
        return Tool(
            name: "screenshots_delete_preview_set",
            description: "Delete an app preview set and all its previews after exact ID confirmation.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Preview set ID to delete"),
                    "confirm_set_id": canonicalIdentifierSchema("Must exactly match set_id because deleting a set cascades to all previews")
                ]),
                "required": .array([.string("set_id"), .string("confirm_set_id")])
            ])
        )
    }

    func uploadPreviewTool() -> Tool {
        return Tool(
            name: "screenshots_upload_preview",
            description: "Upload an app preview from an immutable snapshot, then reserve, transfer, commit, and verify Apple video processing. Pre-commit failures roll back the reservation; uncertain commits are retained for reconciliation. A confirmed commit can return success with deliveryPending=true while Apple continues asynchronous processing; inspect that preview instead of retrying.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Preview set ID"),
                    "file_path": absoluteFilePathSchema("Absolute path to the preview file on disk (e.g. /path/to/preview.mp4)"),
                    "mime_type": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "minLength": .int(1),
                        "pattern": .string(#"^\S(?:.*\S)?$"#),
                        "description": .string("MIME type (default: video/mp4); pass null to let Apple infer it")
                    ]),
                    "preview_frame_time_code": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "minLength": .int(1),
                        "pattern": .string(#"^\S(?:.*\S)?$"#),
                        "description": .string("Timestamp Apple uses for the app preview poster frame; pass null to clear it")
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_path")])
            ])
        )
    }

    func getPreviewTool() -> Tool {
        return Tool(
            name: "screenshots_get_preview",
            description: "Get details of a specific app preview. Returns file info, video and preview image metadata, delivery state, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: identifierOnlySchema(field: "preview_id", description: "Preview ID")
        )
    }

    func listPreviewsTool() -> Tool {
        return Tool(
            name: "screenshots_list_previews",
            description: "List app previews in a preview set. Returns file info, upload status, video details, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Preview set ID"),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": nextURLSchema()
                ]),
                "required": .array([.string("set_id")])
            ])
        )
    }

    func uploadScreenshotBatchTool() -> Tool {
        return Tool(
            name: "screenshots_upload_batch",
            description: "Upload multiple screenshots sequentially. Each file uses its own immutable snapshot, reservation rollback, commit reconciliation, and processing verification. Confirmed processing-pending commits count as uploaded and include inspect guidance; each file has an independent result.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Screenshot set ID"),
                    "file_paths": .object([
                        "type": .string("array"),
                        "description": .string("Array of absolute paths to screenshot files on disk"),
                        "minItems": .int(1),
                        "maxItems": .int(Self.maximumBatchUploadCount),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1),
                            "pattern": .string(#"^/(?:.*\S)?$"#)
                        ])
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_paths")])
            ])
        )
    }

    func deletePreviewTool() -> Tool {
        return Tool(
            name: "screenshots_delete_preview",
            description: "Delete an app preview from a preview set",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "preview_id": canonicalIdentifierSchema("Preview ID to delete"),
                    "confirm_preview_id": canonicalIdentifierSchema("Must exactly match preview_id to confirm deletion")
                ]),
                "required": .array([.string("preview_id"), .string("confirm_preview_id")])
            ])
        )
    }

    func reorderPreviewsTool() -> Tool {
        Tool(
            name: "screenshots_reorder_previews",
            description: "Replace the preview-set relationship order after verifying the array is the complete current membership.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "set_id": canonicalIdentifierSchema("Preview set ID"),
                    "preview_ids": .object([
                        "type": .string("array"),
                        "minItems": .int(1),
                        "maxItems": .int(Self.maximumReorderCount),
                        "uniqueItems": .bool(true),
                        "description": .string("Complete ordered array of preview IDs currently in the set"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1),
                            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                        ])
                    ])
                ]),
                "required": .array([.string("set_id"), .string("preview_ids")])
            ])
        )
    }

    private func localizationParentSchemas() -> Value {
        .array([
            .object(["required": .array([.string("localization_id")])]),
            .object(["required": .array([.string("app_store_version_localization_id")])]),
            .object(["required": .array([.string("custom_product_page_localization_id")])]),
            .object(["required": .array([.string("treatment_localization_id")])])
        ])
    }

    private func stringArraySchema(
        description: String,
        allowedValues: [String]? = nil,
        canonicalIdentifiers: Bool = false
    ) -> Value {
        var items: [String: Value] = [
            "type": .string("string"),
            "minLength": .int(1)
        ]
        if let allowedValues {
            items["enum"] = .array(allowedValues.map(Value.string))
        }
        if canonicalIdentifiers {
            items["pattern"] = .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        }
        return .object([
            "type": .string("array"),
            "description": .string(description),
            "minItems": .int(1),
            "uniqueItems": .bool(true),
            "items": .object(items)
        ])
    }

    private func identifierOnlySchema(field: String, description: String) -> Value {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                field: canonicalIdentifierSchema(description)
            ]),
            "required": .array([.string(field)])
        ])
    }

    private func canonicalIdentifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string(description)
        ])
    }

    private func nextURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "pattern": .string(#"^\S(?:.*\S)?$"#),
            "description": .string("Pagination URL from the previous response; configured origin, exact path, originating query, and non-empty cursor are validated")
        ])
    }

    private func absoluteFilePathSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^/(?:.*\S)?$"#),
            "description": .string(description)
        ])
    }
}
