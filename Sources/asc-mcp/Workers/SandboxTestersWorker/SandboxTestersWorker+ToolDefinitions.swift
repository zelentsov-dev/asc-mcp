import Foundation
import MCP

// MARK: - Tool Definitions
extension SandboxTestersWorker {

    func listSandboxTestersTool() -> Tool {
        return Tool(
            name: "sandbox_list",
            description: "List sandbox testers for the current App Store Connect account",
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

    func updateSandboxTesterTool() -> Tool {
        return Tool(
            name: "sandbox_update",
            description: "Update a sandbox tester's settings (territory, interrupt purchases, subscription renewal rate)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "sandbox_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Sandbox tester ID")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Territory code (e.g. USA, GBR, JPN)")
                    ]),
                    "interrupt_purchases": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether to interrupt purchases for testing interrupted purchase flows")
                    ]),
                    "subscription_renewal_rate": .object([
                        "type": .string("string"),
                        "description": .string("Subscription renewal rate for testing"),
                        "enum": .array([
                            .string("MONTHLY_RENEWAL_EVERY_ONE_HOUR"),
                            .string("MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_FIVE_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_THREE_MINUTES")
                        ])
                    ])
                ]),
                "required": .array([.string("sandbox_tester_id")])
            ])
        )
    }

    func clearPurchaseHistoryTool() -> Tool {
        return Tool(
            name: "sandbox_clear_purchase_history",
            description: "Clear purchase history for one or more sandbox testers (bulk operation supported)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "sandbox_tester_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of sandbox tester IDs to clear purchase history for"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("sandbox_tester_ids")])
            ])
        )
    }
}
