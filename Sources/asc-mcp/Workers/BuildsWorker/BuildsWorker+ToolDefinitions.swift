import Foundation
import MCP

// MARK: - Tool Definitions
extension BuildsWorker {
    
    func listBuildsTool() -> Tool {
        return Tool(
            name: "builds_list",
            description: "Get list of builds for an app with filtering options",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app in App Store Connect")
                    ]),
                    "version": .object([
                        "description": .string("Filter by one or more build numbers"),
                        "oneOf": .array([
                            .object(["type": .string("string")]),
                            .object(["type": .string("array"), "items": .object(["type": .string("string")])])
                        ])
                    ]),
                    "processing_state": .object([
                        "description": .string("Filter by one or more processing states"),
                        "oneOf": .array([
                            .object(["type": .string("string"), "enum": .array([.string("PROCESSING"), .string("FAILED"), .string("INVALID"), .string("VALID")])]),
                            .object(["type": .string("array"), "items": .object(["type": .string("string"), "enum": .array([.string("PROCESSING"), .string("FAILED"), .string("INVALID"), .string("VALID")])])])
                        ])
                    ]),
                    "expired": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by expiration status")
                    ]),
                    "app_store_version_ids": stringListSchema("Filter by App Store version IDs"),
                    "beta_review_states": enumListSchema(
                        "Filter by TestFlight beta review state",
                        values: ["WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED", "APPROVED"]
                    ),
                    "beta_group_ids": stringListSchema("Filter by beta group IDs"),
                    "build_audience_types": enumListSchema(
                        "Filter by build audience type",
                        values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]
                    ),
                    "build_ids": stringListSchema("Filter by build IDs"),
                    "pre_release_platforms": enumListSchema(
                        "Filter by pre-release platform",
                        values: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "pre_release_versions": stringListSchema("Filter by pre-release version strings"),
                    "pre_release_version_ids": stringListSchema("Filter by pre-release version IDs"),
                    "uses_non_exempt_encryption": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by the declared non-exempt encryption value")
                    ]),
                    "uses_non_exempt_encryption_set": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by whether the non-exempt encryption declaration exists")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of builds to return"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order (default: -uploadedDate)"),
                        "enum": .array([.string("version"), .string("-version"), .string("uploadedDate"), .string("-uploadedDate"), .string("preReleaseVersion"), .string("-preReleaseVersion")])
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func getBuildTool() -> Tool {
        return Tool(
            name: "builds_get",
            description: "Get detailed information about a specific build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ]),
                    "include_beta_detail": .object([
                        "type": .string("boolean"),
                        "description": .string("Include beta build details (default: true)")
                    ]),
                    "include_app": .object([
                        "type": .string("boolean"),
                        "description": .string("Include app information (default: false)")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func findBuildByNumberTool() -> Tool {
        return Tool(
            name: "builds_find_by_number",
            description: "Find a build by its version number",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app in App Store Connect")
                    ]),
                    "build_number": .object([
                        "type": .string("string"),
                        "description": .string("Build number/version to search for")
                    ]),
                    "pre_release_platforms": enumListSchema(
                        "Restrict an otherwise ambiguous build number to one or more platforms",
                        values: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
                    ),
                    "pre_release_versions": stringListSchema("Restrict the match to pre-release version strings"),
                    "pre_release_version_ids": stringListSchema("Restrict the match to pre-release version IDs"),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Choose a deterministic match when multiple builds share the number (default: -uploadedDate)"),
                        "enum": .array([.string("version"), .string("-version"), .string("uploadedDate"), .string("-uploadedDate"), .string("preReleaseVersion"), .string("-preReleaseVersion")])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("build_number")])
            ])
        )
    }
    
    func listBuildsForVersionTool() -> Tool {
        return Tool(
            name: "builds_list_for_version",
            description: "Get the single build currently associated with a specific App Store version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app store version")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }

    private func stringListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "minItems": .int(1)
                ])
            ])
        ])
    }

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(values.map(Value.string))
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1)
                ])
            ])
        ])
    }
}
