import MCP

extension SubscriptionsWorker {
    func versionedMetadataTools() -> [Tool] {
        [
            subscriptionVersionedTool(
                name: "subscriptions_create_version",
                description: "Create a discrete metadata version for a subscription",
                properties: [
                    "subscription_id": subscriptionVersionedIdentifier("Subscription ID")
                ],
                required: ["subscription_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_get_version",
                description: "Get a subscription metadata version and its review state",
                properties: [
                    "version_id": subscriptionVersionedIdentifier("Subscription version ID")
                ],
                required: ["version_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_list_versions",
                description: "List discrete metadata versions for a subscription",
                properties: subscriptionVersionListProperties(parentField: "subscription_id", parentDescription: "Subscription ID"),
                required: ["subscription_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_list_version_localizations",
                description: "List localizations owned by a subscription version",
                properties: subscriptionVersionedListProperties(
                    idField: "version_id",
                    idDescription: "Subscription version ID"
                ),
                required: ["version_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_create_version_localization",
                description: "Create a localization for a subscription version",
                properties: [
                    "version_id": subscriptionVersionedIdentifier("Subscription version ID"),
                    "locale": subscriptionVersionedLocale(),
                    "name": subscriptionVersionedString("Localized display name"),
                    "description": subscriptionVersionedNullableString("Localized description; pass null to clear Apple's nullable value")
                ],
                required: ["version_id", "locale", "name"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_get_version_localization",
                description: "Get a localization owned by a subscription version",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Version localization ID")
                ],
                required: ["localization_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_update_version_localization",
                description: "Update nullable text on a subscription version localization",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Version localization ID"),
                    "name": subscriptionVersionedNullableString("Localized display name; pass null to clear Apple's nullable value"),
                    "description": subscriptionVersionedNullableString("Localized description; pass null to clear Apple's nullable value")
                ],
                required: ["localization_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_delete_version_localization",
                description: "Delete a subscription version localization after exact localization-ID confirmation",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Version localization ID"),
                    "confirm_localization_id": subscriptionVersionedIdentifier("Repeat the exact version localization ID to confirm deletion")
                ],
                required: ["localization_id", "confirm_localization_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_list_version_images",
                description: "List promotional images owned by a subscription version",
                properties: subscriptionVersionedListProperties(
                    idField: "version_id",
                    idDescription: "Subscription version ID"
                ),
                required: ["version_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_upload_version_image",
                description: "Upload an immutable promotional image snapshot to a subscription version, commit it, and reconcile Apple processing",
                properties: [
                    "version_id": subscriptionVersionedIdentifier("Subscription version ID"),
                    "file_path": subscriptionVersionedAbsoluteImagePath()
                ],
                required: ["version_id", "file_path"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_get_version_image",
                description: "Get a version-scoped subscription image by resource ID",
                properties: [
                    "image_id": subscriptionVersionedIdentifier("Version image resource ID")
                ],
                required: ["image_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_delete_version_image",
                description: "Delete a version-scoped subscription image after exact image-ID confirmation",
                properties: [
                    "image_id": subscriptionVersionedIdentifier("Version image resource ID"),
                    "confirm_image_id": subscriptionVersionedIdentifier("Repeat the exact version image resource ID to confirm deletion")
                ],
                required: ["image_id", "confirm_image_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_create_group_version",
                description: "Create a discrete metadata version for a subscription group",
                properties: [
                    "group_id": subscriptionVersionedIdentifier("Subscription group ID")
                ],
                required: ["group_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_get_group_version",
                description: "Get a subscription group metadata version and its review state",
                properties: [
                    "version_id": subscriptionVersionedIdentifier("Subscription group version ID")
                ],
                required: ["version_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_list_group_versions",
                description: "List discrete metadata versions for a subscription group",
                properties: subscriptionVersionListProperties(parentField: "group_id", parentDescription: "Subscription group ID"),
                required: ["group_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_list_group_version_localizations",
                description: "List localizations owned by a subscription group version",
                properties: subscriptionVersionedListProperties(
                    idField: "version_id",
                    idDescription: "Subscription group version ID"
                ),
                required: ["version_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_create_group_version_localization",
                description: "Create a localization for a subscription group version",
                properties: [
                    "version_id": subscriptionVersionedIdentifier("Subscription group version ID"),
                    "locale": subscriptionVersionedLocale(),
                    "name": subscriptionVersionedString("Localized group display name"),
                    "custom_app_name": subscriptionVersionedNullableString("Custom app name; pass null to clear Apple's nullable value")
                ],
                required: ["version_id", "locale", "name"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_get_group_version_localization",
                description: "Get a localization owned by a subscription group version",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Group version localization ID")
                ],
                required: ["localization_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_update_group_version_localization",
                description: "Update nullable text on a subscription group version localization",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Group version localization ID"),
                    "name": subscriptionVersionedNullableString("Localized group display name; pass null to clear Apple's nullable value"),
                    "custom_app_name": subscriptionVersionedNullableString("Custom app name; pass null to clear Apple's nullable value")
                ],
                required: ["localization_id"]
            ),
            subscriptionVersionedTool(
                name: "subscriptions_delete_group_version_localization",
                description: "Delete a subscription group version localization after exact localization-ID confirmation",
                properties: [
                    "localization_id": subscriptionVersionedIdentifier("Group version localization ID"),
                    "confirm_localization_id": subscriptionVersionedIdentifier("Repeat the exact group version localization ID to confirm deletion")
                ],
                required: ["localization_id", "confirm_localization_id"]
            )
        ]
    }

    private func subscriptionVersionListProperties(
        parentField: String,
        parentDescription: String
    ) -> [String: Value] {
        [
            parentField: subscriptionVersionedIdentifier(parentDescription),
            "filter_state": subscriptionVersionStateListSchema(),
            "limit": subscriptionVersionedLimit(),
            "next_url": subscriptionVersionedNextURL(
                "Validated uri-reference from the preceding response; repeat the exact \(parentField), filter_state (including omission), and effective limit (default 25)"
            )
        ]
    }

    private func subscriptionVersionedListProperties(
        idField: String,
        idDescription: String
    ) -> [String: Value] {
        [
            idField: subscriptionVersionedIdentifier(idDescription),
            "limit": subscriptionVersionedLimit(),
            "next_url": subscriptionVersionedNextURL(
                "Validated uri-reference from the preceding response; repeat the exact \(idField) and effective limit (default 25)"
            )
        ]
    }

    private func subscriptionVersionedTool(
        name: String,
        description: String,
        properties: [String: Value],
        required: [String]
    ) -> Tool {
        Tool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(Value.string)),
                "additionalProperties": .bool(false)
            ])
        )
    }

    private func subscriptionVersionedString(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "description": .string(description)
        ])
    }

    private func subscriptionVersionedIdentifier(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string("\(description); canonical App Store Connect resource ID")
        ])
    }

    private func subscriptionVersionedAbsoluteImagePath() -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^/"#),
            "description": .string(
                "Absolute path to Apple's required flattened 1024x1024 JPG or PNG image in RGB at 72 dpi"
            )
        ])
    }

    private func subscriptionVersionedNullableString(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func subscriptionVersionedLocale() -> Value {
        .object([
            "type": .string("string"),
            "pattern": .string(#"^[a-z]{2,3}(-([A-Z]{2}|[A-Z][a-z]{3}))?$"#),
            "description": .string("Localization locale such as en-US, ru-RU, ja, or zh-Hans")
        ])
    }

    private func subscriptionVersionedLimit() -> Value {
        .object([
            "type": .string("integer"),
            "description": .string("Maximum results per page"),
            "minimum": .int(1),
            "maximum": .int(200),
            "default": .int(25)
        ])
    }

    private func subscriptionVersionedNextURL(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "description": .string(description)
        ])
    }

    private func subscriptionVersionStateListSchema() -> Value {
        let values = Self.subscriptionVersionStates.map(Value.string)
        return .object([
            "description": .string("Filter by one or more exact version review states"),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(values)
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values)
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
