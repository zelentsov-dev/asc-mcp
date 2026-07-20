import Foundation
import os

/// HTTP client for App Store Connect API using URLSession
public actor HTTPClient {
    private let transport: any HTTPTransport
    private let jwtService: JWTService
    private let baseURL: String
    private let logger = Logger(subsystem: "com.asc-mcp", category: "HTTPClient")
    private var lastRateLimitInfo: ASCRateLimitInfo?

    // Retry configuration
    private let maxRetries: Int
    private let retryableStatusCodes = Set([408, 429, 500, 502, 503, 504])

    public init(
        jwtService: JWTService,
        baseURL: String,
        transport: (any HTTPTransport)? = nil,
        maxRetries: Int = 3
    ) async {
        self.jwtService = jwtService
        self.baseURL = baseURL
        self.maxRetries = maxRetries

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.transport = transport ?? URLSessionTransport(configuration: config)
    }

    /// Returns the last App Store Connect rate-limit state observed by this client.
    /// - Returns: Last parsed rate-limit header values, or nil if no rate-limit headers were seen.
    public func getLastRateLimitInfo() -> ASCRateLimitInfo? {
        lastRateLimitInfo
    }

    /// Fetches a pagination link only when it remains inside the supplied collection scope.
    /// - Parameters:
    ///   - nextURL: Absolute URL returned by an App Store Connect `links.next` field.
    ///   - scope: Exact collection path and query invariants established by the originating tool call.
    /// - Returns: Raw response data for the validated next page.
    /// - Throws: `ASCError` when the link is invalid, leaves the configured origin or scope, or the request fails.
    public func getPage(_ nextURL: String, scope: PaginationScope) async throws -> Data {
        let page = try validatedPaginationRequest(nextURL, baseURL: baseURL, scope: scope)
        return try await get(page.path, parameters: page.parameters)
    }

    /// Performs GET request to App Store Connect API
    public func get(_ endpoint: String, parameters: [String: String] = [:]) async throws -> Data {
        return try await request(.GET, endpoint: endpoint, parameters: parameters)
    }

    /// Performs POST request to App Store Connect API
    public func post(_ endpoint: String, body: Data? = nil) async throws -> Data {
        return try await request(.POST, endpoint: endpoint, body: body)
    }

    /// Performs PATCH request to App Store Connect API
    public func patch(_ endpoint: String, body: Data) async throws -> Data {
        return try await request(.PATCH, endpoint: endpoint, body: body)
    }

    /// Performs PUT request to App Store Connect API
    public func put(_ endpoint: String, body: Data) async throws -> Data {
        return try await request(.PUT, endpoint: endpoint, body: body)
    }

    /// Performs DELETE request to App Store Connect API
    public func delete(_ endpoint: String) async throws -> Data {
        return try await request(.DELETE, endpoint: endpoint)
    }

    /// Performs DELETE request with body (for relationship endpoints)
    public func delete(_ endpoint: String, body: Data) async throws -> Data {
        return try await request(.DELETE, endpoint: endpoint, body: body)
    }

    /// GET request with custom Accept header (for gzip reports like salesReports/financeReports)
    /// - Returns: Raw response data (may be gzip-compressed)
    public func getRaw(_ endpoint: String, parameters: [String: String] = [:], accept: String) async throws -> Data {
        return try await request(.GET, endpoint: endpoint, parameters: parameters, acceptHeader: accept)
    }

    /// Base method for HTTP requests with retry logic
    private func request(
        _ method: HTTPMethod,
        endpoint: String,
        parameters: [String: String] = [:],
        body: Data? = nil,
        acceptHeader: String = "application/json"
    ) async throws -> Data {

        let endpoint = try validatedASCAPIEndpoint(endpoint)

        // Safe URL construction
        guard var urlComponents = URLComponents(string: "\(baseURL)\(endpoint)") else {
            logger.error("Invalid URL components: \(self.baseURL)\(endpoint)")
            throw ASCError.network("Invalid URL: \(baseURL)\(endpoint)")
        }

        if !parameters.isEmpty {
            urlComponents.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            logger.error("Failed to create URL from components")
            throw ASCError.network("Failed to create URL from components")
        }

        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")

        // Add body if present
        if let body = body {
            request.httpBody = body
        }

        let retriesAmbiguousFailures = method == .GET || method == .PUT
        let maxAttempts = maxRetries

        for attempt in 0..<maxAttempts {
            // Get fresh token for each attempt (JWTService caches valid tokens)
            let token = try await jwtService.getToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            logger.debug("[\(method.rawValue)] \(url.absoluteString) - Attempt \(attempt + 1)/\(maxAttempts)")

            let startTime = Date()
            let data: Data
            let httpResponse: HTTPURLResponse
            do {
                (data, httpResponse) = try await transport.data(for: request)
            } catch let error as ASCError {
                if method == .DELETE,
                   let outcomeUnknown = Self.deleteOutcomeUnknownError(from: error) {
                    throw outcomeUnknown
                }
                throw error
            } catch {
                if error is CancellationError, method != .DELETE {
                    throw CancellationError()
                }
                if attempt < maxAttempts - 1 && retriesAmbiguousFailures {
                    let delay = calculateRetryDelay(attempt: attempt, response: nil)
                    logger.warning("Network error: \(error.localizedDescription), retrying in \(delay)s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                logger.error("Network request failed: \(error.localizedDescription)")
                let networkError = ASCError.network("HTTP request failed: \(error.localizedDescription)")
                if method == .DELETE,
                   let outcomeUnknown = Self.deleteOutcomeUnknownError(from: networkError) {
                    throw outcomeUnknown
                }
                throw networkError
            }

            let duration = Date().timeIntervalSince(startTime)
            updateRateLimitInfo(from: httpResponse)
            logger.debug("Response: \(httpResponse.statusCode) in \(String(format: "%.2f", duration))s")

            if 200...299 ~= httpResponse.statusCode {
                return data
            }

            let apiErrorResponse = decodeAPIErrorResponse(from: data)
            let errorMessage = apiErrorResponse?.errors.map(\.safeDescription).joined(separator: "; ")
                ?? "Unknown App Store Connect API error"

            if httpResponse.statusCode == 401 && attempt < maxAttempts - 1 {
                logger.warning("401 Unauthorized, refreshing JWT token and retrying")
                _ = try await jwtService.refreshToken()
                try await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            if attempt < maxAttempts - 1 {
                let isRetryable: Bool
                if retriesAmbiguousFailures {
                    isRetryable = retryableStatusCodes.contains(httpResponse.statusCode)
                } else {
                    isRetryable = httpResponse.statusCode == 429
                }

                if isRetryable {
                    let delay = calculateRetryDelay(attempt: attempt, response: httpResponse)
                    logger.warning("Retryable error \(httpResponse.statusCode), waiting \(delay)s before retry")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }

            logger.error("HTTP error \(httpResponse.statusCode): \(Redactor.redact(errorMessage))")
            let responseError: ASCError
            if let apiErrorResponse {
                responseError = .apiResponse(apiErrorResponse, httpResponse.statusCode)
            } else {
                responseError = .api(errorMessage, httpResponse.statusCode)
            }
            if method == .DELETE,
               let outcomeUnknown = Self.deleteOutcomeUnknownError(from: responseError) {
                throw outcomeUnknown
            }
            throw responseError
        }

        throw ASCError.network("Maximum retry attempts exceeded before a request was sent")
    }

    private static func deleteOutcomeUnknownError(from error: ASCError) -> ASCError? {
        if case .deleteOutcomeUnknown = error {
            return nil
        }

        switch error {
        case .network(let message):
            return .deleteOutcomeUnknown(.network(message))
        case .api(let message, let statusCode)
            where statusCode == 408 || (500...599).contains(statusCode):
            return .deleteOutcomeUnknown(.api(message, statusCode))
        case .apiResponse(_, let statusCode)
            where statusCode == 408 || (500...599).contains(statusCode):
            return .deleteOutcomeUnknown(error)
        default:
            return nil
        }
    }

    /// Calculates retry delay with exponential backoff
    private func calculateRetryDelay(attempt: Int, response: HTTPURLResponse?) -> Double {
        // Check Retry-After header
        if let response = response,
           let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let retryAfter = Self.parseRetryAfter(retryAfterString) {
            return retryAfter
        }

        // Exponential backoff with jitter
        let baseDelay = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...1)
        return min(baseDelay + jitter, 30) // Maximum 30 seconds
    }

    private func updateRateLimitInfo(from response: HTTPURLResponse) {
        let appleHeader = response.value(forHTTPHeaderField: "X-Rate-Limit")
            .flatMap(Self.parseAppleRateLimitHeader)
        let limit = appleHeader?.limit ?? response.integerHeader("X-Rate-Limit-User-Hour-Limit")
        let remaining = appleHeader?.remaining ?? response.integerHeader("X-Rate-Limit-User-Hour-Remaining")
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { Self.parseRetryAfter($0) }

        guard limit != nil || remaining != nil || retryAfter != nil else {
            return
        }

        lastRateLimitInfo = ASCRateLimitInfo(
            userHourLimit: limit,
            userHourRemaining: remaining,
            retryAfterSeconds: retryAfter,
            observedAt: Date()
        )
    }

    private func decodeAPIErrorResponse(from data: Data) -> ASCAPIErrorResponse? {
        try? JSONDecoder().decode(ASCAPIErrorResponse.self, from: data)
    }

    private static func parseAppleRateLimitHeader(_ header: String) -> (limit: Int?, remaining: Int?) {
        var limit: Int?
        var remaining: Int?

        for part in header.split(separator: ";") {
            let pair = part.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2 else { continue }

            switch pair[0] {
            case "user-hour-lim":
                limit = Int(pair[1])
            case "user-hour-rem":
                remaining = Int(pair[1])
            default:
                continue
            }
        }

        return (limit, remaining)
    }

    private static func parseRetryAfter(_ value: String, now: Date = Date()) -> Double? {
        if let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        guard let date = formatter.date(from: value) else {
            return nil
        }

        return max(0, date.timeIntervalSince(now))
    }
}

/// HTTP methods
private enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

private extension HTTPURLResponse {
    func integerHeader(_ name: String) -> Int? {
        value(forHTTPHeaderField: name).flatMap(Int.init)
    }
}

// MARK: - Convenience Methods

extension HTTPClient {
    /// Fetches and decodes a pagination link after enforcing its originating collection scope.
    /// - Parameters:
    ///   - nextURL: Absolute URL returned by an App Store Connect `links.next` field.
    ///   - scope: Exact collection path and query invariants established by the originating tool call.
    ///   - type: Response type expected from the originating collection.
    /// - Returns: Decoded response for the validated next page.
    /// - Throws: `ASCError` when validation, transport, or decoding fails.
    public func getPage<T: Codable & Sendable>(
        _ nextURL: String,
        scope: PaginationScope,
        as type: T.Type
    ) async throws -> T {
        let data = try await getPage(nextURL, scope: scope)

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCError.parsing("Failed to decode \(type): \(error.localizedDescription)")
        }
    }

    /// Decodes JSON response into specified type
    public func get<T: Codable & Sendable>(_ endpoint: String, parameters: [String: String] = [:], as type: T.Type) async throws -> T {
        let data = try await get(endpoint, parameters: parameters)

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCError.parsing("Failed to decode \(type): \(error.localizedDescription)")
        }
    }

    /// POST request with JSON body encoding
    public func post<T: Codable & Sendable, R: Codable & Sendable>(_ endpoint: String, body: T, as responseType: R.Type) async throws -> R {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw ASCError.parsing("Failed to encode request body: \(error.localizedDescription)")
        }

        let responseData = try await post(endpoint, body: bodyData)

        do {
            return try JSONDecoder().decode(responseType, from: responseData)
        } catch {
            throw ASCError.parsing("Failed to decode \(responseType): \(error.localizedDescription)")
        }
    }

    /// PATCH request for updating resources
    public func patch<T: Codable & Sendable, R: Codable & Sendable>(_ endpoint: String, body: T, as responseType: R.Type) async throws -> R {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw ASCError.parsing("Failed to encode request body: \(error.localizedDescription)")
        }

        let responseData = try await request(.PATCH, endpoint: endpoint, body: bodyData)

        do {
            return try JSONDecoder().decode(responseType, from: responseData)
        } catch {
            throw ASCError.parsing("Failed to decode \(responseType): \(error.localizedDescription)")
        }
    }

    /// PUT request with JSON encoding
    public func put<T: Codable & Sendable, R: Codable & Sendable>(_ endpoint: String, body: T, as responseType: R.Type) async throws -> R {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw ASCError.parsing("Failed to encode request body: \(error.localizedDescription)")
        }

        let responseData = try await put(endpoint, body: bodyData)

        do {
            return try JSONDecoder().decode(responseType, from: responseData)
        } catch {
            throw ASCError.parsing("Failed to decode \(responseType): \(error.localizedDescription)")
        }
    }

    /// DELETE request with JSON body encoding
    public func delete<T: Codable & Sendable>(_ endpoint: String, body: T) async throws -> Data {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw ASCError.parsing("Failed to encode request body: \(error.localizedDescription)")
        }
        return try await delete(endpoint, body: bodyData)
    }
}
