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

    func createScreenshotTool() -> Tool {
        return Tool(
            name: "screenshots_create",
            description: "Reserve a screenshot upload in a screenshot set. Returns upload operations with URLs for uploading the image file.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot set ID")
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string("Screenshot file name (e.g. screenshot_1.png)")
                    ]),
                    "file_size": .object([
                        "type": .string("integer"),
                        "description": .string("File size in bytes")
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_name"), .string("file_size")])
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

    func createPreviewTool() -> Tool {
        return Tool(
            name: "screenshots_create_preview",
            description: "Reserve an app preview upload in a preview set. Returns upload operations with URLs for uploading the video file.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "set_id": .object([
                        "type": .string("string"),
                        "description": .string("Preview set ID")
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string("Preview file name (e.g. preview.mp4)")
                    ]),
                    "file_size": .object([
                        "type": .string("integer"),
                        "description": .string("File size in bytes")
                    ]),
                    "mime_type": .object([
                        "type": .string("string"),
                        "description": .string("MIME type (e.g. video/mp4, video/quicktime)")
                    ])
                ]),
                "required": .array([.string("set_id"), .string("file_name"), .string("file_size"), .string("mime_type")])
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
