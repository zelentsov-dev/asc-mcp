import Foundation
import MCP

// MARK: - Tool Definitions
extension ProductPageOptimizationWorker {

    func listExperimentsTool() -> Tool {
        return Tool(
            name: "ppo_list_experiments",
            description: "List product page optimization experiments (A/B tests) for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func getExperimentTool() -> Tool {
        return Tool(
            name: "ppo_get_experiment",
            description: "Get details of a specific product page optimization experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "experiment_id": .object([
                        "type": .string("string"),
                        "description": .string("Experiment ID")
                    ])
                ]),
                "required": .array([.string("experiment_id")])
            ])
        )
    }

    func createExperimentTool() -> Tool {
        return Tool(
            name: "ppo_create_experiment",
            description: "Create a new product page optimization experiment (A/B test)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Experiment name")
                    ]),
                    "traffic_proportion": .object([
                        "type": .string("integer"),
                        "description": .string("Percentage of traffic for the experiment (e.g. 50)")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform (default: IOS)"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS")])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("name"), .string("traffic_proportion")])
            ])
        )
    }

    func updateExperimentTool() -> Tool {
        return Tool(
            name: "ppo_update_experiment",
            description: "Update a product page optimization experiment. Use state START/STOP to control experiment lifecycle",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "experiment_id": .object([
                        "type": .string("string"),
                        "description": .string("Experiment ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New experiment name")
                    ]),
                    "traffic_proportion": .object([
                        "type": .string("integer"),
                        "description": .string("New traffic percentage")
                    ]),
                    "state": .object([
                        "type": .string("string"),
                        "description": .string("Experiment state: START or STOP")
                    ])
                ]),
                "required": .array([.string("experiment_id")])
            ])
        )
    }

    func deleteExperimentTool() -> Tool {
        return Tool(
            name: "ppo_delete_experiment",
            description: "Delete a product page optimization experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "experiment_id": .object([
                        "type": .string("string"),
                        "description": .string("Experiment ID to delete")
                    ])
                ]),
                "required": .array([.string("experiment_id")])
            ])
        )
    }

    func listTreatmentsTool() -> Tool {
        return Tool(
            name: "ppo_list_treatments",
            description: "List treatments (variants) for a product page optimization experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "experiment_id": .object([
                        "type": .string("string"),
                        "description": .string("Experiment ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("experiment_id")])
            ])
        )
    }

    func createTreatmentTool() -> Tool {
        return Tool(
            name: "ppo_create_treatment",
            description: "Create a treatment (variant) for a product page optimization experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "experiment_id": .object([
                        "type": .string("string"),
                        "description": .string("Experiment ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Treatment name")
                    ])
                ]),
                "required": .array([.string("experiment_id"), .string("name")])
            ])
        )
    }

    func listTreatmentLocalizationsTool() -> Tool {
        return Tool(
            name: "ppo_list_treatment_localizations",
            description: "List localizations for a treatment in a product page experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "treatment_id": .object([
                        "type": .string("string"),
                        "description": .string("Treatment ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([.string("treatment_id")])
            ])
        )
    }

    func createTreatmentLocalizationTool() -> Tool {
        return Tool(
            name: "ppo_create_treatment_localization",
            description: "Create a localization for a treatment in a product page experiment",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "treatment_id": .object([
                        "type": .string("string"),
                        "description": .string("Treatment ID")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Locale code (e.g. en-US, ru-RU, de-DE, ja, zh-Hans)")
                    ])
                ]),
                "required": .array([.string("treatment_id"), .string("locale")])
            ])
        )
    }
}
