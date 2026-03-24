import Foundation
import MCP

// MARK: - Tool Definitions
extension ReviewAttachmentsWorker {

    func uploadAttachmentTool() -> Tool {
        return Tool(
            name: "review_attachments_upload",
            description: "Upload a review attachment (full cycle: reserve, upload, commit). Attaches a file to an app store review detail for the review team.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_detail_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store review detail ID")
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the image file on disk")
                    ])
                ]),
                "required": .array([.string("review_detail_id"), .string("file_path")])
            ])
        )
    }

    func getAttachmentTool() -> Tool {
        return Tool(
            name: "review_attachments_get",
            description: "Get details of a specific review attachment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "attachment_id": .object([
                        "type": .string("string"),
                        "description": .string("Review attachment ID")
                    ])
                ]),
                "required": .array([.string("attachment_id")])
            ])
        )
    }

    func deleteAttachmentTool() -> Tool {
        return Tool(
            name: "review_attachments_delete",
            description: "Delete a review attachment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "attachment_id": .object([
                        "type": .string("string"),
                        "description": .string("Review attachment ID to delete")
                    ])
                ]),
                "required": .array([.string("attachment_id")])
            ])
        )
    }

    func listAttachmentsTool() -> Tool {
        return Tool(
            name: "review_attachments_list",
            description: "List review attachments for a review detail",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_detail_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store review detail ID")
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
                "required": .array([.string("review_detail_id")])
            ])
        )
    }
}
