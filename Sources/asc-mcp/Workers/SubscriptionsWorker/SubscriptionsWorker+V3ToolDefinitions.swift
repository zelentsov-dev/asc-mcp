import Foundation
import MCP

extension SubscriptionsWorker {
    func v3CommerceTools() -> [Tool] {
        [
            simpleTool("subscriptions_list_groups", "List subscription groups for an app", ["app_id": "App Store Connect app ID", "limit": "Max results", "next_url": "Pagination URL"], ["app_id"]),
            simpleTool("subscriptions_get_group", "Get a subscription group", ["group_id": "Subscription group ID"], ["group_id"]),
            simpleTool("subscriptions_submit_group", "Submit a subscription group for review", ["group_id": "Subscription group ID"], ["group_id"]),
            simpleTool("subscriptions_get_localization", "Get a subscription localization", ["localization_id": "Subscription localization ID"], ["localization_id"]),
            simpleTool("subscriptions_create_price", "Create a subscription price for a territory and price point", ["subscription_id": "Subscription ID", "territory_id": "Territory ID", "price_point_id": "Subscription price point ID", "start_date": "Optional ISO date"], ["subscription_id", "territory_id", "price_point_id"]),
            simpleTool("subscriptions_get_price_point", "Get one subscription price point", ["price_point_id": "Subscription price point ID"], ["price_point_id"]),
            simpleTool("subscriptions_list_price_point_equalizations", "List equivalent subscription price points", ["price_point_id": "Subscription price point ID", "subscription_id": "Optional subscription filter", "territory_id": "Optional territory filter", "limit": "Max results, up to 8000", "next_url": "Pagination URL"], ["price_point_id"]),
            simpleTool("subscriptions_get_availability", "Deprecated compatibility read for Apple's legacy subscriptionAvailability resource. Apple 4.4.1 replaces it with plan-type-aware subscriptionPlanAvailabilities.", ["subscription_id": "Subscription ID"], ["subscription_id"]),
            simpleTool("subscriptions_set_availability", "Deprecated compatibility write for Apple's legacy subscriptionAvailability resource. Apple 4.4.1 replaces it with plan-type-aware subscriptionPlanAvailabilities.", ["subscription_id": "Subscription ID", "available_in_new_territories": "Whether new territories are automatically enabled", "territory_ids": "Array of territory IDs"], ["subscription_id", "available_in_new_territories", "territory_ids"]),
            simpleTool("subscriptions_list_available_territories", "Deprecated compatibility listing for Apple's legacy subscriptionAvailability resource. Apple 4.4.1 replaces it with plan-type-aware subscriptionPlanAvailabilities.", ["availability_id": "Subscription availability ID", "limit": "Max results", "next_url": "Pagination URL"], ["availability_id"]),
            simpleTool("subscriptions_get_promoted_purchase", "Get promoted purchase for a subscription", ["subscription_id": "Subscription ID"], ["subscription_id"]),
            simpleTool("subscriptions_inventory", "Deprecated compatibility inventory built from Apple's legacy subscriptionAvailability resource. It can omit subscriptions beyond the first included relationship page, so do not treat it as an authoritative complete inventory.", ["app_id": "App Store Connect app ID", "territory_id": "Optional territory for price sampling", "limit": "Max groups/subscriptions per page"], ["app_id"]),
            simpleTool("subscriptions_pricing_summary", "Summarize current and scheduled subscription pricing for a territory", ["subscription_id": "Subscription ID", "territory_id": "Territory ID"], ["subscription_id", "territory_id"]),
            simpleTool("subscriptions_prepare_offer_prices", "Find subscription price point candidates for offer creation", ["subscription_id": "Subscription ID", "territory_id": "Territory ID", "mode": "Offer mode", "customer_price": "Optional customer price to match"], ["subscription_id", "territory_id", "mode"]),
            simpleTool("subscriptions_list_intro_offers", "List introductory offers", ["subscription_id": "Subscription ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["subscription_id"]),
            simpleTool("subscriptions_create_intro_offer", "Create an introductory offer", ["subscription_id": "Subscription ID", "duration": "Offer duration", "offer_mode": "Offer mode", "number_of_periods": "Number of periods", "territory_id": "Territory ID", "price_point_id": "Price point ID for paid modes"], ["subscription_id", "duration", "offer_mode", "number_of_periods"]),
            simpleTool("subscriptions_update_intro_offer", "Update an introductory offer", ["intro_offer_id": "Introductory offer ID", "end_date": "End date"], ["intro_offer_id"]),
            simpleTool("subscriptions_delete_intro_offer", "Delete an introductory offer", ["intro_offer_id": "Introductory offer ID"], ["intro_offer_id"]),
            simpleTool("subscriptions_list_promotional_offers", "List promotional offers", ["subscription_id": "Subscription ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["subscription_id"]),
            simpleTool("subscriptions_get_promotional_offer", "Get a promotional offer", ["promotional_offer_id": "Promotional offer ID"], ["promotional_offer_id"]),
            simpleTool("subscriptions_create_promotional_offer", "Create a promotional offer", ["subscription_id": "Subscription ID", "name": "Reference name", "offer_code": "Offer code", "duration": "Duration", "offer_mode": "Offer mode", "number_of_periods": "Number of periods", "territory_ids": "Array of territory IDs", "price_point_ids": "Array of price point IDs for paid modes", "target_subscription_plan_type": "Optional target subscription plan type"], ["subscription_id", "name", "offer_code", "duration", "offer_mode", "number_of_periods", "territory_ids"]),
            simpleTool("subscriptions_update_promotional_offer", "Update promotional offer prices", ["promotional_offer_id": "Promotional offer ID", "territory_ids": "Array of territory IDs", "price_point_ids": "Array of price point IDs for paid offers; omit for free trials"], ["promotional_offer_id", "territory_ids"]),
            simpleTool("subscriptions_delete_promotional_offer", "Delete a promotional offer", ["promotional_offer_id": "Promotional offer ID"], ["promotional_offer_id"]),
            simpleTool("subscriptions_list_promotional_offer_prices", "List promotional offer prices", ["promotional_offer_id": "Promotional offer ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["promotional_offer_id"]),
            simpleTool("subscriptions_list_offer_codes", "List subscription offer codes", ["subscription_id": "Subscription ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["subscription_id"]),
            simpleTool("subscriptions_get_offer_code", "Get a subscription offer code", ["offer_code_id": "Offer code ID"], ["offer_code_id"]),
            simpleTool("subscriptions_create_offer_code", "Create a subscription offer code", ["subscription_id": "Subscription ID", "name": "Name", "customer_eligibilities": "One or more customer eligibility values", "offer_eligibility": "Introductory-offer stacking eligibility", "offer_mode": "Offer mode", "duration": "Duration", "number_of_periods": "Number of periods", "territory_ids": "Territory IDs", "price_point_ids": "Price point IDs for paid modes", "auto_renew_enabled": "Whether the subscription renews after the offer. false requires FREE_TRIAL and REPLACE_INTRO_OFFERS", "target_subscription_plan_type": "Optional target subscription plan type"], ["subscription_id", "name", "customer_eligibilities", "offer_eligibility", "offer_mode", "duration", "number_of_periods", "territory_ids"]),
            simpleTool("subscriptions_update_offer_code", "Update an offer code", ["offer_code_id": "Offer code ID", "active": "Whether active"], ["offer_code_id"]),
            simpleTool("subscriptions_deactivate_offer_code", "Deactivate an offer code", ["offer_code_id": "Offer code ID"], ["offer_code_id"]),
            simpleTool("subscriptions_list_offer_code_prices", "List offer code prices", ["offer_code_id": "Offer code ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["offer_code_id"]),
            simpleTool("subscriptions_generate_one_time_codes", "Generate one-time offer codes", ["offer_code_id": "Offer code ID", "number_of_codes": "Number of codes", "expiration_date": "Expiration date", "environment": "Optional environment"], ["offer_code_id", "number_of_codes", "expiration_date"]),
            simpleTool("subscriptions_list_one_time_codes", "List one-time offer codes", ["offer_code_id": "Offer code ID", "limit": "Max results", "next_url": "Pagination URL"], ["offer_code_id"]),
            simpleTool("subscriptions_get_one_time_code", "Get one-time offer code batch", ["one_time_code_id": "One-time code resource ID"], ["one_time_code_id"]),
            simpleTool("subscriptions_get_one_time_code_values", "Get generated one-time code values", ["one_time_code_id": "One-time code resource ID"], ["one_time_code_id"]),
            simpleTool("subscriptions_create_custom_code", "Create a custom offer code", ["offer_code_id": "Offer code ID", "custom_code": "Custom code", "number_of_codes": "Number of codes", "expiration_date": "Expiration date"], ["offer_code_id", "custom_code", "number_of_codes"]),
            simpleTool("subscriptions_get_custom_code", "Get custom offer code details", ["custom_code_id": "Custom code ID"], ["custom_code_id"]),
            simpleTool("subscriptions_update_custom_code", "Update custom offer code", ["custom_code_id": "Custom code ID", "active": "Whether active"], ["custom_code_id"]),
            simpleTool("subscriptions_deactivate_custom_code", "Deactivate custom offer code", ["custom_code_id": "Custom code ID"], ["custom_code_id"]),
            simpleTool("subscriptions_list_winback_offers", "List win-back offers", ["subscription_id": "Subscription ID", "limit": "Max results", "next_url": "Pagination URL"], ["subscription_id"]),
            simpleTool("subscriptions_get_winback_offer", "Get a win-back offer", ["winback_offer_id": "Win-back offer ID"], ["winback_offer_id"]),
            simpleTool("subscriptions_create_winback_offer", "Create a win-back offer", ["subscription_id": "Subscription ID", "reference_name": "Reference name", "offer_id": "Offer ID", "duration": "Duration", "offer_mode": "Offer mode", "period_count": "Period count", "priority": "Offer priority", "promotion_intent": "Optional promotion intent", "eligibility_duration_months": "Minimum paid subscription duration in months", "eligibility_time_since_last_months_min": "Optional minimum months since last subscription", "eligibility_time_since_last_months_max": "Optional maximum months since last subscription", "eligibility_wait_between_months": "Optional months to wait between offers", "start_date": "Start date", "end_date": "Optional end date", "territory_ids": "Optional compatibility labels matched to price_point_ids; not sent to Apple", "price_point_ids": "Subscription price point IDs whose encoded territories define offer availability", "target_subscription_plan_type": "Optional target subscription plan type"], ["subscription_id", "reference_name", "offer_id", "duration", "offer_mode", "period_count", "priority", "eligibility_duration_months", "start_date", "price_point_ids"]),
            simpleTool("subscriptions_update_winback_offer", "Update or clear mutable win-back offer attributes", ["winback_offer_id": "Win-back offer ID", "eligibility_duration_months": "Minimum paid subscription duration in months; pass null to clear", "eligibility_time_since_last_months_min": "Minimum months since last subscription; provide independently, or pass null to clear the whole range", "eligibility_time_since_last_months_max": "Maximum months since last subscription; provide independently, or pass null to clear the whole range", "eligibility_wait_between_months": "Months to wait between offers; pass null to clear", "start_date": "Start date; pass null to clear", "end_date": "End date; pass null to clear", "priority": "Offer priority; pass null to clear", "promotion_intent": "Promotion intent; pass null to clear"], ["winback_offer_id"]),
            simpleTool("subscriptions_delete_winback_offer", "Delete a win-back offer", ["winback_offer_id": "Win-back offer ID"], ["winback_offer_id"]),
            simpleTool("subscriptions_list_winback_offer_prices", "List win-back offer prices", ["winback_offer_id": "Win-back offer ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["winback_offer_id"])
        ]
    }

    private func simpleTool(_ name: String, _ description: String, _ properties: [String: String], _ required: [String]) -> Tool {
        Tool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(Dictionary(uniqueKeysWithValues: properties.map { key, fieldDescription in
                    (key, propertySchema(toolName: name, key: key, description: fieldDescription))
                })),
                "required": .array(required.map { .string($0) })
            ])
        )
    }

    private func propertySchema(toolName: String, key: String, description: String) -> Value {
        let baseType = key.hasSuffix("_ids") || key == "customer_eligibilities"
            ? "array"
            : (key == "limit" || key == "number_of_periods" || key == "number_of_codes" || key == "period_count" || key.hasSuffix("_months") || key.hasSuffix("_months_min") || key.hasSuffix("_months_max")
                ? "integer"
                : (key == "active" || key == "available_in_new_territories" || key == "auto_renew_enabled" ? "boolean" : "string"))
        let nullableWinBackFields: Set<String> = [
            "eligibility_duration_months",
            "eligibility_time_since_last_months_min",
            "eligibility_time_since_last_months_max",
            "eligibility_wait_between_months",
            "start_date",
            "end_date",
            "priority",
            "promotion_intent"
        ]
        let isNullable = toolName == "subscriptions_update_winback_offer" && nullableWinBackFields.contains(key)
        var schema: [String: Value] = [
            "type": isNullable ? .array([.string(baseType), .string("null")]) : .string(baseType),
            "description": .string(description)
        ]

        if baseType == "array" {
            var itemSchema: [String: Value] = ["type": .string("string"), "minLength": .int(1)]
            if key == "customer_eligibilities" {
                itemSchema["enum"] = .array(["NEW", "EXISTING", "EXPIRED"].map(Value.string))
                schema["minItems"] = .int(1)
                schema["uniqueItems"] = .bool(true)
            } else if [
                "subscriptions_create_promotional_offer",
                "subscriptions_update_promotional_offer",
                "subscriptions_create_offer_code",
                "subscriptions_create_winback_offer"
            ].contains(toolName) {
                schema["minItems"] = .int(1)
                schema["uniqueItems"] = .bool(true)
            }
            schema["items"] = .object(itemSchema)
        }

        let stringEnums: [String: [String]] = [
            "offer_eligibility": ["STACK_WITH_INTRO_OFFERS", "REPLACE_INTRO_OFFERS"],
            "offer_mode": ["PAY_AS_YOU_GO", "PAY_UP_FRONT", "FREE_TRIAL"],
            "mode": ["PAY_AS_YOU_GO", "PAY_UP_FRONT", "FREE_TRIAL"],
            "duration": ["THREE_DAYS", "ONE_WEEK", "TWO_WEEKS", "ONE_MONTH", "TWO_MONTHS", "THREE_MONTHS", "SIX_MONTHS", "ONE_YEAR"],
            "target_subscription_plan_type": ["MONTHLY", "UPFRONT"],
            "priority": ["HIGH", "NORMAL"],
            "promotion_intent": ["NOT_PROMOTED", "USE_AUTO_GENERATED_ASSETS"],
            "environment": ["PRODUCTION", "SANDBOX"]
        ]
        if let values = stringEnums[key] {
            var enumValues = values.map(Value.string)
            if isNullable {
                enumValues.append(.null)
            }
            schema["enum"] = .array(enumValues)
        }

        if key == "eligibility_duration_months" {
            var values = (Array(1...24) + [36, 48, 60]).map(Value.int)
            if isNullable {
                values.append(.null)
            }
            schema["enum"] = .array(values)
        }
        if key == "eligibility_wait_between_months" {
            schema["minimum"] = .int(2)
            schema["maximum"] = .int(24)
        } else if key.hasSuffix("_months_min") || key.hasSuffix("_months_max") {
            schema["minimum"] = .int(0)
        } else if ["number_of_periods", "number_of_codes", "period_count"].contains(key) {
            schema["minimum"] = .int(1)
        }
        if key.hasSuffix("_date") {
            schema["format"] = .string("date")
        }
        if baseType == "string", (key.hasSuffix("_id") || ["name", "reference_name", "offer_id", "offer_code", "custom_code"].contains(key)) {
            schema["minLength"] = .int(1)
        }

        return .object(schema)
    }
}
