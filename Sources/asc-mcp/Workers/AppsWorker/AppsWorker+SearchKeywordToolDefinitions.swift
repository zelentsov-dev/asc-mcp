import MCP

extension AppsWorker {
    func listSearchKeywordsTool() -> Tool {
        Tool(
            name: "apps_list_search_keywords",
            description: "List App Store search keyword IDs available to an app for Custom Product Page localization targeting",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID"),
                        "minLength": .int(1),
                        "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
                    ]),
                    "platforms": searchKeywordArrayProperty("Filter by App Store platform"),
                    "locales": searchKeywordArrayProperty("Filter by locale codes"),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of search keyword IDs per page (default 200)"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(200)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat app_id, platforms, locales, and the effective limit; the exact path, query, and cursor are validated."),
                        "minLength": .int(1),
                        "format": .string("uri-reference"),
                        "pattern": .string(#"^(?!.*\s).+$"#)
                    ])
                ]),
                "required": .array([.string("app_id")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    private func searchKeywordArrayProperty(_ description: String) -> Value {
        return .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("string"),
                "minLength": .int(1),
                "pattern": .string(#"^(?!\s)(?!.*\s$)[^,\u0000-\u001F\u007F]+$"#)
            ]),
            "description": .string(description),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ])
    }
}
