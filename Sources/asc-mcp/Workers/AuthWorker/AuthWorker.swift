import Foundation
import MCP

/// Handles authentication for App Store Connect API
public final class AuthWorker: Sendable {
    let jwtService: JWTService
    
    public init(jwtService: JWTService) {
        self.jwtService = jwtService
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            generateTokenTool(),
            validateTokenTool(),
            refreshTokenTool(),
            tokenStatusTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "auth_generate_token":
            return try await self.generateToken()
        case "auth_validate_token":
            return try await self.validateToken(params)
        case "auth_refresh_token":
            return try await self.refreshToken()
        case "auth_token_status":
            return try await self.getTokenStatus()
        default:
            throw MCPError.methodNotFound("Unknown tool")
        }
    }
    
}
