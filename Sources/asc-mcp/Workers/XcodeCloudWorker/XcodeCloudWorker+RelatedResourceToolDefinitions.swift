import MCP

extension XcodeCloudWorker {
    func appProductGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_app_product_get",
            description: "Get the Xcode Cloud product associated with an App Store Connect app.",
            inputSchema: relatedObjectSchema(
                properties: [
                    "app_id": relatedIdentifierSchema("App Store Connect app ID"),
                    "include": relatedEnumListSchema(
                        "Related product resources to include",
                        values: ["app", "bundleId", "primaryRepositories"]
                    ),
                    "primary_repositories_limit": relatedIntegerSchema(
                        "Maximum included primary repositories; requires include to contain primaryRepositories",
                        minimum: 1,
                        maximum: 50
                    )
                ],
                required: ["app_id"]
            )
        )
    }

    func actionBuildRunGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_action_build_run_get",
            description: "Get the Xcode Cloud build run that owns a build action.",
            inputSchema: relatedObjectSchema(
                properties: [
                    "action_id": relatedIdentifierSchema("Xcode Cloud build action ID"),
                    "include": relatedEnumListSchema(
                        "Related build-run resources to include",
                        values: [
                            "builds", "workflow", "product", "sourceBranchOrTag",
                            "destinationBranch", "pullRequest"
                        ]
                    ),
                    "builds_limit": relatedIntegerSchema(
                        "Maximum included builds; requires include to contain builds",
                        minimum: 1,
                        maximum: 50
                    )
                ],
                required: ["action_id"]
            )
        )
    }

    func macOSVersionXcodeVersionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_macos_version_xcode_versions_list",
            description: "List Xcode versions compatible with an Xcode Cloud macOS version.",
            inputSchema: relatedCollectionSchema(
                parentField: "macos_version_id",
                parentDescription: "Xcode Cloud macOS version ID",
                extraProperties: [
                    "include": relatedEnumListSchema(
                        "Related resources to include",
                        values: ["macOsVersions"]
                    ),
                    "macos_versions_limit": relatedIntegerSchema(
                        "Maximum included macOS versions; requires include to contain macOsVersions",
                        minimum: 1,
                        maximum: 50
                    )
                ]
            )
        )
    }

    func productAdditionalRepositoriesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_product_additional_repositories_list",
            description: "List additional SCM repositories attached to an Xcode Cloud product.",
            inputSchema: relatedRepositoryCollectionSchema()
        )
    }

    func productAppGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_product_app_get",
            description: "Get a compact projection of the App Store Connect app associated with an Xcode Cloud product.",
            inputSchema: relatedObjectSchema(
                properties: [
                    "product_id": relatedIdentifierSchema("Xcode Cloud product ID")
                ],
                required: ["product_id"]
            )
        )
    }

    func productPrimaryRepositoriesListTool() -> Tool {
        Tool(
            name: "xcode_cloud_product_primary_repositories_list",
            description: "List primary SCM repositories attached to an Xcode Cloud product.",
            inputSchema: relatedRepositoryCollectionSchema()
        )
    }

    func workflowRepositoryGetTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflow_repository_get",
            description: "Get the SCM repository used by an Xcode Cloud workflow.",
            inputSchema: relatedObjectSchema(
                properties: [
                    "workflow_id": relatedIdentifierSchema("Xcode Cloud workflow ID"),
                    "include": relatedEnumListSchema(
                        "Related repository resources to include",
                        values: ["scmProvider", "defaultBranch"]
                    )
                ],
                required: ["workflow_id"]
            )
        )
    }

    func xcodeVersionMacOSVersionsListTool() -> Tool {
        Tool(
            name: "xcode_cloud_xcode_version_macos_versions_list",
            description: "List macOS versions compatible with an Xcode Cloud Xcode version.",
            inputSchema: relatedCollectionSchema(
                parentField: "xcode_version_id",
                parentDescription: "Xcode Cloud Xcode version ID",
                extraProperties: [
                    "include": relatedEnumListSchema(
                        "Related resources to include",
                        values: ["xcodeVersions"]
                    ),
                    "xcode_versions_limit": relatedIntegerSchema(
                        "Maximum included Xcode versions; requires include to contain xcodeVersions",
                        minimum: 1,
                        maximum: 50
                    )
                ]
            )
        )
    }

    private func relatedRepositoryCollectionSchema() -> Value {
        relatedCollectionSchema(
            parentField: "product_id",
            parentDescription: "Xcode Cloud product ID",
            extraProperties: [
                "repository_id": relatedIdentifierListSchema("Filter by one or more SCM repository IDs"),
                "include": relatedEnumListSchema(
                    "Related repository resources to include",
                    values: ["scmProvider", "defaultBranch"]
                )
            ]
        )
    }

    private func relatedCollectionSchema(
        parentField: String,
        parentDescription: String,
        extraProperties: [String: Value]
    ) -> Value {
        var properties = extraProperties
        properties[parentField] = relatedIdentifierSchema(parentDescription)
        properties["limit"] = relatedIntegerSchema("Maximum resources per page", minimum: 1, maximum: 200)
        properties["next_url"] = relatedPaginationURLSchema()
        return relatedObjectSchema(properties: properties, required: [parentField])
    }

    private func relatedObjectSchema(properties: [String: Value], required: [String]) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private func relatedIdentifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string("\(description); canonical App Store Connect resource ID"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
    }

    private func relatedIdentifierListSchema(_ description: String) -> Value {
        relatedListSchema(description: description, item: relatedIdentifierSchema("SCM repository ID"))
    }

    private func relatedEnumListSchema(_ description: String, values: [String]) -> Value {
        relatedListSchema(
            description: description,
            item: .object([
                "type": .string("string"),
                "enum": .array(values.map(Value.string))
            ])
        )
    }

    private func relatedListSchema(description: String, item: Value) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                item,
                .object([
                    "type": .string("array"),
                    "items": item,
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func relatedIntegerSchema(_ description: String, minimum: Int, maximum: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(minimum),
            "maximum": .int(maximum)
        ])
    }

    private func relatedPaginationURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "description": .string(
                "Pagination URL from the previous response; repeat the original parent ID, filters, include values, and limits unchanged."
            ),
            "minLength": .int(1),
            "format": .string("uri-reference")
        ])
    }
}
