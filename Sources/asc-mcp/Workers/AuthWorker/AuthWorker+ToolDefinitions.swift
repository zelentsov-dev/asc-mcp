import Foundation
import MCP

// MARK: - Tool Definitions
extension AuthWorker {

    func generateTokenTool() -> Tool {
        return Tool(
            name: "auth_generate_token",
            description: "Generate JWT token for App Store Connect API authentication",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }

    func validateTokenTool() -> Tool {
        return Tool(
            name: "auth_validate_token",
            description: "Validate a JWT token",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "token": .object([
                        "type": .string("string"),
                        "description": .string("JWT token to validate")
                    ])
                ]),
                "required": .array([.string("token")])
            ])
        )
    }

    func refreshTokenTool() -> Tool {
        return Tool(
            name: "auth_refresh_token",
            description: "Force refresh JWT token",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }
    
    func tokenStatusTool() -> Tool {
        return Tool(
            name: "auth_token_status",
            description: "Get JWT token cache status information",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }
}
