import Foundation
import MCP

// MARK: - Tool Handlers
extension AuthWorker {

    /// Generates a new JWT token for App Store Connect API authentication
    /// - Returns: Success message confirming token generation
    /// - Throws: CallTool.Result with error if token generation fails
    func generateToken() async throws -> CallTool.Result {
        do {
            let _ = try await jwtService.getToken()
            return CallTool.Result(content: [
                .text("JWT токен успешно сгенерирован")
            ])
        } catch {
            return CallTool.Result(
                content: [.text("Error: Ошибка генерации токена: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Validates a JWT token to check if it's still valid
    /// - Returns: Success or failure message based on token validity
    /// - Throws: CallTool.Result with error if token parameter is missing
    func validateToken(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let tokenValue = arguments["token"],
              let token = tokenValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Требуется параметр 'token'")],
                isError: true
            )
        }

        let isValid = await jwtService.validateToken(token)

        if isValid {
            return CallTool.Result(content: [
                .text("JWT токен действителен")
            ])
        } else {
            return CallTool.Result(content: [
                .text("JWT токен недействителен или истек")
            ])
        }
    }

    /// Forces refresh of the JWT token before expiration
    /// - Returns: Success message confirming token refresh
    /// - Throws: CallTool.Result with error if token refresh fails
    func refreshToken() async throws -> CallTool.Result {
        do {
            let _ = try await jwtService.refreshToken()
            return CallTool.Result(content: [
                .text("JWT токен успешно обновлен")
            ])
        } catch {
            return CallTool.Result(
                content: [.text("Error: Ошибка обновления токена: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets the current JWT token cache status and information
    /// - Returns: JSON with cache status including expiration time and validity
    /// - Throws: Never throws, always returns status information
    func getTokenStatus() async throws -> CallTool.Result {
        let cacheInfo = await jwtService.getCacheInfo()
        
        var statusMessage = "JWT Token Cache Status:\n"
        
        statusMessage += "• Cached token: \(cacheInfo.hasCachedToken ? "Yes" : "No")\n"
        statusMessage += "• Refresh leeway: \(cacheInfo.refreshLeewaySeconds) seconds\n"
        
        if let expiresIn = cacheInfo.expiresInSeconds {
            if expiresIn > 0 {
                let minutes = expiresIn / 60
                let seconds = expiresIn % 60
                statusMessage += "• Expires in: \(minutes)m \(seconds)s\n"
            } else {
                statusMessage += "• Token expired\n"
            }
        }
        
        if let isValid = cacheInfo.isValid {
            statusMessage += "• Status: \(isValid ? "Valid" : "Needs refresh")\n"
        }
        
        if let expirationDate = cacheInfo.expirationDate {
            statusMessage += "• Expiration: \(expirationDate)\n"
        }
        
        // Also return JSON for programmatic access
        let jsonResult: [String: Any] = [
            "status": "success",
            "cacheInfo": [
                "hasCachedToken": cacheInfo.hasCachedToken,
                "refreshLeewaySeconds": cacheInfo.refreshLeewaySeconds,
                "expiresInSeconds": cacheInfo.expiresInSeconds as Any,
                "isValid": cacheInfo.isValid as Any,
                "expirationDate": cacheInfo.expirationDate as Any
            ]
        ]
        
        return CallTool.Result(content: [
            .text(statusMessage),
            .text("\nJSON Response:"),
            .text(JSONFormatter.formatJSON(jsonResult))
        ])
    }

}
