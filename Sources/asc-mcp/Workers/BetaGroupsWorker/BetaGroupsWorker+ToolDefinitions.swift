import Foundation
import MCP

// MARK: - Tool Definitions
extension BetaGroupsWorker {

    func listBetaGroupsTool() -> Tool {
        return Tool(
            name: "beta_groups_list",
            description: "List TestFlight beta groups for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "is_internal": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter internal groups only")
                    ]),
                    "name": stringListSchema("Filter by exact group name"),
                    "build_ids": stringListSchema("Filter by associated build IDs"),
                    "group_ids": stringListSchema("Filter by beta group IDs"),
                    "public_link_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by whether the public link is enabled")
                    ]),
                    "public_link_limit_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by whether a public-link tester limit is enabled")
                    ]),
                    "public_link": stringListSchema("Filter by public link value"),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort beta groups"),
                        "enum": .array([.string("name"), .string("-name"), .string("createdDate"), .string("-createdDate"), .string("publicLinkEnabled"), .string("-publicLinkEnabled"), .string("publicLinkLimit"), .string("-publicLinkLimit")])
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

    func createBetaGroupTool() -> Tool {
        return Tool(
            name: "beta_groups_create",
            description: "Create a new TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Beta group name")
                    ]),
                    "is_internal_group": .object([
                        "type": .string("boolean"),
                        "description": .string("Internal group (default: false)")
                    ]),
                    "has_access_to_all_builds": .object([
                        "type": .string("boolean"),
                        "description": .string("Access to all builds (default: false)")
                    ]),
                    "public_link_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable public invite link")
                    ]),
                    "public_link_limit_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable a tester limit for the public link")
                    ]),
                    "public_link_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum testers allowed through the public link")
                    ]),
                    "feedback_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable feedback (default: false)")
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Optional build IDs to assign when creating the group"),
                        "items": .object(["type": .string("string")]),
                        "minItems": .int(1)
                    ]),
                    "tester_ids": .object([
                        "type": .string("array"),
                        "description": .string("Optional beta tester IDs to assign when creating the group"),
                        "items": .object(["type": .string("string")]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("app_id"), .string("name")])
            ])
        )
    }

    func updateBetaGroupTool() -> Tool {
        return Tool(
            name: "beta_groups_update",
            description: "Update TestFlight beta group settings",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
                    ]),
                    "name": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("New group name, or null to clear it")
                    ]),
                    "public_link_enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Enable public invite link, or null to clear the setting")
                    ]),
                    "public_link_limit": .object([
                        "type": .array([.string("integer"), .string("null")]),
                        "description": .string("Max testers via public link, or null to clear the limit")
                    ]),
                    "public_link_limit_enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Enable or disable the public-link tester limit, or null to clear the setting")
                    ]),
                    "feedback_enabled": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Enable feedback, or null to clear the setting")
                    ]),
                    "ios_builds_available_for_apple_silicon_mac": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Make eligible iOS builds available on Apple silicon Macs, or null to clear the setting")
                    ]),
                    "ios_builds_available_for_apple_vision": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Make eligible iOS builds available on Apple Vision, or null to clear the setting")
                    ])
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func deleteBetaGroupTool() -> Tool {
        return Tool(
            name: "beta_groups_delete",
            description: "Delete a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID to delete")
                    ])
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func addTestersTool() -> Tool {
        return Tool(
            name: "beta_groups_add_testers",
            description: "Add testers to a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
                    ]),
                    "tester_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of beta tester IDs"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("group_id"), .string("tester_ids")])
            ])
        )
    }

    func listTestersTool() -> Tool {
        return Tool(
            name: "beta_groups_list_testers",
            description: "List testers in a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
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
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func addBuildsTool() -> Tool {
        return Tool(
            name: "beta_groups_add_builds",
            description: "Add builds to a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of build IDs to add"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("group_id"), .string("build_ids")])
            ])
        )
    }

    func removeBuildsTool() -> Tool {
        return Tool(
            name: "beta_groups_remove_builds",
            description: "Remove builds from a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of build IDs to remove"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("group_id"), .string("build_ids")])
            ])
        )
    }

    func removeTestersTool() -> Tool {
        return Tool(
            name: "beta_groups_remove_testers",
            description: "Remove testers from a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "group_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta group ID")
                    ]),
                    "tester_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of beta tester IDs"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("group_id"), .string("tester_ids")])
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
}
