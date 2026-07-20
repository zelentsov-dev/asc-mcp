import Foundation
import MCP

// MARK: - Tool Definitions
extension BetaTestersWorker {

    func listBetaTestersTool() -> Tool {
        return Tool(
            name: "beta_testers_list",
            description: "List TestFlight beta testers. Optionally filter by app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID to filter testers by app")
                    ]),
                    "first_name": stringListSchema("Filter by first name"),
                    "last_name": stringListSchema("Filter by last name"),
                    "email": stringListSchema("Filter by exact email address"),
                    "invite_type": enumListSchema("Filter by invitation type", values: ["EMAIL", "PUBLIC_LINK"]),
                    "group_ids": stringListSchema("Filter by beta group IDs"),
                    "build_ids": stringListSchema("Filter by build IDs"),
                    "tester_ids": stringListSchema("Filter by beta tester IDs"),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort beta testers"),
                        "enum": .array([.string("firstName"), .string("-firstName"), .string("lastName"), .string("-lastName"), .string("email"), .string("-email"), .string("inviteType"), .string("-inviteType"), .string("state"), .string("-state")])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ])
            ])
        )
    }

    func searchBetaTestersTool() -> Tool {
        return Tool(
            name: "beta_testers_search",
            description: "Search beta tester by email address. Exact email match only. Partial/wildcard not supported.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "email": .object([
                        "type": .string("string"),
                        "description": .string("Email address to search for")
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID to filter by app")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum exact-email matches to return"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("email")])
            ])
        )
    }

    func getBetaTesterTool() -> Tool {
        return Tool(
            name: "beta_testers_get",
            description: "Get detailed information about a specific beta tester",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "include": .object([
                        "description": .string("Related resources to include"),
                        "oneOf": .array([
                            .object([
                                "type": .string("string"),
                                "description": .string("Comma-separated: apps,betaGroups,builds")
                            ]),
                            .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("string"),
                                    "enum": .array([.string("apps"), .string("betaGroups"), .string("builds")])
                                ]),
                                "minItems": .int(1)
                            ])
                        ])
                    ])
                ]),
                "required": .array([.string("tester_id")])
            ])
        )
    }

    func createBetaTesterTool() -> Tool {
        return Tool(
            name: "beta_testers_create",
            description: "Invite a new beta tester to TestFlight. Tester will be added to specified beta groups",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "email": .object([
                        "type": .string("string"),
                        "description": .string("Email address of the beta tester")
                    ]),
                    "first_name": .object([
                        "type": .string("string"),
                        "description": .string("First name of the beta tester")
                    ]),
                    "last_name": .object([
                        "type": .string("string"),
                        "description": .string("Last name of the beta tester")
                    ]),
                    "group_ids": .object([
                        "type": .string("array"),
                        "description": .string("Optional beta group IDs to add the tester to"),
                        "items": .object([
                            "type": .string("string")
                        ]),
                        "minItems": .int(1)
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Optional build IDs for individual testing"),
                        "items": .object([
                            "type": .string("string")
                        ]),
                        "minItems": .int(1)
                    ])
                ]),
                "required": .array([.string("email")])
            ])
        )
    }

    func deleteBetaTesterTool() -> Tool {
        return Tool(
            name: "beta_testers_delete",
            description: "Request removal of a beta tester from all beta groups and report whether Apple completed the deletion or accepted it for asynchronous processing",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID to remove")
                    ])
                ]),
                "required": .array([.string("tester_id")])
            ])
        )
    }

    func listBetaTesterAppsTool() -> Tool {
        return Tool(
            name: "beta_testers_list_apps",
            description: "List apps a beta tester has access to",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("tester_id")])
            ])
        )
    }

    func sendInvitationTool() -> Tool {
        return Tool(
            name: "beta_testers_send_invitation",
            description: "Send or resend a TestFlight invitation to a beta tester for a specific app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID to send invitation to")
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID to invite the tester to")
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("app_id")])
            ])
        )
    }

    func addToGroupsTool() -> Tool {
        return Tool(
            name: "beta_testers_add_to_groups",
            description: "Add a beta tester to one or more beta groups",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "group_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of beta group IDs to add the tester to"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("group_ids")])
            ])
        )
    }

    func removeFromGroupsTool() -> Tool {
        return Tool(
            name: "beta_testers_remove_from_groups",
            description: "Remove a beta tester from one or more beta groups",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "group_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of beta group IDs to remove the tester from"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("group_ids")])
            ])
        )
    }

    func addToBuildsTool() -> Tool {
        return Tool(
            name: "beta_testers_add_to_builds",
            description: "Assign one or more builds to a beta tester for individual testing",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of build IDs to assign to the tester"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("build_ids")])
            ])
        )
    }

    func removeFromBuildsTool() -> Tool {
        return Tool(
            name: "beta_testers_remove_from_builds",
            description: "Remove build access from a beta tester",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "build_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of build IDs to remove from the tester"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("build_ids")])
            ])
        )
    }

    func removeFromAppTool() -> Tool {
        return Tool(
            name: "beta_testers_remove_from_app",
            description: "Request removal of a beta tester's app access and report whether Apple completed the relationship deletion or accepted it for asynchronous processing",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta tester ID")
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App ID to remove tester access from")
                    ])
                ]),
                "required": .array([.string("beta_tester_id"), .string("app_id")])
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
                .object(["type": .string("string"), "enum": .array(values.map(Value.string))]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string"), "enum": .array(values.map(Value.string))]),
                    "minItems": .int(1)
                ])
            ])
        ])
    }
}
