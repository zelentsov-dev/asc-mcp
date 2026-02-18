import Foundation
import CryptoKit

/// Token cache status information
public struct TokenCacheInfo: Sendable {
    public let hasCachedToken: Bool
    public let refreshLeewaySeconds: Int
    public let expiresInSeconds: Int?
    public let isValid: Bool?
    public let expirationDate: String?
}

/// Decoded JWT payload
private struct DecodedJWTPayload: Decodable {
    let exp: Int  // Unix timestamp
    let iat: Int?
    let iss: String?
}

/// JWT token service for App Store Connect API
public actor JWTService {
    private let company: Company
    private let privateKey: P256.Signing.PrivateKey

    /// Cached token
    private var cachedToken: String?

    /// Token refresh leeway (seconds before expiration)
    private let tokenRefreshLeeway: TimeInterval = 90 // 1.5 minutes

    public init(company: Company) throws {
        self.company = company

        // Load key: prefer inline content, fallback to file path
        let keyString: String
        if let content = company.privateKeyContent, !content.isEmpty {
            keyString = content
        } else if !company.privateKeyPath.isEmpty,
                  let keyData = FileManager.default.contents(atPath: company.privateKeyPath) {
            keyString = String(data: keyData, encoding: .utf8) ?? ""
        } else {
            throw ASCError.configuration(
                "No private key provided for company '\(company.name)'. "
                + "Set privateKeyContent or privateKeyPath."
            )
        }

        // Parse PEM format
        let cleanedKey = keyString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let keyBytes = Data(base64Encoded: cleanedKey) else {
            throw ASCError.configuration("Invalid private key format for company '\(company.name)'")
        }

        do {
            self.privateKey = try P256.Signing.PrivateKey(derRepresentation: keyBytes)
        } catch {
            throw ASCError.configuration("Failed to load private key for company '\(company.name)': \(error.localizedDescription)")
        }
    }

    /// Decodes JWT token and extracts expiration time
    private func decodeTokenExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        let payloadBase64 = String(parts[1])
        // Add padding if needed
        let padded = payloadBase64.padding(toLength: ((payloadBase64.count + 3) / 4) * 4,
                                           withPad: "=",
                                           startingAt: 0)

        guard let payloadData = Data(base64Encoded: padded.replacingOccurrences(of: "-", with: "+")
                                                          .replacingOccurrences(of: "_", with: "/")) else {
            return nil
        }

        do {
            let payload = try JSONDecoder().decode(DecodedJWTPayload.self, from: payloadData)
            return Date(timeIntervalSince1970: TimeInterval(payload.exp))
        } catch {
            #if DEBUG
            print("🔐 JWT: Failed to decode token payload: \(error)")
            #endif
            return nil
        }
    }

    /// Get a valid JWT token (with caching)
    public func getToken() async throws -> String {
        let now = Date()

        // Check if there is a valid cached token
        if let token = cachedToken,
           let expirationDate = decodeTokenExpiration(token) {
            let timeUntilExpiry = expirationDate.timeIntervalSince(now)

            if timeUntilExpiry > tokenRefreshLeeway {
                // Token is still valid
                #if DEBUG
                print("🔐 JWT: Using cached token (expires in \(Int(timeUntilExpiry))s)")
                #endif
                return token
            } else {
                #if DEBUG
                print("🔐 JWT: Token expires in \(Int(timeUntilExpiry))s, refreshing...")
                #endif
            }
        }

        // Generate new token
        let token = try generateToken()
        self.cachedToken = token

        #if DEBUG
        if let exp = decodeTokenExpiration(token) {
            let duration = exp.timeIntervalSince(now)
            print("🔐 JWT: Generated new token (valid for \(Int(duration))s)")
        }
        #endif

        return token
    }

    /// Generates a new JWT token
    private func generateToken() throws -> String {
        let now = Date()
        let expiration = now.addingTimeInterval(20 * 60) // 20 minutes

        // Header
        let header = JWTHeader(
            alg: "ES256",
            kid: company.keyID,
            typ: "JWT"
        )

        // Payload
        let payload = JWTPayload(
            iss: company.issuerID,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(expiration.timeIntervalSince1970),
            aud: "appstoreconnect-v1"
        )

        // Encode header and payload as Base64URL
        let headerData = try JSONEncoder().encode(header)
        let payloadData = try JSONEncoder().encode(payload)

        let headerBase64 = headerData.base64URLEncodedString()
        let payloadBase64 = payloadData.base64URLEncodedString()

        // Create signing input string
        let signingInput = "\(headerBase64).\(payloadBase64)"

        // Sign
        guard let signingData = signingInput.data(using: .utf8) else {
            throw ASCError.authentication("Failed to encode JWT signing input as UTF-8")
        }
        let signature = try privateKey.signature(for: signingData)
        let signatureBase64 = signature.rawRepresentation.base64URLEncodedString()

        return "\(signingInput).\(signatureBase64)"
    }

    /// Validate token (check expiration)
    public func validateToken(_ token: String) -> Bool {
        guard let expirationDate = decodeTokenExpiration(token) else { return false }
        // Token is invalid if less than leeway time until expiration
        return expirationDate.timeIntervalSinceNow > tokenRefreshLeeway
    }

    /// Force token refresh
    public func refreshToken() async throws -> String {
        self.cachedToken = nil
        return try await getToken()
    }

    /// Get token cache status information
    public func getCacheInfo() -> TokenCacheInfo {
        let now = Date()

        var expiresInSeconds: Int? = nil
        var isValid: Bool? = nil
        var expirationDateString: String? = nil

        if let token = cachedToken,
           let expirationDate = decodeTokenExpiration(token) {
            let timeUntilExpiry = expirationDate.timeIntervalSince(now)
            expiresInSeconds = Int(timeUntilExpiry)
            isValid = timeUntilExpiry > tokenRefreshLeeway
            expirationDateString = ISO8601DateFormatter().string(from: expirationDate)
        }

        return TokenCacheInfo(
            hasCachedToken: cachedToken != nil,
            refreshLeewaySeconds: Int(tokenRefreshLeeway),
            expiresInSeconds: expiresInSeconds,
            isValid: isValid,
            expirationDate: expirationDateString
        )
    }
}

// MARK: - JWT Models

private struct JWTHeader: Codable {
    let alg: String
    let kid: String
    let typ: String
}

private struct JWTPayload: Codable {
    let iss: String
    let iat: Int
    let exp: Int
    let aud: String
}

// MARK: - Base64URL Extension

private extension Data {
    /// Base64URL encoding (without padding)
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
