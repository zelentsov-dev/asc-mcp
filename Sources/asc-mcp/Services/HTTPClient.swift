import Foundation
import os

/// HTTP client for App Store Connect API using URLSession
public actor HTTPClient {
    private let urlSession: URLSession
    private let jwtService: JWTService
    private let baseURL: String
    private let logger = Logger(subsystem: "com.asc-mcp", category: "HTTPClient")

    // Retry configuration
    private let maxRetries = 3
    private let retryableStatusCodes = Set([408, 429, 500, 502, 503, 504])

    public init(jwtService: JWTService, baseURL: String) async {
        self.jwtService = jwtService
        self.baseURL = baseURL

        // Configure URLSession for Swift 6
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    deinit {
        // Properly invalidate URLSession to avoid leaks
        urlSession.invalidateAndCancel()
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

        // Retry logic: all methods retry on 429 (rate limit),
        // only idempotent methods retry on other errors
        let isIdempotent = method == .GET || method == .PUT || method == .DELETE
        let maxAttempts = maxRetries

        for attempt in 0..<maxAttempts {
            // Get fresh token for each attempt (JWTService caches valid tokens)
            let token = try await jwtService.getToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                // Log request
                logger.debug("[\(method.rawValue)] \(url.absoluteString) - Attempt \(attempt + 1)/\(maxAttempts)")

                let startTime = Date()
                let (data, response) = try await urlSession.data(for: request)
                let duration = Date().timeIntervalSince(startTime)

                // Check HTTP status code
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ASCError.network("Invalid response format")
                }

                logger.debug("Response: \(httpResponse.statusCode) in \(String(format: "%.2f", duration))s")

                // Successful response
                if 200...299 ~= httpResponse.statusCode {
                    return data
                }

                // Error handling
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"

                // Handle 401 Unauthorized: refresh token and retry
                if httpResponse.statusCode == 401 && attempt < maxAttempts - 1 {
                    logger.warning("401 Unauthorized, refreshing JWT token and retrying")
                    _ = try await jwtService.refreshToken()
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }

                // Check if this error is retryable
                if attempt < maxAttempts - 1 {
                    let isRetryable: Bool
                    if isIdempotent {
                        // Idempotent methods: retry all retryable status codes
                        isRetryable = retryableStatusCodes.contains(httpResponse.statusCode)
                    } else {
                        // Non-idempotent (POST/PATCH): only retry rate limiting
                        isRetryable = httpResponse.statusCode == 429
                    }

                    if isRetryable {
                        let delay = calculateRetryDelay(attempt: attempt, response: httpResponse)
                        logger.warning("Retryable error \(httpResponse.statusCode), waiting \(delay)s before retry")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                // Final error
                logger.error("HTTP error \(httpResponse.statusCode): \(errorMessage)")
                throw ASCError.api(errorMessage, httpResponse.statusCode)

            } catch let error as ASCError {
                // Propagate ASCError
                throw error
            } catch {
                // Network errors: only retry for idempotent methods
                if attempt < maxAttempts - 1 && isIdempotent {
                    let delay = calculateRetryDelay(attempt: attempt, response: nil)
                    logger.warning("Network error: \(error.localizedDescription), retrying in \(delay)s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                logger.error("Network request failed: \(error.localizedDescription)")
                throw ASCError.network("HTTP request failed: \(error.localizedDescription)")
            }
        }

        // Should not reach here, but for safety
        throw ASCError.network("Maximum retry attempts exceeded")
    }

    /// Calculates retry delay with exponential backoff
    private func calculateRetryDelay(attempt: Int, response: HTTPURLResponse?) -> Double {
        // Check Retry-After header
        if let response = response,
           let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let retryAfter = Double(retryAfterString) {
            return retryAfter
        }

        // Exponential backoff with jitter
        let baseDelay = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...1)
        return min(baseDelay + jitter, 30) // Maximum 30 seconds
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

// MARK: - Convenience Methods

extension HTTPClient {
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
    public func patch<T: Encodable & Sendable, R: Codable & Sendable>(_ endpoint: String, body: T, as responseType: R.Type) async throws -> R {
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
