import Foundation

enum Redactor {
    static func redact(_ value: String) -> String {
        var result = value
        result = redactBearerTokens(in: result)
        result = redactLongIdentifiers(in: result)
        result = redactPrivateKeyPaths(in: result)
        result = redactPEMBlocks(in: result)
        return result
    }

    static func maskIdentifier(_ value: String, visibleSuffix: Int = 4) -> String {
        guard value.count > visibleSuffix else { return "****" }
        return "****" + value.suffix(visibleSuffix)
    }

    private static func redactBearerTokens(in value: String) -> String {
        value.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._\-]+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
    }

    private static func redactLongIdentifiers(in value: String) -> String {
        value.replacingOccurrences(
            of: #"\b[A-Za-z0-9_-]{20,}\b"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
    }

    private static func redactPrivateKeyPaths(in value: String) -> String {
        value.replacingOccurrences(
            of: #"(/[^ \n\t"]+\.p8)\b"#,
            with: "[REDACTED_PRIVATE_KEY_PATH]",
            options: .regularExpression
        )
    }

    private static func redactPEMBlocks(in value: String) -> String {
        value.replacingOccurrences(
            of: #"-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----"#,
            with: "[REDACTED_PRIVATE_KEY]",
            options: .regularExpression
        )
    }
}
