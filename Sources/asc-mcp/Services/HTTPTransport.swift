import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

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
}
