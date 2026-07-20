import Foundation
import MCP

// MARK: - Tool Definitions
extension UsersWorker {

    func listUsersTool() -> Tool {
        return Tool(
            name: "users_list",
            description: "List team members in App Store Connect",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "filter_username": stringListSchema("Filter by one or more exact usernames"),
                    "filter_roles": enumListSchema("Filter by one or more roles", values: UsersWorker.assignableRoles),
                    "filter_visible_apps": stringListSchema("Filter by one or more related visible app IDs"),
                    "sort": enumListSchema("Sort by username or last name; prefix with - for descending order", values: UsersWorker.userSortValues),
                    "include": enumListSchema("Include related visible apps", values: UsersWorker.includeValues),
                    "limit_visible_apps": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included visible apps per user (max: 50)"),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getUserTool() -> Tool {
        return Tool(
            name: "users_get",
            description: "Get details of a team member",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
                    ]),
                    "include": enumListSchema("Related resources to include", values: UsersWorker.includeValues),
                    "limit_visible_apps": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included visible apps (max: 50)"),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ])
                ]),
                "required": .array([.string("user_id")])
            ])
        )
    }

    func updateUserTool() -> Tool {
        return Tool(
            name: "users_update",
            description: "Update a team member's roles, app visibility, or provisioning access. Provide at least one field to change.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
                    ]),
                    "roles": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array(UsersWorker.assignableRoles.map(Value.string))
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "description": .string("Roles or permissions to assign. ACCESS_TO_REPORTS is deprecated by Apple but remains accepted for backward compatibility.")
                    ]),
                    "all_apps_visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the user can access all apps")
                    ]),
                    "provisioning_allowed": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the user's role can access provisioning on the Apple Developer website")
                    ]),
                    "visible_app_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "uniqueItems": .bool(true),
                        "description": .string("Complete set of app resource IDs visible to the user; pass an empty array to clear specific app visibility")
                    ])
                ]),
                "required": .array([.string("user_id")])
            ])
        )
    }

    func removeUserTool() -> Tool {
        return Tool(
            name: "users_remove",
            description: "Remove a user from the team",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID to remove")
                    ])
                ]),
                "required": .array([.string("user_id")])
            ])
        )
    }

    func inviteUserTool() -> Tool {
        return Tool(
            name: "users_invite",
            description: "Invite a new user to the team",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "email": .object([
                        "type": .string("string"),
                        "description": .string("Email address of the user to invite")
                    ]),
                    "first_name": .object([
                        "type": .string("string"),
                        "description": .string("First name of the user")
                    ]),
                    "last_name": .object([
                        "type": .string("string"),
                        "description": .string("Last name of the user")
                    ]),
                    "roles": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array(UsersWorker.assignableRoles.map(Value.string))
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "description": .string("Roles to assign. ACCESS_TO_REPORTS is deprecated by Apple but remains accepted for backward compatibility.")
                    ]),
                    "all_apps_visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether user can see all apps (default: true)")
                    ]),
                    "provisioning_allowed": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the invited role can access provisioning on the Apple Developer website")
                    ]),
                    "visible_app_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "uniqueItems": .bool(true),
                        "description": .string("Array of app IDs visible to user (when all_apps_visible is false)")
                    ])
                ]),
                "required": .array([.string("email"), .string("first_name"), .string("last_name"), .string("roles")])
            ])
        )
    }

    func cancelInvitationTool() -> Tool {
        return Tool(
            name: "users_cancel_invitation",
            description: "Cancel a pending user invitation",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "invitation_id": .object([
                        "type": .string("string"),
                        "description": .string("User invitation ID to cancel (get from users_list_invitations)")
                    ])
                ]),
                "required": .array([.string("invitation_id")])
            ])
        )
    }

    func listInvitationsTool() -> Tool {
        return Tool(
            name: "users_list_invitations",
            description: "List pending user invitations",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "filter_email": stringListSchema("Filter by one or more exact email addresses"),
                    "filter_roles": enumListSchema("Filter by one or more roles", values: UsersWorker.assignableRoles),
                    "filter_visible_apps": stringListSchema("Filter by one or more related visible app IDs"),
                    "sort": enumListSchema("Sort by email or last name; prefix with - for descending order", values: UsersWorker.invitationSortValues),
                    "include": enumListSchema("Include related visible apps", values: UsersWorker.includeValues),
                    "limit_visible_apps": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included visible apps per invitation (max: 50)"),
                        "minimum": .int(1),
                        "maximum": .int(50)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func listVisibleAppsTool() -> Tool {
        return Tool(
            name: "users_list_visible_apps",
            description: "List apps visible to a specific user",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
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
                "required": .array([.string("user_id")])
            ])
        )
    }

    func addVisibleAppsTool() -> Tool {
        return Tool(
            name: "users_add_visible_apps",
            description: "Grant user access to specific apps",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
                    ]),
                    "app_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of app IDs to grant access to"),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("user_id"), .string("app_ids")])
            ])
        )
    }

    func removeVisibleAppsTool() -> Tool {
        return Tool(
            name: "users_remove_visible_apps",
            description: "Remove user's access to specific apps",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
                    ]),
                    "app_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of app IDs to remove access from"),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("user_id"), .string("app_ids")])
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
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
