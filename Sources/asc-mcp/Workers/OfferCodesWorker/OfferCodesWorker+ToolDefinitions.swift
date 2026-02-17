import Foundation
import MCP

// MARK: - Tool Definitions
extension OfferCodesWorker {

    func listOfferCodesTool() -> Tool {
        return Tool(
            name: "offer_codes_list",
            description: "List offer codes for a subscription",
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

    func createOfferCodeTool() -> Tool {
        return Tool(
            name: "offer_codes_create",
            description: "Create a new offer code for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "subscription_id": .object([
                        "type": .string("string"),
                        "description": .string("Subscription ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Offer code name (visible to users)")
                    ]),
                    "offer_eligibility": .object([
                        "type": .string("string"),
                        "description": .string("Eligibility for the offer"),
                        "enum": .array([.string("STACK_WITH_INTRO_OFFERS"), .string("REPLACE_INTRO_OFFERS")])
                    ]),
                    "offer_mode": .object([
                        "type": .string("string"),
                        "description": .string("Offer pricing mode"),
                        "enum": .array([.string("FREE_TRIAL"), .string("PAY_UP_FRONT"), .string("PAY_AS_YOU_GO")])
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Duration: ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR")
                    ]),
                    "number_of_periods": .object([
                        "type": .string("integer"),
                        "description": .string("Number of periods (for PAY_AS_YOU_GO)")
                    ]),
                    "customer_eligibilities": .object([
                        "type": .string("array"),
                        "description": .string("Customer eligibilities array"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([.string("NEW"), .string("EXISTING"), .string("EXPIRED")])
                        ])
                    ]),
                    "price_point_ids": .object([
                        "type": .string("array"),
                        "description": .string("Array of subscription price point IDs for offer code prices"),
                        "items": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                "required": .array([.string("subscription_id"), .string("name"), .string("offer_eligibility"), .string("offer_mode"), .string("duration"), .string("number_of_periods"), .string("price_point_ids")])
            ])
        )
    }

    func updateOfferCodeTool() -> Tool {
        return Tool(
            name: "offer_codes_update",
            description: "Update an offer code (e.g. activate/deactivate)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_code_id": .object([
                        "type": .string("string"),
                        "description": .string("Offer code ID")
                    ]),
                    "active": .object([
                        "type": .string("boolean"),
                        "description": .string("Set active state")
                    ])
                ]),
                "required": .array([.string("offer_code_id")])
            ])
        )
    }

    func deactivateOfferCodeTool() -> Tool {
        return Tool(
            name: "offer_codes_deactivate",
            description: "Deactivate an offer code",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_code_id": .object([
                        "type": .string("string"),
                        "description": .string("Offer code ID to deactivate")
                    ])
                ]),
                "required": .array([.string("offer_code_id")])
            ])
        )
    }

    func listOfferCodePricesTool() -> Tool {
        return Tool(
            name: "offer_codes_list_prices",
            description: "List prices for an offer code",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_code_id": .object([
                        "type": .string("string"),
                        "description": .string("Offer code ID")
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
                "required": .array([.string("offer_code_id")])
            ])
        )
    }

    func generateOneTimeCodesTool() -> Tool {
        return Tool(
            name: "offer_codes_generate_one_time",
            description: "Generate one-time use codes for an offer code",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_code_id": .object([
                        "type": .string("string"),
                        "description": .string("Offer code ID")
                    ]),
                    "number_of_codes": .object([
                        "type": .string("integer"),
                        "description": .string("Number of one-time codes to generate")
                    ]),
                    "expiration_date": .object([
                        "type": .string("string"),
                        "description": .string("Expiration date (ISO 8601 format, e.g. 2025-12-31)")
                    ])
                ]),
                "required": .array([.string("offer_code_id"), .string("number_of_codes"), .string("expiration_date")])
            ])
        )
    }

    func listOneTimeCodesTool() -> Tool {
        return Tool(
            name: "offer_codes_list_one_time",
            description: "List one-time use codes for an offer code",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "offer_code_id": .object([
                        "type": .string("string"),
                        "description": .string("Offer code ID")
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
                "required": .array([.string("offer_code_id")])
            ])
        )
    }
}
