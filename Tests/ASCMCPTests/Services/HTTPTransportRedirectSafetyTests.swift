import Foundation
import Testing
@testable import asc_mcp

@Suite("HTTP Transport Redirect Safety Tests")
struct HTTPTransportRedirectSafetyTests {
    @Test(
        "App Store Connect transport refuses every redirect and authorization forwarding",
        arguments: ["GET", "POST", "PUT", "PATCH", "DELETE"]
    )
    func redirectDelegateRefusesReplay(_ method: String) {
        let delegate = ASCAPIRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        var originalRequest = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/resources")!)
        originalRequest.httpMethod = method
        originalRequest.httpBody = Data(#"{"value":"original"}"#.utf8)
        originalRequest.setValue("Bearer asc-jwt", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: originalRequest)
        defer { task.cancel() }

        let redirectResponse = HTTPURLResponse(
            url: originalRequest.url!,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://redirect.example.test/capture"]
        )!
        var proposedRequest = URLRequest(url: URL(string: "https://redirect.example.test/capture")!)
        proposedRequest.httpMethod = method
        proposedRequest.httpBody = originalRequest.httpBody
        proposedRequest.setValue("Bearer asc-jwt", forHTTPHeaderField: "Authorization")
        let completion = RedirectDecisionRecorder()

        #expect(proposedRequest.url?.host != originalRequest.url?.host)
        #expect(proposedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer asc-jwt")

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: redirectResponse,
            newRequest: proposedRequest
        ) { request in
            completion.record(request)
        }

        let result = completion.result()
        #expect(result.callCount == 1)
        #expect(result.forwardedRequests.isEmpty)
    }

    @Test("production URLSession transport returns the original redirect without replay")
    func productionTransportWiresRedirectDelegate() async throws {
        ProductionRedirectURLProtocol.recorder.reset()
        defer { ProductionRedirectURLProtocol.recorder.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionRedirectURLProtocol.self]
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let transport = URLSessionTransport(configuration: configuration)

        var request = URLRequest(url: ProductionRedirectURLProtocol.initialURL)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"value":"original"}"#.utf8)
        request.setValue("Bearer asc-jwt", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.data(for: request)

        #expect(response.statusCode == 307)
        #expect(response.url == ProductionRedirectURLProtocol.initialURL)
        #expect(data == ProductionRedirectURLProtocol.originalBody)
        #expect(
            ProductionRedirectURLProtocol.recorder.count(for: ProductionRedirectURLProtocol.initialURL) == 1
        )
        #expect(
            ProductionRedirectURLProtocol.recorder.count(for: ProductionRedirectURLProtocol.targetURL) == 0
        )
    }

    @Test(
        "non-idempotent requests preserve the original redirect failure without retry",
        arguments: ["POST", "PATCH", "DELETE"]
    )
    func mutationRedirectRemainsUnknown(_ method: String) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 307,
                headers: ["Location": "https://redirect.example.test/capture"],
                body: #"{"errors":[{"status":"307","code":"REDIRECT","detail":"original redirect receipt"}]}"#
            ),
            .init(statusCode: 204, body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.appstoreconnect.apple.com",
            transport: transport,
            maxRetries: 3
        )

        do {
            switch method {
            case "POST":
                _ = try await client.postReceipt("/v1/resources", body: Data(#"{"value":1}"#.utf8))
            case "PATCH":
                _ = try await client.patchReceipt("/v1/resources/resource-1", body: Data(#"{"value":1}"#.utf8))
            default:
                _ = try await client.deleteReceipt("/v1/resources/resource-1")
            }
            Issue.record("Expected the original HTTP 307 response")
        } catch let error as ASCError {
            let cause: ASCError
            switch (method, error) {
            case ("DELETE", .deleteOutcomeUnknown(let underlying)):
                cause = underlying
            case (_, .mutationOutcomeUnknown(let actualMethod, let underlying)):
                #expect(actualMethod == method)
                cause = underlying
            default:
                Issue.record("Expected a typed unknown mutation outcome, got \(error)")
                return
            }
            guard case .apiResponse(let response, let statusCode) = cause else {
                Issue.record("Expected the original App Store Connect redirect response, got \(cause)")
                return
            }
            #expect(statusCode == 307)
            #expect(response.errors.first?.safeDescription.contains("original redirect receipt") == true)
            #expect(
                ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request)
                    == .outcomeUnknown
            )
        }

        #expect(await transport.requestCount() == 1)
        let requests = await transport.recordedRequests()
        #expect(requests.first?.httpMethod == method)
        #expect(requests.first?.url?.host == "api.appstoreconnect.apple.com")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    }
}

private final class ProductionRedirectURLProtocol: URLProtocol, @unchecked Sendable {
    static let initialURL = URL(string: "https://redirect-source.example.test/v1/resources")!
    static let targetURL = URL(string: "https://redirect-target.example.test/capture")!
    static let originalBody = Data("original redirect response".utf8)
    static let recorder = RedirectRequestRecorder()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == initialURL.host || host == targetURL.host
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.recorder.record(request)
        if url == Self.initialURL {
            loadRedirectResponse()
        } else {
            loadTargetResponse(at: url)
        }
    }

    override func stopLoading() {}

    private func loadRedirectResponse() {
        guard let response = HTTPURLResponse(
            url: Self.initialURL,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Length": String(Self.originalBody.count),
                "Location": Self.targetURL.absoluteString
            ]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        var redirectedRequest = request
        redirectedRequest.url = Self.targetURL
        client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.originalBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func loadTargetResponse(at url: URL) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("redirect target reached".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class RedirectDecisionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var forwardedRequests: [URLRequest] = []

    func record(_ request: URLRequest?) {
        lock.lock()
        callCount += 1
        if let request {
            forwardedRequests.append(request)
        }
        lock.unlock()
    }

    func result() -> (callCount: Int, forwardedRequests: [URLRequest]) {
        lock.lock()
        let result = (callCount, forwardedRequests)
        lock.unlock()
        return result
    }
}

private final class RedirectRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }

    func record(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func count(for url: URL) -> Int {
        lock.lock()
        let count = requests.count { $0.url == url }
        lock.unlock()
        return count
    }
}
