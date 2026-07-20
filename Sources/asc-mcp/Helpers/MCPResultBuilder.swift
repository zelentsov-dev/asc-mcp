import Foundation
import MCP

enum MCPContent {
    static func text(_ text: String, _meta: Metadata? = nil) -> Tool.Content {
        .text(text: text, annotations: nil, _meta: _meta)
    }
}

enum MCPResult {
    static func text(_ text: String, isError: Bool = false, _meta: Metadata? = nil) -> CallTool.Result {
        normalizeForTransport(CallTool.Result(
            content: [MCPContent.text(text)],
            isError: isError ? true : nil,
            _meta: _meta
        ))
    }

    static func json(
        _ value: Value,
        text: String? = nil,
        isError: Bool = false,
        _meta: Metadata? = nil
    ) -> CallTool.Result {
        let sanitizedValue = MCPValueSanitizer.sanitize(value)
        let textContent = text ?? (try? MCPValue.prettyJSONString(from: sanitizedValue)) ?? sanitizedValue.description
        return normalizeForTransport(CallTool.Result(
            content: [MCPContent.text(textContent)],
            structuredContent: Optional.some(sanitizedValue),
            isError: isError ? true : nil,
            _meta: _meta
        ))
    }

    static func jsonObject(
        _ object: [String: Any],
        text: String? = nil,
        isError: Bool = false,
        _meta: Metadata? = nil
    ) -> CallTool.Result {
        do {
            return json(try MCPValue.fromAny(object), text: text, isError: isError, _meta: _meta)
        } catch {
            return self.text(
                "Error: Failed to encode structured result: \(error.localizedDescription)",
                isError: true,
                _meta: _meta
            )
        }
    }

    static func error(_ message: String, details: Value? = nil, _meta: Metadata? = nil) -> CallTool.Result {
        let redactedMessage = Redactor.redact(message)
        let structured: Value = .object([
            "success": .bool(false),
            "error": .string(redactedMessage),
            "details": details ?? .null
        ])
        return json(structured, text: "Error: \(redactedMessage)", isError: true, _meta: _meta)
    }

    static func error(
        _ error: Error,
        prefix: String? = nil,
        _meta: Metadata? = nil
    ) -> CallTool.Result {
        let message = prefix.map { "\($0): \(error.localizedDescription)" }
            ?? error.localizedDescription

        guard let ascError = error as? ASCError else {
            return self.error(message, _meta: _meta)
        }

        var object: [String: Value] = [
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "details": ascError.structuredValue
        ]
        if case .deleteOutcomeUnknown = ascError {
            object["operationCommitState"] = .string("unknown")
            object["outcomeUnknown"] = .bool(true)
            object["retrySafe"] = .bool(false)
        }
        if case .deleteCommittedUnverified = ascError {
            object["operationCommitState"] = .string("committed_unverified")
            object["operationCommitted"] = .bool(true)
            object["retrySafe"] = .bool(false)
            object["inspectionRequired"] = .bool(true)
        }
        return json(
            .object(object),
            text: "Error: \(Redactor.redact(message))",
            isError: true,
            _meta: _meta
        )
    }

    static func normalizeForTransport(_ result: CallTool.Result) -> CallTool.Result {
        guard result.isError == true else { return result }

        let rawMirrors = result.structuredContent.map { [$0] } ?? []
        let redactedContent = result.content.filter { content in
            guard case .text(let text, _, _) = content else { return true }
            return !isJSONMirror(text, of: rawMirrors)
        }.map(redactErrorText)
        let originalStructured = result.structuredContent.map {
            MCPValueSanitizer.sanitizeError($0)
        }
        let originalMirrors = originalStructured.map { [$0] } ?? []
        let humanText = redactedContent.compactMap { content -> String? in
            guard case .text(let text, _, _) = content,
                  !isJSONMirror(text, of: originalMirrors) else {
                return nil
            }
            return text
        }.first
        let message = errorMessage(from: originalStructured, humanText: humanText)
        let candidate = canonicalError(from: originalStructured, message: message)
        let (structuredContent, mirror) = encodedError(candidate, message: message)
        let mirrorCandidates = originalMirrors + [structuredContent]

        var content = redactedContent.filter { content in
            guard case .text(let text, _, _) = content else { return true }
            return !isJSONMirror(text, of: mirrorCandidates)
        }
        if humanText == nil {
            content.insert(MCPContent.text("Error: \(message)"), at: 0)
        }
        content.append(MCPContent.text(mirror))

        return CallTool.Result(
            content: content,
            structuredContent: Optional.some(structuredContent),
            isError: true,
            _meta: result._meta
        )
    }

    private static func redactErrorText(_ content: Tool.Content) -> Tool.Content {
        guard case .text(let text, let annotations, let metadata) = content else {
            return content
        }
        return .text(
            text: Redactor.redact(text),
            annotations: annotations,
            _meta: metadata
        )
    }

    private static func errorMessage(from structured: Value?, humanText: String?) -> String {
        if case .object(let object)? = structured {
            if case .string(let error)? = object["error"], !error.isEmpty {
                return error
            }
            if case .string(let message)? = object["message"], !message.isEmpty {
                return message
            }
        }

        if let humanText {
            let prefix = "Error:"
            if humanText.hasPrefix(prefix) {
                let message = humanText.dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    return message
                }
            } else if !humanText.isEmpty {
                return humanText
            }
        }

        return "Tool execution failed"
    }

    private static func canonicalError(from structured: Value?, message: String) -> Value {
        var object: [String: Value]
        switch structured {
        case .object(let existing)?:
            object = existing
        case let details?:
            object = ["details": details]
        case nil:
            object = [:]
        }

        object["success"] = .bool(false)
        object["error"] = .string(Redactor.redact(message))
        if object["details"] == nil {
            object["details"] = .null
        }
        return MCPValueSanitizer.sanitizeError(.object(object))
    }

    private static func encodedError(_ value: Value, message: String) -> (Value, String) {
        if let mirror = try? MCPValue.compactJSONString(from: value) {
            return (value, mirror)
        }

        let fallback: Value = .object([
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "details": .object([
                "encodingFailure": .bool(true)
            ])
        ])
        if let mirror = try? MCPValue.compactJSONString(from: fallback) {
            return (fallback, mirror)
        }

        let terminal: Value = .object([
            "success": .bool(false),
            "error": .string("Tool execution failed"),
            "details": .null
        ])
        return (terminal, #"{"details":null,"error":"Tool execution failed","success":false}"#)
    }

    private static func isJSONMirror(_ text: String, of values: [Value]) -> Bool {
        guard !values.isEmpty else { return false }
        let mirrors = values.compactMap { try? MCPValue.compactJSONString(from: $0) }
        if mirrors.contains(text) {
            return true
        }
        if let normalized = normalizedJSONString(text), mirrors.contains(normalized) {
            return true
        }
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
            return false
        }
        return values.contains(decoded)
    }

    private static func normalizedJSONString(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let normalized = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        return String(data: normalized, encoding: .utf8)
    }
}

enum MCPValueSanitizer {
    static func sanitize(_ value: Value) -> Value {
        switch value {
        case .object(let object):
            var sanitized: [String: Value] = [:]
            for (key, child) in object {
                sanitized[key] = isSensitiveKey(key) ? .string("[REDACTED]") : sanitize(child)
            }
            return .object(sanitized)
        case .array(let array):
            return .array(array.map(sanitize))
        default:
            return value
        }
    }

    static func sanitizeError(_ value: Value, key: String? = nil) -> Value {
        switch value {
        case .object(let object):
            var sanitized: [String: Value] = [:]
            for (key, child) in object {
                sanitized[key] = isSensitiveKey(key)
                    ? .string("[REDACTED]")
                    : sanitizeError(child, key: key)
            }
            return .object(sanitized)
        case .array(let array):
            return .array(array.map { sanitizeError($0, key: key) })
        case .string(let string):
            return .string(
                preservesOpaqueIdentifiers(key)
                    ? Redactor.redactPreservingOpaqueIdentifiers(string)
                    : Redactor.redact(string)
            )
        case .double(let number) where !number.isFinite:
            return .null
        default:
            return value
        }
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let normalized = lower.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)

        if normalized == "hascachedtoken" {
            return false
        }

        return lower.contains("password") ||
            lower.contains("secret") ||
            lower.contains("authorization") ||
            lower.contains("bearer") ||
            normalized.contains("privatekey") ||
            normalized.contains("keycontent") ||
            normalized == "token" ||
            lower.hasSuffix("_token") ||
            lower.hasSuffix("-token") ||
            (normalized.hasSuffix("token") && !normalized.hasPrefix("has"))
    }

    private static func isIdentifierKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return key == "id" ||
            key.hasSuffix("Id") ||
            key.hasSuffix("ID") ||
            key.lowercased().hasSuffix("_id") ||
            key.lowercased().hasSuffix("-id")
    }

    private static func preservesOpaqueIdentifiers(_ key: String?) -> Bool {
        guard let key else { return false }
        if isIdentifierKey(key) {
            return true
        }
        let normalized = key.lowercased().replacingOccurrences(
            of: "[^a-z0-9]",
            with: "",
            options: .regularExpression
        )
        if normalized.hasSuffix("state") ||
            normalized.contains("checksum") ||
            normalized == "filename" ||
            normalized == "fingerprintkey" {
            return true
        }
        return [
            "reason",
            "code",
            "failedstep",
            "recoverytool",
            "recoverytools"
        ].contains(normalized)
    }
}

enum MCPValue {
    static func fromAny(_ any: Any) throws -> Value {
        switch any {
        case let value as Value:
            return value
        case _ as NSNull:
            return .null
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as Int8:
            return .int(Int(value))
        case let value as Int16:
            return .int(Int(value))
        case let value as Int32:
            return .int(Int(value))
        case let value as Int64:
            guard value >= Int64(Int.min), value <= Int64(Int.max) else {
                throw ASCError.parsing("Integer value is outside Swift Int range")
            }
            return .int(Int(value))
        case let value as UInt:
            guard value <= UInt(Int.max) else {
                throw ASCError.parsing("Unsigned integer value is outside Swift Int range")
            }
            return .int(Int(value))
        case let value as UInt8:
            return .int(Int(value))
        case let value as UInt16:
            return .int(Int(value))
        case let value as UInt32:
            guard value <= UInt32(Int.max) else {
                throw ASCError.parsing("Unsigned integer value is outside Swift Int range")
            }
            return .int(Int(value))
        case let value as UInt64:
            guard value <= UInt64(Int.max) else {
                throw ASCError.parsing("Unsigned integer value is outside Swift Int range")
            }
            return .int(Int(value))
        case let value as Float:
            guard value.isFinite else {
                throw ASCError.parsing("Non-finite floating point value cannot be encoded")
            }
            return .double(Double(value))
        case let value as Double:
            guard value.isFinite else {
                throw ASCError.parsing("Non-finite floating point value cannot be encoded")
            }
            return .double(value)
        case let value as Decimal:
            return .string(NSDecimalNumber(decimal: value).stringValue)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            let double = value.doubleValue
            guard double.isFinite else {
                throw ASCError.parsing("Non-finite numeric value cannot be encoded")
            }
            if floor(double) == double,
               double >= Double(Int.min),
               double <= Double(Int.max) {
                return .int(value.intValue)
            }
            return .double(double)
        case let value as Date:
            return .string(ISO8601DateFormatter().string(from: value))
        case let value as [Any]:
            return .array(try value.map { try fromAny($0) })
        case let value as [String: Any]:
            var object: [String: Value] = [:]
            for (key, child) in value {
                object[key] = try fromAny(child)
            }
            return .object(object)
        default:
            throw ASCError.parsing("Unsupported structured value type: \(type(of: any))")
        }
    }

    static func prettyJSONString(from value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func compactJSONString(from value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ASCError.parsing("Failed to encode structured value as UTF-8 JSON")
        }
        return string
    }
}
