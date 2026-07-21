import Foundation
import MCP

/// ASC Error types
public enum ASCError: LocalizedError, Sendable {
    case configuration(String)
    case api(String, Int)
    case apiResponse(ASCAPIErrorResponse, Int)
    case network(String)
    indirect case mutationOutcomeUnknown(method: String, cause: ASCError)
    indirect case mutationCommittedUnverified(
        method: String,
        expectedStatusCode: Int,
        actualStatusCode: Int,
        cause: ASCError?
    )
    indirect case deleteOutcomeUnknown(ASCError)
    case deleteCommittedUnverified(statusCode: Int)
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
        case .mutationOutcomeUnknown(let method, let cause):
            return "\(method) outcome is unknown: \(cause.localizedDescription) Inspect the exact target before another mutation attempt."
        case .mutationCommittedUnverified(
            let method,
            let expectedStatusCode,
            let actualStatusCode,
            let cause
        ):
            if let cause, actualStatusCode == expectedStatusCode {
                return "\(method) was accepted with HTTP \(actualStatusCode), but response verification failed and completion is unverified. Inspect the exact target before another mutation attempt. Cause: \(cause.localizedDescription)"
            }
            let suffix = cause.map { " Cause: \($0.localizedDescription)" } ?? ""
            return "\(method) was accepted with HTTP \(actualStatusCode), but HTTP \(expectedStatusCode) was required and completion is unverified. Inspect the exact target before another mutation attempt.\(suffix)"
        case .deleteOutcomeUnknown(let cause):
            return "DELETE outcome is unknown: \(cause.localizedDescription) Inspect the exact target before another delete attempt."
        case .deleteCommittedUnverified(let statusCode):
            return "DELETE returned HTTP \(statusCode), but completion is unverified because the success response did not match the required contract. Inspect the exact target before another delete attempt."
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
        case .mutationOutcomeUnknown(let method, let cause):
            return .object([
                "type": .string("mutation_unknown"),
                "method": .string(method),
                "operationCommitState": .string("unknown"),
                "outcomeUnknown": .bool(true),
                "retrySafe": .bool(false),
                "inspectionRequired": .bool(true),
                "cause": cause.structuredValue
            ])
        case .mutationCommittedUnverified(
            let method,
            let expectedStatusCode,
            let actualStatusCode,
            let cause
        ):
            var object: [String: Value] = [
                "type": .string("mutation_unverified"),
                "method": .string(method),
                "expectedStatusCode": .int(expectedStatusCode),
                "statusCode": .int(actualStatusCode),
                "operationCommitState": .string("committed_unverified"),
                "operationCommitted": .bool(true),
                "outcomeUnknown": .bool(false),
                "retrySafe": .bool(false),
                "inspectionRequired": .bool(true)
            ]
            if let cause {
                object["cause"] = cause.structuredValue
            }
            return .object(object)
        case .deleteOutcomeUnknown(let cause):
            return .object([
                "type": .string("delete_unknown"),
                "method": .string("DELETE"),
                "operationCommitState": .string("unknown"),
                "outcomeUnknown": .bool(true),
                "retrySafe": .bool(false),
                "inspectionRequired": .bool(true),
                "cause": cause.structuredValue
            ])
        case .deleteCommittedUnverified(let statusCode):
            return .object([
                "type": .string("delete_unverified"),
                "method": .string("DELETE"),
                "statusCode": .int(statusCode),
                "operationCommitState": .string("committed_unverified"),
                "operationCommitted": .bool(true),
                "outcomeUnknown": .bool(false),
                "retrySafe": .bool(false),
                "inspectionRequired": .bool(true)
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
