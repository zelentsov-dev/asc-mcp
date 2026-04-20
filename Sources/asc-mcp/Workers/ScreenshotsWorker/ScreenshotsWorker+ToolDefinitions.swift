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
            description: "Create a screenshot set for a version localization. Display types: APP_IPHONE_67, APP_IPHONE_65, APP_IPHONE_61, APP_IPHONE_58, APP_IPHONE_55, APP_IPHONE_47, APP_IPHONE_40, APP_IPAD_PRO_3GEN_129, APP_IPAD_PRO_3GEN_11, APP_IPAD_PRO_129, APP_IPAD_105, APP_IPAD_97, APP_DESKTOP, APP_WATCH_ULTRA, APP_WATCH_SERIES_10, APP_WATCH_SERIES_7, APP_WATCH_SERIES_4, APP_WATCH_SERIES_3, APP_APPLE_TV, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "display_type": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot display type (e.g. APP_IPHONE_67, APP_IPAD_PRO_3GEN_129, APP_DESKTOP)")
                    ])
                ]),
                "required": .array([.string("localization_id"), .string("display_type")])
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
            description: "List screenshots in a screenshot set. Returns file info, upload status, and image asset details.",
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
            description: "Upload a screenshot to a screenshot set (full cycle: reserve, upload file, commit). Provide the local file path and the set ID.",
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
            description: "Get details of a specific screenshot. Returns fileName, fileSize, imageAsset, assetDeliveryState, etc.",
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
            description: "Create an app preview set for a version localization. Preview types: IPHONE_67, IPHONE_65, IPHONE_61, IPHONE_58, IPHONE_55, IPAD_PRO_3GEN_129, IPAD_PRO_3GEN_11, IPAD_PRO_129, IPAD_105, DESKTOP, etc.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version localization ID")
                    ]),
                    "preview_type": .object([
                        "type": .string("string"),
                        "description": .string("Preview type (e.g. IPHONE_67, IPAD_PRO_3GEN_129, DESKTOP)")
                    ])
                ]),
                "required": .array([.string("localization_id"), .string("preview_type")])
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
            description: "Upload an app preview to a preview set (full cycle: reserve, upload file, commit). Provide the local file path and the set ID.",
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
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_path")])
            ])
        )
    }

    func getPreviewTool() -> Tool {
        return Tool(
            name: "screenshots_get_preview",
            description: "Get details of a specific app preview. Returns fileName, fileSize, mimeType, videoUrl, previewImage, assetDeliveryState, etc.",
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
            description: "List app previews in a preview set. Returns file info, upload status, and video details.",
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
            description: "Upload multiple screenshots to a screenshot set in one call. Each file goes through the full upload cycle (reserve, upload, commit). Returns results for each file.",
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

    func updatePreviewTool() -> Tool {
        return Tool(
            name: "screenshots_update_preview",
            description: "Update the preview frame timecode of an app preview. Use this after uploading a preview to set the thumbnail frame (e.g. '00:00:02:00' for the 2-second frame).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "preview_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview ID to update")
                    ]),
                    "preview_frame_timecode": .object([
                        "type": .string("string"),
                        "description": .string("Timecode for the thumbnail frame in HH:MM:SS:FF format, e.g. '00:00:02:00'")
                    ])
                ]),
                "required": .array([.string("preview_id"), .string("preview_frame_timecode")])
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
}
