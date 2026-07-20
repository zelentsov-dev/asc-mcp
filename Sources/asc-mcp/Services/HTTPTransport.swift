import Foundation

public protocol HTTPTransport: Sendable {
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

// URLSession is documented as safe for concurrent use. This wrapper is immutable after init,
// so unchecked Sendable only covers the Foundation type boundary.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let urlSession: URLSession

    public init(configuration: URLSessionConfiguration) {
        self.urlSession = URLSession(configuration: configuration)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

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
