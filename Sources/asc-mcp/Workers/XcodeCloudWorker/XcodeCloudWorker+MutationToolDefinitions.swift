import Foundation
import MCP

extension XcodeCloudWorker {
    func productsDeleteTool() -> Tool {
        Tool(
            name: "xcode_cloud_products_delete",
            description: "Preview or permanently delete an Xcode Cloud product. Preview is the default. Permanent deletion requires the latest dynamic receipt plus the exact current product name, workflow count, build-run count, and confirm_permanent_deletion=true.",
            inputSchema: xcMutationObjectSchema(
                properties: [
                    "product_id": xcMutationResourceIDSchema("Xcode Cloud product ID"),
                    "confirm_permanent_deletion": xcMutationBooleanSchema("Must be true to execute permanent deletion"),
                    "confirmation_receipt": xcMutationIDSchema("Dynamic receipt from the latest preview"),
                    "expected_product_name": xcMutationStringSchema("Exact current product name from the latest preview"),
                    "expected_workflow_count": xcMutationNonNegativeIntegerSchema("Exact current workflow count from the latest preview"),
                    "expected_build_run_count": xcMutationNonNegativeIntegerSchema("Exact current build-run count from the latest preview")
                ],
                required: ["product_id"]
            )
        )
    }

    func workflowsCreateTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflows_create",
            description: "Create an Xcode Cloud workflow using the complete App Store Connect API 4.4.1 create contract. A verified result requires Apple's exact HTTP 201 response with a valid workflow identity and canonical links.",
            inputSchema: xcWorkflowMutationSchema(isCreate: true)
        )
    }

    func workflowsUpdateTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflows_update",
            description: "Update selected Xcode Cloud workflow attributes or version relationships. Omitted fields remain unchanged; explicit null is preserved for every nullable Apple PATCH attribute; empty patches are rejected.",
            inputSchema: xcWorkflowMutationSchema(isCreate: false)
        )
    }

    func workflowsDeleteTool() -> Tool {
        Tool(
            name: "xcode_cloud_workflows_delete",
            description: "Preview or permanently delete an Xcode Cloud workflow. Preview is the default. Permanent deletion requires the latest dynamic receipt plus the exact current workflow name, build-run count, and confirm_permanent_deletion=true.",
            inputSchema: xcMutationObjectSchema(
                properties: [
                    "workflow_id": xcMutationResourceIDSchema("Xcode Cloud workflow ID"),
                    "confirm_permanent_deletion": xcMutationBooleanSchema("Must be true to execute permanent deletion"),
                    "confirmation_receipt": xcMutationIDSchema("Dynamic receipt from the latest preview"),
                    "expected_workflow_name": xcMutationStringSchema("Exact current workflow name from the latest preview"),
                    "expected_build_run_count": xcMutationNonNegativeIntegerSchema("Exact current build-run count from the latest preview")
                ],
                required: ["workflow_id"]
            )
        )
    }
}

private extension XcodeCloudWorker {
    enum XCMutationStartConditionKind {
        case branch
        case tag
        case pullRequest
        case scheduled
        case manualBranch
        case manualTag
        case manualPullRequest
    }

    func xcWorkflowMutationSchema(isCreate: Bool) -> Value {
        var properties: [String: Value] = [
            "name": xcMutationNullableStringSchema(
                isCreate ? "Workflow name" : "Workflow name; null clears the attribute",
                nullable: !isCreate
            ),
            "description": xcMutationNullableStringSchema(
                isCreate ? "Workflow description" : "Workflow description; null clears the attribute",
                nullable: !isCreate
            ),
            "branch_start_condition": xcMutationStartConditionSchema(kind: .branch),
            "tag_start_condition": xcMutationStartConditionSchema(kind: .tag),
            "pull_request_start_condition": xcMutationStartConditionSchema(kind: .pullRequest),
            "scheduled_start_condition": xcMutationStartConditionSchema(kind: .scheduled),
            "manual_branch_start_condition": xcMutationStartConditionSchema(kind: .manualBranch),
            "manual_tag_start_condition": xcMutationStartConditionSchema(kind: .manualTag),
            "manual_pull_request_start_condition": xcMutationStartConditionSchema(kind: .manualPullRequest),
            "actions": xcMutationActionsSchema(nullable: !isCreate),
            "is_enabled": xcMutationNullableBooleanSchema(
                isCreate ? "Whether the workflow can start" : "Whether the workflow can start; null clears the attribute",
                nullable: !isCreate
            ),
            "is_locked_for_editing": xcMutationNullableBooleanSchema(
                "Whether Xcode Cloud locks the workflow for editing; null clears the attribute",
                nullable: true
            ),
            "clean": xcMutationNullableBooleanSchema(
                isCreate ? "Whether workflow builds use a clean build" : "Whether workflow builds use a clean build; null clears the attribute",
                nullable: !isCreate
            ),
            "container_file_path": xcMutationNullableStringSchema(
                isCreate ? "Path to the Xcode project or workspace container" : "Container path; null clears the attribute",
                nullable: !isCreate
            ),
            "xcode_version_id": xcMutationResourceIDSchema("Compatible Xcode version ID"),
            "macos_version_id": xcMutationResourceIDSchema("Compatible macOS version ID")
        ]

        if isCreate {
            properties["product_id"] = xcMutationResourceIDSchema("Xcode Cloud product ID")
            properties["repository_id"] = xcMutationResourceIDSchema("SCM repository ID")
            return xcMutationObjectSchema(
                properties: properties,
                required: [
                    "name", "description", "actions", "is_enabled", "clean", "container_file_path",
                    "product_id", "repository_id", "xcode_version_id", "macos_version_id"
                ]
            )
        }

        properties["workflow_id"] = xcMutationResourceIDSchema("Xcode Cloud workflow ID")
        return xcMutationObjectSchema(properties: properties, required: ["workflow_id"])
    }

    func xcMutationStartConditionSchema(kind: XCMutationStartConditionKind) -> Value {
        let properties: [String: Value]
        switch kind {
        case .branch, .tag:
            properties = [
                "source": xcMutationPatternGroupSchema(),
                "files_and_folders_rule": xcMutationFilesAndFoldersRuleSchema(),
                "auto_cancel": xcMutationBooleanSchema("Whether a newer matching change cancels the current build")
            ]
        case .pullRequest:
            properties = [
                "source": xcMutationPatternGroupSchema(),
                "destination": xcMutationPatternGroupSchema(),
                "files_and_folders_rule": xcMutationFilesAndFoldersRuleSchema(),
                "auto_cancel": xcMutationBooleanSchema("Whether a newer matching pull-request change cancels the current build")
            ]
        case .scheduled:
            properties = [
                "source": xcMutationPatternGroupSchema(),
                "schedule": xcMutationScheduleSchema()
            ]
        case .manualBranch, .manualTag:
            properties = ["source": xcMutationPatternGroupSchema()]
        case .manualPullRequest:
            properties = [
                "source": xcMutationPatternGroupSchema(),
                "destination": xcMutationPatternGroupSchema()
            ]
        }
        return xcMutationObjectSchema(properties: properties, nullable: true)
    }

    func xcMutationActionsSchema(nullable: Bool) -> Value {
        let schema: [String: Value] = [
            "type": nullable
                ? .array([.string("array"), .string("null")])
                : .string("array"),
            "description": .string("Workflow actions using the complete Apple API 4.4.1 action contract"),
            "items": xcMutationObjectSchema(properties: [
                "name": xcMutationStringSchema("Action name"),
                "action_type": xcMutationEnumSchema("Action type", values: ["BUILD", "ANALYZE", "TEST", "ARCHIVE"]),
                "destination": xcMutationEnumSchema("Build or test destination", values: [
                    "ANY_IOS_DEVICE", "ANY_IOS_SIMULATOR", "ANY_TVOS_DEVICE", "ANY_TVOS_SIMULATOR",
                    "ANY_WATCHOS_DEVICE", "ANY_WATCHOS_SIMULATOR", "ANY_MAC", "ANY_MAC_CATALYST",
                    "ANY_VISIONOS_DEVICE", "ANY_VISIONOS_SIMULATOR"
                ]),
                "build_distribution_audience": xcMutationEnumSchema(
                    "Archive distribution audience",
                    values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]
                ),
                "test_configuration": xcMutationObjectSchema(properties: [
                    "kind": xcMutationEnumSchema(
                        "Test configuration kind",
                        values: ["USE_SCHEME_SETTINGS", "SPECIFIC_TEST_PLANS"]
                    ),
                    "test_plan_name": xcMutationStringSchema("Specific test plan name"),
                    "test_destinations": .object([
                        "type": .string("array"),
                        "items": xcMutationObjectSchema(properties: [
                            "device_type_name": xcMutationStringSchema("Device type name"),
                            "device_type_identifier": xcMutationStringSchema("Device type identifier"),
                            "runtime_name": xcMutationStringSchema("Runtime name"),
                            "runtime_identifier": xcMutationStringSchema("Runtime identifier"),
                            "kind": xcMutationEnumSchema("Test destination kind", values: ["SIMULATOR", "MAC"])
                        ])
                    ])
                ]),
                "scheme": xcMutationStringSchema("Xcode scheme"),
                "platform": xcMutationEnumSchema(
                    "Apple platform",
                    values: ["MACOS", "IOS", "TVOS", "WATCHOS", "VISIONOS"]
                ),
                "is_required_to_pass": xcMutationBooleanSchema("Whether this action must pass")
            ])
        ]
        return .object(schema)
    }

    func xcMutationPatternGroupSchema() -> Value {
        xcMutationObjectSchema(properties: [
            "is_all_match": xcMutationBooleanSchema("Whether every reference matches"),
            "patterns": .object([
                "type": .string("array"),
                "items": xcMutationObjectSchema(properties: [
                    "pattern": xcMutationStringSchema("Reference pattern"),
                    "is_prefix": xcMutationBooleanSchema("Whether the pattern is a prefix")
                ])
            ])
        ])
    }

    func xcMutationFilesAndFoldersRuleSchema() -> Value {
        xcMutationObjectSchema(properties: [
            "mode": xcMutationEnumSchema(
                "File matching mode",
                values: ["START_IF_ANY_FILE_MATCHES", "DO_NOT_START_IF_ALL_FILES_MATCH"]
            ),
            "matchers": .object([
                "type": .string("array"),
                "items": xcMutationObjectSchema(properties: [
                    "directory": xcMutationStringSchema("Directory matcher"),
                    "file_extension": xcMutationStringSchema("File-extension matcher"),
                    "file_name": xcMutationStringSchema("File-name matcher")
                ])
            ])
        ])
    }

    func xcMutationScheduleSchema() -> Value {
        xcMutationObjectSchema(properties: [
            "frequency": xcMutationEnumSchema("Schedule frequency", values: ["WEEKLY", "DAILY", "HOURLY"]),
            "days": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                    "enum": .array([
                        "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
                        "THURSDAY", "FRIDAY", "SATURDAY"
                    ].map(Value.string))
                ])
            ]),
            "hour": xcMutationIntegerSchema("Scheduled hour"),
            "minute": xcMutationIntegerSchema("Scheduled minute"),
            "timezone": xcMutationStringSchema("IANA time-zone identifier")
        ])
    }

    func xcMutationObjectSchema(
        properties: [String: Value],
        required: [String] = [],
        nullable: Bool = false
    ) -> Value {
        var schema: [String: Value] = [
            "type": nullable
                ? .array([.string("object"), .string("null")])
                : .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    func xcMutationNullableStringSchema(_ description: String, nullable: Bool) -> Value {
        nullable
            ? .object([
                "type": .array([.string("string"), .string("null")]),
                "description": .string(description)
            ])
            : xcMutationStringSchema(description)
    }

    func xcMutationNullableBooleanSchema(_ description: String, nullable: Bool) -> Value {
        nullable
            ? .object([
                "type": .array([.string("boolean"), .string("null")]),
                "description": .string(description)
            ])
            : xcMutationBooleanSchema(description)
    }

    func xcMutationIDSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    func xcMutationResourceIDSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string("\(description); canonical App Store Connect resource ID"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
    }

    func xcMutationStringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    func xcMutationBooleanSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    func xcMutationIntegerSchema(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description)
        ])
    }

    func xcMutationNonNegativeIntegerSchema(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "minimum": .int(0),
            "description": .string(description)
        ])
    }

    func xcMutationEnumSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string))
        ])
    }
}
