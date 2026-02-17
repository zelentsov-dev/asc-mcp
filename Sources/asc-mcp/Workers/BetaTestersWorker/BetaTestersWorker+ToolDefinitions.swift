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
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to get next page")
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
                        "type": .string("string"),
                        "description": .string("Related resources to include (comma-separated: apps,betaGroups,builds)")
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
                        "description": .string("Array of beta group IDs to add the tester to"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("email"), .string("group_ids")])
            ])
        )
    }

    func deleteBetaTesterTool() -> Tool {
        return Tool(
            name: "beta_testers_delete",
            description: "Remove a beta tester from all beta groups and revoke access",
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
                        "description": .string("Pagination URL from previous response to get next page")
                    ])
                ]),
                "required": .array([.string("tester_id")])
            ])
        )
    }
}
