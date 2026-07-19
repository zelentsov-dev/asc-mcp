import Foundation

enum Redactor {
    private static let longIdentifierExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])"#
    )

    private static let semanticIdentifiers: Set<String> = {
        var identifiers: Set<String> = [
            "REPLACE_INTRO_OFFERS",
            "STACK_WITH_INTRO_OFFERS",
            "USE_AUTO_GENERATED_ASSETS"
        ]
        if let manifest = try? ASCOperationManifestBundle.loadBundled() {
            identifiers.formUnion(manifest.tools.map(\.tool))
        }
        return identifiers
    }()

    static func redact(_ value: String) -> String {
        var result = value
        result = redactBearerTokens(in: result)
        result = redactLongOpaqueIdentifiers(in: result)
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
            of: #"(?i)\bBearer[ \t]+[A-Za-z0-9\-._~+/]+=*"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
    }

    private static func redactLongOpaqueIdentifiers(in value: String) -> String {
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = longIdentifierExpression.matches(in: value, range: fullRange)
        var result = value
        for match in matches.reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let identifier = String(value[range])
            guard !semanticIdentifiers.contains(identifier) else { continue }
            result.replaceSubrange(range, with: "[REDACTED]")
        }
        return result
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
