import Foundation

public protocol HTTPTransport: Sendable {
    /// Executes an HTTP request and returns its body and HTTP response metadata.
    /// - Parameter request: Request to execute.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: A transport error or `ASCError` for a non-HTTP response.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Executes a request with a response body limit.
    /// - Returns: Body and metadata within the requested byte budget.
    /// - Throws: A transport error or an error when the response exceeds the budget.
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse)

    /// Uploads a request body from a local file without materializing it as `Data`.
    /// - Parameters:
    ///   - request: Request whose body is supplied by `fileURL`.
    ///   - fileURL: Local file containing the complete request body.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: `ASCError` when file uploads are unsupported, or a transport error.
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse)

    /// Uploads a file while limiting the response body retained by the transport.
    /// - Returns: Response data and metadata within the requested byte budget.
    /// - Throws: A transport error, cancellation, or a response-limit error.
    func upload(for request: URLRequest, fromFile fileURL: URL, maximumBytes: Int) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPTransport {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let result = try await data(for: request)
        guard result.0.count <= maximumBytes else { throw ASCError.network("Response exceeded the configured byte limit") }
        return result
    }
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("File upload is not supported by this transport")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes >= 0 else { throw ASCError.network("Upload response byte limit must not be negative") }
        let result = try await upload(for: request, fromFile: fileURL)
        guard result.0.count <= maximumBytes else { throw ASCError.network("Upload response exceeded the configured byte limit") }
        return result
    }
}

final class ASCAPIRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// URLSession is documented as safe for concurrent use. This wrapper is immutable after init,
// so unchecked Sendable only covers the Foundation type boundary.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let redirectDelegate: ASCAPIRedirectDelegate
    private let urlSession: URLSession

    /// Creates a URL session transport that returns redirect responses without following them.
    /// - Parameter configuration: URL session configuration for App Store Connect requests.
    public init(configuration: URLSessionConfiguration) {
        let redirectDelegate = ASCAPIRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        self.urlSession = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    /// Executes an HTTP request without following redirects.
    /// - Parameter request: Request to execute.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: A transport error or `ASCError` for a non-HTTP response.
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ASCError.network("Invalid response format")
        }
        return (data, httpResponse)
    }

    /// Streams an API response within a fixed memory budget without following redirects.
    /// - Returns: Body and HTTP metadata within the budget.
    /// - Throws: A transport error, cancellation, or a size-limit error.
    public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ASCError.network("Invalid response format") }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            bytes.task.cancel()
            throw ASCError.network("Response exceeded the configured byte limit")
        }
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < maximumBytes else { throw ASCError.network("Response exceeded the configured byte limit") }
                data.append(byte)
            }
        } catch {
            bytes.task.cancel()
            throw error
        }
        return (data, response)
    }

    /// Uploads a request body directly from a local file.
    /// - Parameters:
    ///   - request: Request whose body is supplied by `fileURL`.
    ///   - fileURL: Local file containing the complete request body.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: A transport error or `ASCError` for a non-HTTP response.
    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.upload(for: request, fromFile: fileURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ASCError.network("Invalid response format")
        }
        return (data, httpResponse)
    }
}

struct BoundedHTTPTransport: HTTPTransport {
    let upstream: any HTTPTransport
    let maximumBytes: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await upstream.data(for: request, maximumBytes: maximumBytes)
    }
}
