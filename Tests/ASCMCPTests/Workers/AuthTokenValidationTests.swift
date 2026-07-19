import CryptoKit
import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Auth Token Validation Tests")
struct AuthTokenValidationTests {
    @Test("auth_validate_token verifies the configured team token and discloses its local scope")
    func validatesConfiguredTeamToken() async throws {
        let company = authValidationCompany()
        let service = try JWTService(company: company)
        let worker = AuthWorker(jwtService: service)
        let token = try await service.getToken()

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "auth_validate_token",
            arguments: ["token": .string(token)]
        ))

        #expect(result.isError != true)
        let content = try authValidationObject(result.structuredContent)
        #expect(content["success"] == .bool(true))
        #expect(content["isValid"] == .bool(true))
        #expect(content["validationScope"] == .string("configured_team_key"))
        #expect(content["appleAcceptanceChecked"] == .bool(false))
        #expect(content["failureReason"] == nil)
    }

    @Test("auth_validate_token rejects a token with a different ES256 signature")
    func rejectsDifferentSignature() async throws {
        let expectedCompany = authValidationCompany()
        let unexpectedCompany = Company(
            id: "unexpected",
            name: "Unexpected",
            keyID: expectedCompany.keyID,
            issuerID: expectedCompany.issuerID,
            privateKeyContent: P256.Signing.PrivateKey().pemRepresentation
        )
        let service = try JWTService(company: expectedCompany)
        let unexpectedService = try JWTService(company: unexpectedCompany)
        let token = try await unexpectedService.getToken()

        let validation = await service.validateTokenDetails(token)

        #expect(validation.isValid == false)
        #expect(validation.failure == .invalidSignature)
    }

    @Test("auth_validate_token rejects incorrect App Store Connect header and company claims")
    func rejectsIncorrectHeaderAndClaims() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let company = authValidationCompany(privateKey: privateKey)
        let service = try JWTService(company: company)
        let now = Int(Date().timeIntervalSince1970)

        let wrongAlgorithm = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now + 600,
            algorithm: "HS256"
        )
        let wrongKeyID = try authValidationToken(
            privateKey: privateKey,
            keyID: "OTHER_KEY",
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now + 600
        )
        let wrongTokenType = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now + 600,
            tokenType: "NOT_JWT"
        )
        let wrongIssuer = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: "OTHER_ISSUER",
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now + 600
        )
        let wrongAudience = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "other-audience",
            issuedAt: now,
            expiration: now + 600
        )

        let wrongAlgorithmResult = await service.validateTokenDetails(wrongAlgorithm)
        let wrongKeyIDResult = await service.validateTokenDetails(wrongKeyID)
        let wrongTokenTypeResult = await service.validateTokenDetails(wrongTokenType)
        let wrongIssuerResult = await service.validateTokenDetails(wrongIssuer)
        let wrongAudienceResult = await service.validateTokenDetails(wrongAudience)

        #expect(wrongAlgorithmResult.failure == .unsupportedAlgorithm)
        #expect(wrongKeyIDResult.failure == .incorrectKeyID)
        #expect(wrongTokenTypeResult.failure == .incorrectTokenType)
        #expect(wrongIssuerResult.failure == .incorrectIssuer)
        #expect(wrongAudienceResult.failure == .incorrectAudience)
    }

    @Test("auth_validate_token rejects invalid times and a lifetime above 1200 seconds")
    func rejectsInvalidTimes() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let company = authValidationCompany(privateKey: privateKey)
        let service = try JWTService(company: company)
        let now = Int(Date().timeIntervalSince1970)
        let expired = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now - 600,
            expiration: now - 1
        )
        let futureIssued = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now + 120,
            expiration: now + 600
        )
        let nonIncreasingLifetime = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now
        )
        let excessiveLifetime = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now,
            expiration: now + 1201
        )
        let withinRefreshLeeway = try authValidationToken(
            privateKey: privateKey,
            keyID: company.keyID,
            issuerID: company.issuerID,
            audience: "appstoreconnect-v1",
            issuedAt: now - 100,
            expiration: now + 60
        )

        let expiredResult = await service.validateTokenDetails(expired)
        let futureIssuedResult = await service.validateTokenDetails(futureIssued)
        let nonIncreasingLifetimeResult = await service.validateTokenDetails(nonIncreasingLifetime)
        let excessiveLifetimeResult = await service.validateTokenDetails(excessiveLifetime)
        let withinRefreshLeewayResult = await service.validateTokenDetails(withinRefreshLeeway)

        #expect(expiredResult.failure == .expiredOrExpiring)
        #expect(futureIssuedResult.failure == .invalidIssuedAt)
        #expect(nonIncreasingLifetimeResult.failure == .invalidIssuedAt)
        #expect(excessiveLifetimeResult.failure == .excessiveLifetime)
        #expect(withinRefreshLeewayResult.failure == .expiredOrExpiring)
    }

    @Test("auth_validate_token reports malformed JWT header and payload")
    func rejectsMalformedJSON() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let company = authValidationCompany(privateKey: privateKey)
        let service = try JWTService(company: company)
        let now = Int(Date().timeIntervalSince1970)
        let validHeader = try JSONSerialization.data(withJSONObject: [
            "alg": "ES256",
            "kid": company.keyID,
            "typ": "JWT"
        ])
        let validPayload = try JSONSerialization.data(withJSONObject: [
            "iss": company.issuerID,
            "iat": now,
            "exp": now + 600,
            "aud": "appstoreconnect-v1"
        ])
        let malformedHeader = try authValidationSignedToken(
            privateKey: privateKey,
            header: Data("not-json".utf8),
            payload: validPayload
        )
        let malformedPayload = try authValidationSignedToken(
            privateKey: privateKey,
            header: validHeader,
            payload: Data("not-json".utf8)
        )

        let malformedHeaderResult = await service.validateTokenDetails(malformedHeader)
        let malformedPayloadResult = await service.validateTokenDetails(malformedPayload)

        #expect(malformedHeaderResult.failure == .malformedHeader)
        #expect(malformedPayloadResult.failure == .malformedPayload)
    }
}

private func authValidationCompany(
    privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()
) -> Company {
    Company(
        id: "auth-validation",
        name: "Auth Validation",
        keyID: "AUTH_KEY",
        issuerID: "AUTH_ISSUER",
        privateKeyContent: privateKey.pemRepresentation
    )
}

private func authValidationToken(
    privateKey: P256.Signing.PrivateKey,
    keyID: String,
    issuerID: String,
    audience: String,
    issuedAt: Int,
    expiration: Int,
    tokenType: String = "JWT",
    algorithm: String = "ES256"
) throws -> String {
    let header = try JSONSerialization.data(withJSONObject: [
        "alg": algorithm,
        "kid": keyID,
        "typ": tokenType
    ])
    let payload = try JSONSerialization.data(withJSONObject: [
        "iss": issuerID,
        "iat": issuedAt,
        "exp": expiration,
        "aud": audience
    ])
    return try authValidationSignedToken(privateKey: privateKey, header: header, payload: payload)
}

private func authValidationSignedToken(
    privateKey: P256.Signing.PrivateKey,
    header: Data,
    payload: Data
) throws -> String {
    let encodedHeader = authValidationBase64URL(header)
    let encodedPayload = authValidationBase64URL(payload)
    let signingInput = Data("\(encodedHeader).\(encodedPayload)".utf8)
    let signature = try privateKey.signature(for: signingInput)
    return "\(encodedHeader).\(encodedPayload).\(authValidationBase64URL(signature.rawRepresentation))"
}

private func authValidationBase64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func authValidationObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw AuthTokenValidationTestFailure.expectedObject
    }
    return object
}

private enum AuthTokenValidationTestFailure: Error {
    case expectedObject
}
