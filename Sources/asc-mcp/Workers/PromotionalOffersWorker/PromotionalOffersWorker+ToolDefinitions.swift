import Foundation
import MCP

// MARK: - Tool Definitions
extension PromotionalOffersWorker {

    func listPromotionalOffersTool() -> Tool {
        return Tool(
            name: "promo_offers_list",
            description: "List promotional offers for a subscription",
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

    func getPromotionalOfferTool() -> Tool {
        return Tool(
            name: "promo_offers_get",
            description: "Get a single promotional offer by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promotional_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Promotional offer ID")
                    ])
                ]),
                "required": .array([.string("promotional_offer_id")])
            ])
        )
    }

    func createPromotionalOfferTool() -> Tool {
        return Tool(
            name: "promo_offers_create",
            description: "Create a new promotional offer for a subscription. For FREE_TRIAL: provide territory_ids only. For PAY_AS_YOU_GO/PAY_UP_FRONT: provide both territory_ids and price_point_ids (same count).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Display name for the offer (e.g. 'Summer Promo')")
                    ]),
                    "offer_code": .object([
                        "type": .string("string"),
                        "description": .string("Unique offer code identifier (e.g. 'SUMMER2024')")
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Duration: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR")
                    ]),
                    "offer_mode": .object([
                        "type": .string("string"),
                        "description": .string("Offer pricing mode"),
                        "enum": .array([.string("FREE_TRIAL"), .string("PAY_AS_YOU_GO"), .string("PAY_UP_FRONT")])
                    ]),
                    "number_of_periods": .object([
                        "type": .string("integer"),
                        "description": .string("Number of periods for the offer")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of territory IDs (e.g. [\"USA\", \"GBR\"]). Required for all offer modes."),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "price_point_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of subscription price point IDs (not needed for FREE_TRIAL). Must match territory_ids count."),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([
                    .string("subscription_id"), .string("name"), .string("offer_code"),
                    .string("duration"), .string("offer_mode"), .string("number_of_periods")
                ])
            ])
        )
    }

    func updatePromotionalOfferTool() -> Tool {
        return Tool(
            name: "promo_offers_update",
            description: "Update a promotional offer's prices. PATCH cannot change attributes (name, offerCode, duration, offerMode, numberOfPeriods) — only prices via inline creates.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promotional_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Promotional offer ID")
                    ]),
                    "territory_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of territory IDs for new prices"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "price_point_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of subscription price point IDs (for PAY modes). Must match territory_ids count."),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("promotional_offer_id")])
            ])
        )
    }

    func deletePromotionalOfferTool() -> Tool {
        return Tool(
            name: "promo_offers_delete",
            description: "Delete a promotional offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promotional_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Promotional offer ID to delete")
                    ])
                ]),
                "required": .array([.string("promotional_offer_id")])
            ])
        )
    }

    func listPromotionalOfferPricesTool() -> Tool {
        return Tool(
            name: "promo_offers_list_prices",
            description: "List prices for a promotional offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "promotional_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Promotional offer ID")
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
                "required": .array([.string("promotional_offer_id")])
            ])
        )
    }
}
