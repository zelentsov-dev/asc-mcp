import Foundation
import MCP

public struct ASCAPIErrorResponse: Codable, Sendable {
    public let errors: [ASCAPIError]
}

public struct ASCAPIError: Codable, Sendable {
    public let id: String?
    public let status: String?
    public let code: String?
    public let title: String?
    public let detail: String?
    public let source: ASCAPIErrorSource?

    var safeDescription: String {
        let statusPrefix = status.map { "[\($0)] " } ?? ""
        let codeSuffix = code.map { " (\($0))" } ?? ""
        let message = detail ?? title ?? "Unknown App Store Connect API error"
        return "\(statusPrefix)\(message)\(codeSuffix)"
    }

    var structuredValue: Value {
        .object([
            "id": id.map(Value.string) ?? .null,
            "status": status.map(Value.string) ?? .null,
            "code": code.map(Value.string) ?? .null,
            "title": title.map(Value.string) ?? .null,
            "detail": detail.map(Value.string) ?? .null,
            "source": source?.structuredValue ?? .null
        ])
    }
}

public struct ASCAPIErrorSource: Codable, Sendable {
    public let pointer: String?
    public let parameter: String?

    var structuredValue: Value {
        .object([
            "pointer": pointer.map(Value.string) ?? .null,
            "parameter": parameter.map(Value.string) ?? .null
        ])
    }
}

public struct ASCRateLimitInfo: Codable, Equatable, Sendable {
    public let userHourLimit: Int?
    public let userHourRemaining: Int?
    public let retryAfterSeconds: Double?
    public let observedAt: Date

    var metadataFields: [String: Value] {
        var fields: [String: Value] = [
            "asc/rateLimit/observedAt": .string(ISO8601DateFormatter().string(from: observedAt))
        ]
        if let userHourLimit {
            fields["asc/rateLimit/userHourLimit"] = .int(userHourLimit)
        }
        if let userHourRemaining {
            fields["asc/rateLimit/userHourRemaining"] = .int(userHourRemaining)
        }
        if let retryAfterSeconds {
            fields["asc/rateLimit/retryAfterSeconds"] = .double(retryAfterSeconds)
        }
        return fields
    }
}
