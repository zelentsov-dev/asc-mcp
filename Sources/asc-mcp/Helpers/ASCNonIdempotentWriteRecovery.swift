import Foundation
import MCP

enum ASCNonIdempotentWriteFailurePhase: Equatable, Sendable {
    case request
    case acceptedResponse
}

enum ASCNonIdempotentWriteFailureDisposition: String, Equatable, Sendable {
    case rejected
    case outcomeUnknown = "unknown"
    case committedUnverified = "committed_unverified"
}

enum ASCNonIdempotentWriteRecovery {
    static func validateSuccessfulStatus(
        _ statusCode: Int,
        expectedStatusCode: Int,
        context: String
    ) throws {
        guard statusCode == expectedStatusCode else {
            throw ASCError.api(
                "\(context) returned unexpected successful HTTP status \(statusCode); expected \(expectedStatusCode)",
                statusCode
            )
        }
    }

    static func validateResourceIdentity(
        type: String,
        id: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws {
        guard type == expectedType else {
            throw ASCError.parsing(
                "\(context) returned unexpected resource type '\(type)'"
            )
        }

        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, trimmedID == id else {
            throw ASCError.parsing("\(context) returned an invalid resource ID")
        }

        let encodedID = try ASCPathSegment.encode(id, field: "\(context) resource ID")
        guard encodedID == id else {
            throw ASCError.parsing("\(context) returned a non-canonical resource ID")
        }

        if let expectedID, id != expectedID {
            throw ASCError.parsing("\(context) returned an unexpected resource ID")
        }
    }

    static func validateCreatedResource(
        type: String,
        id: String,
        expectedType: String
    ) throws {
        try validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            context: "Apple create response"
        )
    }

    static func failureDisposition(
        for error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> ASCNonIdempotentWriteFailureDisposition {
        switch phase {
        case .acceptedResponse:
            return .committedUnverified
        case .request:
            break
        }

        guard let ascError = error as? ASCError else {
            return .outcomeUnknown
        }
        switch ascError {
        case .api(_, let statusCode)
            where (400...499).contains(statusCode) && statusCode != 408:
            return .rejected
        case .apiResponse(_, let statusCode)
            where (400...499).contains(statusCode) && statusCode != 408:
            return .rejected
        default:
            return .outcomeUnknown
        }
    }

    static func failureDetails(
        for error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        operation: String,
        identifiers: [String: Value],
        listTool: String,
        listArguments: [String: Value],
        getTool: String,
        getIDArgument: String,
        listResultIDPath: String,
        matchingFields: [String]
    ) -> Value {
        var details = identifiers
        let disposition = failureDisposition(for: error, phase: phase)
        details["operation"] = .string(operation)
        details["write_outcome"] = .string(disposition.rawValue)
        details["operationCommitState"] = .string(disposition.rawValue)
        details["retrySafe"] = .bool(false)
        details["cause"] = structuredCause(for: error, phase: phase)

        if disposition == .rejected {
            return .object(details)
        }

        details["inspectionRequired"] = .bool(true)
        switch disposition {
        case .rejected:
            break
        case .outcomeUnknown:
            details["outcomeUnknown"] = .bool(true)
        case .committedUnverified:
            details["operationCommitted"] = .bool(true)
            details["outcomeUnknown"] = .bool(false)
        }
        let presentMatchingFields = matchingFields.filter { identifiers[$0] != nil }
        details["recovery"] = .object([
            "list_candidates": .object([
                "tool": .string(listTool),
                "arguments": .object(listArguments),
                "continue_with_next_url": .bool(true)
            ]),
            "match_requested": .object([
                "fields": .array(presentMatchingFields.map(Value.string)),
                "identifiers": .object(identifiers)
            ]),
            "get_candidate": .object([
                "tool": .string(getTool),
                "id_argument": .string(getIDArgument),
                "id_source": .string(listResultIDPath),
                "after": .string("list_candidates")
            ])
        ])
        return .object(details)
    }

    private static func structuredCause(
        for error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> Value {
        if let ascError = error as? ASCError {
            return ascError.structuredValue
        }

        if error is CancellationError {
            return .object([
                "type": .string("cancellation"),
                "message": .string("The request was cancelled before its write outcome was confirmed")
            ])
        }

        let type = switch phase {
        case .request:
            "request"
        case .acceptedResponse:
            "response_validation"
        }
        return .object([
            "type": .string(type),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }
}
