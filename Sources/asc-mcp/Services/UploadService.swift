import Foundation
import CryptoKit
import os

/// Service for uploading assets to App Store Connect
/// Handles the 3-step upload flow: reserve (caller) → upload chunks → commit (caller)
public actor UploadService {
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.asc-mcp", category: "UploadService")

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    deinit {
        urlSession.invalidateAndCancel()
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
        // Read file
        let fileURL = URL(fileURLWithPath: filePath)
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ASCError.network("Failed to read file at '\(filePath)': \(error.localizedDescription)")
        }

        logger.info("Uploading file: \(filePath) (\(fileData.count) bytes, \(uploadOperations.count) chunks)")

        // Upload all chunks in parallel
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, operation) in uploadOperations.enumerated() {
                group.addTask {
                    try await self.uploadChunk(
                        fileData: fileData,
                        operation: operation,
                        chunkIndex: index
                    )
                }
            }
            try await group.waitForAll()
        }

        // Compute MD5 of entire file
        let md5 = computeMD5(data: fileData)
        logger.info("Upload complete. MD5: \(md5)")
        return md5
    }

    /// Uploads a single chunk to the presigned URL
    private func uploadChunk(
        fileData: Data,
        operation: ASCUploadOperation,
        chunkIndex: Int
    ) async throws {
        guard let urlString = operation.url,
              let url = URL(string: urlString) else {
            throw ASCError.network("Upload operation \(chunkIndex) has no URL")
        }

        let offset = operation.offset ?? 0
        let length = operation.length ?? fileData.count

        // Extract chunk from file data
        let endIndex = min(offset + length, fileData.count)
        let chunkData = fileData[offset..<endIndex]

        // Build request — presigned URL, no JWT
        var request = URLRequest(url: url)
        request.httpMethod = operation.method ?? "PUT"
        request.httpBody = Data(chunkData)

        // Set headers from upload operation (Content-Type, Content-MD5, etc.)
        if let headers = operation.requestHeaders {
            for header in headers {
                if let name = header.name, let value = header.value {
                    request.setValue(value, forHTTPHeaderField: name)
                }
            }
        }

        logger.debug("Uploading chunk \(chunkIndex): offset=\(offset), length=\(length)")

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ASCError.network("Upload chunk \(chunkIndex) failed with status \(statusCode)")
        }

        logger.debug("Chunk \(chunkIndex) uploaded successfully")
    }

    /// Computes MD5 hex checksum of data
    /// - Returns: Lowercase hex string (e.g. "d41d8cd98f00b204e9800998ecf8427e")
    public func computeMD5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
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
