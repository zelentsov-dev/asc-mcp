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

    @Test(
        "GET accepts only the Apple-documented 200 status",
        arguments: [201, 202, 206, 299]
    )
    func getRejectsUnexpectedSuccessfulStatus(_ statusCode: Int) async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: statusCode, headers: [:], body: #"{"data":[]}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        do {
            _ = try await client.get("/v1/apps")
            Issue.record("Expected GET to reject HTTP \(statusCode)")
        } catch let error as ASCError {
            guard case .api(let message, let actualStatusCode) = error else {
                Issue.record("Expected a typed API status error, got \(error)")
                return
            }
            #expect(actualStatusCode == statusCode)
            #expect(message.contains("expected 200"))
        }

        #expect(await transport.requestCount() == 1)
    }

    @Test(
        "raw GET accepts only the Apple-documented 200 status",
        arguments: [201, 202, 206, 299]
    )
    func rawGetRejectsUnexpectedSuccessfulStatus(_ statusCode: Int) async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: statusCode, headers: [:], body: "payload")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        do {
            _ = try await client.getRaw(
                "/v1/salesReports",
                accept: "application/a-gzip"
            )
            Issue.record("Expected raw GET to reject HTTP \(statusCode)")
        } catch let error as ASCError {
            guard case .api(let message, let actualStatusCode) = error else {
                Issue.record("Expected a typed API status error, got \(error)")
                return
            }
            #expect(actualStatusCode == statusCode)
            #expect(message.contains("expected 200"))
        }

        #expect(await transport.requestCount() == 1)
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

    @Test("generic DELETE accepts exact 204 with and without a body")
    func genericDeleteAcceptsExact204() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 204, headers: [:], body: ""),
            .response(statusCode: 204, headers: [:], body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        let unqualifiedResult = try await client.delete("/v1/resources/resource-1")
        let relationshipResult = try await client.delete(
            "/v1/resources/resource-1/relationships/apps",
            body: Data(#"{"data":[]}"#.utf8)
        )

        #expect(unqualifiedResult.isEmpty)
        #expect(relationshipResult.isEmpty)
        #expect(await transport.requestCount() == 2)
    }

    @Test(
        "generic DELETE treats unexpected successful status as committed but unverified",
        arguments: [200, 201, 202, 206, 299]
    )
    func genericDeleteRejectsUnexpectedSuccessfulStatus(_ expectedStatusCode: Int) async throws {
        for includesBody in [false, true] {
            let transport = ScriptedHTTPTransport(steps: [
                .response(statusCode: expectedStatusCode, headers: [:], body: #"{"accepted":true}"#),
                .response(statusCode: 204, headers: [:], body: "")
            ])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 2
            )

            do {
                if includesBody {
                    _ = try await client.delete(
                        "/v1/resources/resource-1/relationships/apps",
                        body: Data(#"{"data":[]}"#.utf8)
                    )
                } else {
                    _ = try await client.delete("/v1/resources/resource-1")
                }
                Issue.record("Expected a committed-unverified DELETE error for HTTP \(expectedStatusCode)")
            } catch let error as ASCError {
                guard case .deleteCommittedUnverified(let statusCode) = error else {
                    Issue.record("Expected deleteCommittedUnverified, got \(error)")
                    continue
                }
                #expect(statusCode == expectedStatusCode)
                #expect(error.localizedDescription.contains("completion is unverified"))
                #expect(error.localizedDescription.contains("Inspect the exact target"))
            }

            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("DELETE does not retry an ambiguous network failure")
    func deleteDoesNotRetryNetworkFailure() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .networkFailure,
            .response(statusCode: 204, headers: [:], body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        do {
            _ = try await client.delete("/v1/resources/resource-1")
            Issue.record("Expected an ambiguous network error")
        } catch let error as ASCError {
            guard case .deleteOutcomeUnknown(let cause) = error else {
                Issue.record("Expected an unknown mutation outcome, got \(error)")
                return
            }
            guard case .network(let message) = cause else {
                Issue.record("Expected an underlying network error, got \(cause)")
                return
            }
            #expect(message.contains("HTTP request failed"))
            #expect(error.localizedDescription.contains("DELETE outcome is unknown"))
            #expect(error.localizedDescription.contains("Inspect the exact target"))
        }

        #expect(await transport.requestCount() == 1)
    }

    @Test("DELETE does not retry ambiguous HTTP failures")
    func deleteDoesNotRetryAmbiguousHTTPFailures() async throws {
        for expectedStatusCode in [408, 500, 502, 503, 504] {
            let transport = ScriptedHTTPTransport(steps: [
                .response(
                    statusCode: expectedStatusCode,
                    headers: ["Retry-After": "0"],
                    body: #"{"errors":[{"status":"\#(expectedStatusCode)","detail":"failed"}]}"#
                ),
                .response(statusCode: 204, headers: [:], body: "")
            ])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 2
            )

            do {
                _ = try await client.delete("/v1/resources/resource-1")
                Issue.record("Expected an API error for \(expectedStatusCode)")
            } catch let error as ASCError {
                guard case .deleteOutcomeUnknown(let cause) = error,
                      case .apiResponse(let response, let statusCode) = cause else {
                    Issue.record("Expected an unknown-outcome API error, got \(error)")
                    return
                }
                #expect(statusCode == expectedStatusCode)
                #expect(response.errors.first?.safeDescription.contains("failed") == true)
                #expect(error.localizedDescription.contains("DELETE outcome is unknown"))
                #expect(error.localizedDescription.contains("Inspect the exact target"))
            }

            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("DELETE retries a rate-limit rejection")
    func deleteRetriesRateLimitRejection() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 429,
                headers: ["Retry-After": "0"],
                body: #"{"errors":[{"status":"429","detail":"rate limited"}]}"#
            ),
            .response(statusCode: 204, headers: [:], body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        _ = try await client.delete("/v1/resources/resource-1")

        #expect(await transport.requestCount() == 2)
    }

    @Test("DELETE refreshes authorization after a 401 rejection")
    func deleteRefreshesAuthorizationAfter401() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 401,
                headers: [:],
                body: #"{"errors":[{"status":"401","detail":"expired"}]}"#
            ),
            .response(statusCode: 204, headers: [:], body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        _ = try await client.delete("/v1/resources/resource-1")

        #expect(await transport.requestCount() == 2)
    }

    @Test("DELETE cancellation during a definite retry delay stays cancellation")
    func deleteCancellationDuringDefiniteRetryDelayStaysCancellation() async throws {
        for statusCode in [401, 429] {
            let headers = statusCode == 429 ? ["Retry-After": "30"] : [:]
            let transport = RetryCancellationGateHTTPTransport(
                statusCode: statusCode,
                headers: headers
            )
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 2
            )
            let task = Task {
                try await client.delete("/v1/resources/resource-1")
            }

            await transport.waitForFirstRequest()
            task.cancel()
            await transport.releaseFirstResponse()

            do {
                _ = try await task.value
                Issue.record("Expected cancellation after HTTP \(statusCode)")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected CancellationError after HTTP \(statusCode), got \(error)")
            }
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("PUT retains retry behavior for a transient server failure")
    func putRetainsTransientFailureRetry() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 500,
                headers: ["Retry-After": "0"],
                body: #"{"errors":[{"status":"500","detail":"failed"}]}"#
            ),
            .response(statusCode: 200, headers: [:], body: #"{"ok":true}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        let data = try await client.put("/v1/resources/resource-1", body: Data())

        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        #expect(await transport.requestCount() == 2)
    }

    @Test("mutation receipts preserve the exact successful status")
    func mutationReceiptsPreserveExactSuccessfulStatus() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 201, headers: [:], body: #"{"data":{"id":"created"}}"#),
            .response(statusCode: 200, headers: [:], body: #"{"data":{"id":"updated"}}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 2
        )

        let create = try await client.postReceipt("/v1/resources", body: Data())
        let update = try await client.patchReceipt("/v1/resources/resource-1", body: Data())

        #expect(create.statusCode == 201)
        #expect(String(data: create.data, encoding: .utf8)?.contains("created") == true)
        #expect(update.statusCode == 200)
        #expect(String(data: update.data, encoding: .utf8)?.contains("updated") == true)
        #expect(await transport.requestCount() == 2)
    }

    @Test("POST and PATCH do not repeat ambiguous server failures")
    func mutationsDoNotRepeatAmbiguousServerFailures() async throws {
        for method in ["POST", "PATCH"] {
            let transport = ScriptedHTTPTransport(steps: [
                .response(
                    statusCode: 500,
                    headers: ["Retry-After": "0"],
                    body: #"{"errors":[{"status":"500","detail":"failed"}]}"#
                ),
                .response(statusCode: 200, headers: [:], body: #"{"data":{}}"#)
            ])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 2
            )

            do {
                if method == "POST" {
                    _ = try await client.postReceipt("/v1/resources", body: Data())
                } else {
                    _ = try await client.patchReceipt("/v1/resources/resource-1", body: Data())
                }
                Issue.record("Expected HTTP 500 for \(method)")
            } catch let error as ASCError {
                guard case .apiResponse(_, let statusCode) = error else {
                    Issue.record("Expected a typed API response error for \(method), got \(error)")
                    continue
                }
                #expect(statusCode == 500)
            }

            #expect(await transport.requestCount() == 1)
        }
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

private actor ScriptedHTTPTransport: HTTPTransport {
    enum Step: Sendable {
        case networkFailure
        case response(statusCode: Int, headers: [String: String], body: String)
    }

    private var steps: [Step]
    private var requests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else {
            throw URLError(.badServerResponse)
        }

        switch steps.removeFirst() {
        case .networkFailure:
            throw URLError(.networkConnectionLost)
        case .response(let statusCode, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.example.test")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (Data(body.utf8), response)
        }
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor RetryCancellationGateHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private let headers: [String: String]
    private var requests = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(statusCode: Int, headers: [String: String]) {
        self.statusCode = statusCode
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        if requests == 1 {
            let waiters = requestWaiters
            requestWaiters.removeAll(keepingCapacity: true)
            waiters.forEach { $0.resume() }
            if !released {
                await withCheckedContinuation { continuation in
                    releaseWaiters.append(continuation)
                }
            }
            return response(
                for: request,
                statusCode: statusCode,
                headers: headers,
                body: #"{"errors":[{"status":"\#(statusCode)","detail":"rejected"}]}"#
            )
        }

        return response(for: request, statusCode: 204, headers: [:], body: "")
    }

    func waitForFirstRequest() async {
        guard requests == 0 else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func releaseFirstResponse() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    func requestCount() -> Int {
        requests
    }

    private func response(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String],
        body: String
    ) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (Data(body.utf8), response)
    }
}
