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
            return MCPResult.json(
                .object([
                    "success": .bool(true),
                    "message": .string("JWT token generated successfully")
                ]),
                text: "JWT token generated successfully"
            )
        } catch {
            return MCPResult.error("Token generation failed: \(error.localizedDescription)")
        }
    }

    /// Validates a team-key JWT locally against the configured key and claims
    /// - Returns: Local validation result and whether Apple acceptance was checked
    /// - Throws: CallTool.Result with error if token parameter is missing
    func validateToken(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let tokenValue = arguments["token"],
              let token = tokenValue.stringValue else {
            return MCPResult.error("Required parameter 'token' is missing")
        }

        let validation = await jwtService.validateTokenDetails(token)

        var result: [String: Value] = [
            "success": .bool(true),
            "isValid": .bool(validation.isValid),
            "validationScope": .string("configured_team_key"),
            "appleAcceptanceChecked": .bool(false)
        ]
        if let failure = validation.failure {
            result["failureReason"] = .string(failure.rawValue)
        }

        return MCPResult.json(
            .object(result),
            text: validation.isValid
                ? "JWT token passed local signature and claim validation"
                : "JWT token failed local validation: \(validation.failure?.rawValue ?? "unknown")"
        )
    }

    /// Forces refresh of the JWT token before expiration
    /// - Returns: Success message confirming token refresh
    /// - Throws: CallTool.Result with error if token refresh fails
    func refreshToken() async throws -> CallTool.Result {
        do {
            let _ = try await jwtService.refreshToken()
            return MCPResult.json(
                .object([
                    "success": .bool(true),
                    "message": .string("JWT token refreshed successfully")
                ]),
                text: "JWT token refreshed successfully"
            )
        } catch {
            return MCPResult.error("Token refresh failed: \(error.localizedDescription)")
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
        
        let jsonResult: [String: Any] = [
            "status": "success",
            "cacheInfo": [
                "hasCachedToken": cacheInfo.hasCachedToken,
                "refreshLeewaySeconds": cacheInfo.refreshLeewaySeconds,
                "expiresInSeconds": cacheInfo.expiresInSeconds.jsonSafe,
                "isValid": cacheInfo.isValid.jsonSafe,
                "expirationDate": cacheInfo.expirationDate.jsonSafe
            ]
        ]
        
        return MCPResult.jsonObject(jsonResult, text: statusMessage)
    }

}
