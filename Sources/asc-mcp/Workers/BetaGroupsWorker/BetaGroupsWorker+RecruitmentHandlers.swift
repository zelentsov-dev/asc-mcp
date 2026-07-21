import Foundation
import MCP

extension BetaGroupsWorker {
    func getRecruitmentCriteria(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }

        do {
            try validateRecruitmentArguments(arguments, allowed: ["group_id"])
            let groupID = try recruitmentIdentifier("group_id", from: arguments)
            try await confirmBetaGroup(groupID)
            switch try await recruitmentCriteria(for: groupID) {
            case .absent:
                return MCPResult.jsonObject([
                    "success": true,
                    "groupId": groupID,
                    "criteriaPresent": false
                ])
            case .present(let criterion):
                return MCPResult.jsonObject([
                    "success": true,
                    "groupId": groupID,
                    "criteriaPresent": true,
                    "recruitmentCriteria": formatRecruitmentCriterion(criterion)
                ])
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to get beta recruitment criteria")
        }
    }

    func createRecruitmentCriteria(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters 'group_id' and 'device_filters' are missing")
        }

        let groupID: String
        let filters: [ASCDeviceFamilyOsVersionFilter]
        do {
            try validateRecruitmentArguments(arguments, allowed: ["group_id", "device_filters"])
            groupID = try recruitmentIdentifier("group_id", from: arguments)
            filters = try recruitmentFilters(arguments["device_filters"], field: "device_filters")
            try await confirmBetaGroup(groupID)
            if case .present(let existing) = try await recruitmentCriteria(for: groupID) {
                return MCPResult.error(
                    "Beta group already has recruitment criteria",
                    details: .object([
                        "groupId": .string(groupID),
                        "criterionId": .string(existing.id),
                        "inspection": recruitmentInspectionValue(groupID: groupID)
                    ])
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate beta recruitment criteria creation")
        }

        let request = CreateBetaRecruitmentCriterionRequest(
            data: .init(
                attributes: .init(deviceFamilyOsVersionFilters: filters),
                relationships: .init(
                    betaGroup: .init(
                        data: ASCResourceIdentifier(type: "betaGroups", id: groupID)
                    )
                )
            )
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            return recruitmentPreRequestFailure(
                operation: "create",
                groupID: groupID,
                criterionID: nil,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/betaRecruitmentCriteria", body: requestData)
        } catch {
            return await recruitmentRequestFailure(
                operation: "create",
                groupID: groupID,
                criterionID: nil,
                error: error
            )
        }

        let response: ASCBetaRecruitmentCriterionResponse
        var validatedResponseCriterionID: String? = nil
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Beta recruitment criterion create"
            )
            response = try JSONDecoder().decode(ASCBetaRecruitmentCriterionResponse.self, from: receipt.data)
            try validateRecruitmentCriterion(
                response.data,
                expectedID: nil,
                context: "beta recruitment criterion create"
            )
            validatedResponseCriterionID = response.data.id
            try validateRecruitmentDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/betaRecruitmentCriteria/\(try ASCPathSegment.encode(response.data.id))",
                context: "beta recruitment criterion create"
            )
            guard filtersMatch(response.data, expected: filters) else {
                throw RecruitmentArgumentError("Apple create response did not preserve the requested device filters")
            }
        } catch {
            return await recruitmentAcceptedResponseFailure(
                operation: "create",
                groupID: groupID,
                criterionID: nil,
                responseCriterionID: validatedResponseCriterionID,
                error: error
            )
        }

        do {
            guard case .present(let confirmed) = try await recruitmentCriteria(for: groupID) else {
                throw RecruitmentArgumentError("The freshly created criterion was not present in the requested beta group")
            }
            try validateRecruitmentCriterion(
                confirmed,
                expectedID: response.data.id,
                context: "beta recruitment criterion create postflight"
            )
            guard filtersMatch(confirmed, expected: filters) else {
                throw RecruitmentArgumentError("The group-scoped criterion did not preserve the requested device filters")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "createdByInvocation": true,
                "candidateAttributionConfirmed": true,
                "changed": true,
                "retrySafe": false,
                "groupId": groupID,
                "statusCode": receipt.statusCode,
                "recruitmentCriteria": formatRecruitmentCriterion(confirmed)
            ])
        } catch {
            return await recruitmentAcceptedResponseFailure(
                operation: "create",
                groupID: groupID,
                criterionID: response.data.id,
                responseCriterionID: response.data.id,
                error: error
            )
        }
    }

    func updateRecruitmentCriteria(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters 'group_id', 'criterion_id', and 'device_filters' are missing")
        }

        let groupID: String
        let criterionID: String
        let update: ASCNullableDeviceFamilyOsVersionFilters
        do {
            try validateRecruitmentArguments(
                arguments,
                allowed: ["group_id", "criterion_id", "device_filters"]
            )
            groupID = try recruitmentIdentifier("group_id", from: arguments)
            criterionID = try recruitmentIdentifier("criterion_id", from: arguments)
            update = try nullableRecruitmentFilters(arguments["device_filters"], field: "device_filters")
            try await confirmBetaGroup(groupID)
            guard case .present(let current) = try await recruitmentCriteria(for: groupID) else {
                return MCPResult.error("Beta group has no recruitment criteria to update")
            }
            guard current.id == criterionID else {
                return MCPResult.error("criterion_id does not match the criterion attached to this beta group")
            }
            if filtersMatch(current, expected: update) {
                return MCPResult.jsonObject([
                    "success": true,
                    "operation": "update",
                    "operationCommitted": false,
                    "operationCommitState": "not_attempted",
                    "changed": false,
                    "retrySafe": false,
                    "groupId": groupID,
                    "recruitmentCriteria": formatRecruitmentCriterion(current)
                ])
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate beta recruitment criteria update")
        }

        let request = UpdateBetaRecruitmentCriterionRequest(
            data: .init(
                id: criterionID,
                attributes: .init(deviceFamilyOsVersionFilters: update)
            )
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            return recruitmentPreRequestFailure(
                operation: "update",
                groupID: groupID,
                criterionID: criterionID,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/betaRecruitmentCriteria/\(try ASCPathSegment.encode(criterionID, field: "criterion_id"))",
                body: requestData
            )
        } catch {
            return await recruitmentRequestFailure(
                operation: "update",
                groupID: groupID,
                criterionID: criterionID,
                error: error
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Beta recruitment criterion update"
            )
            let response = try JSONDecoder().decode(ASCBetaRecruitmentCriterionResponse.self, from: receipt.data)
            try validateRecruitmentCriterion(
                response.data,
                expectedID: criterionID,
                context: "beta recruitment criterion update"
            )
            try validateRecruitmentDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/betaRecruitmentCriteria/\(try ASCPathSegment.encode(criterionID))",
                context: "beta recruitment criterion update"
            )
            guard filtersMatch(response.data, expected: update) else {
                throw RecruitmentArgumentError("Apple update response omitted or changed the requested filter state")
            }
            guard case .present(let confirmed) = try await recruitmentCriteria(for: groupID) else {
                throw RecruitmentArgumentError("The updated criterion was absent from the requested beta group")
            }
            try validateRecruitmentCriterion(
                confirmed,
                expectedID: criterionID,
                context: "beta recruitment criterion update postflight"
            )
            guard filtersMatch(confirmed, expected: update) else {
                throw RecruitmentArgumentError("The group-scoped criterion did not preserve the requested filter state")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "update",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "changed": true,
                "retrySafe": false,
                "groupId": groupID,
                "statusCode": receipt.statusCode,
                "recruitmentCriteria": formatRecruitmentCriterion(confirmed)
            ])
        } catch {
            return await recruitmentAcceptedResponseFailure(
                operation: "update",
                groupID: groupID,
                criterionID: criterionID,
                responseCriterionID: nil,
                error: error
            )
        }
    }

    func deleteRecruitmentCriteria(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters 'group_id', 'criterion_id', and 'confirm_criterion_id' are missing")
        }

        let groupID: String
        let criterionID: String
        do {
            try validateRecruitmentArguments(
                arguments,
                allowed: ["group_id", "criterion_id", "confirm_criterion_id"]
            )
            groupID = try recruitmentIdentifier("group_id", from: arguments)
            criterionID = try recruitmentIdentifier("criterion_id", from: arguments)
            let confirmationID = try recruitmentIdentifier("confirm_criterion_id", from: arguments)
            guard confirmationID == criterionID else {
                throw RecruitmentArgumentError(
                    "Deleting beta recruitment criteria is irreversible. Set confirm_criterion_id to the exact criterion_id to continue."
                )
            }
            try await confirmBetaGroup(groupID)
            guard case .present(let current) = try await recruitmentCriteria(for: groupID) else {
                return MCPResult.error("Beta group has no recruitment criteria to delete")
            }
            guard current.id == criterionID else {
                return MCPResult.error("criterion_id does not match the criterion attached to this beta group")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate beta recruitment criteria deletion")
        }

        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(
                "/v1/betaRecruitmentCriteria/\(try ASCPathSegment.encode(criterionID, field: "criterion_id"))"
            )
        } catch {
            return await recruitmentRequestFailure(
                operation: "delete",
                groupID: groupID,
                criterionID: criterionID,
                error: error
            )
        }

        guard receipt.statusCode == 204 else {
            return await recruitmentAcceptedResponseFailure(
                operation: "delete",
                groupID: groupID,
                criterionID: criterionID,
                responseCriterionID: nil,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode)
            )
        }

        return MCPResult.jsonObject([
            "success": true,
            "operation": "delete",
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changed": true,
            "retrySafe": false,
            "groupId": groupID,
            "criterionId": criterionID,
            "statusCode": receipt.statusCode,
            "message": "Beta recruitment criteria deleted"
        ])
    }

    func listRecruitmentOptions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateRecruitmentArguments(arguments, allowed: ["limit", "next_url"])
            let limit = try recruitmentLimit(arguments["limit"])
            let path = "/v1/betaRecruitmentCriterionOptions"
            let query = [
                "fields[betaRecruitmentCriterionOptions]": "deviceFamilyOsVersions",
                "limit": String(limit)
            ]
            let response: ASCBetaRecruitmentCriterionOptionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCBetaRecruitmentCriterionOptionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCBetaRecruitmentCriterionOptionsResponse.self
                )
            }
            try validateRecruitmentDocumentSelf(response.links.`self`, expectedPath: path, context: "recruitment options")
            var identities = Set<String>()
            for option in response.data {
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: option.type.rawValue,
                    id: option.id,
                    expectedType: "betaRecruitmentCriterionOptions",
                    context: "recruitment option"
                )
                guard identities.insert(option.id).inserted else {
                    throw RecruitmentArgumentError("Apple returned a duplicate recruitment-option identity")
                }
            }
            try validateRecruitmentPaging(
                links: response.links,
                meta: response.meta,
                pageCount: response.data.count,
                context: "recruitment options"
            )

            var result: [String: Any] = [
                "success": true,
                "options": response.data.map(formatRecruitmentOption),
                "count": response.data.count,
                "limit": limit
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list beta recruitment options")
        }
    }

    func checkRecruitmentCompatibility(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }

        do {
            try validateRecruitmentArguments(arguments, allowed: ["group_id"])
            let groupID = try recruitmentIdentifier("group_id", from: arguments)
            try await confirmBetaGroup(groupID)
            let path = "/v1/betaGroups/\(try ASCPathSegment.encode(groupID, field: "group_id"))/betaRecruitmentCriterionCompatibleBuildCheck"
            let response = try await httpClient.get(
                path,
                parameters: ["fields[betaRecruitmentCriterionCompatibleBuildChecks]": "hasCompatibleBuild"],
                as: ASCBetaRecruitmentCompatibilityResponse.self
            )
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: response.data.type.rawValue,
                id: response.data.id,
                expectedType: "betaRecruitmentCriterionCompatibleBuildChecks",
                context: "recruitment compatibility check"
            )
            try validateRecruitmentDocumentSelf(response.links.`self`, expectedPath: path, context: "recruitment compatibility check")
            return MCPResult.jsonObject([
                "success": true,
                "groupId": groupID,
                "compatibilityCheckId": response.data.id,
                "hasCompatibleBuild": (response.data.attributes?.hasCompatibleBuild).jsonSafe
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to check beta recruitment compatibility")
        }
    }
}

private extension BetaGroupsWorker {
    enum RecruitmentCriteriaLookup {
        case present(ASCBetaRecruitmentCriterion)
        case absent
    }

    struct RecruitmentDiagnostic {
        let criterion: ASCBetaRecruitmentCriterion?
        let error: String?
    }

    func confirmBetaGroup(_ groupID: String) async throws {
        let path = "/v1/betaGroups/\(try ASCPathSegment.encode(groupID, field: "group_id"))"
        let response = try await httpClient.get(
            path,
            parameters: ["fields[betaGroups]": "name"],
            as: ASCBetaRecruitmentParentResponse.self
        )
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: response.data.type,
            id: response.data.id,
            expectedType: "betaGroups",
            expectedID: groupID,
            context: "beta recruitment parent lookup"
        )
        try validateRecruitmentDocumentSelf(response.links.`self`, expectedPath: path, context: "beta recruitment parent lookup")
    }

    func recruitmentCriteria(for groupID: String) async throws -> RecruitmentCriteriaLookup {
        let path = "/v1/betaGroups/\(try ASCPathSegment.encode(groupID, field: "group_id"))/betaRecruitmentCriteria"
        do {
            let response = try await httpClient.get(
                path,
                parameters: ["fields[betaRecruitmentCriteria]": "lastModifiedDate,deviceFamilyOsVersionFilters"],
                as: ASCBetaRecruitmentCriterionResponse.self
            )
            try validateRecruitmentCriterion(response.data, expectedID: nil, context: "group-scoped recruitment criterion")
            try validateRecruitmentDocumentSelf(response.links.`self`, expectedPath: path, context: "group-scoped recruitment criterion")
            return .present(response.data)
        } catch let error as ASCError {
            switch error {
            case .api(_, 404), .apiResponse(_, 404):
                return .absent
            default:
                throw error
            }
        }
    }

    func diagnosticRecruitmentCriterion(groupID: String) async -> RecruitmentDiagnostic {
        do {
            switch try await recruitmentCriteria(for: groupID) {
            case .present(let criterion):
                return RecruitmentDiagnostic(criterion: criterion, error: nil)
            case .absent:
                return RecruitmentDiagnostic(criterion: nil, error: nil)
            }
        } catch {
            return RecruitmentDiagnostic(
                criterion: nil,
                error: Redactor.redact(error.localizedDescription)
            )
        }
    }

    func recruitmentRequestFailure(
        operation: String,
        groupID: String,
        criterionID: String?,
        error: Error
    ) async -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request)
        let diagnostic = await diagnosticRecruitmentCriterion(groupID: groupID)
        return recruitmentMutationFailure(
            operation: operation,
            groupID: groupID,
            criterionID: criterionID,
            responseCriterionID: nil,
            disposition: disposition,
            error: error,
            diagnostic: diagnostic
        )
    }

    func recruitmentAcceptedResponseFailure(
        operation: String,
        groupID: String,
        criterionID: String?,
        responseCriterionID: String?,
        error: Error
    ) async -> CallTool.Result {
        let diagnostic = await diagnosticRecruitmentCriterion(groupID: groupID)
        return recruitmentMutationFailure(
            operation: operation,
            groupID: groupID,
            criterionID: criterionID,
            responseCriterionID: responseCriterionID,
            disposition: .committedUnverified,
            error: error,
            diagnostic: diagnostic
        )
    }

    func recruitmentMutationFailure(
        operation: String,
        groupID: String,
        criterionID: String?,
        responseCriterionID: String?,
        disposition: ASCNonIdempotentWriteFailureDisposition,
        error: Error,
        diagnostic: RecruitmentDiagnostic
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": operation,
            "operationCommitState": disposition.rawValue,
            "write_outcome": disposition.rawValue,
            "mutationAttempted": true,
            "groupId": groupID,
            "retrySafe": disposition == .rejected,
            "error": Redactor.redact(error.localizedDescription),
            "inspection": recruitmentInspection(groupID: groupID)
        ]
        if let criterionID {
            payload["criterionId"] = criterionID
        }
        if let responseCriterionID {
            payload["responseCriterionId"] = responseCriterionID
        }
        if let criterion = diagnostic.criterion {
            payload["observedCandidate"] = formatRecruitmentCriterion(criterion)
            payload["candidateId"] = criterion.id
            payload["candidateAttributionConfirmed"] = false
            if operation == "create" {
                payload["createdByInvocation"] = false
            }
        }
        if let diagnosticError = diagnostic.error {
            payload["inspectionError"] = diagnosticError
        }
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = false
            payload["outcomeUnknown"] = false
        case .outcomeUnknown:
            payload["operationCommitted"] = NSNull()
            payload["outcomeUnknown"] = true
            payload["inspectionRequired"] = true
        case .committedUnverified:
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
        }
        let text: String
        switch disposition {
        case .rejected:
            text = "Error: Apple definitively rejected the beta recruitment \(operation); the mutation was not committed."
        case .outcomeUnknown:
            text = "Error: The beta recruitment \(operation) outcome is unknown. Inspect the exact group state before retrying."
        case .committedUnverified:
            text = "Error: Apple accepted the beta recruitment \(operation), but completion was not safely verified. Inspect the exact group state before retrying."
        }
        return MCPResult.jsonObject(payload, text: text, isError: true)
    }

    func recruitmentPreRequestFailure(
        operation: String,
        groupID: String,
        criterionID: String?,
        error: Error
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": operation,
            "operationCommitState": "not_attempted",
            "write_outcome": "not_attempted",
            "mutationAttempted": false,
            "operationCommitted": false,
            "groupId": groupID,
            "retrySafe": true,
            "error": Redactor.redact(error.localizedDescription)
        ]
        if let criterionID {
            payload["criterionId"] = criterionID
        }
        return MCPResult.jsonObject(payload, isError: true)
    }

    func recruitmentInspection(groupID: String) -> [String: Any] {
        [
            "tool": "beta_groups_get_recruitment_criteria",
            "arguments": ["group_id": groupID],
            "instruction": "Inspect the exact beta group criterion before any retry or follow-up mutation."
        ]
    }

    func recruitmentInspectionValue(groupID: String) -> Value {
        .object([
            "tool": .string("beta_groups_get_recruitment_criteria"),
            "arguments": .object(["group_id": .string(groupID)]),
            "instruction": .string("Inspect the exact beta group criterion before any retry or follow-up mutation.")
        ])
    }

    func validateRecruitmentArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw RecruitmentArgumentError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    func recruitmentIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw RecruitmentArgumentError("\(name) must be a string")
        }
        let encoded = try ASCPathSegment.encode(value, field: name)
        guard encoded == value else {
            throw RecruitmentArgumentError("\(name) must be a canonical App Store Connect resource ID")
        }
        return value
    }

    func recruitmentFilters(_ value: Value?, field: String) throws -> [ASCDeviceFamilyOsVersionFilter] {
        guard let values = value?.arrayValue else {
            throw RecruitmentArgumentError("\(field) must be an array")
        }
        return try values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw RecruitmentArgumentError("\(field)[\(index)] must be an object")
            }
            let allowed = Set(["device_family", "minimum_os_inclusive", "maximum_os_inclusive"])
            guard Set(object.keys).isSubset(of: allowed) else {
                throw RecruitmentArgumentError("\(field)[\(index)] contains an unsupported property")
            }
            let deviceFamily = try optionalDeviceFamily(
                object["device_family"],
                field: "\(field)[\(index)].device_family"
            )
            let minimum = try optionalRecruitmentString(
                object["minimum_os_inclusive"],
                field: "\(field)[\(index)].minimum_os_inclusive"
            )
            let maximum = try optionalRecruitmentString(
                object["maximum_os_inclusive"],
                field: "\(field)[\(index)].maximum_os_inclusive"
            )
            return ASCDeviceFamilyOsVersionFilter(
                deviceFamily: deviceFamily,
                minimumOsInclusive: minimum,
                maximumOsInclusive: maximum
            )
        }
    }

    func nullableRecruitmentFilters(
        _ value: Value?,
        field: String
    ) throws -> ASCNullableDeviceFamilyOsVersionFilters {
        guard let value else {
            throw RecruitmentArgumentError("\(field) is required")
        }
        if case .null = value {
            return .null
        }
        return .value(try recruitmentFilters(value, field: field))
    }

    func optionalDeviceFamily(_ value: Value?, field: String) throws -> ASCDeviceFamily? {
        guard let value else { return nil }
        guard let string = value.stringValue else {
            throw RecruitmentArgumentError("\(field) must be a string")
        }
        guard let deviceFamily = ASCDeviceFamily(rawValue: string) else {
            throw RecruitmentArgumentError("\(field) contains unsupported value '\(string)'")
        }
        return deviceFamily
    }

    func optionalRecruitmentString(_ value: Value?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let string = value.stringValue else {
            throw RecruitmentArgumentError("\(field) must be a string")
        }
        return string
    }

    func recruitmentLimit(_ value: Value?) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw RecruitmentArgumentError("limit must be an integer between 1 and 200")
        }
        return limit
    }

    func validateRecruitmentCriterion(
        _ criterion: ASCBetaRecruitmentCriterion,
        expectedID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: criterion.type.rawValue,
            id: criterion.id,
            expectedType: "betaRecruitmentCriteria",
            expectedID: expectedID,
            context: context
        )
    }

    func filtersMatch(
        _ criterion: ASCBetaRecruitmentCriterion,
        expected: [ASCDeviceFamilyOsVersionFilter]
    ) -> Bool {
        guard let attributes = criterion.attributes,
              attributes.hasDeviceFamilyOsVersionFilters,
              let actual = attributes.deviceFamilyOsVersionFilters else {
            return false
        }
        return actual.map(recruitmentFilterIdentity).sorted()
            == expected.map(recruitmentFilterIdentity).sorted()
    }

    func filtersMatch(
        _ criterion: ASCBetaRecruitmentCriterion,
        expected: ASCNullableDeviceFamilyOsVersionFilters
    ) -> Bool {
        guard let attributes = criterion.attributes,
              attributes.hasDeviceFamilyOsVersionFilters else {
            return false
        }
        switch expected {
        case .null:
            return attributes.deviceFamilyOsVersionFilters == nil
        case .value(let filters):
            return filtersMatch(criterion, expected: filters)
        }
    }

    func recruitmentFilterIdentity(_ filter: ASCDeviceFamilyOsVersionFilter) -> String {
        [filter.deviceFamily?.rawValue, filter.minimumOsInclusive, filter.maximumOsInclusive]
            .map { value in
                guard let value else { return "nil;" }
                return "value[\(value.utf8.count)]:\(value);"
            }
            .joined()
    }

    func formatRecruitmentCriterion(_ criterion: ASCBetaRecruitmentCriterion) -> [String: Any] {
        var result: [String: Any] = [
            "id": criterion.id,
            "type": criterion.type.rawValue,
            "lastModifiedDate": (criterion.attributes?.lastModifiedDate).jsonSafe
        ]
        guard let attributes = criterion.attributes,
              attributes.hasDeviceFamilyOsVersionFilters else {
            result["deviceFiltersState"] = "omitted"
            return result
        }
        if let filters = attributes.deviceFamilyOsVersionFilters {
            result["deviceFiltersState"] = "value"
            result["deviceFilters"] = filters.map(formatRecruitmentFilter)
        } else {
            result["deviceFiltersState"] = "null"
            result["deviceFilters"] = NSNull()
        }
        return result
    }

    func formatRecruitmentFilter(_ filter: ASCDeviceFamilyOsVersionFilter) -> [String: Any] {
        [
            "deviceFamily": (filter.deviceFamily?.rawValue).jsonSafe,
            "minimumOsInclusive": filter.minimumOsInclusive.jsonSafe,
            "maximumOsInclusive": filter.maximumOsInclusive.jsonSafe
        ]
    }

    func formatRecruitmentOption(_ option: ASCBetaRecruitmentCriterionOption) -> [String: Any] {
        let deviceFamilyOsVersions = option.attributes?.deviceFamilyOsVersions?.map { item in
            [
                "deviceFamily": (item.deviceFamily?.rawValue).jsonSafe,
                "osVersions": item.osVersions.jsonSafe
            ] as [String: Any]
        }
        return [
            "id": option.id,
            "type": option.type.rawValue,
            "deviceFamilyOsVersions": deviceFamilyOsVersions.jsonSafe
        ]
    }

    func validateRecruitmentDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String
    ) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              components.fragment == nil,
              components.user == nil,
              components.password == nil else {
            throw RecruitmentArgumentError("Apple returned an invalid required links.self in \(context)")
        }
        if components.scheme != nil || components.host != nil {
            guard components.scheme == "https", components.host?.isEmpty == false else {
                throw RecruitmentArgumentError("Apple returned a non-HTTPS required links.self in \(context)")
            }
        }
        guard components.percentEncodedPath == expectedPath else {
            throw RecruitmentArgumentError("Apple returned required links.self outside \(context)")
        }
        _ = try validatedASCAPIEndpoint(components.percentEncodedPath)
    }

    func validateRecruitmentPaging(
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        pageCount: Int,
        context: String
    ) throws {
        if let next = links.next,
           next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RecruitmentArgumentError("Apple returned an empty continuation URL in \(context)")
        }
        guard let meta else { return }
        guard let paging = meta.paging,
              let limit = paging.limit else {
            throw RecruitmentArgumentError("Apple returned incomplete paging metadata in \(context)")
        }
        if limit <= 0 || limit < pageCount {
            throw RecruitmentArgumentError("Apple returned an invalid paging limit in \(context)")
        }
        if let total = paging.total, total < pageCount {
            throw RecruitmentArgumentError("Apple returned paging total below the page count in \(context)")
        }
        if let cursor = paging.nextCursor,
           cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || links.next == nil {
            throw RecruitmentArgumentError("Apple returned inconsistent paging cursor state in \(context)")
        }
    }
}

private struct RecruitmentArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
