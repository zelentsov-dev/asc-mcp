import Foundation
import MCP

// MARK: - Tool Definitions
extension ProductPageOptimizationWorker {
    func listExperimentsTool() -> Tool {
        collectionTool(
            name: "ppo_list_experiments",
            description: "List current V2 product page optimization experiments for an app",
            parentField: "app_id",
            parentDescription: "App Store Connect app ID",
            supportsStateFilter: true
        )
    }

    func listVersionExperimentsTool() -> Tool {
        collectionTool(
            name: "ppo_list_version_experiments",
            description: "List current V2 product page optimization experiments scoped to one App Store version",
            parentField: "version_id",
            parentDescription: "App Store version ID",
            supportsStateFilter: true
        )
    }

    func getExperimentTool() -> Tool {
        Tool(
            name: "ppo_get_experiment",
            description: "Get one current V2 product page optimization experiment",
            inputSchema: strictObject(
                properties: ["experiment_id": identifierSchema("Experiment ID")],
                required: ["experiment_id"]
            )
        )
    }

    func createExperimentTool() -> Tool {
        Tool(
            name: "ppo_create_experiment",
            description: "Create a current V2 product page optimization experiment. Ambiguous POST outcomes are never replayed automatically.",
            inputSchema: strictObject(
                properties: [
                    "app_id": identifierSchema("App Store Connect app ID"),
                    "name": nonEmptyStringSchema("Experiment name"),
                    "traffic_proportion": .object([
                        "type": .string("integer"),
                        "description": .string("Traffic proportion accepted by Apple")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Apple platform; defaults to IOS when omitted"),
                        "enum": .array(Self.supportedPlatforms.map(Value.string)),
                        "default": .string("IOS")
                    ])
                ],
                required: ["app_id", "name", "traffic_proportion"]
            )
        )
    }

    func updateExperimentTool() -> Tool {
        var schema = strictObjectDictionary(
            properties: [
                "experiment_id": identifierSchema("Experiment ID"),
                "name": nullableStringSchema("New experiment name, or null to send an explicit Apple null"),
                "traffic_proportion": .object([
                    "type": .array([.string("integer"), .string("null")]),
                    "description": .string("New traffic proportion, or null to send an explicit Apple null")
                ]),
                "state": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "description": .string("START maps to started=true, STOP maps to started=false, and null sends started=null"),
                    "enum": .array([.string("START"), .string("STOP"), .null])
                ]),
                "confirm_experiment_id": identifierSchema("Exact experiment_id required whenever state is supplied")
            ],
            required: ["experiment_id"]
        )
        schema["minProperties"] = .int(2)
        schema["anyOf"] = .array([
            .object(["required": .array([.string("name")])]),
            .object(["required": .array([.string("traffic_proportion")])]),
            .object(["required": .array([.string("state")])])
        ])
        schema["allOf"] = .array([
            .object([
                "if": .object(["required": .array([.string("state")])]),
                "then": .object(["required": .array([.string("confirm_experiment_id")])])
            ])
        ])
        return Tool(
            name: "ppo_update_experiment",
            description: "Update a V2 experiment without collapsing omission into null. Lifecycle writes require exact ID confirmation; STOP is verified only from an explicit STOPPED response, while START and started=null return inspection-required committed_unverified outcomes.",
            inputSchema: .object(schema)
        )
    }

    func deleteExperimentTool() -> Tool {
        Tool(
            name: "ppo_delete_experiment",
            description: "Delete a V2 product page optimization experiment after exact experiment-ID confirmation",
            inputSchema: strictObject(
                properties: [
                    "experiment_id": identifierSchema("Experiment ID to delete"),
                    "confirm_experiment_id": identifierSchema("Exact experiment_id required to confirm irreversible deletion")
                ],
                required: ["experiment_id", "confirm_experiment_id"]
            )
        )
    }

    func listTreatmentsTool() -> Tool {
        collectionTool(
            name: "ppo_list_treatments",
            description: "List treatments belonging to one current V2 product page optimization experiment",
            parentField: "experiment_id",
            parentDescription: "Current V2 experiment ID",
            supportsStateFilter: false
        )
    }

    func getTreatmentTool() -> Tool {
        Tool(
            name: "ppo_get_treatment",
            description: "Get one product page optimization treatment and its current V2 parent identity when Apple returns it",
            inputSchema: strictObject(
                properties: ["treatment_id": identifierSchema("Treatment ID")],
                required: ["treatment_id"]
            )
        )
    }

    func createTreatmentTool() -> Tool {
        Tool(
            name: "ppo_create_treatment",
            description: "Create a treatment under a current V2 experiment. The deprecated V1 parent relationship is never used.",
            inputSchema: strictObject(
                properties: [
                    "experiment_id": identifierSchema("Current V2 experiment ID"),
                    "name": nonEmptyStringSchema("Treatment name"),
                    "app_icon_name": nullableStringSchema("App icon name, or null to send an explicit Apple null")
                ],
                required: ["experiment_id", "name"]
            )
        )
    }

    func updateTreatmentTool() -> Tool {
        var schema = strictObjectDictionary(
            properties: [
                "treatment_id": identifierSchema("Treatment ID"),
                "name": nullableStringSchema("New treatment name, or null to send an explicit Apple null"),
                "app_icon_name": nullableStringSchema("New app icon name, or null to send an explicit Apple null")
            ],
            required: ["treatment_id"]
        )
        schema["minProperties"] = .int(2)
        schema["anyOf"] = .array([
            .object(["required": .array([.string("name")])]),
            .object(["required": .array([.string("app_icon_name")])])
        ])
        return Tool(
            name: "ppo_update_treatment",
            description: "Update one treatment while preserving omitted, explicit-null, and concrete attribute states; empty updates are rejected",
            inputSchema: .object(schema)
        )
    }

    func deleteTreatmentTool() -> Tool {
        Tool(
            name: "ppo_delete_treatment",
            description: "Delete a product page optimization treatment after exact treatment-ID confirmation",
            inputSchema: strictObject(
                properties: [
                    "treatment_id": identifierSchema("Treatment ID to delete"),
                    "confirm_treatment_id": identifierSchema("Exact treatment_id required to confirm irreversible deletion")
                ],
                required: ["treatment_id", "confirm_treatment_id"]
            )
        )
    }

    func listTreatmentLocalizationsTool() -> Tool {
        var properties = collectionProperties(
            parentField: "treatment_id",
            parentDescription: "Treatment ID"
        )
        properties["locale"] = stringOrArraySchema("Filter by one or more locale codes")
        return Tool(
            name: "ppo_list_treatment_localizations",
            description: "List localizations belonging to one product page optimization treatment",
            inputSchema: strictObject(properties: properties, required: ["treatment_id"])
        )
    }

    func getTreatmentLocalizationTool() -> Tool {
        Tool(
            name: "ppo_get_treatment_localization",
            description: "Get one product page optimization treatment localization",
            inputSchema: strictObject(
                properties: ["localization_id": identifierSchema("Treatment localization ID")],
                required: ["localization_id"]
            )
        )
    }

    func createTreatmentLocalizationTool() -> Tool {
        Tool(
            name: "ppo_create_treatment_localization",
            description: "Create a locale resource under one product page optimization treatment",
            inputSchema: strictObject(
                properties: [
                    "treatment_id": identifierSchema("Treatment ID"),
                    "locale": nonEmptyStringSchema("Locale code such as en-US, de-DE, ja, or zh-Hans")
                ],
                required: ["treatment_id", "locale"]
            )
        )
    }

    func deleteTreatmentLocalizationTool() -> Tool {
        Tool(
            name: "ppo_delete_treatment_localization",
            description: "Delete a product page optimization treatment localization after exact localization-ID confirmation",
            inputSchema: strictObject(
                properties: [
                    "localization_id": identifierSchema("Treatment localization ID to delete"),
                    "confirm_localization_id": identifierSchema("Exact localization_id required to confirm irreversible deletion")
                ],
                required: ["localization_id", "confirm_localization_id"]
            )
        )
    }

    private func collectionTool(
        name: String,
        description: String,
        parentField: String,
        parentDescription: String,
        supportsStateFilter: Bool
    ) -> Tool {
        var properties = collectionProperties(
            parentField: parentField,
            parentDescription: parentDescription
        )
        if supportsStateFilter {
            properties["states"] = stringOrArrayEnumSchema(
                "Filter by one or more experiment states",
                values: Self.supportedExperimentStates
            )
        }
        return Tool(
            name: name,
            description: description,
            inputSchema: strictObject(properties: properties, required: [parentField])
        )
    }

    private func collectionProperties(
        parentField: String,
        parentDescription: String
    ) -> [String: Value] {
        [
            parentField: identifierSchema(parentDescription),
            "limit": .object([
                "type": .string("integer"),
                "description": .string("Maximum resources per page"),
                "minimum": .int(1),
                "maximum": .int(200),
                "default": .int(25)
            ]),
            "next_url": .object([
                "type": .string("string"),
                "description": .string("Apple continuation URL from the previous response; repeat the exact originating limit and filters"),
                "format": .string("uri-reference"),
                "minLength": .int(1),
                "pattern": .string(#"^(?!.*[\s\u0000-\u001F\u007F]).+$"#)
            ])
        ]
    }

    private func strictObject(
        properties: [String: Value],
        required: [String]
    ) -> Value {
        .object(strictObjectDictionary(properties: properties, required: required))
    }

    private func strictObjectDictionary(
        properties: [String: Value],
        required: [String]
    ) -> [String: Value] {
        [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties),
            "required": .array(required.map(Value.string))
        ]
    }

    private func identifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#)
        ])
    }

    private func nonEmptyStringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    private func nullableStringSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("string"), .string("null")]),
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    private func stringOrArraySchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string"), "minLength": .int(1)]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string"), "minLength": .int(1)]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func stringOrArrayEnumSchema(_ description: String, values: [String]) -> Value {
        let enumValues = Value.array(values.map(Value.string))
        return .object([
            "description": .string(description + ": " + values.joined(separator: ", ")),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": enumValues
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": enumValues
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
