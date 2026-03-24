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
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by platform"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "version": .object([
                        "type": .string("string"),
                        "description": .string("Filter by version string (e.g. '2.1.0')")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order: version, -version")
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
}
