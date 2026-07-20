import MCP

extension SubscriptionsWorker {
    func legacySubscriptionResult(
        _ result: CallTool.Result,
        tool: String
    ) -> CallTool.Result {
        guard result.isError != true,
              let replacements = Self.legacySubscriptionReplacements[tool],
              case .object(var payload)? = result.structuredContent else {
            return result
        }

        payload["deprecated"] = .bool(true)
        payload["deprecated_since"] = .string("App Store Connect API 4.4.1")
        payload["warnings"] = .array([
            .string("\(tool) uses an Apple-deprecated product-scoped commerce API and remains available only for backward compatibility. It does not create or select a version automatically.")
        ])
        payload["replacement_tools"] = .array(replacements.map(Value.string))
        return MCPResult.json(.object(payload), _meta: result._meta)
    }

    static let legacySubscriptionReplacements: [String: [String]] = [
        "subscriptions_list_localizations": [
            "subscriptions_list_versions",
            "subscriptions_list_version_localizations"
        ],
        "subscriptions_create_localization": [
            "subscriptions_create_version",
            "subscriptions_create_version_localization"
        ],
        "subscriptions_get_localization": ["subscriptions_get_version_localization"],
        "subscriptions_update_localization": ["subscriptions_update_version_localization"],
        "subscriptions_delete_localization": ["subscriptions_delete_version_localization"],
        "subscriptions_list_group_localizations": [
            "subscriptions_list_group_versions",
            "subscriptions_list_group_version_localizations"
        ],
        "subscriptions_create_group_localization": [
            "subscriptions_create_group_version",
            "subscriptions_create_group_version_localization"
        ],
        "subscriptions_get_group_localization": ["subscriptions_get_group_version_localization"],
        "subscriptions_update_group_localization": ["subscriptions_update_group_version_localization"],
        "subscriptions_delete_group_localization": ["subscriptions_delete_group_version_localization"],
        "subscriptions_list_images": [
            "subscriptions_list_versions",
            "subscriptions_list_version_images"
        ],
        "subscriptions_upload_image": [
            "subscriptions_create_version",
            "subscriptions_upload_version_image"
        ],
        "subscriptions_get_image": ["subscriptions_get_version_image"],
        "subscriptions_delete_image": ["subscriptions_delete_version_image"],
        "subscriptions_submit": [
            "subscriptions_create_version",
            "review_submissions_create",
            "review_submissions_add_item",
            "review_submissions_submit"
        ],
        "subscriptions_submit_group": [
            "subscriptions_create_group_version",
            "review_submissions_create",
            "review_submissions_add_item",
            "review_submissions_submit"
        ]
    ]
}
