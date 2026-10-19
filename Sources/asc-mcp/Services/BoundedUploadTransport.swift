import Foundation

struct ResponseLimitedUploadTransport: HTTPTransport {
    let upstream: any HTTPTransport
    let maximumBytes: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await upstream.data(for: request, maximumBytes: maximumBytes)
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try await upstream.data(for: request, maximumBytes: min(self.maximumBytes, maximumBytes))
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        try await upstream.upload(for: request, fromFile: fileURL, maximumBytes: maximumBytes)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try await upstream.upload(for: request, fromFile: fileURL, maximumBytes: min(self.maximumBytes, maximumBytes))
    }
}

final class BoundedUploadSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maximumHeaderBytes = 64 * 1_024
    static let maximumHeaderCount = 128

    private struct State {
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
        var session: URLSession?
        var task: URLSessionUploadTask?
        var response: HTTPURLResponse?
        var data = Data()
        var finished = false
    }

    private let maximumBytes: Int
    private let lock = NSLock()
    private var state = State()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func upload(request: URLRequest, fileURL: URL, configuration: URLSessionConfiguration) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes >= 0 else { throw ASCError.network("Upload response byte limit must not be negative") }
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                begin(request: request, fileURL: fileURL, configuration: configuration, continuation: continuation)
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        return result
    }

    private func begin(
        request: URLRequest,
        fileURL: URL,
        configuration: URLSessionConfiguration,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>
    ) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.uploadTask(with: request, fromFile: fileURL)
        let started = withState { state in
            guard !state.finished else { return false }
            state.continuation = continuation
            state.session = session
            state.task = task
            return true
        }
        if started {
            task.resume()
        } else {
            session.invalidateAndCancel()
            continuation.resume(throwing: CancellationError())
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(ASCError.network("Invalid upload response format")))
            return
        }
        guard Self.headersFit(response) else {
            completionHandler(.cancel)
            finish(.failure(ASCError.network("Upload response headers exceeded the configured limit")))
            return
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            completionHandler(.cancel)
            finish(.failure(ASCError.network("Upload response exceeded the configured byte limit")))
            return
        }
        let accepted = withState { state in
            guard !state.finished, state.response == nil else { return false }
            state.response = response
            return true
        }
        completionHandler(accepted ? .allow : .cancel)
        if !accepted {
            finish(.failure(ASCError.network("Upload returned multiple response bodies")))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let failure: ASCError? = withState { state in
            guard !state.finished else { return nil }
            guard state.response != nil else { return .network("Upload body arrived without response metadata") }
            guard data.count <= maximumBytes - state.data.count else {
                return .network("Upload response exceeded the configured byte limit")
            }
            state.data.append(data)
            return nil
        }
        if let failure { finish(.failure(failure)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        let result: Result<(Data, HTTPURLResponse), any Error> = withState { state in
            guard let response = state.response else { return .failure(ASCError.network("Upload response metadata is missing")) }
            return .success((state.data, response))
        }
        finish(result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), any Error>) {
        let resources = withState { state -> (CheckedContinuation<(Data, HTTPURLResponse), any Error>?, URLSession?)? in
            guard !state.finished else { return nil }
            state.finished = true
            let resources = (state.continuation, state.session)
            state.continuation = nil
            state.session = nil
            state.task = nil
            state.response = nil
            state.data = Data()
            return resources
        }
        guard let resources else { return }
        resources.1?.invalidateAndCancel()
        resources.0?.resume(with: result)
    }

    private func withState<T>(_ action: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action(&state)
    }

    private static func headersFit(_ response: HTTPURLResponse) -> Bool {
        guard response.allHeaderFields.count <= maximumHeaderCount else { return false }
        var remaining = maximumHeaderBytes
        for (key, value) in response.allHeaderFields {
            let keyLength = String(describing: key).utf8.count
            guard keyLength <= remaining else { return false }
            remaining -= keyLength
            let valueLength = String(describing: value).utf8.count
            guard valueLength <= remaining else { return false }
            remaining -= valueLength
        }
        return true
    }
}
