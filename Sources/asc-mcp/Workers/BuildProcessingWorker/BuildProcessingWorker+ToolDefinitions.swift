import Foundation
import MCP

// MARK: - Tool Definitions
extension BuildProcessingWorker {
    
    func getProcessingStateTool() -> Tool {
        return Tool(
            name: "builds_get_processing_state",
            description: "Get the current processing state of a build",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func updateEncryptionTool() -> Tool {
        return Tool(
            name: "builds_update_encryption",
            description: "Update encryption compliance via the build's App Encryption Declaration. Fetches the declaration for the given build and patches usesNonExemptEncryption.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ]),
                    "uses_non_exempt_encryption": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether the build uses non-exempt encryption")
                    ])
                ]),
                "required": .array([.string("build_id"), .string("uses_non_exempt_encryption")])
            ])
        )
    }

    func getProcessingStatusTool() -> Tool {
        return Tool(
            name: "builds_get_processing_status",
            description: "Check current processing status of a build. Returns state, readiness, and time since upload. Non-blocking — call again to re-check.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
    
    func checkReadinessTool() -> Tool {
        return Tool(
            name: "builds_check_readiness",
            description: "Check if a build is ready for submission or TestFlight",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "build_id": .object([
                        "type": .string("string"),
                        "description": .string("ID of the build")
                    ])
                ]),
                "required": .array([.string("build_id")])
            ])
        )
    }
}