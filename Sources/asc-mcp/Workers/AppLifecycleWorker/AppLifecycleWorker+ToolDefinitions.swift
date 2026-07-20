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
                    ]),
                    "copyright": .object([
                        "type": .string("string"),
                        "description": .string("Copyright text")
                    ]),
                    "review_type": .object([
                        "type": .string("string"),
                        "description": .string("Review flow type"),
                        "enum": .array([.string("APP_STORE"), .string("NOTARIZATION")])
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
                                .string("ACCEPTED"),
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
                                .string("REPLACED_WITH_NEW_VERSION"),
                                .string("NOT_APPLICABLE")
                            ])
                        ]),
                        "description": .string("Deprecated compatibility filter mapped to Apple's filter[appStoreState]"),
                        "deprecated": .bool(true)
                    ]),
                    "app_version_states": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("ACCEPTED"),
                                .string("DEVELOPER_REJECTED"),
                                .string("IN_REVIEW"),
                                .string("INVALID_BINARY"),
                                .string("METADATA_REJECTED"),
                                .string("PENDING_APPLE_RELEASE"),
                                .string("PENDING_DEVELOPER_RELEASE"),
                                .string("PREPARE_FOR_SUBMISSION"),
                                .string("PROCESSING_FOR_DISTRIBUTION"),
                                .string("READY_FOR_DISTRIBUTION"),
                                .string("READY_FOR_REVIEW"),
                                .string("REJECTED"),
                                .string("REPLACED_WITH_NEW_VERSION"),
                                .string("WAITING_FOR_EXPORT_COMPLIANCE"),
                                .string("WAITING_FOR_REVIEW")
                            ])
                        ]),
                        "description": .string("Current version-state filter mapped to Apple's filter[appVersionState]")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by platform"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of versions to return (default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
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
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Release type after approval"),
                        "enum": .array([.string("MANUAL"), .string("AFTER_APPROVAL"), .string("SCHEDULED"), .null])
                    ]),
                    "earliest_release_date": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Earliest release date for SCHEDULED release (ISO 8601)")
                    ]),
                    "copyright": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Copyright text")
                    ]),
                    "version_string": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Version number (can only be updated before submission)")
                    ]),
                    "review_type": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Review flow type"),
                        "enum": .array([.string("APP_STORE"), .string("NOTARIZATION"), .null])
                    ]),
                    "downloadable": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the version remains downloadable")
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
                        "description": .string("Optional submission platform; when supplied, it must match the version platform"),
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
    
    func getPhasedReleaseTool() -> Tool {
        Tool(
            name: "app_versions_get_phased_release",
            description: "Get phased release info for an app version. Returns phased_release_id needed for app_versions_update_phased_release.",
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

    func updatePhasedReleaseTool() -> Tool {
        Tool(
            name: "app_versions_update_phased_release",
            description: "Update phased release state (pause/resume/complete). Get phased_release_id from app_versions_get_phased_release.",
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

    func deletePhasedReleaseTool() -> Tool {
        Tool(
            name: "app_versions_delete_phased_release",
            description: "Delete a phased release configuration",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "phased_release_id": .object([
                        "type": .string("string"),
                        "description": .string("Phased release ID")
                    ])
                ]),
                "required": .array([.string("phased_release_id")])
            ])
        )
    }
    
    func releaseVersionTool() -> Tool {
        Tool(
            name: "app_versions_release",
            description: "Release an approved version in PENDING_DEVELOPER_RELEASE state to the App Store",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID to release")
                    ]),
                    "confirm_version_string": .object([
                        "type": .string("string"),
                        "description": .string("Exact version string required to confirm the irreversible release request")
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
                        "description": .string("Version ID"),
                        "minLength": .int(1)
                    ]),
                    "contact_first_name": nullablePropertySchema(type: "string", description: "Contact first name"),
                    "contact_last_name": nullablePropertySchema(type: "string", description: "Contact last name"),
                    "contact_phone": nullablePropertySchema(type: "string", description: "Contact phone number"),
                    "contact_email": nullablePropertySchema(type: "string", description: "Contact email address"),
                    "demo_account_name": nullablePropertySchema(type: "string", description: "Demo account username"),
                    "demo_account_password": nullablePropertySchema(type: "string", description: "Demo account password"),
                    "demo_account_required": nullablePropertySchema(type: "boolean", description: "Whether demo account is required"),
                    "notes": nullablePropertySchema(type: "string", description: "Additional notes for reviewers"),
                    "attachment_file_id": .object([
                        "type": .string("string"),
                        "description": .string("Legacy unsupported parameter. Use review_attachments_upload after creating or updating review details.")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
    
    func updateAgeRatingTool() -> Tool {
        let intensityValues = ["NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT"]
        return Tool(
            name: "app_versions_update_age_rating",
            description: "Update the app-level age rating declaration. Prefer app_info_id from app_info_list; version_id remains available for compatible-state lookup. INFREQUENT_OR_MILD and FREQUENT_OR_INTENSE are accepted only for legacy compatibility; use INFREQUENT or FREQUENT.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Legacy compatibility input used to resolve a uniquely state-compatible App Info"),
                        "minLength": .int(1)
                    ]),
                    "app_info_id": .object([
                        "type": .string("string"),
                        "description": .string("Authoritative App Info ID from app_info_list"),
                        "minLength": .int(1)
                    ]),
                    "alcohol_tobacco_or_drug_use": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Alcohol, tobacco, or drug use references"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "contests": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Contests"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "gambling": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app contains gambling (true/false)")
                    ]),
                    "gambling_simulated": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Simulated gambling intensity level"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "unrestricted_web_access": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app provides unrestricted web access (true/false)")
                    ]),
                    "horror_fear_themes": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Horror or fear themes"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "mature_suggestive_themes": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Mature or suggestive themes"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "medical_treatment_information": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Medical treatment information"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "profanity_crude_humor": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Profanity or crude humor"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "sexual_content_nudity": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Sexual content or nudity"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "violence_cartoon": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Cartoon or fantasy violence"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "violence_realistic": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Realistic violence"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "violence_realistic_prolonged": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Prolonged graphic or sadistic realistic violence"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "sexual_content_graphic_nudity": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Graphic sexual content and nudity"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "guns_or_other_weapons": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Guns or other weapons"),
                        "enum": .array(intensityValues.map(Value.string) + [.null])
                    ]),
                    "kids_age_band": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Kids age band (for kids apps)"),
                        "enum": .array([.string("FIVE_AND_UNDER"), .string("SIX_TO_EIGHT"), .string("NINE_TO_ELEVEN"), .null])
                    ]),
                    "age_rating_override": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Age rating override (v2)"),
                        "enum": .array([.string("NONE"), .string("NINE_PLUS"), .string("THIRTEEN_PLUS"), .string("SIXTEEN_PLUS"), .string("EIGHTEEN_PLUS"), .string("UNRATED"), .null])
                    ]),
                    "korea_age_rating_override": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Korea-specific age rating override"),
                        "enum": .array([.string("NONE"), .string("FIFTEEN_PLUS"), .string("NINETEEN_PLUS"), .null])
                    ]),
                    "advertising": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app contains advertising (true/false)")
                    ]),
                    "age_assurance": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app uses age assurance (true/false)")
                    ]),
                    "health_or_wellness_topics": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app covers health or wellness topics (true/false)")
                    ]),
                    "loot_box": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app contains loot boxes (true/false)")
                    ]),
                    "messaging_and_chat": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app includes messaging or chat (true/false)")
                    ]),
                    "parental_controls": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app has parental controls (true/false)")
                    ]),
                    "social_media": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app includes social media features (true/false)")
                    ]),
                    "social_media_age_restricted": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether social media is disabled for users under 13 (true/false)")
                    ]),
                    "user_generated_content": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether the app contains user-generated content (true/false)")
                    ]),
                    "developer_age_rating_info_url": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("URL with developer's age rating information")
                    ])
                ]),
                "anyOf": .array([
                    .object(["required": .array([.string("app_info_id")])]),
                    .object(["required": .array([.string("version_id")])])
                ])
            ])
        )
    }

    func deleteVersionTool() -> Tool {
        Tool(
            name: "app_versions_delete",
            description: "Delete an app store version. App Store Connect validates whether the version is currently deletable.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("Version ID to delete")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }

    private func nullablePropertySchema(type: String, description: String) -> Value {
        .object([
            "type": .array([.string(type), .string("null")]),
            "description": .string("\(description). Pass null to clear the saved value.")
        ])
    }
}
