import Foundation

enum Redactor {
    private static let longIdentifierExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])"#
    )
    private static let identifierContextExpression = try! NSRegularExpression(
        pattern: #"(?i)(?:(?:[a-z][a-z0-9_]*_id|resource id)|(?:app|build|version|resource|attachment))\s*(?:[:=]|\bis\b)?\s*['\"]?\s*$"#
    )
    private static let doubleQuotedCredentialAssignmentExpression = try! NSRegularExpression(
        pattern: #"(?i)([\"']?(?:[a-z0-9_-]*(?:password|secret|authorization|bearer|token|credential)[a-z0-9_-]*|private[_-]?key(?:[_-]?(?:path|content))?|api[_-]?key|key[_-]?content)[\"']?\s*[:=]\s*)\"(?:\\.|[^\"\\])*\""#
    )
    private static let singleQuotedCredentialAssignmentExpression = try! NSRegularExpression(
        pattern: #"(?i)([\"']?(?:[a-z0-9_-]*(?:password|secret|authorization|bearer|token|credential)[a-z0-9_-]*|private[_-]?key(?:[_-]?(?:path|content))?|api[_-]?key|key[_-]?content)[\"']?\s*[:=]\s*)'(?:\\.|[^'\\])*'"#
    )
    private static let unquotedCredentialAssignmentExpression = try! NSRegularExpression(
        pattern: #"(?i)([\"']?(?:[a-z0-9_-]*(?:password|secret|authorization|bearer|token|credential)[a-z0-9_-]*|private[_-]?key(?:[_-]?(?:path|content))?|api[_-]?key|key[_-]?content)[\"']?\s*[:=]\s*)(?![\"'\[])[^\s,;&{}\[\]]+"#
    )

    private static let semanticIdentifiers: Set<String> = {
        var identifiers: Set<String> = [
            "REPLACE_INTRO_OFFERS",
            "STACK_WITH_INTRO_OFFERS",
            "USE_AUTO_GENERATED_ASSETS",
            "REDACTED_PRIVATE_KEY",
            "REDACTED_PRIVATE_KEY_PATH",
            "confirmation_required",
            "invalid_app_version_state",
            "confirmation_mismatch",
            "create_review_submission_item",
            "confirm_review_submission",
            "review_submission_id",
            "committed_unverified",
            "absolute-path-to-the-exact-reserved-bytes"
        ]
        if let manifest = try? ASCOperationManifestBundle.loadBundled() {
            identifiers.formUnion(manifest.tools.map(\.tool))
        }
        return identifiers
    }()

    static func redact(_ value: String) -> String {
        var result = value
        result = redactBearerTokens(in: result)
        result = redactCredentialAssignments(in: result)
        result = redactLongOpaqueIdentifiers(in: result)
        result = redactPrivateKeyPaths(in: result)
        result = redactPEMBlocks(in: result)
        return result
    }

    static func redact(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return redact(string)
        case let array as [Any]:
            return array.map { redact($0) }
        case let object as [String: Any]:
            return object.mapValues { redact($0) }
        default:
            return value
        }
    }

    static func redactPreservingOpaqueIdentifiers(_ value: String) -> String {
        var result = value
        result = redactBearerTokens(in: result)
        result = redactCredentialAssignments(in: result)
        result = redactCredentialLikeIdentifiers(in: result)
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

    private static func redactCredentialAssignments(in value: String) -> String {
        var result = replacingMatches(
            of: doubleQuotedCredentialAssignmentExpression,
            in: value,
            with: "$1\"[REDACTED]\""
        )
        result = replacingMatches(
            of: singleQuotedCredentialAssignmentExpression,
            in: result,
            with: "$1'[REDACTED]'"
        )
        return replacingMatches(
            of: unquotedCredentialAssignmentExpression,
            in: result,
            with: "$1[REDACTED]"
        )
    }

    private static func replacingMatches(
        of expression: NSRegularExpression,
        in value: String,
        with template: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: template
        )
    }

    private static func redactLongOpaqueIdentifiers(in value: String) -> String {
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = longIdentifierExpression.matches(in: value, range: fullRange)
        var result = value
        for match in matches.reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let identifier = String(value[range])
            if semanticIdentifiers.contains(identifier) {
                continue
            }
            if isCredentialLikeIdentifier(identifier) {
                result.replaceSubrange(range, with: "[REDACTED]")
                continue
            }
            guard !isUppercaseSemanticIdentifier(identifier),
                  !hasIdentifierContext(in: value, before: range.lowerBound) else {
                continue
            }
            result.replaceSubrange(range, with: "[REDACTED]")
        }
        return result
    }

    private static func isUppercaseSemanticIdentifier(_ identifier: String) -> Bool {
        guard identifier.contains("_"), identifier == identifier.uppercased() else {
            return false
        }
        return true
    }

    private static func isCredentialLikeIdentifier(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        let normalized = lower.replacingOccurrences(
            of: "[^a-z0-9]",
            with: "",
            options: .regularExpression
        )
        let components = Set(
            lower.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        )
        return normalized.contains("token") ||
            normalized.contains("secret") ||
            normalized.contains("password") ||
            normalized.contains("authorization") ||
            normalized.contains("bearer") ||
            normalized.contains("privatekey") ||
            normalized.contains("apikey") ||
            normalized.contains("keycontent") ||
            normalized.contains("credential") ||
            normalized.hasPrefix("eyj") ||
            components.contains("key")
    }

    private static func redactCredentialLikeIdentifiers(in value: String) -> String {
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = longIdentifierExpression.matches(in: value, range: fullRange)
        var result = value
        for match in matches.reversed() {
            guard let range = Range(match.range, in: value) else { continue }
            let identifier = String(value[range])
            guard !semanticIdentifiers.contains(identifier),
                  isCredentialLikeIdentifier(identifier) else {
                continue
            }
            result.replaceSubrange(range, with: "[REDACTED]")
        }
        return result
    }

    private static func hasIdentifierContext(in value: String, before index: String.Index) -> Bool {
        let prefix = String(value[..<index].suffix(80))
        let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
        return identifierContextExpression.firstMatch(in: prefix, range: range) != nil
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
