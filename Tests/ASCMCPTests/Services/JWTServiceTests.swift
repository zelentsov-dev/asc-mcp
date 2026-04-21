import Testing
import Foundation
import CryptoKit
@testable import asc_mcp

@Suite("JWTService Tests")
struct JWTServiceTests {

    // MARK: - Helpers

    private func makeCompany() -> Company {
        TestFactory.makeCompany()
    }

    // MARK: - Init

    @Test("Create service with valid in-memory key")
    func createService() throws {
        _ = try JWTService(company: makeCompany())
    }

    @Test("Invalid key content throws ASCError.configuration")
    func invalidKeyThrows() {
        let company = Company(
            id: "bad", name: "Bad",
            keyID: "K", issuerID: "I",
            privateKeyContent: "not-a-valid-key"
        )
        #expect(throws: ASCError.self) {
            _ = try JWTService(company: company)
        }
    }

    @Test("Empty key content and empty path throws ASCError.configuration")
    func emptyKeyThrows() {
        let company = Company(
            id: "empty", name: "Empty",
            keyID: "K", issuerID: "I",
            privateKeyPath: "",
            privateKeyContent: ""
        )
        #expect(throws: ASCError.self) {
            _ = try JWTService(company: company)
        }
    }

    // MARK: - Token format

    @Test("Token has three dot-separated parts (header.payload.signature)")
    func tokenFormat() async throws {
        let service = try JWTService(company: makeCompany())
        let token = try await service.getToken()
        let parts = token.split(separator: ".")
        #expect(parts.count == 3)
    }

    // MARK: - Token claims

    @Test("Token payload contains correct issuer and audience claims")
    func tokenClaims() async throws {
        let company = makeCompany()
        let service = try JWTService(company: company)
        let token = try await service.getToken()

        let payload = try decodeJWTPayload(token)

        #expect(payload["iss"] as? String == company.issuerID)
        #expect(payload["aud"] as? String == "appstoreconnect-v1")
        #expect(payload["exp"] is Int)
        #expect(payload["iat"] is Int)
    }

    @Test("Individual key payload has sub user and no iss")
    func individualKey_payloadHasSubUser_noIss() async throws {
        let individual = TestFactory.makeIndividualCompany()
        let company = Company(
            id: individual.id,
            name: individual.name,
            keyID: individual.keyID,
            issuerID: individual.issuerID,
            privateKeyPath: individual.privateKeyPath,
            privateKeyContent: TestFactory.testPEM
        )
        let service = try JWTService(company: company)
        let token = try await service.getToken()

        let payload = try decodeJWTPayload(token)
        let rawPayload = try decodePayloadRawString(token)

        #expect(payload["sub"] as? String == "user")
        #expect(rawPayload.contains("\"iss\"") == false)
        #expect(payload["aud"] as? String == "appstoreconnect-v1")
    }

    @Test("Individual key header remains unchanged")
    func individualKey_headerUnchanged() async throws {
        let individual = TestFactory.makeIndividualCompany()
        let company = Company(
            id: individual.id,
            name: individual.name,
            keyID: individual.keyID,
            issuerID: individual.issuerID,
            privateKeyPath: individual.privateKeyPath,
            privateKeyContent: TestFactory.testPEM
        )
        let service = try JWTService(company: company)
        let token = try await service.getToken()

        let header = try decodeJWTHeader(token)

        #expect(header["alg"] as? String == "ES256")
        #expect(header["typ"] as? String == "JWT")
        #expect(header["kid"] as? String == company.keyID)
    }

    @Test("Individual key token duration is 1200 seconds")
    func individualKey_duration1200() async throws {
        let individual = TestFactory.makeIndividualCompany()
        let company = Company(
            id: individual.id,
            name: individual.name,
            keyID: individual.keyID,
            issuerID: individual.issuerID,
            privateKeyPath: individual.privateKeyPath,
            privateKeyContent: TestFactory.testPEM
        )
        let service = try JWTService(company: company)
        let token = try await service.getToken()

        let payload = try decodeJWTPayload(token)

        let exp = try #require(payload["exp"] as? Int)
        let iat = try #require(payload["iat"] as? Int)
        #expect(exp - iat == 1200)
    }

    @Test("Team key payload has iss and no sub")
    func teamKey_payloadHasIss_noSub() async throws {
        let company = makeCompany()
        let service = try JWTService(company: company)
        let token = try await service.getToken()

        let payload = try decodeJWTPayload(token)
        let rawPayload = try decodePayloadRawString(token)

        #expect(payload["iss"] as? String == company.issuerID)
        #expect(rawPayload.contains("\"sub\"") == false)
    }

    @Test("Token expires in exactly 20 minutes (1200 seconds)")
    func tokenExpiration() async throws {
        let service = try JWTService(company: makeCompany())
        let token = try await service.getToken()

        let payload = try decodeJWTPayload(token)

        let exp = try #require(payload["exp"] as? Int)
        let iat = try #require(payload["iat"] as? Int)
        let duration = exp - iat
        #expect(duration == 1200) // 20 minutes
    }

    // MARK: - Caching

    @Test("Consecutive getToken calls return the same cached token")
    func tokenCaching() async throws {
        let service = try JWTService(company: makeCompany())
        let token1 = try await service.getToken()
        let token2 = try await service.getToken()
        #expect(token1 == token2)
    }

    // MARK: - Cache info

    @Test("Cache info reports no token before first generation")
    func cacheInfoBeforeGeneration() async throws {
        let service = try JWTService(company: makeCompany())
        let info = await service.getCacheInfo()
        #expect(info.hasCachedToken == false)
        #expect(info.isValid == nil)
        #expect(info.expiresInSeconds == nil)
    }

    @Test("Cache info reports valid token after generation")
    func cacheInfoAfterGeneration() async throws {
        let service = try JWTService(company: makeCompany())
        _ = try await service.getToken()
        let info = await service.getCacheInfo()
        #expect(info.hasCachedToken == true)
        #expect(info.isValid == true)
        #expect(info.expiresInSeconds != nil)
        #expect(info.expirationDate != nil)
    }

    @Test("Cache info refreshLeewaySeconds is 90")
    func cacheInfoLeeway() async throws {
        let service = try JWTService(company: makeCompany())
        let info = await service.getCacheInfo()
        #expect(info.refreshLeewaySeconds == 90)
    }

    // MARK: - Refresh

    @Test("refreshToken generates a new token different from the cached one")
    func refreshToken() async throws {
        let service = try JWTService(company: makeCompany())
        let token1 = try await service.getToken()
        // Small delay so iat differs
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let token2 = try await service.refreshToken()
        #expect(token1 != token2)
    }

    // MARK: - Validate

    @Test("A freshly generated token is valid")
    func validateToken() async throws {
        let service = try JWTService(company: makeCompany())
        let token = try await service.getToken()
        let isValid = await service.validateToken(token)
        #expect(isValid == true)
    }

    @Test("A garbage string is not a valid token")
    func validateGarbageToken() async throws {
        let service = try JWTService(company: makeCompany())
        let isValid = await service.validateToken("not.a.token")
        #expect(isValid == false)
    }

    // MARK: - JWT Decode Helper

    private func decodeJWTPayload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw TestError(message: "Invalid JWT format")
        }
        var payloadBase64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payloadBase64.count % 4 != 0 { payloadBase64 += "=" }

        let payloadData = try #require(Data(base64Encoded: payloadBase64))
        let payload = try #require(
            try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )
        return payload
    }

    private func decodeJWTHeader(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw TestError(message: "Invalid JWT format")
        }
        var headerBase64 = String(parts[0])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while headerBase64.count % 4 != 0 { headerBase64 += "=" }

        let headerData = try #require(Data(base64Encoded: headerBase64))
        let header = try #require(
            try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        )
        return header
    }

    private func decodePayloadRawString(_ token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw TestError(message: "Invalid JWT format")
        }
        var payloadBase64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payloadBase64.count % 4 != 0 { payloadBase64 += "=" }

        let payloadData = try #require(Data(base64Encoded: payloadBase64))
        return try #require(String(data: payloadData, encoding: .utf8))
    }
}

private struct TestError: Error {
    let message: String
}
