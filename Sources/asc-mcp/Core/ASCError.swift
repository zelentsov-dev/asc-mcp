import Foundation
import MCP

/// ASC Error types
public enum ASCError: LocalizedError, Sendable {
    case configuration(String)
    case api(String, Int)
    case apiResponse(ASCAPIErrorResponse, Int)
    case network(String)
    indirect case deleteOutcomeUnknown(ASCError)
    case authentication(String)
    case parsing(String)
    
    public var errorDescription: String? {
        switch self {
        case .configuration(let message):
            return "Configuration error: \(message)"
        case .api(let message, let code):
            return "API error (\(code)): \(message)"
        case .apiResponse(let response, let code):
            let message = response.errors.map(\.safeDescription).joined(separator: "; ")
            return "API error (\(code)): \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .deleteOutcomeUnknown(let cause):
            return "DELETE outcome is unknown: \(cause.localizedDescription) Inspect the exact target before another delete attempt."
        case .authentication(let message):
            return "Authentication error: \(message)"
        case .parsing(let message):
            return "Parsing error: \(message)"
        }
    }

    var structuredValue: Value {
        switch self {
        case .configuration(let message):
            return structuredError(type: "configuration", message: message)
        case .api(let message, let statusCode):
            return structuredError(type: "api", message: message, statusCode: statusCode)
        case .apiResponse(let response, let statusCode):
            return .object([
                "type": .string("api"),
                "statusCode": .int(statusCode),
                "errors": .array(response.errors.map(\.structuredValue))
            ])
        case .network(let message):
            return structuredError(type: "network", message: message)
        case .deleteOutcomeUnknown(let cause):
            return .object([
                "type": .string("delete_unknown"),
                "method": .string("DELETE"),
                "operationCommitState": .string("unknown"),
                "outcomeUnknown": .bool(true),
                "retrySafe": .bool(false),
                "cause": cause.structuredValue
            ])
        case .authentication(let message):
            return structuredError(type: "authentication", message: message)
        case .parsing(let message):
            return structuredError(type: "parsing", message: message)
        }
    }

    private func structuredError(type: String, message: String, statusCode: Int? = nil) -> Value {
        var object: [String: Value] = [
            "type": .string(type),
            "message": .string(message)
        ]
        if let statusCode {
            object["statusCode"] = .int(statusCode)
        }
        return .object(object)
    }
}
