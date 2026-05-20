import Foundation
import Testing
@testable import asc_mcp

@Suite("HTTP Client Tests")
struct HTTPClientTests {
    @Test("retries 429 and stores Apple X-Rate-Limit header")
    func retries429AndStoresRateLimitHeaders() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(statusCode: 429, headers: ["Retry-After": "0"], body: #"{"errors":[{"status":"429","detail":"rate limited"}]}"#),
            .init(
                statusCode: 200,
                headers: [
                    "X-Rate-Limit": "user-hour-lim:3600;user-hour-rem:3599;"
                ],
                body: #"{"ok":true}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        let data = try await client.get("/v1/apps")

        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        #expect(await transport.requestCount() == 2)
        let rateLimit = await client.getLastRateLimitInfo()
        #expect(rateLimit?.userHourLimit == 3600)
        #expect(rateLimit?.userHourRemaining == 3599)
    }

    @Test("stores legacy split rate-limit headers")
    func storesLegacySplitRateLimitHeaders() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(
                statusCode: 200,
                headers: [
                    "X-Rate-Limit-User-Hour-Limit": "3600",
                    "X-Rate-Limit-User-Hour-Remaining": "3598"
                ],
                body: #"{"ok":true}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )

        _ = try await client.get("/v1/apps")

        let rateLimit = await client.getLastRateLimitInfo()
        #expect(rateLimit?.userHourLimit == 3600)
        #expect(rateLimit?.userHourRemaining == 3598)
    }

    @Test("refreshes token on 401 and retries")
    func refreshesOn401() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(statusCode: 401, body: #"{"errors":[{"status":"401","detail":"expired"}]}"#),
            .init(statusCode: 200, body: #"{"ok":true}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        _ = try await client.get("/v1/apps")

        #expect(await transport.requestCount() == 2)
    }

    @Test("decodes Apple error response")
    func decodesAppleErrorResponse() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(statusCode: 403, body: #"{"errors":[{"id":"1","status":"403","code":"FORBIDDEN","title":"Forbidden","detail":"Role is missing"}]}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )

        do {
            _ = try await client.get("/v1/apps")
            Issue.record("Expected ASCError.apiResponse")
        } catch let error as ASCError {
            guard case .apiResponse(let response, let statusCode) = error else {
                Issue.record("Expected apiResponse, got \(error)")
                return
            }
            #expect(statusCode == 403)
            #expect(response.errors.first?.code == "FORBIDDEN")
            #expect(error.errorDescription?.contains("Role is missing") == true)
        }
    }

    @Test("honors numeric Retry-After without failing")
    func honorsNumericRetryAfter() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(statusCode: 503, headers: ["Retry-After": "0"], body: #"{"errors":[{"status":"503","detail":"busy"}]}"#),
            .init(statusCode: 200, body: #"{"ok":true}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        _ = try await client.get("/v1/apps")

        #expect(await transport.requestCount() == 2)
    }

    @Test("honors HTTP-date Retry-After without failing")
    func honorsHTTPDateRetryAfter() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(statusCode: 503, headers: ["Retry-After": "Fri, 31 Dec 1999 23:59:59 GMT"], body: #"{"errors":[{"status":"503","detail":"busy"}]}"#),
            .init(statusCode: 200, body: #"{"ok":true}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        _ = try await client.get("/v1/apps")

        #expect(await transport.requestCount() == 2)
    }

    @Test("stores past HTTP-date Retry-After as zero seconds")
    func storesPastHTTPDateRetryAfterAsZero() async throws {
        let transport = MockHTTPTransport(responses: [
            .init(
                statusCode: 200,
                headers: ["Retry-After": "Fri, 31 Dec 1999 23:59:59 GMT"],
                body: #"{"ok":true}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )

        _ = try await client.get("/v1/apps")

        let rateLimit = await client.getLastRateLimitInfo()
        #expect(rateLimit?.retryAfterSeconds == 0)
    }
}

private actor MockHTTPTransport: HTTPTransport {
    struct Response: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let data: Data

        init(statusCode: Int, headers: [String: String] = [:], body: String) {
            self.statusCode = statusCode
            self.headers = headers
            self.data = Data(body.utf8)
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw ASCError.network("No mock response queued")
        }
        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.data, httpResponse)
    }

    func requestCount() -> Int {
        requests.count
    }
}
