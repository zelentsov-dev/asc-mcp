import Foundation
import MCP

enum ASCMetadataValidator {
    struct FieldLimit: Sendable {
        let name: String
        let maxLength: Int
    }

    struct FieldError: Codable, Equatable, Sendable {
        let field: String
        let message: String
    }

    static func validateTextFields(
        _ fields: [String: String],
        limits: [String: Int] = [:]
    ) -> [FieldError] {
        var errors: [FieldError] = []

        for (field, value) in fields {
            if containsEmoji(value) {
                errors.append(FieldError(field: field, message: "Emoji characters are not allowed"))
            }
            if let limit = limits[field], value.count > limit {
                errors.append(FieldError(field: field, message: "Value exceeds \(limit) characters"))
            }
        }

        return errors
    }

    static func validateLocale(_ locale: String, field: String = "locale") -> [FieldError] {
        let pattern = #"^[a-z]{2,3}(-([A-Z]{2}|[A-Z][a-z]{3}))?$"#
        let range = NSRange(locale.startIndex..<locale.endIndex, in: locale)
        let regex = try? NSRegularExpression(pattern: pattern)
        if regex?.firstMatch(in: locale, range: range) == nil {
            return [FieldError(field: field, message: "Locale must use a valid code such as en-US, ru-RU, ja, or zh-Hans")]
        }
        return []
    }

    static func validateHTTPURL(_ value: String, field: String) -> [FieldError] {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host?.isEmpty == false else {
            return [FieldError(field: field, message: "URL must be absolute and use http or https")]
        }
        return []
    }

    static func containsEmoji(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation ||
                (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }

    static func errorResult(_ errors: [FieldError]) -> CallTool.Result {
        let structuredErrors: [Value] = errors.map {
            .object([
                "field": .string($0.field),
                "message": .string($0.message)
            ])
        }
        let text = errors
            .map { "\($0.field): \($0.message)" }
            .joined(separator: "\n")
        return MCPResult.json(
            .object([
                "success": .bool(false),
                "validationErrors": .array(structuredErrors)
            ]),
            text: "Validation failed:\n\(text)",
            isError: true
        )
    }
}
