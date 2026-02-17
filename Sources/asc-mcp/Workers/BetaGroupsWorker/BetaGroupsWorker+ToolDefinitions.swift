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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "is_internal": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter internal groups only")
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
                    "feedback_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable feedback (default: false)")
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
                        "type": .string("string"),
                        "description": .string("New group name")
                    ]),
                    "public_link_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable public invite link")
                    ]),
                    "public_link_limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max testers via public link")
                    ]),
                    "feedback_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable feedback")
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
                            "type": .string("string")
                        ])
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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
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
                            "type": .string("string")
                        ])
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
                            "type": .string("string")
                        ])
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
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("group_id"), .string("tester_ids")])
            ])
        )
    }
}
