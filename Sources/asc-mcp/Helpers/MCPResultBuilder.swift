import Foundation
import MCP

enum MCPContent {
    static func text(_ text: String, _meta: Metadata? = nil) -> Tool.Content {
        .text(text: text, annotations: nil, _meta: _meta)
    }
}

enum MCPResult {
    static func text(_ text: String, isError: Bool = false, _meta: Metadata? = nil) -> CallTool.Result {
        CallTool.Result(
            content: [MCPContent.text(text)],
            isError: isError ? true : nil,
            _meta: _meta
        )
    }

    static func json(
        _ value: Value,
        text: String? = nil,
        isError: Bool = false,
        _meta: Metadata? = nil
    ) -> CallTool.Result {
        let sanitizedValue = MCPValueSanitizer.sanitize(value)
        let textContent = text ?? (try? MCPValue.prettyJSONString(from: sanitizedValue)) ?? sanitizedValue.description
        return CallTool.Result(
            content: [MCPContent.text(textContent)],
            structuredContent: Optional.some(sanitizedValue),
            isError: isError ? true : nil,
            _meta: _meta
        )
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
        let structured: Value = .object([
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "details": details ?? .null
        ])
        return json(structured, text: "Error: \(Redactor.redact(message))", isError: true, _meta: _meta)
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
}
