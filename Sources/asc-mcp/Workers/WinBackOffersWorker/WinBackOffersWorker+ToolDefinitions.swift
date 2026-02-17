import Foundation
import MCP

// MARK: - Tool Definitions
extension WinBackOffersWorker {

    func listWinBackOffersTool() -> Tool {
        return Tool(
            name: "winback_list",
            description: "List win-back offers for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
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
                "required": .array([.string("subscription_id")])
            ])
        )
    }

    func createWinBackOfferTool() -> Tool {
        return Tool(
            name: "winback_create",
            description: "Create a new win-back offer for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "reference_name": .object([
                        "type": .string("string"),
                        "description": .string("Internal reference name")
                    ]),
                    "offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Unique offer identifier")
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Duration: ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR")
                    ]),
                    "offer_mode": .object([
                        "type": .string("string"),
                        "description": .string("Mode: PAY_AS_YOU_GO, PAY_UP_FRONT, FREE")
                    ]),
                    "period_count": .object([
                        "type": .string("integer"),
                        "description": .string("Number of periods")
                    ]),
                    "priority": .object([
                        "type": .string("string"),
                        "description": .string("Priority: HIGH, NORMAL")
                    ]),
                    "eligibility_duration_months": .object([
                        "type": .string("integer"),
                        "description": .string("Min months of paid subscription for eligibility")
                    ]),
                    "eligibility_time_since_last_months": .object([
                        "type": .string("integer"),
                        "description": .string("Min months since last subscribed")
                    ]),
                    "eligibility_wait_between_months": .object([
                        "type": .string("integer"),
                        "description": .string("Min months between offers")
                    ]),
                    "start_date": .object([
                        "type": .string("string"),
                        "description": .string("Start date (ISO 8601 format, e.g. 2025-01-01)")
                    ]),
                    "end_date": .object([
                        "type": .string("string"),
                        "description": .string("End date (ISO 8601 format, optional)")
                    ])
                ]),
                "required": .array([
                    .string("subscription_id"), .string("reference_name"), .string("offer_id"),
                    .string("duration"), .string("offer_mode"), .string("priority"), .string("start_date")
                ])
            ])
        )
    }

    func updateWinBackOfferTool() -> Tool {
        return Tool(
            name: "winback_update",
            description: "Update a win-back offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "winback_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Win-back offer ID")
                    ]),
                    "priority": .object([
                        "type": .string("string"),
                        "description": .string("New priority: HIGH, NORMAL")
                    ]),
                    "start_date": .object([
                        "type": .string("string"),
                        "description": .string("New start date (ISO 8601)")
                    ]),
                    "end_date": .object([
                        "type": .string("string"),
                        "description": .string("New end date (ISO 8601)")
                    ])
                ]),
                "required": .array([.string("winback_offer_id")])
            ])
        )
    }

    func deleteWinBackOfferTool() -> Tool {
        return Tool(
            name: "winback_delete",
            description: "Delete a win-back offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "winback_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Win-back offer ID to delete")
                    ])
                ]),
                "required": .array([.string("winback_offer_id")])
            ])
        )
    }

    func listWinBackOfferPricesTool() -> Tool {
        return Tool(
            name: "winback_list_prices",
            description: "List prices for a win-back offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "winback_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Win-back offer ID")
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
                "required": .array([.string("winback_offer_id")])
            ])
        )
    }
}
