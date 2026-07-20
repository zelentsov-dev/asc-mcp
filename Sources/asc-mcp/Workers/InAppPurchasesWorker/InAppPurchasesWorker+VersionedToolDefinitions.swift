import MCP

extension InAppPurchasesWorker {
    func versionedCommerceTools() -> [Tool] {
        [
            iapVersionedTool(
                name: "iap_create_version",
                description: "Create a reviewable version for an in-app purchase",
                properties: [
                    "iap_id": iapVersionedIdentifier("In-app purchase ID")
                ],
                required: ["iap_id"]
            ),
            iapVersionedTool(
                name: "iap_get_version",
                description: "Get an in-app purchase version and its review state",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID")
                ],
                required: ["version_id"]
            ),
            iapVersionedTool(
                name: "iap_list_versions",
                description: "List reviewable versions for an in-app purchase",
                properties: [
                    "iap_id": iapVersionedIdentifier("In-app purchase ID"),
                    "filter_state": iapVersionStateListSchema(),
                    "limit": iapVersionedLimit(maximum: 200),
                    "next_url": iapVersionedNextURL("Pagination URL returned by the previous response; repeat the same filter_state and effective limit, including the default limit of 25")
                ],
                required: ["iap_id"]
            ),
            iapVersionedTool(
                name: "iap_list_version_localizations",
                description: "List localizations owned by an in-app purchase version",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID"),
                    "limit": iapVersionedLimit(maximum: 200),
                    "next_url": iapVersionedNextURL("Pagination URL returned by the previous response; repeat the same effective limit, including the default limit of 25")
                ],
                required: ["version_id"]
            ),
            iapVersionedTool(
                name: "iap_create_version_localization",
                description: "Create a localization for an in-app purchase version",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID"),
                    "locale": iapVersionedLocale(),
                    "name": iapVersionedString("Localized display name", minLength: 2, maxLength: 30),
                    "description": iapNullableVersionedString("Localized description; pass null to clear Apple's nullable value", maxLength: 45)
                ],
                required: ["version_id", "locale", "name"]
            ),
            iapVersionedTool(
                name: "iap_get_version_localization",
                description: "Get a localization owned by an in-app purchase version",
                properties: [
                    "localization_id": iapVersionedIdentifier("Version localization ID")
                ],
                required: ["localization_id"]
            ),
            iapVersionedTool(
                name: "iap_update_version_localization",
                description: "Update nullable text on an in-app purchase version localization",
                properties: [
                    "localization_id": iapVersionedIdentifier("Version localization ID"),
                    "name": iapNullableVersionedString("Localized display name; pass null to clear Apple's nullable value", minLength: 2, maxLength: 30),
                    "description": iapNullableVersionedString("Localized description; pass null to clear Apple's nullable value", maxLength: 45)
                ],
                required: ["localization_id"],
                anyOfRequired: [["name"], ["description"]]
            ),
            iapVersionedTool(
                name: "iap_delete_version_localization",
                description: "Irreversibly delete an in-app purchase version localization after exact resource-ID confirmation",
                properties: [
                    "localization_id": iapVersionedIdentifier("Version localization ID"),
                    "confirm_localization_id": iapVersionedIdentifier("Must exactly match localization_id")
                ],
                required: ["localization_id", "confirm_localization_id"]
            ),
            iapVersionedTool(
                name: "iap_get_version_image",
                description: "Get the singular image related to an in-app purchase version",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID")
                ],
                required: ["version_id"]
            ),
            iapVersionedTool(
                name: "iap_list_version_images",
                description: "List all review images owned by an in-app purchase version",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID"),
                    "limit": iapVersionedLimit(maximum: 200),
                    "next_url": iapVersionedNextURL("Pagination URL returned by the previous response; repeat the same effective limit, including the default limit of 25")
                ],
                required: ["version_id"]
            ),
            iapVersionedTool(
                name: "iap_upload_version_image",
                description: "Upload an immutable image snapshot to an in-app purchase version, commit it, and reconcile Apple processing",
                properties: [
                    "version_id": iapVersionedIdentifier("In-app purchase version ID"),
                    "file_path": iapVersionedAbsoluteFilePath()
                ],
                required: ["version_id", "file_path"]
            ),
            iapVersionedTool(
                name: "iap_get_version_image_resource",
                description: "Get a version-scoped in-app purchase image by resource ID",
                properties: [
                    "image_id": iapVersionedIdentifier("Version image resource ID")
                ],
                required: ["image_id"]
            ),
            iapVersionedTool(
                name: "iap_delete_version_image",
                description: "Irreversibly delete a version-scoped in-app purchase image after exact resource-ID confirmation",
                properties: [
                    "image_id": iapVersionedIdentifier("Version image resource ID"),
                    "confirm_image_id": iapVersionedIdentifier("Must exactly match image_id")
                ],
                required: ["image_id", "confirm_image_id"]
            )
        ]
    }

    private func iapVersionedTool(
        name: String,
        description: String,
        properties: [String: Value],
        required: [String],
        anyOfRequired: [[String]] = []
    ) -> Tool {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string)),
            "additionalProperties": .bool(false)
        ]
        if !anyOfRequired.isEmpty {
            schema["anyOf"] = .array(anyOfRequired.map { fields in
                .object(["required": .array(fields.map(Value.string))])
            })
        }
        return Tool(
            name: name,
            description: description,
            inputSchema: .object(schema)
        )
    }

    private func iapVersionedString(
        _ description: String,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        format: String? = nil
    ) -> Value {
        var schema: [String: Value] = [
            "type": .string("string"),
            "description": .string(description)
        ]
        if let minLength { schema["minLength"] = .int(minLength) }
        if let maxLength { schema["maxLength"] = .int(maxLength) }
        if let pattern { schema["pattern"] = .string(pattern) }
        if let format { schema["format"] = .string(format) }
        return .object(schema)
    }

    private func iapNullableVersionedString(
        _ description: String,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) -> Value {
        var schema: [String: Value] = [
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description)
        ]
        if let minLength { schema["minLength"] = .int(minLength) }
        if let maxLength { schema["maxLength"] = .int(maxLength) }
        return .object(schema)
    }

    private func iapVersionedIdentifier(_ description: String) -> Value {
        iapVersionedString(
            description,
            minLength: 1,
            pattern: #"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#
        )
    }

    private func iapVersionedLocale() -> Value {
        iapVersionedString(
            "Localization locale",
            minLength: 2,
            pattern: #"^[a-z]{2,3}(-([A-Z]{2}|[A-Z][a-z]{3}))?$"#
        )
    }

    private func iapVersionedNextURL(_ description: String) -> Value {
        iapVersionedString(description, minLength: 1, format: "uri-reference")
    }

    private func iapVersionedAbsoluteFilePath() -> Value {
        iapVersionedString(
            "Absolute path to Apple's required flattened 1024x1024 JPG or PNG image in RGB at 72 dpi",
            minLength: 1,
            pattern: #"^/"#
        )
    }

    private func iapVersionedLimit(maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string("Maximum results per page"),
            "minimum": .int(1),
            "maximum": .int(maximum),
            "default": .int(25)
        ])
    }

    private func iapVersionStateListSchema() -> Value {
        let values = Self.iapVersionStates.map(Value.string)
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
