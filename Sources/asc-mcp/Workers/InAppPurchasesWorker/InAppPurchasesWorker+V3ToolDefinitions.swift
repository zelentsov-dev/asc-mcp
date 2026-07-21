import Foundation
import MCP

extension InAppPurchasesWorker {
    func v3CommerceTools() -> [Tool] {
        [
            iapSimpleTool("iap_list_price_point_equalizations", "List IAP price point equalizations", ["price_point_id": "IAP price point ID", "iap_id": "Optional IAP ID filter", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["price_point_id"]),
            iapSimpleTool("iap_pricing_summary", "Summarize current and scheduled IAP prices for one territory", ["iap_id": "In-app purchase ID", "territory_id": "Territory ID"], ["iap_id", "territory_id"]),
            iapSimpleTool("iap_prepare_offer_prices", "Find IAP price point candidates for offer-code creation", ["iap_id": "In-app purchase ID", "territory_id": "Territory ID", "customer_price": "Optional exact customer price"], ["iap_id", "territory_id"]),
            iapSimpleTool("iap_inventory", "List AI-friendly IAP inventory for an app", ["app_id": "App Store Connect app ID", "filter_name": "Filter by one or more exact reference names", "filter_product_id": "Filter by one or more exact product identifiers", "filter_state": "Filter by one or more App Store states", "filter_type": "Filter by one or more in-app purchase types", "sort": "Sort by reference name or in-app purchase type; prefix with - for descending order", "limit": "Max results", "next_url": "Pagination URL"], ["app_id"]),
            iapSimpleTool("iap_get_promoted_purchase", "Get promoted purchase state for an IAP", ["iap_id": "In-app purchase ID"], ["iap_id"]),
            iapSimpleTool("iap_list_available_territories", "List territories for an IAP availability resource", ["availability_id": "IAP availability ID", "limit": "Max results", "next_url": "Pagination URL"], ["availability_id"]),
            iapSimpleTool("iap_list_offer_codes", "List IAP offer codes", ["iap_id": "In-app purchase ID", "limit": "Max results", "next_url": "Pagination URL"], ["iap_id"]),
            iapSimpleTool("iap_get_offer_code", "Get an IAP offer code", ["offer_code_id": "IAP offer code ID"], ["offer_code_id"]),
            iapSimpleTool("iap_create_offer_code", "Create an IAP offer code", ["iap_id": "In-app purchase ID", "name": "Offer code name", "customer_eligibilities": "Array of NON_SPENDER, ACTIVE_SPENDER, CHURNED_SPENDER", "territory_ids": "Array of territory IDs", "price_point_ids": "Array of IAP price point IDs"], ["iap_id", "name", "customer_eligibilities", "territory_ids", "price_point_ids"]),
            iapSimpleTool("iap_update_offer_code", "Update or clear an IAP offer code active state", ["offer_code_id": "IAP offer code ID", "active": "Whether active, or null to clear"], ["offer_code_id", "active"]),
            iapSimpleTool("iap_deactivate_offer_code", "Deactivate an IAP offer code", ["offer_code_id": "IAP offer code ID"], ["offer_code_id"]),
            iapSimpleTool("iap_list_offer_code_prices", "List IAP offer code prices", ["offer_code_id": "IAP offer code ID", "territory_id": "Optional territory filter", "limit": "Max results", "next_url": "Pagination URL"], ["offer_code_id"]),
            iapSimpleTool("iap_generate_one_time_codes", "Generate one-time IAP offer codes", ["offer_code_id": "IAP offer code ID", "number_of_codes": "Number of codes", "expiration_date": "Expiration date", "environment": "Optional environment"], ["offer_code_id", "number_of_codes", "expiration_date"]),
            iapSimpleTool("iap_list_one_time_codes", "List one-time IAP offer code batches", ["offer_code_id": "IAP offer code ID", "limit": "Max results", "next_url": "Pagination URL"], ["offer_code_id"]),
            iapSimpleTool("iap_get_one_time_code", "Get one-time IAP offer code batch", ["one_time_code_id": "One-time code resource ID"], ["one_time_code_id"]),
            iapSimpleTool("iap_update_one_time_code", "Update or clear a one-time IAP offer code batch active state", ["one_time_code_id": "One-time code resource ID", "active": "Whether active, or null to clear"], ["one_time_code_id", "active"]),
            iapSimpleTool("iap_deactivate_one_time_code", "Deactivate one-time IAP offer code batch", ["one_time_code_id": "One-time code resource ID"], ["one_time_code_id"]),
            iapSimpleTool("iap_get_one_time_code_values", "Get generated one-time IAP offer code values as lossless CSV", ["one_time_code_id": "One-time code resource ID"], ["one_time_code_id"]),
            iapSimpleTool("iap_create_custom_code", "Create a custom IAP offer code", ["offer_code_id": "IAP offer code ID", "custom_code": "Custom code", "number_of_codes": "Number of codes", "expiration_date": "Optional expiration date"], ["offer_code_id", "custom_code", "number_of_codes"]),
            iapSimpleTool("iap_get_custom_code", "Get custom IAP offer code", ["custom_code_id": "Custom code ID"], ["custom_code_id"]),
            iapSimpleTool("iap_update_custom_code", "Update or clear a custom IAP offer code active state", ["custom_code_id": "Custom code ID", "active": "Whether active, or null to clear"], ["custom_code_id", "active"]),
            iapSimpleTool("iap_deactivate_custom_code", "Deactivate custom IAP offer code", ["custom_code_id": "Custom code ID"], ["custom_code_id"])
        ]
    }

    private func iapSimpleTool(_ name: String, _ description: String, _ properties: [String: String], _ required: [String]) -> Tool {
        let schemaProperties = Dictionary(uniqueKeysWithValues: properties.map { key, description in
            if key == "filter_name" || key == "filter_product_id" {
                return (key, iapStringListSchema(description))
            }
            if key == "filter_state" {
                return (key, iapEnumListSchema(description, values: Self.iapCatalogStates))
            }
            if key == "filter_type" {
                return (key, iapEnumListSchema(description, values: Self.iapCatalogTypes))
            }
            if key == "sort" {
                return (key, iapEnumListSchema(description, values: Self.iapCatalogSortValues))
            }
            let type: String
            if key.hasSuffix("_ids") || key == "customer_eligibilities" {
                type = "array"
            } else if key == "limit" || key == "number_of_codes" {
                type = "integer"
            } else if key == "active" {
                type = "boolean"
            } else {
                type = "string"
            }
            var property: [String: Value] = [
                "type": .string(type),
                "description": .string(description)
            ]
            if key == "limit" {
                property["minimum"] = .int(1)
                property["maximum"] = .int(name == "iap_list_price_point_equalizations" ? 8000 : 200)
            }
            if type == "array" {
                var items: [String: Value] = ["type": .string("string")]
                if key == "customer_eligibilities" {
                    items["enum"] = .array([
                        .string("NON_SPENDER"),
                        .string("ACTIVE_SPENDER"),
                        .string("CHURNED_SPENDER")
                    ])
                    property["minItems"] = .int(1)
                    property["uniqueItems"] = .bool(true)
                }
                property["items"] = .object(items)
            }
            if key == "active", [
                "iap_update_offer_code",
                "iap_update_one_time_code",
                "iap_update_custom_code"
            ].contains(name) {
                property["type"] = .array([.string("boolean"), .string("null")])
            }
            if name == "iap_generate_one_time_codes", key == "environment" {
                property["type"] = .array([.string("string"), .string("null")])
                property["enum"] = .array([.string("PRODUCTION"), .string("SANDBOX"), .null])
            }
            return (key, Value.object(property))
        })

        return Tool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(schemaProperties),
                "required": .array(required.map(Value.string))
            ])
        )
    }
}
