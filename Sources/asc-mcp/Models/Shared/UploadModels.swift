import Foundation

// MARK: - Upload Operation Models (Shared)

/// Upload operation details returned by App Store Connect for asset uploads
public struct ASCUploadOperation: Codable, Sendable {
    public let method: String?
    public let url: String?
    public let length: Int?
    public let offset: Int?
    public let requestHeaders: [ASCUploadRequestHeader]?
    public let expiration: String?
    public let partNumber: Int?
    public let entityTag: String?

    /// Creates an upload operation with optional delivery-file multipart metadata.
    /// - Parameters:
    ///   - method: HTTP method for the presigned transfer.
    ///   - url: Presigned HTTPS destination.
    ///   - length: Number of snapshot bytes to transfer.
    ///   - offset: Snapshot byte offset.
    ///   - requestHeaders: Exact headers supplied by Apple.
    ///   - expiration: Optional presigned operation expiration.
    ///   - partNumber: Optional multipart part number.
    ///   - entityTag: Optional multipart entity tag supplied by Apple.
    public init(
        method: String?,
        url: String?,
        length: Int?,
        offset: Int?,
        requestHeaders: [ASCUploadRequestHeader]?,
        expiration: String? = nil,
        partNumber: Int? = nil,
        entityTag: String? = nil
    ) {
        self.method = method
        self.url = url
        self.length = length
        self.offset = offset
        self.requestHeaders = requestHeaders
        self.expiration = expiration
        self.partNumber = partNumber
        self.entityTag = entityTag
    }
}

/// HTTP request header for upload operations
public struct ASCUploadRequestHeader: Codable, Sendable {
    public let name: String?
    public let value: String?
}

struct UploadTransferResult: Sendable {
    let fileMD5: String
    let receipts: [UploadPartReceipt]
}

struct UploadPartReceipt: Sendable {
    let operationIndex: Int
    let method: String
    let offset: Int
    let length: Int
    let attempts: Int
    let statusCode: Int
    let expiration: String?
    let partNumber: Int?
    let entityTag: String?
    let responseEntityTag: String?
}

struct UploadTransferFailure: Error, LocalizedError, Sendable {
    let message: String
    let receipts: [UploadPartReceipt]

    var errorDescription: String? { message }
}

/// Image asset with template URL and dimensions
public struct ASCImageAsset: Codable, Sendable {
    public let templateUrl: String?
    public let width: Int?
    public let height: Int?
}

/// Asset delivery state for uploaded assets
public struct ASCAssetDeliveryState: Codable, Sendable {
    public let state: String?
    public let errors: [ASCAssetDeliveryError]?
    public let warnings: [ASCAssetDeliveryError]?
}

/// Error details for asset delivery failures
public struct ASCAssetDeliveryError: Codable, Sendable {
    public let code: String?
    public let description: String?
}
