import Foundation
import MCP

// MARK: - Tool Definitions
extension BuildsWorker {
    
    func listBuildsTool() -> Tool {
        return Tool(
            name: "builds_list",
            description: "Get list of builds for an app with filtering options",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app in App Store Connect")
                    ]),
                    "version": .object([
                        "type": .string("string"),
                        "description": .string("Filter by specific version number")
                    ]),
                    "processing_state": .object([
                        "type": .string("string"),
                        "description": .string("Filter by processing state: PROCESSING, FAILED, INVALID, VALID")
                    ]),
                    "expired": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter by expiration status")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of builds to return (default: 25, max: 200)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order: uploadedDate, -uploadedDate, version, -version")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL of the next page from previous response (next_url field)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func getBuildTool() -> Tool {
        return Tool(
            name: "builds_get",
            description: "Get detailed information about a specific build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ]),
                    "include_beta_detail": .object([
                        "type": .string("boolean"),
                        "description": .string("Include beta build details (default: true)")
                    ]),
                    "include_app": .object([
                        "type": .string("boolean"),
                        "description": .string("Include app information (default: false)")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func findBuildByNumberTool() -> Tool {
        return Tool(
            name: "builds_find_by_number",
            description: "Find a build by its version number",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app in App Store Connect")
                    ]),
                    "build_number": .object([
                        "type": .string("string"),
                        "description": .string("Build number/version to search for")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("build_number")])
            ])
        )
    }
    
    func listBuildsForVersionTool() -> Tool {
        return Tool(
            name: "builds_list_for_version",
            description: "Get all builds associated with a specific app store version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the app store version")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }
}