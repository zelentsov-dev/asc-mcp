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
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
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
                "minProperties": .int(2),
                "properties": .object([
                    "sandbox_tester_id": .object([
                        "type": .string("string"),
                        "description": .string("Sandbox tester ID")
                    ]),
                    "territory": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "enum": .array(SandboxTesterTerritoryValues.all.map(Value.string) + [.null]),
                        "description": .string("Territory code, or null to clear it")
                    ]),
                    "interrupt_purchases": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Whether to interrupt purchases, or null to restore the default")
                    ]),
                    "subscription_renewal_rate": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("Subscription renewal rate for testing"),
                        "enum": .array([
                            .string("MONTHLY_RENEWAL_EVERY_ONE_HOUR"),
                            .string("MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_FIVE_MINUTES"),
                            .string("MONTHLY_RENEWAL_EVERY_THREE_MINUTES"),
                            .null
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
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ])
                ]),
                "required": .array([.string("sandbox_tester_ids")])
            ])
        )
    }
}
