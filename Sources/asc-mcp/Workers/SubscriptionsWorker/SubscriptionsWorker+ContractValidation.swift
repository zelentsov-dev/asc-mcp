import Foundation
import MCP

extension SubscriptionsWorker {
    func validateSubscriptionResourceIdentity(
        type: String,
        id: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validateSubscriptionResourceCollection(
        _ resources: [(type: String, id: String)],
        expectedType: String,
        context: String
    ) throws {
        var identities = Set<String>()
        for resource in resources {
            try validateSubscriptionResourceIdentity(
                type: resource.type,
                id: resource.id,
                expectedType: expectedType,
                context: context
            )
            guard identities.insert(resource.id).inserted else {
                throw ASCError.parsing("\(context) returned duplicate resource ID '\(resource.id)'")
            }
        }
    }

    func validateSubscriptionRelationshipIdentity(
        _ identifier: ASCResourceIdentifier,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validateSubscriptionPagedRelationship(
        _ relationship: ASCPricingPagedRelationship?,
        expectedType: String,
        context: String
    ) throws {
        guard let relationship else { return }
        let resources = relationship.data ?? []
        try validateSubscriptionResourceCollection(
            resources.map { (type: $0.type, id: $0.id) },
            expectedType: expectedType,
            context: context
        )
        try validateSubscriptionPagingInformation(
            relationship.meta,
            resourceCount: resources.count,
            context: context
        )
    }

    func validateSubscriptionPagingInformation(
        _ meta: ASCPagingInformation?,
        resourceCount: Int,
        nextLink: String? = nil,
        validatesContinuation: Bool = false,
        context: String
    ) throws {
        if validatesContinuation, let nextLink {
            guard !nextLink.isEmpty,
                  nextLink == nextLink.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ASCError.parsing("\(context) returned an invalid links.next")
            }
        }
        guard let meta else { return }
        guard let paging = meta.paging, let limit = paging.limit else {
            throw ASCError.parsing("\(context) returned incomplete paging metadata")
        }
        guard limit > 0, limit >= resourceCount else {
            throw ASCError.parsing("\(context) returned paging.limit smaller than the resource count")
        }
        if let total = paging.total {
            guard total >= 0, total >= resourceCount else {
                throw ASCError.parsing("\(context) returned paging.total smaller than the resource count")
            }
        }
        if let nextCursor = paging.nextCursor {
            guard !nextCursor.isEmpty,
                  nextCursor == nextCursor.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ASCError.parsing("\(context) returned an invalid nextCursor")
            }
            if validatesContinuation, nextLink == nil {
                throw ASCError.parsing("\(context) returned nextCursor without a usable links.next")
            }
        }
    }

    func validateSubscriptionDocumentSelfLink(
        _ link: String,
        expectedPath: String,
        context: String
    ) throws {
        guard !link.isEmpty,
              link == link.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: link),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.percentEncodedPath == expectedPath else {
            throw ASCError.parsing("\(context) returned an invalid links.self URL")
        }

        if let scheme = components.scheme {
            guard ["http", "https"].contains(scheme.lowercased()),
                  components.host?.isEmpty == false else {
                throw ASCError.parsing("\(context) returned an invalid links.self URL")
            }
        } else if components.host != nil {
            throw ASCError.parsing("\(context) returned an invalid links.self URL")
        }
    }

    func subscriptionCommittedUnverifiedMutationFailure(
        operation: String,
        targetField: String,
        targetID: String,
        requestedArguments: [String: Value] = [:],
        error: Error,
        inspectionTool: String
    ) -> CallTool.Result {
        let cause = (error as? ASCError)?.structuredValue ?? .object([
            "type": .string("response_validation"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
        var details = requestedArguments
        details["requestedArguments"] = .object(requestedArguments)
        details.merge([
            "operation": .string(operation),
            "operationCommitState": .string("committed_unverified"),
            "operationCommitted": .bool(true),
            "outcomeUnknown": .bool(false),
            "retrySafe": .bool(false),
            "inspectionRequired": .bool(true),
            "mutationAttempted": .bool(true),
            "targetId": .string(targetID),
            targetField: .string(targetID),
            "cause": cause,
            "inspection": .object([
                "tool": .string(inspectionTool),
                "arguments": .object([targetField: .string(targetID)]),
                "instruction": .string("Inspect this exact resource before retrying the mutation.")
            ])
        ]) { _, replacement in replacement }
        let message = "Apple accepted the mutation, but the returned resource identity could not be verified. Inspect the exact target before retrying."
        return MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string(message),
                "details": .object(details),
                "operationCommitState": .string("committed_unverified"),
                "operationCommitted": .bool(true),
                "outcomeUnknown": .bool(false),
                "inspectionRequired": .bool(true),
                "retrySafe": .bool(false)
            ]),
            text: "Error: \(message)",
            isError: true
        )
    }

    func subscriptionMutationRequestFailure(
        operation: String,
        action: String,
        targetField: String,
        targetID: String,
        requestedArguments: [String: Value],
        error: Error,
        inspectionTool: String
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request)
        guard disposition != .rejected else {
            return MCPResult.error(error, prefix: "Failed to \(action)")
        }

        let cause = (error as? ASCError)?.structuredValue ?? .object([
            "type": .string(error is CancellationError ? "cancellation" : "request"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
        var details = requestedArguments
        details.merge([
            "requestedArguments": .object(requestedArguments),
            "operation": .string(operation),
            "operationCommitState": .string("unknown"),
            "outcomeUnknown": .bool(true),
            "retrySafe": .bool(false),
            "inspectionRequired": .bool(true),
            "mutationAttempted": .bool(true),
            "targetId": .string(targetID),
            targetField: .string(targetID),
            "cause": cause,
            "inspection": .object([
                "tool": .string(inspectionTool),
                "arguments": .object([targetField: .string(targetID)]),
                "instruction": .string("Inspect this exact resource before retrying the mutation.")
            ])
        ]) { _, replacement in replacement }
        let message = "The \(action) outcome is unknown. Inspect the exact target before retrying."
        return MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string(message),
                "details": .object(details),
                "operationCommitState": .string("unknown"),
                "outcomeUnknown": .bool(true),
                "inspectionRequired": .bool(true),
                "retrySafe": .bool(false)
            ]),
            text: "Error: \(message)",
            isError: true
        )
    }
}
