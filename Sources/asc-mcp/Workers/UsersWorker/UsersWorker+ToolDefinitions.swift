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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_roles": .object([
                        "type": .string("string"),
                        "description": .string("Filter by roles, comma-separated (e.g. ADMIN,DEVELOPER,APP_MANAGER,MARKETING,SALES,CUSTOMER_SUPPORT,FINANCE)")
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
                    "include": .object([
                        "type": .string("string"),
                        "description": .string("Related resources to include (e.g. visibleApps)")
                    ])
                ]),
                "required": .array([.string("user_id")])
            ])
        )
    }

    func updateUserTool() -> Tool {
        return Tool(
            name: "users_update",
            description: "Update user roles in the team",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "user_id": .object([
                        "type": .string("string"),
                        "description": .string("User resource ID")
                    ]),
                    "roles": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of roles to assign (e.g. [\"DEVELOPER\",\"MARKETING\"]). Valid: ADMIN, FINANCE, TECHNICAL, ACCOUNT_HOLDER, SALES, MARKETING, APP_MANAGER, DEVELOPER, ACCESS_TO_REPORTS, CUSTOMER_SUPPORT, CREATE_APPS, CLOUD_MANAGED_DEVELOPER_ID, CLOUD_MANAGED_APP_DISTRIBUTION, GENERATE_INDIVIDUAL_KEYS")
                    ])
                ]),
                "required": .array([.string("user_id"), .string("roles")])
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
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of roles to assign (e.g. [\"DEVELOPER\"])")
                    ]),
                    "all_apps_visible": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether user can see all apps (default: true)")
                    ]),
                    "visible_app_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
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
                        "description": .string("Max results (default: 25, max: 200)")
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
}
