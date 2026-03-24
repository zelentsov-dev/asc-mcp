import Foundation
import MCP

// MARK: - Tool Definitions
extension IntroductoryOffersWorker {

    func listIntroductoryOffersTool() -> Tool {
        return Tool(
            name: "intro_offers_list",
            description: "List introductory offers for a subscription (free trials, pay-as-you-go, pay-up-front). Returns offer mode, duration, number of periods, and date range.",
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
                    "filter_territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g. USA, GBR, RUS)")
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

    func createIntroductoryOfferTool() -> Tool {
        return Tool(
            name: "intro_offers_create",
            description: "Create an introductory offer for a subscription. The subscription must have pricing configured (not MISSING_METADATA state). For FREE_TRIAL mode, price point is not needed. For PAY_AS_YOU_GO or PAY_UP_FRONT modes, subscription_price_point_id is required. Each offer is per-territory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Offer duration: THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR")
                    ]),
                    "offer_mode": .object([
                        "type": .string("string"),
                        "description": .string("Pricing mode for the offer"),
                        "enum": .array([.string("FREE_TRIAL"), .string("PAY_AS_YOU_GO"), .string("PAY_UP_FRONT")])
                    ]),
                    "number_of_periods": .object([
                        "type": .string("integer"),
                        "description": .string("Number of periods for the offer")
                    ]),
                    "start_date": .object([
                        "type": .string("string"),
                        "description": .string("Start date (ISO 8601 format, e.g. 2026-01-01)")
                    ]),
                    "end_date": .object([
                        "type": .string("string"),
                        "description": .string("End date (ISO 8601 format, optional)")
                    ]),
                    "territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Territory code (e.g. USA, GBR). Each introductory offer is per-territory.")
                    ]),
                    "subscription_price_point_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription price point ID (required for PAY_AS_YOU_GO and PAY_UP_FRONT modes, not needed for FREE_TRIAL)")
                    ])
                ]),
                "required": .array([
                    .string("subscription_id"), .string("duration"),
                    .string("offer_mode"), .string("number_of_periods")
                ])
            ])
        )
    }

    func updateIntroductoryOfferTool() -> Tool {
        return Tool(
            name: "intro_offers_update",
            description: "Update an introductory offer. Only end_date can be changed. To change offer mode or duration, delete and recreate the offer.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "introductory_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Introductory offer ID")
                    ]),
                    "end_date": .object([
                        "type": .string("string"),
                        "description": .string("New end date (ISO 8601 format, e.g. 2026-12-31)")
                    ])
                ]),
                "required": .array([.string("introductory_offer_id")])
            ])
        )
    }

    func deleteIntroductoryOfferTool() -> Tool {
        return Tool(
            name: "intro_offers_delete",
            description: "Delete an introductory offer",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "introductory_offer_id": .object([
                        "type": .string("string"),
                        "description": .string("Introductory offer ID to delete")
                    ])
                ]),
                "required": .array([.string("introductory_offer_id")])
            ])
        )
    }
}
