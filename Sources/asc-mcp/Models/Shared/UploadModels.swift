import Foundation

// MARK: - Upload Operation Models (Shared)

/// Upload operation details returned by App Store Connect for asset uploads
public struct ASCUploadOperation: Codable, Sendable {
    public let method: String?
    public let url: String?
    public let length: Int?
    public let offset: Int?
    public let requestHeaders: [ASCUploadRequestHeader]?
}

/// HTTP request header for upload operations
public struct ASCUploadRequestHeader: Codable, Sendable {
    public let name: String?
    public let value: String?
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
}

/// Error details for asset delivery failures
public struct ASCAssetDeliveryError: Codable, Sendable {
    public let code: String?
    public let description: String?
}
