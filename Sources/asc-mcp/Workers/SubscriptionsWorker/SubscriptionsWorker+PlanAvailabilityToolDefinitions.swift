import MCP

extension SubscriptionsWorker {
    func subscriptionPlanAvailabilityTools() -> [Tool] {
        [
            createSubscriptionPlanAvailabilityTool(),
            getSubscriptionPlanAvailabilityTool(),
            updateSubscriptionPlanAvailabilityTool(),
            listSubscriptionPlanAvailabilitiesTool(),
            listSubscriptionPlanAvailabilityTerritoriesTool(),
            listSubscriptionPricePointAdjustedEqualizationsTool()
        ]
    }

    private func createSubscriptionPlanAvailabilityTool() -> Tool {
        Tool(
            name: "subscriptions_create_plan_availability",
            description: "Create MONTHLY or UPFRONT territory availability for a subscription",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "subscription_id": subscriptionPlanIdentifierSchema("Subscription ID"),
                    "plan_type": subscriptionPlanTypeSchema("Subscription plan type"),
                    "territory_ids": subscriptionPlanTerritoryIDsSchema("Territories available for this plan"),
                    "available_in_new_territories": subscriptionPlanNullableBoolSchema("Whether Apple automatically adds newly supported territories; omit to use Apple's default or pass null to clear")
                ]),
                "required": .array([
                    .string("subscription_id"),
                    .string("plan_type"),
                    .string("territory_ids")
                ])
            ])
        )
    }

    private func getSubscriptionPlanAvailabilityTool() -> Tool {
        Tool(
            name: "subscriptions_get_plan_availability",
            description: "Get one plan-type-aware subscription availability and up to 50 related territories",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "plan_availability_id": subscriptionPlanIdentifierSchema("Subscription plan availability ID")
                ]),
                "required": .array([.string("plan_availability_id")])
            ])
        )
    }

    private func updateSubscriptionPlanAvailabilityTool() -> Tool {
        Tool(
            name: "subscriptions_update_plan_availability",
            description: "Update automatic territory enrollment, available territories, or both for a subscription plan availability",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "minProperties": .int(2),
                "properties": .object([
                    "plan_availability_id": subscriptionPlanIdentifierSchema("Subscription plan availability ID"),
                    "available_in_new_territories": subscriptionPlanNullableBoolSchema("Whether Apple automatically adds newly supported territories; pass null to clear"),
                    "territory_ids": subscriptionPlanTerritoryIDsSchema("Complete replacement set of available territory IDs; an empty array removes all territories")
                ]),
                "required": .array([.string("plan_availability_id")])
            ])
        )
    }

    private func listSubscriptionPlanAvailabilitiesTool() -> Tool {
        Tool(
            name: "subscriptions_list_plan_availabilities",
            description: "List MONTHLY and UPFRONT availability resources for a subscription",
            inputSchema: subscriptionPlanListSchema(
                idField: "subscription_id",
                idDescription: "Subscription ID",
                maximum: 200
            )
        )
    }

    private func listSubscriptionPlanAvailabilityTerritoriesTool() -> Tool {
        Tool(
            name: "subscriptions_list_plan_availability_territories",
            description: "List all territories attached to a subscription plan availability",
            inputSchema: subscriptionPlanListSchema(
                idField: "plan_availability_id",
                idDescription: "Subscription plan availability ID",
                maximum: 200
            )
        )
    }

    private func listSubscriptionPricePointAdjustedEqualizationsTool() -> Tool {
        Tool(
            name: "subscriptions_list_price_point_adjusted_equalizations",
            description: "List Apple-adjusted territory equalizations for a subscription price point",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "price_point_id": subscriptionPlanIdentifierSchema("Subscription price point ID"),
                    "territory_ids": subscriptionPlanIdentifierListSchema("Filter by one or more territory IDs"),
                    "subscription_ids": subscriptionPlanIdentifierListSchema("Filter by one or more subscription IDs"),
                    "upfront_price_point_ids": subscriptionPlanIdentifierListSchema("Filter by one or more upfront price point IDs"),
                    "plan_types": subscriptionEnumListSchema(
                        "Filter by one or more Apple subscription plan types",
                        values: ASCSubscriptionPlanType.allCases.map(\.rawValue)
                    ),
                    "limit": subscriptionPlanLimitSchema(maximum: 8000),
                    "next_url": subscriptionPlanNextURLSchema()
                ]),
                "required": .array([.string("price_point_id")])
            ])
        )
    }

    private func subscriptionPlanListSchema(
        idField: String,
        idDescription: String,
        maximum: Int
    ) -> Value {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                idField: subscriptionPlanIdentifierSchema(idDescription),
                "limit": subscriptionPlanLimitSchema(maximum: maximum),
                "next_url": subscriptionPlanNextURLSchema()
            ]),
            "required": .array([.string(idField)])
        ])
    }

    private func subscriptionPlanIdentifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string("\(description); canonical App Store Connect resource ID")
        ])
    }

    private func subscriptionPlanTypeSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "enum": .array(ASCSubscriptionPlanType.allCases.map { .string($0.rawValue) }),
            "description": .string(description)
        ])
    }

    private func subscriptionPlanTerritoryIDsSchema(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
                "minLength": .int(1),
                "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
            ]),
            "uniqueItems": .bool(true),
            "description": .string(description)
        ])
    }

    private func subscriptionPlanIdentifierListSchema(_ description: String) -> Value {
        let identifier = Value.object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
        return .object([
            "description": .string("\(description); canonical IDs cannot contain commas"),
            "oneOf": .array([
                identifier,
                .object([
                    "type": .string("array"),
                    "items": identifier,
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func subscriptionPlanNullableBoolSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func subscriptionPlanLimitSchema(maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "minimum": .int(1),
            "maximum": .int(maximum),
            "default": .int(25),
            "description": .string("Maximum resources returned by Apple per page")
        ])
    }

    private func subscriptionPlanNextURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "description": .string("Validated uri-reference from the preceding response; repeat the exact originating parent ID, every original filter (including omission), and effective limit (default 25)")
        ])
    }
}
