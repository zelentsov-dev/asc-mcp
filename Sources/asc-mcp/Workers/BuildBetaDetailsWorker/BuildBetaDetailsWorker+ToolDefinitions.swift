import Foundation
import MCP

// MARK: - Tool Definitions
extension BuildBetaDetailsWorker {
    
    func getBetaDetailTool() -> Tool {
        Tool(
            name: "builds_get_beta_detail",
            description: "Get TestFlight beta details for a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID in App Store Connect")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func updateBetaDetailTool() -> Tool {
        Tool(
            name: "builds_update_beta_detail",
            description: "Update TestFlight beta details for a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_detail_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta detail ID")
                    ]),
                    "auto_notify": .object([
                        "type": .string("boolean"),
                        "description": .string("Automatically notify testers")
                    ]),
                    "internal_build_state": .object([
                        "type": .string("string"),
                        "description": .string("Internal build state"),
                        "enum": .array([.string("PROCESSING"), .string("PROCESSING_EXCEPTION"), .string("MISSING_EXPORT_COMPLIANCE"), .string("READY_FOR_BETA_TESTING"), .string("IN_BETA_TESTING"), .string("EXPIRED"), .string("IN_EXPORT_COMPLIANCE_REVIEW")])
                    ]),
                    "external_build_state": .object([
                        "type": .string("string"),
                        "description": .string("External build state"),
                        "enum": .array([.string("PROCESSING"), .string("PROCESSING_EXCEPTION"), .string("MISSING_EXPORT_COMPLIANCE"), .string("READY_FOR_BETA_SUBMISSION"), .string("IN_BETA_REVIEW"), .string("BETA_APPROVED"), .string("BETA_REJECTED"), .string("IN_BETA_TESTING"), .string("EXPIRED"), .string("READY_FOR_BETA_TESTING"), .string("IN_EXPORT_COMPLIANCE_REVIEW")])
                    ])
                ]),
                "required": .array([.string("beta_detail_id")])
            ])
        )
    }
    
    func setBetaLocalizationTool() -> Tool {
        Tool(
            name: "builds_set_beta_localization",
            description: "Set TestFlight What's New text for a specific locale",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ]),
                    "whats_new": .object([
                        "type": .string("string"),
                        "description": .string("What's New text for TestFlight (max 4000 characters)")
                    ]),
                    "feedback_email": .object([
                        "type": .string("string"),
                        "description": .string("Feedback email for testers")
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
                    ])
                ]),
                "required": .array([.string("build_id"), .string("locale")])
            ])
        )
    }
    
    func listBetaLocalizationsTool() -> Tool {
        Tool(
            name: "builds_list_beta_localizations",
            description: "List all beta localizations for a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of localizations to return (1-200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func getBetaGroupsTool() -> Tool {
        Tool(
            name: "builds_get_beta_groups",
            description: "Get beta groups associated with a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID in App Store Connect")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of groups to return (1-200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func getBetaTestersTool() -> Tool {
        Tool(
            name: "builds_get_beta_testers",
            description: "Get beta testers who have access to a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID in App Store Connect")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of testers to return (1-200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func addToBetaGroupsTool() -> Tool {
        Tool(
            name: "builds_add_to_beta_groups",
            description: "Add a build to one or more TestFlight beta groups",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID in App Store Connect")
                    ]),
                    "group_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of beta group IDs to add the build to"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("build_id"), .string("group_ids")])
            ])
        )
    }

    func sendBetaNotificationTool() -> Tool {
        Tool(
            name: "builds_send_beta_notification",
            description: "Send TestFlight notification to all beta testers about a new build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID in App Store Connect")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
}