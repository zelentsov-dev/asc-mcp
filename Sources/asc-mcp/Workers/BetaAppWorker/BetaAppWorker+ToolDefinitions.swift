import Foundation
import MCP

// MARK: - Tool Definitions
extension BetaAppWorker {

    // MARK: - Beta App Localizations

    func listLocalizationsTool() -> Tool {
        return Tool(
            name: "beta_app_list_localizations",
            description: "List beta app localizations for an app (TestFlight description, feedback email, marketing URL per locale)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func createLocalizationTool() -> Tool {
        return Tool(
            name: "beta_app_create_localization",
            description: "Create a beta app localization for an app (TestFlight metadata for a specific locale)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("App ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Locale code (e.g. en-US, de-DE)")
                    ]),
                    "feedback_email": .object([
                        "type": .string("string"),
                        "description": .string("Feedback email address for testers")
                    ]),
                    "marketing_url": .object([
                        "type": .string("string"),
                        "description": .string("Marketing URL")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy URL")
                    ]),
                    "tv_os_privacy_policy": .object([
                        "type": .string("string"),
                        "description": .string("tvOS privacy policy text")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("TestFlight app description shown to testers")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("locale")])
            ])
        )
    }

    func getLocalizationTool() -> Tool {
        return Tool(
            name: "beta_app_get_localization",
            description: "Get a specific beta app localization by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Beta app localization ID")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func updateLocalizationTool() -> Tool {
        return Tool(
            name: "beta_app_update_localization",
            description: "Update a beta app localization (TestFlight metadata for a locale)",
            inputSchema: .object([
                "type": .string("object"),
                "minProperties": .int(2),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Beta app localization ID")
                    ]),
                    "feedback_email": .object([
                        "type": .string("string"),
                        "description": .string("Feedback email address for testers")
                    ]),
                    "marketing_url": .object([
                        "type": .string("string"),
                        "description": .string("Marketing URL")
                    ]),
                    "privacy_policy_url": .object([
                        "type": .string("string"),
                        "description": .string("Privacy policy URL")
                    ]),
                    "tv_os_privacy_policy": .object([
                        "type": .string("string"),
                        "description": .string("tvOS privacy policy text")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("TestFlight app description shown to testers")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func deleteLocalizationTool() -> Tool {
        return Tool(
            name: "beta_app_delete_localization",
            description: "Delete a beta app localization",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Beta app localization ID to delete")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    // MARK: - Beta App Review Submissions

    func submitForReviewTool() -> Tool {
        return Tool(
            name: "beta_app_submit_for_review",
            description: "Submit a build for external beta (TestFlight) review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Build ID to submit for beta review")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }

    func listSubmissionsTool() -> Tool {
        return Tool(
            name: "beta_app_list_submissions",
            description: "List beta app review submissions for one or more builds, with optional review-state filtering and included Build status",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "oneOf": .array([
                            .object(["type": .string("string"), "minLength": .int(1)]),
                            .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string"), "minLength": .int(1)]),
                                "minItems": .int(1),
                                "uniqueItems": .bool(true)
                            ])
                        ]),
                        "description": .string("One or more build IDs required by Apple")
                    ]),
                    "review_state": .object([
                        "oneOf": .array([
                            .object([
                                "type": .string("string"),
                                "enum": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW"), .string("REJECTED"), .string("APPROVED")])
                            ]),
                            .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("string"),
                                    "enum": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW"), .string("REJECTED"), .string("APPROVED")])
                                ]),
                                "minItems": .int(1),
                                "uniqueItems": .bool(true)
                            ])
                        ]),
                        "description": .string("Filter by review state"),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }

    func getSubmissionTool() -> Tool {
        return Tool(
            name: "beta_app_get_submission",
            description: "Get a specific beta app review submission by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "submission_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta app review submission ID")
                    ])
                ]),
                "required": .array([.string("submission_id")])
            ])
        )
    }

    // MARK: - Beta App Review Details

    func getReviewDetailsTool() -> Tool {
        return Tool(
            name: "beta_app_get_review_details",
            description: "Get beta app review details for an app (demo account info, contact details for beta review)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func updateReviewDetailsTool() -> Tool {
        return Tool(
            name: "beta_app_update_review_details",
            description: "Update beta app review details (demo account, contact info for beta review)",
            inputSchema: .object([
                "type": .string("object"),
                "minProperties": .int(2),
                "properties": .object([
                    "review_detail_id": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Beta app review detail ID")
                    ]),
                    "contact_first_name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Contact first name")
                    ]),
                    "contact_last_name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Contact last name")
                    ]),
                    "contact_phone": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Contact phone number")
                    ]),
                    "contact_email": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Contact email address")
                    ]),
                    "demo_account_name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Demo account username")
                    ]),
                    "demo_account_password": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Demo account password")
                    ]),
                    "demo_account_required": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether a demo account is required for review")
                    ]),
                    "notes": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Additional notes for the reviewer")
                    ])
                ]),
                "required": .array([.string("review_detail_id")])
            ])
        )
    }
}
