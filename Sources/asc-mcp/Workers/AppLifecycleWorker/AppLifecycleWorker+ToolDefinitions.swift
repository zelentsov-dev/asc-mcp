import Foundation
import MCP

// MARK: - Tool Definitions
extension AppLifecycleWorker {
    
    func createVersionTool() -> Tool {
        Tool(
            name: "app_versions_create",
            description: "Create a new app version for release",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID in App Store Connect")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform for the version"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "version_string": .object([
                        "type": .string("string"),
                        "description": .string("Version number (e.g., 1.2.0)")
                    ]),
                    "release_type": .object([
                        "type": .string("string"),
                        "description": .string("Release type after approval"),
                        "enum": .array([.string("MANUAL"), .string("AFTER_APPROVAL"), .string("SCHEDULED")])
                    ]),
                    "earliest_release_date": .object([
                        "type": .string("string"),
                        "description": .string("Earliest release date for SCHEDULED release (ISO 8601)")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("platform"), .string("version_string")])
            ])
        )
    }
    
    func listVersionsTool() -> Tool {
        Tool(
            name: "app_versions_list",
            description: "List all versions for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID in App Store Connect")
                    ]),
                    "states": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("DEVELOPER_REMOVED_FROM_SALE"),
                                .string("DEVELOPER_REJECTED"),
                                .string("IN_REVIEW"),
                                .string("INVALID_BINARY"),
                                .string("METADATA_REJECTED"),
                                .string("PENDING_APPLE_RELEASE"),
                                .string("PENDING_CONTRACT"),
                                .string("PENDING_DEVELOPER_RELEASE"),
                                .string("PREPARE_FOR_SUBMISSION"),
                                .string("PREORDER_READY_FOR_SALE"),
                                .string("PROCESSING_FOR_APP_STORE"),
                                .string("READY_FOR_REVIEW"),
                                .string("READY_FOR_SALE"),
                                .string("REJECTED"),
                                .string("REMOVED_FROM_SALE"),
                                .string("WAITING_FOR_EXPORT_COMPLIANCE"),
                                .string("WAITING_FOR_REVIEW"),
                                .string("REPLACED_WITH_NEW_VERSION")
                            ])
                        ]),
                        "description": .string("Filter by version states")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by platform"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of versions to return (default: 25)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }
    
    func getVersionTool() -> Tool {
        Tool(
            name: "app_versions_get",
            description: "Get detailed information about a specific app version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID in App Store Connect")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func updateVersionTool() -> Tool {
        Tool(
            name: "app_versions_update",
            description: "Update app version attributes",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID in App Store Connect")
                    ]),
                    "release_type": .object([
                        "type": .string("string"),
                        "description": .string("Release type after approval"),
                        "enum": .array([.string("MANUAL"), .string("AFTER_APPROVAL"), .string("SCHEDULED")])
                    ]),
                    "earliest_release_date": .object([
                        "type": .string("string"),
                        "description": .string("Earliest release date for SCHEDULED release (ISO 8601)")
                    ]),
                    "copyright": .object([
                        "type": .string("string"),
                        "description": .string("Copyright text")
                    ]),
                    "version_string": .object([
                        "type": .string("string"),
                        "description": .string("Version number (can only be updated before submission)")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func attachBuildTool() -> Tool {
        Tool(
            name: "app_versions_attach_build",
            description: "Attach a build to an app version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID in App Store Connect")
                    ]),
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("Build ID to attach")
                    ])
                ]),
                "required": .array([.string("version_id"), .string("build_id")])
            ])
        )
    }
    
    func submitForReviewTool() -> Tool {
        Tool(
            name: "app_versions_submit_for_review",
            description: "Submit an app version for App Store review using Review Submissions API",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID to submit for review")
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID (optional, auto-resolved from version_id if not provided)")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform for submission (default: IOS)"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func cancelReviewTool() -> Tool {
        Tool(
            name: "app_versions_cancel_review",
            description: "Cancel an ongoing App Store review submission",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_submission_id": .object([
                        "type": .string("string"),
                        "description": .string("Review submission ID to cancel")
                    ])
                ]),
                "required": .array([.string("review_submission_id")])
            ])
        )
    }
    
    func createPhasedReleaseTool() -> Tool {
        Tool(
            name: "app_versions_create_phased_release",
            description: "Create a phased release for gradual rollout",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID for phased release")
                    ]),
                    "phased_release_state": .object([
                        "type": .string("string"),
                        "description": .string("Initial state of phased release"),
                        "enum": .array([.string("INACTIVE"), .string("ACTIVE"), .string("PAUSED")])
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func updatePhasedReleaseTool() -> Tool {
        Tool(
            name: "app_versions_update_phased_release",
            description: "Update phased release state (pause/resume/complete)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "phased_release_id": .object([
                        "type": .string("string"),
                        "description": .string("Phased release ID")
                    ]),
                    "phased_release_state": .object([
                        "type": .string("string"),
                        "description": .string("New state for phased release"),
                        "enum": .array([.string("ACTIVE"), .string("PAUSED"), .string("COMPLETE")])
                    ])
                ]),
                "required": .array([.string("phased_release_id"), .string("phased_release_state")])
            ])
        )
    }
    
    func releaseVersionTool() -> Tool {
        Tool(
            name: "app_versions_release",
            description: "Release an approved version to the App Store",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID to release")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func setReviewDetailsTool() -> Tool {
        Tool(
            name: "app_versions_set_review_details",
            description: "Set review details for App Store reviewers",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID")
                    ]),
                    "contact_first_name": .object([
                        "type": .string("string"),
                        "description": .string("Contact first name")
                    ]),
                    "contact_last_name": .object([
                        "type": .string("string"),
                        "description": .string("Contact last name")
                    ]),
                    "contact_phone": .object([
                        "type": .string("string"),
                        "description": .string("Contact phone number")
                    ]),
                    "contact_email": .object([
                        "type": .string("string"),
                        "description": .string("Contact email address")
                    ]),
                    "demo_account_name": .object([
                        "type": .string("string"),
                        "description": .string("Demo account username")
                    ]),
                    "demo_account_password": .object([
                        "type": .string("string"),
                        "description": .string("Demo account password")
                    ]),
                    "demo_account_required": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether demo account is required")
                    ]),
                    "notes": .object([
                        "type": .string("string"),
                        "description": .string("Additional notes for reviewers")
                    ]),
                    "attachment_file_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of uploaded attachment file")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func updateAgeRatingTool() -> Tool {
        Tool(
            name: "app_versions_update_age_rating",
            description: "Update age rating declaration for the app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID")
                    ]),
                    "alcohol_tobacco_or_drug_use": .object([
                        "type": .string("string"),
                        "description": .string("Alcohol, tobacco, or drug use references"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "contests": .object([
                        "type": .string("string"),
                        "description": .string("Contests"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "gambling": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app contains gambling (true/false)")
                    ]),
                    "gambling_simulated": .object([
                        "type": .string("string"),
                        "description": .string("Simulated gambling intensity level"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "unrestricted_web_access": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app provides unrestricted web access (true/false)")
                    ]),
                    "horror_fear_themes": .object([
                        "type": .string("string"),
                        "description": .string("Horror or fear themes"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "mature_suggestive_themes": .object([
                        "type": .string("string"),
                        "description": .string("Mature or suggestive themes"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "medical_treatment_information": .object([
                        "type": .string("string"),
                        "description": .string("Medical treatment information"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "profanity_crude_humor": .object([
                        "type": .string("string"),
                        "description": .string("Profanity or crude humor"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "sexual_content_nudity": .object([
                        "type": .string("string"),
                        "description": .string("Sexual content or nudity"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "violence_cartoon": .object([
                        "type": .string("string"),
                        "description": .string("Cartoon or fantasy violence"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "violence_realistic": .object([
                        "type": .string("string"),
                        "description": .string("Realistic violence"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "violence_realistic_prolonged": .object([
                        "type": .string("string"),
                        "description": .string("Prolonged graphic or sadistic realistic violence"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "sexual_content_graphic_nudity": .object([
                        "type": .string("string"),
                        "description": .string("Graphic sexual content and nudity"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "guns_or_other_weapons": .object([
                        "type": .string("string"),
                        "description": .string("Guns or other weapons"),
                        "enum": .array([.string("NONE"), .string("INFREQUENT_OR_MILD"), .string("FREQUENT_OR_INTENSE")])
                    ]),
                    "kids_age_band": .object([
                        "type": .string("string"),
                        "description": .string("Kids age band (for kids apps)"),
                        "enum": .array([.string("FIVE_AND_UNDER"), .string("SIX_TO_EIGHT"), .string("NINE_TO_ELEVEN")])
                    ]),
                    "age_rating_override": .object([
                        "type": .string("string"),
                        "description": .string("Age rating override (v2)"),
                        "enum": .array([.string("NONE"), .string("NINE_PLUS"), .string("THIRTEEN_PLUS"), .string("SIXTEEN_PLUS"), .string("EIGHTEEN_PLUS"), .string("UNRATED")])
                    ]),
                    "korea_age_rating_override": .object([
                        "type": .string("string"),
                        "description": .string("Korea-specific age rating override"),
                        "enum": .array([.string("NONE"), .string("FIFTEEN_PLUS"), .string("NINETEEN_PLUS")])
                    ]),
                    "advertising": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app contains advertising (true/false)")
                    ]),
                    "age_assurance": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app uses age assurance (true/false)")
                    ]),
                    "health_or_wellness_topics": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app covers health or wellness topics (true/false)")
                    ]),
                    "loot_box": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app contains loot boxes (true/false)")
                    ]),
                    "messaging_and_chat": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app includes messaging or chat (true/false)")
                    ]),
                    "parental_controls": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app has parental controls (true/false)")
                    ]),
                    "user_generated_content": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the app contains user-generated content (true/false)")
                    ]),
                    "developer_age_rating_info_url": .object([
                        "type": .string("string"),
                        "description": .string("URL with developer's age rating information")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
}