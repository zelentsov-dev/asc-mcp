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
            description: "Locally validate a standard team-key JWT signature and App Store Connect claims against the configured company, including the 20-minute maximum lifetime. This does not call Apple or prove that Apple will accept a specific API request.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "token": .object([
                        "type": .string("string"),
                        "description": .string("Non-scoped team-key JWT to validate using the configured ES256 key, key ID, issuer, audience, issued-at time, expiration, and standard maximum lifetime")
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
