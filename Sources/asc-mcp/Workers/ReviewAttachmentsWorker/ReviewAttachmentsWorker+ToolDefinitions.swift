import Foundation
import MCP

// MARK: - Tool Definitions
extension ReviewAttachmentsWorker {

    func uploadAttachmentTool() -> Tool {
        return Tool(
            name: "review_attachments_upload",
            description: "Upload a review attachment through exact HTTP 201 reservation, immutable snapshot binding, transfer, exact HTTP 200 commit, and delivery reconciliation. Automatic rollback is limited to failures before commit. A confirmed commit can return success with deliveryPending=true while Apple continues processing. An ambiguous reservation is never auto-matched from non-unique file hints and requires manual inspection before retry; uncertain or terminal failures retain the attachment and provide exact get/delete guidance.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "review_detail_id": .object([
                        "type": .string("string"),
                        "description": .string("Canonical App Store review detail ID"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the attachment file on disk"),
                        "minLength": .int(1),
                        "pattern": .string(#"^/"#)
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
                "additionalProperties": .bool(false),
                "properties": .object([
                    "attachment_id": .object([
                        "type": .string("string"),
                        "description": .string("Canonical review attachment ID"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ])
                ]),
                "required": .array([.string("attachment_id")])
            ])
        )
    }

    func deleteAttachmentTool() -> Tool {
        return Tool(
            name: "review_attachments_delete",
            description: "Delete a review attachment only after an exact attachment-ID confirmation. Apple must return exactly HTTP 204; ambiguous or unexpected successful outcomes require inspection before another delete attempt.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "attachment_id": .object([
                        "type": .string("string"),
                        "description": .string("Canonical review attachment ID to delete"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ]),
                    "confirm_attachment_id": .object([
                        "type": .string("string"),
                        "description": .string("Must exactly match attachment_id"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ])
                ]),
                "required": .array([
                    .string("attachment_id"),
                    .string("confirm_attachment_id")
                ])
            ])
        )
    }

    func listAttachmentsTool() -> Tool {
        return Tool(
            name: "review_attachments_list",
            description: "List review attachments for a review detail",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "review_detail_id": .object([
                        "type": .string("string"),
                        "description": .string("Canonical App Store review detail ID"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "format": .string("uri-reference"),
                        "minLength": .int(1),
                        "pattern": .string(#"^\S(?:.*\S)?$"#),
                        "description": .string("Apple continuation URL from the previous response. When the first page used a non-default limit, pass the same limit again with next_url; the full query and cursor are validated.")
                    ])
                ]),
                "required": .array([.string("review_detail_id")])
            ])
        )
    }
}
