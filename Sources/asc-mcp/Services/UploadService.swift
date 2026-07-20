import Foundation
import CryptoKit
import os

/// Service for uploading assets to App Store Connect
/// Transfers immutable file snapshots with bounded memory after validating HTTPS targets and exact byte coverage.
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

    /// Uploads an immutable snapshot of a file using the provided upload operations
    /// - Parameters:
    ///   - filePath: Absolute path to the file on disk
    ///   - uploadOperations: Upload operations from the ASC reserve response
    /// - Returns: MD5 hex checksum of the exact snapshot bytes uploaded
    /// - Throws: ASCError on file read, unsafe or incomplete upload operations, or transfer failure
    public func uploadFile(
        filePath: String,
        uploadOperations: [ASCUploadOperation]
    ) async throws -> String {
        let snapshot = try prepareSnapshot(filePath: filePath)
        defer { discardSnapshot(snapshot) }
        return try await uploadFile(snapshot: snapshot, uploadOperations: uploadOperations)
    }

    func prepareSnapshot(filePath: String) throws -> UploadFileSnapshot {
        let sourceURL = URL(fileURLWithPath: filePath)
        let snapshotURL = try createSnapshot(of: sourceURL)
        do {
            return UploadFileSnapshot(
                url: snapshotURL,
                fileName: sourceURL.lastPathComponent,
                fileSize: try fileSize(at: snapshotURL.path),
                md5Checksum: try computeMD5(fileURL: snapshotURL)
            )
        } catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
    }

    func discardSnapshot(_ snapshot: UploadFileSnapshot) {
        snapshot.discard()
    }

    func uploadFile(
        snapshot: UploadFileSnapshot,
        uploadOperations: [ASCUploadOperation]
    ) async throws -> String {
        let size = snapshot.fileSize
        try validateUploadOperations(uploadOperations, fileSize: size)

        logger.info("Uploading file: \(snapshot.fileName) (\(size) bytes, \(uploadOperations.count) chunks)")

        var nextIndex = 0
        while nextIndex < uploadOperations.count {
            let batchEnd = min(nextIndex + batchSize, uploadOperations.count)
            let batch = Array(uploadOperations[nextIndex..<batchEnd].enumerated())

            try await withThrowingTaskGroup(of: Void.self) { group in
                for (batchOffset, operation) in batch {
                    let chunkIndex = nextIndex + batchOffset
                    group.addTask {
                        try await self.uploadChunk(
                            fileURL: snapshot.url,
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

        let md5 = try computeMD5(fileURL: snapshot.url)
        guard md5 == snapshot.md5Checksum else {
            throw ASCError.network("The immutable upload snapshot changed during transfer")
        }
        logger.info("Upload complete. MD5: \(md5)")
        return md5
    }

    private func createSnapshot(of fileURL: URL) throws -> URL {
        var snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-upload-snapshot-\(UUID().uuidString)")
        if !fileURL.pathExtension.isEmpty {
            snapshotURL.appendPathExtension(fileURL.pathExtension)
        }

        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to snapshot upload file '\(fileURL.path)': \(error.localizedDescription)")
        }

        guard FileManager.default.createFile(
            atPath: snapshotURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? sourceHandle.close()
            throw ASCError.network("Failed to create an upload snapshot for '\(fileURL.path)'")
        }

        let snapshotHandle: FileHandle
        do {
            snapshotHandle = try FileHandle(forWritingTo: snapshotURL)
        } catch {
            try? sourceHandle.close()
            try? FileManager.default.removeItem(at: snapshotURL)
            throw ASCError.network("Failed to open the upload snapshot: \(error.localizedDescription)")
        }

        do {
            while true {
                if Task.isCancelled {
                    throw CancellationError()
                }
                let data = try sourceHandle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                try snapshotHandle.write(contentsOf: data)
            }
            try snapshotHandle.synchronize()
            try sourceHandle.close()
            try snapshotHandle.close()
            return snapshotURL
        } catch {
            try? sourceHandle.close()
            try? snapshotHandle.close()
            try? FileManager.default.removeItem(at: snapshotURL)
            if error is CancellationError {
                throw CancellationError()
            }
            throw ASCError.network("Failed to snapshot upload file '\(fileURL.path)': \(error.localizedDescription)")
        }
    }

    func validateUploadOperations(_ operations: [ASCUploadOperation], fileSize: Int) throws {
        guard !operations.isEmpty else {
            throw ASCError.network("Apple returned no upload operations")
        }

        var ranges: [(offset: Int, length: Int, index: Int)] = []
        ranges.reserveCapacity(operations.count)

        for (index, operation) in operations.enumerated() {
            guard let urlString = operation.url,
                  let components = URLComponents(string: urlString),
                  components.scheme?.lowercased() == "https",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil,
                  components.fragment == nil,
                  components.url != nil else {
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

            ranges.append((offset: offset, length: length, index: index))
        }

        var expectedOffset = 0
        for range in ranges.sorted(by: {
            if $0.offset == $1.offset {
                return $0.index < $1.index
            }
            return $0.offset < $1.offset
        }) {
            guard range.offset == expectedOffset else {
                let issue = range.offset < expectedOffset ? "overlaps" : "leaves a gap in"
                throw ASCError.network(
                    "Upload operation \(range.index) \(issue) the file byte coverage"
                )
            }
            expectedOffset = range.offset + range.length
        }

        guard expectedOffset == fileSize else {
            throw ASCError.network("Upload operations do not cover the complete file")
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
        try Task.checkCancellation()

        let uploadFileURL: URL
        let discardUploadFile: Bool
        if offset == 0, length == fileSize {
            uploadFileURL = fileURL
            discardUploadFile = false
        } else {
            uploadFileURL = try createChunkFile(
                from: fileURL,
                offset: offset,
                length: length,
                chunkIndex: chunkIndex
            )
            discardUploadFile = true
        }
        defer {
            if discardUploadFile {
                try? FileManager.default.removeItem(at: uploadFileURL)
            }
        }

        try Task.checkCancellation()

        // Build request — presigned URL, no JWT
        var request = URLRequest(url: url)
        request.httpMethod = operation.method ?? "PUT"

        // Set headers from upload operation (Content-Type, Content-MD5, etc.)
        if let headers = operation.requestHeaders {
            for header in headers {
                if let name = header.name, let value = header.value {
                    request.setValue(value, forHTTPHeaderField: name)
                }
            }
        }

        logger.debug("Uploading chunk \(chunkIndex): offset=\(offset), length=\(length)")

        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.upload(for: request, fromFile: uploadFileURL)
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            throw ASCError.network("Upload chunk \(chunkIndex) transfer failed")
        }

        try Task.checkCancellation()

        guard 200...299 ~= response.statusCode else {
            throw ASCError.network("Upload chunk \(chunkIndex) failed with status \(response.statusCode)")
        }

        logger.debug("Chunk \(chunkIndex) uploaded successfully")
    }

    private func createChunkFile(
        from fileURL: URL,
        offset: Int,
        length: Int,
        chunkIndex: Int
    ) throws -> URL {
        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to open file '\(fileURL.path)': \(error.localizedDescription)")
        }

        let chunkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-upload-chunk-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: chunkURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? sourceHandle.close()
            throw ASCError.network("Failed to create temporary upload chunk \(chunkIndex)")
        }

        let chunkHandle: FileHandle
        do {
            chunkHandle = try FileHandle(forWritingTo: chunkURL)
        } catch {
            try? sourceHandle.close()
            try? FileManager.default.removeItem(at: chunkURL)
            throw ASCError.network("Failed to open temporary upload chunk \(chunkIndex)")
        }

        do {
            try sourceHandle.seek(toOffset: UInt64(offset))
            var remaining = length
            while remaining > 0 {
                if Task.isCancelled {
                    throw CancellationError()
                }

                let readLength = min(remaining, 1024 * 1024)
                guard let data = try sourceHandle.read(upToCount: readLength), !data.isEmpty else {
                    throw ASCError.network(
                        "Failed to read exact upload range offset=\(offset), length=\(length)"
                    )
                }
                try chunkHandle.write(contentsOf: data)
                remaining -= data.count
            }

            try chunkHandle.synchronize()
            try sourceHandle.close()
            try chunkHandle.close()
            return chunkURL
        } catch {
            try? sourceHandle.close()
            try? chunkHandle.close()
            try? FileManager.default.removeItem(at: chunkURL)
            if error is CancellationError {
                throw CancellationError()
            }
            if let ascError = error as? ASCError {
                throw ascError
            }
            throw ASCError.network("Failed to prepare upload chunk \(chunkIndex)")
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

struct UploadFileSnapshot: Sendable {
    let url: URL
    let fileName: String
    let fileSize: Int
    let md5Checksum: String

    func discard() {
        try? FileManager.default.removeItem(at: url)
    }
}
