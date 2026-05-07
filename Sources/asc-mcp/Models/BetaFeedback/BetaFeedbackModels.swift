import Foundation

public enum BetaFeedbackPlatformValues {
    public static let all: [String] = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
}

public struct ASCBetaFeedbackCrashSubmissionsResponse: Codable, Sendable {
    public let data: [ASCBetaFeedbackCrashSubmission]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCBetaFeedbackCrashSubmissionResponse: Codable, Sendable {
    public let data: ASCBetaFeedbackCrashSubmission
}

public struct ASCBetaFeedbackCrashSubmission: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let createdDate: String?
        public let comment: String?
        public let email: String?
        public let deviceModel: String?
        public let osVersion: String?
        public let locale: String?
        public let timeZone: String?
        public let architecture: String?
        public let connectionType: String?
        public let pairedAppleWatch: String?
        public let appUptimeInMilliseconds: Int64?
        public let diskBytesAvailable: Int64?
        public let diskBytesTotal: Int64?
        public let batteryPercentage: Int?
        public let screenWidthInPoints: Int?
        public let screenHeightInPoints: Int?
        public let appPlatform: String?
        public let devicePlatform: String?
        public let deviceFamily: String?
        public let buildBundleId: String?
    }

    public struct Relationships: Codable, Sendable {
        public let crashLog: ASCRelationship?
        public let build: ASCRelationship?
        public let tester: ASCRelationship?
    }
}

public struct ASCBetaCrashLogResponse: Codable, Sendable {
    public let data: ASCBetaCrashLog
}

public struct ASCBetaCrashLog: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let logText: String?
    }
}

public struct ASCBetaFeedbackScreenshotSubmissionsResponse: Codable, Sendable {
    public let data: [ASCBetaFeedbackScreenshotSubmission]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCBetaFeedbackScreenshotSubmissionResponse: Codable, Sendable {
    public let data: ASCBetaFeedbackScreenshotSubmission
}

public struct ASCBetaFeedbackScreenshotSubmission: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let relationships: Relationships?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let createdDate: String?
        public let comment: String?
        public let email: String?
        public let deviceModel: String?
        public let osVersion: String?
        public let locale: String?
        public let timeZone: String?
        public let architecture: String?
        public let connectionType: String?
        public let pairedAppleWatch: String?
        public let appUptimeInMilliseconds: Int64?
        public let diskBytesAvailable: Int64?
        public let diskBytesTotal: Int64?
        public let batteryPercentage: Int?
        public let screenWidthInPoints: Int?
        public let screenHeightInPoints: Int?
        public let appPlatform: String?
        public let devicePlatform: String?
        public let deviceFamily: String?
        public let buildBundleId: String?
        public let screenshots: [ASCBetaFeedbackScreenshotImage]?
    }

    public struct Relationships: Codable, Sendable {
        public let build: ASCRelationship?
        public let tester: ASCRelationship?
    }
}

public struct ASCBetaFeedbackScreenshotImage: Codable, Sendable {
    public let url: String?
    public let width: Int?
    public let height: Int?
    public let expirationDate: String?
}
