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
    let exp: Int
    let iat: Int?
    let iss: String?
    let aud: String?
}

private struct DecodedJWTHeader: Decodable {
    let alg: String?
    let kid: String?
    let typ: String?
}

enum TokenValidationFailure: String, Sendable, Equatable {
    case malformedToken = "malformed_token"
    case malformedHeader = "malformed_header"
    case unsupportedAlgorithm = "unsupported_algorithm"
    case incorrectKeyID = "incorrect_key_id"
    case incorrectTokenType = "incorrect_token_type"
    case invalidSignature = "invalid_signature"
    case malformedPayload = "malformed_payload"
    case incorrectIssuer = "incorrect_issuer"
    case incorrectAudience = "incorrect_audience"
    case invalidIssuedAt = "invalid_issued_at"
    case excessiveLifetime = "excessive_lifetime"
    case expiredOrExpiring = "expired_or_expiring"
}

struct TokenValidationResult: Sendable {
    let isValid: Bool
    let failure: TokenValidationFailure?
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
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        guard let payloadData = decodeBase64URL(parts[1]) else {
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

    /// Validate a token against the configured App Store Connect team key and claims
    public func validateToken(_ token: String) -> Bool {
        validateTokenDetails(token).isValid
    }

    func validateTokenDetails(_ token: String) -> TokenValidationResult {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return TokenValidationResult(isValid: false, failure: .malformedToken)
        }

        guard let headerData = decodeBase64URL(parts[0]),
              let header = try? JSONDecoder().decode(DecodedJWTHeader.self, from: headerData) else {
            return TokenValidationResult(isValid: false, failure: .malformedHeader)
        }
        guard header.alg == "ES256" else {
            return TokenValidationResult(isValid: false, failure: .unsupportedAlgorithm)
        }
        guard header.kid == company.keyID else {
            return TokenValidationResult(isValid: false, failure: .incorrectKeyID)
        }
        guard header.typ == "JWT" else {
            return TokenValidationResult(isValid: false, failure: .incorrectTokenType)
        }

        guard let signatureData = decodeBase64URL(parts[2]),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            return TokenValidationResult(isValid: false, failure: .invalidSignature)
        }

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        guard privateKey.publicKey.isValidSignature(signature, for: signingInput) else {
            return TokenValidationResult(isValid: false, failure: .invalidSignature)
        }

        guard let payloadData = decodeBase64URL(parts[1]),
              let payload = try? JSONDecoder().decode(DecodedJWTPayload.self, from: payloadData) else {
            return TokenValidationResult(isValid: false, failure: .malformedPayload)
        }
        guard payload.iss == company.issuerID else {
            return TokenValidationResult(isValid: false, failure: .incorrectIssuer)
        }
        guard payload.aud == "appstoreconnect-v1" else {
            return TokenValidationResult(isValid: false, failure: .incorrectAudience)
        }

        let now = Date().timeIntervalSince1970
        guard let issuedAt = payload.iat,
              TimeInterval(issuedAt) <= now + 30,
              issuedAt < payload.exp else {
            return TokenValidationResult(isValid: false, failure: .invalidIssuedAt)
        }
        guard TimeInterval(payload.exp) - TimeInterval(issuedAt) <= 20 * 60 else {
            return TokenValidationResult(isValid: false, failure: .excessiveLifetime)
        }
        guard TimeInterval(payload.exp) - now > tokenRefreshLeeway else {
            return TokenValidationResult(isValid: false, failure: .expiredOrExpiring)
        }

        return TokenValidationResult(isValid: true, failure: nil)
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

private func decodeBase64URL(_ value: Substring) -> Data? {
    var base64 = String(value)
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: padding))
    return Data(base64Encoded: base64)
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
