import Foundation
import MCP

// MARK: - Tool Definitions
extension AuthWorker {

    func generateTokenTool() -> Tool {
        return Tool(
            name: "auth_generate_token",
            description: "Генерирует JWT токен для аутентификации в App Store Connect API",
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
            description: "Проверяет действительность JWT токена",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "token": .object([
                        "type": .string("string"),
                        "description": .string("JWT токен для проверки")
                    ])
                ]),
                "required": .array([.string("token")])
            ])
        )
    }

    func refreshTokenTool() -> Tool {
        return Tool(
            name: "auth_refresh_token",
            description: "Принудительно обновляет JWT токен",
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
            description: "Получает информацию о состоянии кэша JWT токена",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }
}
