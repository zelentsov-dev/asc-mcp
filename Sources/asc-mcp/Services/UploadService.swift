import Foundation
import CryptoKit
import os

/// Service for uploading assets to App Store Connect
/// Handles the 3-step upload flow: reserve (caller) → upload chunks → commit (caller)
public actor UploadService {
    private let transport: any HTTPTransport
    private let batchSize: Int
    private let logger = Logger(subsystem: "com.asc-mcp", category: "UploadService")

    public init(transport: (any HTTPTransport)? = nil, batchSize: Int = 3) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.transport = transport ?? URLSessionTransport(configuration: config)
        self.batchSize = max(1, batchSize)
    }

    /// Reads a file from disk and uploads it using the provided upload operations
    /// - Parameters:
    ///   - filePath: Absolute path to the file on disk
    ///   - uploadOperations: Upload operations from the ASC reserve response
    /// - Returns: MD5 hex checksum of the entire file (for commit step)
    /// - Throws: ASCError on file read or upload failure
    public func uploadFile(
        filePath: String,
        uploadOperations: [ASCUploadOperation]
    ) async throws -> String {
        let fileURL = URL(fileURLWithPath: filePath)
        let size = try fileSize(at: filePath)
        try validateUploadOperations(uploadOperations, fileSize: size)

        logger.info("Uploading file: \(fileURL.lastPathComponent) (\(size) bytes, \(uploadOperations.count) chunks)")

        var nextIndex = 0
        while nextIndex < uploadOperations.count {
            let batchEnd = min(nextIndex + batchSize, uploadOperations.count)
            let batch = Array(uploadOperations[nextIndex..<batchEnd].enumerated())

            try await withThrowingTaskGroup(of: Void.self) { group in
                for (batchOffset, operation) in batch {
                    let chunkIndex = nextIndex + batchOffset
                    group.addTask {
                        try await self.uploadChunk(
                            fileURL: fileURL,
                            fileSize: size,
                            operation: operation,
                            chunkIndex: chunkIndex
                        )
                    }
                }
                try await group.waitForAll()
            }

            nextIndex = batchEnd
        }

        let md5 = try computeMD5(fileURL: fileURL)
        logger.info("Upload complete. MD5: \(md5)")
        return md5
    }

    func validateUploadOperations(_ operations: [ASCUploadOperation], fileSize: Int) throws {
        for (index, operation) in operations.enumerated() {
            guard let urlString = operation.url,
                  URL(string: urlString) != nil else {
                throw ASCError.network("Upload operation \(index) has an invalid URL")
            }

            let offset = operation.offset ?? 0
            let length = operation.length ?? fileSize

            guard offset >= 0 else {
                throw ASCError.network("Upload operation \(index) has negative offset")
            }
            guard length > 0 else {
                throw ASCError.network("Upload operation \(index) has non-positive length")
            }
            guard offset <= fileSize, length <= fileSize - offset else {
                throw ASCError.network("Upload operation \(index) range exceeds file size")
            }
        }
    }

    /// Uploads a single chunk to the presigned URL
    private func uploadChunk(
        fileURL: URL,
        fileSize: Int,
        operation: ASCUploadOperation,
        chunkIndex: Int
    ) async throws {
        guard let urlString = operation.url,
              let url = URL(string: urlString) else {
            throw ASCError.network("Upload operation \(chunkIndex) has no URL")
        }

        let offset = operation.offset ?? 0
        let length = operation.length ?? fileSize
        let chunkData = try readChunk(fileURL: fileURL, offset: offset, length: length)

        // Build request — presigned URL, no JWT
        var request = URLRequest(url: url)
        request.httpMethod = operation.method ?? "PUT"
        request.httpBody = chunkData

        // Set headers from upload operation (Content-Type, Content-MD5, etc.)
        if let headers = operation.requestHeaders {
            for header in headers {
                if let name = header.name, let value = header.value {
                    request.setValue(value, forHTTPHeaderField: name)
                }
            }
        }

        logger.debug("Uploading chunk \(chunkIndex): offset=\(offset), length=\(length)")

        let (_, response) = try await transport.data(for: request)

        guard 200...299 ~= response.statusCode else {
            throw ASCError.network("Upload chunk \(chunkIndex) failed with status \(response.statusCode)")
        }

        logger.debug("Chunk \(chunkIndex) uploaded successfully")
    }

    private func readChunk(fileURL: URL, offset: Int, length: Int) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to open file '\(fileURL.path)': \(error.localizedDescription)")
        }

        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: length), data.count == length else {
                throw ASCError.network("Failed to read exact upload range offset=\(offset), length=\(length)")
            }
            try handle.close()
            return data
        } catch {
            try? handle.close()
            if let ascError = error as? ASCError {
                throw ascError
            }
            throw ASCError.network("Failed to read chunk: \(error.localizedDescription)")
        }
    }

    /// Computes MD5 hex checksum of data
    /// - Returns: Lowercase hex string (e.g. "d41d8cd98f00b204e9800998ecf8427e")
    public func computeMD5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes MD5 hex checksum of a file without loading it fully into memory.
    /// - Parameter fileURL: File URL to hash.
    /// - Returns: Lowercase hex MD5 checksum.
    /// - Throws: ASCError if the file cannot be read.
    public func computeMD5(fileURL: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to open file '\(fileURL.path)': \(error.localizedDescription)")
        }

        var hasher = Insecure.MD5()
        do {
            while true {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw ASCError.network("Failed to hash file: \(error.localizedDescription)")
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns file size for a given path
    /// - Throws: ASCError if file doesn't exist
    public func fileSize(at filePath: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let size = attributes[.size] as? Int else {
            throw ASCError.network("Cannot determine file size for '\(filePath)'")
        }
        return size
    }

    /// Returns file name from path
    public func fileName(at filePath: String) -> String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
}
