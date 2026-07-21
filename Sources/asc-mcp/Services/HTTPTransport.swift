import Foundation

public protocol HTTPTransport: Sendable {
    /// Executes an HTTP request and returns its body and HTTP response metadata.
    /// - Parameter request: Request to execute.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: A transport error or `ASCError` for a non-HTTP response.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Uploads a request body from a local file without materializing it as `Data`.
    /// - Parameters:
    ///   - request: Request whose body is supplied by `fileURL`.
    ///   - fileURL: Local file containing the complete request body.
    /// - Returns: Response data and HTTP response metadata.
    /// - Throws: `ASCError` when file uploads are unsupported, or a transport error.
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPTransport {
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("File upload is not supported by this transport")
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
