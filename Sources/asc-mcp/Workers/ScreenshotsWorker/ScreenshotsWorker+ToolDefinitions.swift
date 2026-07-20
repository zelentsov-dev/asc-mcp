import Foundation
import MCP

// MARK: - Tool Definitions
extension ScreenshotsWorker {

    func listScreenshotSetsTool() -> Tool {
        return Tool(
            name: "screenshots_list_sets",
            description: "List screenshot sets for a version localization. Returns display types available for the localization.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "display_types": stringArraySchema(
                        description: "Screenshot display types to include",
                        allowedValues: Self.screenshotDisplayTypes
                    ),
                    "custom_product_page_localization_ids": stringArraySchema(
                        description: "Custom product page localization IDs to match"
                    ),
                    "treatment_localization_ids": stringArraySchema(
                        description: "Product page optimization treatment localization IDs to match"
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func createScreenshotSetTool() -> Tool {
        return Tool(
            name: "screenshots_create_set",
            description: "Create a screenshot set for exactly one App Store, custom product page, or PPO treatment localization. Display types: APP_IPHONE_67, APP_IPAD_PRO_3GEN_129, APP_DESKTOP, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Legacy alias for app_store_version_localization_id")
                    ]),
                    "app_store_version_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "custom_product_page_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page localization ID")
                    ]),
                    "treatment_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Product page optimization treatment localization ID")
                    ]),
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
            description: "Delete a screenshot set and all its screenshots",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID to delete")
                    ])
                ]),
                "required": .array([.string("set_id")])
            ])
        )
    }

    func listScreenshotsTool() -> Tool {
        return Tool(
            name: "screenshots_list",
            description: "List screenshots in a screenshot set. Returns file info, upload status, image asset details, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
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
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the screenshot file on disk (e.g. /path/to/screenshot.png)")
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_path")])
            ])
        )
    }

    func getScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_get",
            description: "Get details of a specific screenshot. Returns file info, image asset, delivery state, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screenshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot ID")
                    ])
                ]),
                "required": .array([.string("screenshot_id")])
            ])
        )
    }

    func deleteScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_delete",
            description: "Delete a screenshot from a screenshot set",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "screenshot_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot ID to delete")
                    ])
                ]),
                "required": .array([.string("screenshot_id")])
            ])
        )
    }

    func reorderScreenshotsTool() -> Tool {
        return Tool(
            name: "screenshots_reorder",
            description: "Reorder screenshots within a screenshot set. Provide screenshot IDs in desired order.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID")
                    ]),
                    "screenshot_ids": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated screenshot IDs in desired order")
                    ])
                ]),
                "required": .array([.string("set_id"), .string("screenshot_ids")])
            ])
        )
    }

    func listPreviewSetsTool() -> Tool {
        return Tool(
            name: "screenshots_list_preview_sets",
            description: "List app preview sets for a version localization. Returns preview types available for the localization.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "preview_types": stringArraySchema(
                        description: "App preview display types to include",
                        allowedValues: Self.previewTypes
                    ),
                    "custom_product_page_localization_ids": stringArraySchema(
                        description: "Custom product page localization IDs to match"
                    ),
                    "treatment_localization_ids": stringArraySchema(
                        description: "Product page optimization treatment localization IDs to match"
                    ),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func createPreviewSetTool() -> Tool {
        return Tool(
            name: "screenshots_create_preview_set",
            description: "Create an app preview set for exactly one App Store, custom product page, or PPO treatment localization. Preview types: IPHONE_67, IPAD_PRO_3GEN_129, DESKTOP, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Legacy alias for app_store_version_localization_id")
                    ]),
                    "app_store_version_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "custom_product_page_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Custom product page localization ID")
                    ]),
                    "treatment_localization_id": .object([
                        "type": .string("string"),
                        "description": .string("Product page optimization treatment localization ID")
                    ]),
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
            description: "Delete an app preview set and all its previews",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview set ID to delete")
                    ])
                ]),
                "required": .array([.string("set_id")])
            ])
        )
    }

    func uploadPreviewTool() -> Tool {
        return Tool(
            name: "screenshots_upload_preview",
            description: "Upload an app preview from an immutable snapshot, then reserve, transfer, commit, and verify Apple video processing. Pre-commit failures roll back the reservation; uncertain commits are retained for reconciliation. A confirmed commit can return success with deliveryPending=true while Apple continues asynchronous processing; inspect that preview instead of retrying.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview set ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the preview file on disk (e.g. /path/to/preview.mp4)")
                    ]),
                    "mime_type": .object([
                        "type": .string("string"),
                        "description": .string("MIME type (default: video/mp4). Options: video/mp4, video/quicktime")
                    ]),
                    "preview_frame_time_code": .object([
                        "type": .string("string"),
                        "description": .string("Timestamp Apple uses for the app preview poster frame")
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
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "preview_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview ID")
                    ])
                ]),
                "required": .array([.string("preview_id")])
            ])
        )
    }

    func listPreviewsTool() -> Tool {
        return Tool(
            name: "screenshots_list_previews",
            description: "List app previews in a preview set. Returns file info, upload status, video details, and safe upload operation metadata. Signed upload URLs and request headers are omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview set ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
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
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID")
                    ]),
                    "file_paths": .object([
                        "type": .string("array"),
                        "description": .string("Array of absolute paths to screenshot files on disk"),
                        "items": .object([
                            "type": .string("string")
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
                "properties": .object([
                    "preview_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview ID to delete")
                    ])
                ]),
                "required": .array([.string("preview_id")])
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

    private func stringArraySchema(description: String, allowedValues: [String]? = nil) -> Value {
        var items: [String: Value] = ["type": .string("string")]
        if let allowedValues {
            items["enum"] = .array(allowedValues.map(Value.string))
        }
        return .object([
            "type": .string("array"),
            "description": .string(description),
            "minItems": .int(1),
            "uniqueItems": .bool(true),
            "items": .object(items)
        ])
    }
}
