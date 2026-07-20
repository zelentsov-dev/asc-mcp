import Foundation
import MCP

extension ReviewSubmissionsWorker {
    func listSubmissionsTool() -> Tool {
        Tool(
            name: "review_submissions_list",
            description: "List App Store review submissions for one app with state/platform filters and resumable item, app, version, and actor context",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "app_id": idSchema("App ID; Apple requires this ownership filter"),
                    "states": stringListSchema(
                        description: "Submission states as one value, CSV, or a unique array",
                        values: ASCReviewSubmissionState.allCases.map(\.rawValue)
                    ),
                    "platforms": stringListSchema(
                        description: "Platforms as one value, CSV, or a unique array",
                        values: ASCReviewSubmissionPlatform.allCases.map(\.rawValue)
                    ),
                    "include": stringListSchema(
                        description: "Apple relationships to include for recovery inspection",
                        values: Self.submissionIncludes
                    ),
                    "item_limit": integerSchema(
                        description: "Maximum included review items (default: 50, max: 50)",
                        maximum: 50,
                        defaultValue: 50
                    ),
                    "limit": integerSchema(
                        description: "Maximum submissions per page (default: 25, max: 200)",
                        maximum: 200,
                        defaultValue: 25
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "format": .string("uri-reference"),
                        "minLength": .int(1),
                        "description": .string("Exact next_url returned by this tool. Repeat app_id and every originating query control: states, platforms, include, item_limit, and the effective or default limit; the exact query and a non-empty cursor are validated")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func getSubmissionTool() -> Tool {
        Tool(
            name: "review_submissions_get",
            description: "Inspect one App Store review submission with its items, owning app, version, and actor context for recovery",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "submission_id": idSchema("Review submission ID"),
                    "include": stringListSchema(
                        description: "Apple relationships to include for recovery inspection",
                        values: Self.submissionIncludes
                    ),
                    "item_limit": integerSchema(
                        description: "Maximum included review items (default: 50, max: 50)",
                        maximum: 50,
                        defaultValue: 50
                    )
                ]),
                "required": .array([.string("submission_id")])
            ])
        )
    }

    func createSubmissionTool() -> Tool {
        Tool(
            name: "review_submissions_create",
            description: "Create an empty App Store review submission that can be inspected and populated before submission",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "app_id": idSchema("Owning App ID"),
                    "platform": nullableEnumSchema(
                        description: "Optional submission platform; null is distinct from omission",
                        values: ASCReviewSubmissionPlatform.allCases.map(\.rawValue)
                    )
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func listItemsTool() -> Tool {
        Tool(
            name: "review_submissions_list_items",
            description: "List every item in a review submission with typed resource IDs, including scoped relationships this worker cannot add, for resume and repair workflows",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "submission_id": idSchema("Review submission ID"),
                    "limit": integerSchema(
                        description: "Maximum review items per page (default: 25, max: 200)",
                        maximum: 200,
                        defaultValue: 25
                    ),
                    "next_url": .object([
                        "type": .string("string"),
                        "format": .string("uri-reference"),
                        "minLength": .int(1),
                        "description": .string("Exact next_url returned by this tool. Repeat the same submission_id and effective or default limit; the parent path, exact fixed query, and a non-empty cursor are validated")
                    ])
                ]),
                "required": .array([.string("submission_id")])
            ])
        )
    }

    func addItemTool() -> Tool {
        Tool(
            name: "review_submissions_add_item",
            description: "Add exactly one supported typed resource version to an App Store review submission; Game Center content is outside this worker",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "minProperties": .int(2),
                "maxProperties": .int(2),
                "properties": .object([
                    "submission_id": idSchema("Review submission ID"),
                    "app_store_version_id": idSchema("App Store version ID"),
                    "app_custom_product_page_version_id": idSchema("Custom product page version ID"),
                    "app_store_version_experiment_v2_id": idSchema("Product page optimization V2 experiment ID"),
                    "app_event_id": idSchema("In-app event ID"),
                    "background_asset_version_id": idSchema("Background asset version ID"),
                    "in_app_purchase_version_id": idSchema("In-app purchase version ID"),
                    "subscription_version_id": idSchema("Subscription version ID"),
                    "subscription_group_version_id": idSchema("Subscription group version ID")
                ]),
                "required": .array([.string("submission_id")])
            ])
        )
    }

    func updateItemTool() -> Tool {
        Tool(
            name: "review_submissions_update_item",
            description: "Update an unresolved or removed review item with its parent submission ID for deterministic full-pagination recovery inspection",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "minProperties": .int(3),
                "properties": .object([
                    "submission_id": idSchema("Parent review submission ID used for postflight and recovery inspection"),
                    "item_id": idSchema("Review submission item ID"),
                    "resolved": nullableBoolSchema("Mark an issue resolved, unresolved, or clear the value with null"),
                    "removed": nullableBoolSchema("Mark the item removed, retained, or clear the value with null")
                ]),
                "required": .array([.string("submission_id"), .string("item_id")])
            ])
        )
    }

    func removeItemTool() -> Tool {
        Tool(
            name: "review_submissions_remove_item",
            description: "Delete a review submission item after exact item-ID confirmation, retaining its parent submission ID for strict full-pagination recovery inspection",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "submission_id": idSchema("Parent review submission ID used for recovery inspection"),
                    "item_id": idSchema("Review submission item ID to delete"),
                    "confirm_item_id": idSchema("Exact item_id confirmation required for this destructive operation")
                ]),
                "required": .array([
                    .string("submission_id"),
                    .string("item_id"),
                    .string("confirm_item_id")
                ])
            ])
        )
    }

    func submitTool() -> Tool {
        Tool(
            name: "review_submissions_submit",
            description: "Submit an assembled App Store review submission by setting Apple's submitted flag to true",
            inputSchema: requiredIDSchema(
                field: "submission_id",
                description: "Review submission ID to submit"
            )
        )
    }

    func cancelTool() -> Tool {
        Tool(
            name: "review_submissions_cancel",
            description: "Cancel an App Store review submission by setting Apple's canceled flag to true",
            inputSchema: requiredIDSchema(
                field: "submission_id",
                description: "Review submission ID to cancel"
            )
        )
    }

    private func idSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string("\(description); canonical App Store Connect resource ID")
        ])
    }

    private func integerSchema(
        description: String,
        maximum: Int,
        defaultValue: Int
    ) -> Value {
        .object([
            "type": .string("integer"),
            "minimum": .int(1),
            "maximum": .int(maximum),
            "default": .int(defaultValue),
            "description": .string(description)
        ])
    }

    private func stringListSchema(description: String, values: [String]) -> Value {
        .object([
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "minLength": .int(1)
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ]),
            "description": .string(description)
        ])
    }

    private func nullableEnumSchema(description: String, values: [String]) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "enum": .array(values.map(Value.string) + [.null]),
            "description": .string(description)
        ])
    }

    private func nullableBoolSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func requiredIDSchema(field: String, description: String) -> Value {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                field: idSchema(description)
            ]),
            "required": .array([.string(field)])
        ])
    }
}
