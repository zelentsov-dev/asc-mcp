import Foundation
import MCP

// MARK: - Tool Definitions
extension PreReleaseVersionsWorker {

    func listPreReleaseVersionsTool() -> Tool {
        return Tool(
            name: "pre_release_list",
            description: "List pre-release versions (TestFlight versions) with optional filtering by app, platform, or version string",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by app ID")
                    ]),
                    "platform": enumListSchema("Filter by platform", values: ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]),
                    "version": stringListSchema("Filter by version string (for example, 2.1.0)"),
                    "build_audience_types": enumListSchema("Filter by related build audience type", values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"]),
                    "build_expired": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by related build expiration status")
                    ]),
                    "build_processing_states": enumListSchema("Filter by related build processing state", values: ["PROCESSING", "FAILED", "INVALID", "VALID"]),
                    "build_versions": stringListSchema("Filter by related build numbers"),
                    "build_ids": stringListSchema("Filter by related build IDs"),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order"),
                        "enum": .array([.string("version"), .string("-version")])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getPreReleaseVersionTool() -> Tool {
        return Tool(
            name: "pre_release_get",
            description: "Get details of a specific pre-release version by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pre_release_version_id": .object([
                        "type": .string("string"),
                        "description": .string("Pre-release version ID")
                    ])
                ]),
                "required": .array([.string("pre_release_version_id")])
            ])
        )
    }

    func listPreReleaseVersionBuildsTool() -> Tool {
        return Tool(
            name: "pre_release_list_builds",
            description: "List builds associated with a specific pre-release version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pre_release_version_id": .object([
                        "type": .string("string"),
                        "description": .string("Pre-release version ID")
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
                "required": .array([.string("pre_release_version_id")])
            ])
        )
    }

    private func stringListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string")]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "minItems": .int(1)
                ])
            ])
        ])
    }

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object(["type": .string("string"), "enum": .array(values.map(Value.string))]),
                .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string"), "enum": .array(values.map(Value.string))]),
                    "minItems": .int(1)
                ])
            ])
        ])
    }
}
