import Foundation
import MCP

extension SubscriptionsWorker {
    func createSubscriptionPlanAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let prepared: (
            subscriptionID: String,
            body: Data,
            identifiers: [String: Value]
        )
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: ["subscription_id", "plan_type", "territory_ids", "available_in_new_territories"]
            )
            let subscriptionID = try subscriptionPlanIdentifier(arguments, key: "subscription_id")
            let planType = try subscriptionPlanType(arguments["plan_type"])
            let territoryIDs = try subscriptionPlanTerritoryIDs(arguments["territory_ids"], required: true) ?? []
            let availableInNewTerritories = try subscriptionPlanNullableBool(
                arguments["available_in_new_territories"]
            )
            let request = ASCSubscriptionPlanAvailabilityCreateRequest(
                subscriptionID: subscriptionID,
                planType: planType,
                territoryIDs: territoryIDs,
                availableInNewTerritories: availableInNewTerritories
            )
            var identifiers: [String: Value] = [
                "subscription_id": .string(subscriptionID),
                "plan_type": .string(planType.rawValue),
                "territory_ids": .array(territoryIDs.map(Value.string))
            ]
            if let value = arguments["available_in_new_territories"] {
                identifiers["available_in_new_territories"] = value
            }
            prepared = (subscriptionID, try JSONEncoder().encode(request), identifiers)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create subscription plan availability")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt(
                "/v1/subscriptionPlanAvailabilities",
                body: prepared.body
            )
        } catch {
            return MCPResult.error(
                "Failed to create subscription plan availability: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .request,
                    operation: "subscriptions_create_plan_availability",
                    identifiers: prepared.identifiers,
                    listTool: "subscriptions_list_plan_availabilities",
                    listArguments: [
                        "subscription_id": .string(prepared.subscriptionID),
                        "limit": .int(200)
                    ],
                    getTool: "subscriptions_get_plan_availability",
                    getIDArgument: "plan_availability_id",
                    listResultIDPath: "plan_availabilities[].id",
                    matchingFields: ["plan_type"]
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Subscription plan availability create"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionPlanAvailabilityResponse.self,
                from: receipt.data
            )
            try validateSubscriptionPlanAvailabilityResponse(
                response,
                expectedPath: "/v1/subscriptionPlanAvailabilities/\(try ASCPathSegment.encode(response.data.id))",
                context: "Apple subscription plan availability create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "plan_availability": formatSubscriptionPlanAvailability(
                    response.data,
                    included: response.included
                )
            ])
        } catch {
            return MCPResult.error(
                "Failed to create subscription plan availability: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .acceptedResponse,
                    operation: "subscriptions_create_plan_availability",
                    identifiers: prepared.identifiers,
                    listTool: "subscriptions_list_plan_availabilities",
                    listArguments: [
                        "subscription_id": .string(prepared.subscriptionID),
                        "limit": .int(200)
                    ],
                    getTool: "subscriptions_get_plan_availability",
                    getIDArgument: "plan_availability_id",
                    listResultIDPath: "plan_availabilities[].id",
                    matchingFields: ["plan_type"]
                )
            )
        }
    }

    func getSubscriptionPlanAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: ["plan_availability_id"]
            )
            let availabilityID = try subscriptionPlanIdentifier(arguments, key: "plan_availability_id")
            let endpoint = "/v1/subscriptionPlanAvailabilities/\(try ASCPathSegment.encode(availabilityID))"
            let response = try await httpClient.get(
                endpoint,
                parameters: subscriptionPlanAvailabilityQuery(),
                as: ASCSubscriptionPlanAvailabilityResponse.self
            )
            try validateSubscriptionPlanAvailabilityResponse(
                response,
                expectedID: availabilityID,
                expectedPath: endpoint,
                context: "Apple subscription plan availability get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "plan_availability": formatSubscriptionPlanAvailability(
                    response.data,
                    included: response.included
                )
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription plan availability")
        }
    }

    func updateSubscriptionPlanAvailability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: ["plan_availability_id", "available_in_new_territories", "territory_ids"]
            )
            let availabilityID = try subscriptionPlanIdentifier(arguments, key: "plan_availability_id")
            let availableInNewTerritories = try subscriptionPlanNullableBool(
                arguments["available_in_new_territories"]
            )
            let territoryIDs = try subscriptionPlanTerritoryIDs(arguments["territory_ids"], required: false)
            guard availableInNewTerritories != nil || territoryIDs != nil else {
                throw ASCError.parsing(
                    "Provide at least one of: available_in_new_territories, territory_ids"
                )
            }
            var requestedArguments: [String: Value] = [
                "plan_availability_id": .string(availabilityID)
            ]
            if let value = arguments["available_in_new_territories"] {
                requestedArguments["available_in_new_territories"] = value
            }
            if let value = arguments["territory_ids"] {
                requestedArguments["territory_ids"] = value
            }
            let request = ASCSubscriptionPlanAvailabilityUpdateRequest(
                id: availabilityID,
                availableInNewTerritories: availableInNewTerritories,
                territoryIDs: territoryIDs
            )
            let body = try JSONEncoder().encode(request)
            let endpoint = "/v1/subscriptionPlanAvailabilities/\(try ASCPathSegment.encode(availabilityID))"
            let receipt: ASCMutationReceipt
            do {
                receipt = try await httpClient.patchReceipt(
                    endpoint,
                    body: body
                )
            } catch {
                return subscriptionMutationRequestFailure(
                    operation: "subscriptions_update_plan_availability",
                    action: "subscription plan availability update",
                    targetField: "plan_availability_id",
                    targetID: availabilityID,
                    requestedArguments: requestedArguments,
                    error: error,
                    inspectionTool: "subscriptions_get_plan_availability"
                )
            }

            do {
                try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                    receipt.statusCode,
                    expectedStatusCode: 200,
                    context: "Subscription plan availability update"
                )
                let response = try JSONDecoder().decode(
                    ASCSubscriptionPlanAvailabilityResponse.self,
                    from: receipt.data
                )
                try validateSubscriptionPlanAvailabilityResponse(
                    response,
                    expectedID: availabilityID,
                    expectedPath: endpoint,
                    context: "Apple subscription plan availability update response"
                )
                return MCPResult.jsonObject([
                    "success": true,
                    "plan_availability": formatSubscriptionPlanAvailability(
                        response.data,
                        included: response.included
                    )
                ])
            } catch {
                return subscriptionCommittedUnverifiedMutationFailure(
                    operation: "subscriptions_update_plan_availability",
                    targetField: "plan_availability_id",
                    targetID: availabilityID,
                    requestedArguments: requestedArguments,
                    error: error,
                    inspectionTool: "subscriptions_get_plan_availability"
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to update subscription plan availability")
        }
    }

    func listSubscriptionPlanAvailabilities(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: ["subscription_id", "limit", "next_url"]
            )
            let subscriptionID = try subscriptionPlanIdentifier(arguments, key: "subscription_id")
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionID))/planAvailabilities"
            var query = subscriptionPlanAvailabilityQuery()
            query["limit"] = String(try subscriptionPlanLimit(arguments["limit"], maximum: 200))
            let response: ASCSubscriptionPlanAvailabilitiesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionPlanAvailabilitiesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionPlanAvailabilitiesResponse.self
                )
            }
            try validateSubscriptionPlanAvailabilityCollectionResponse(
                response,
                expectedPath: endpoint,
                context: "Apple subscription plan availability list response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "plan_availabilities": response.data.map {
                    formatSubscriptionPlanAvailability($0, included: response.included)
                },
                "count": response.data.count,
                "total": subscriptionPlanJSONSafe(response.meta?.paging?.total),
                "next_url": subscriptionPlanJSONSafe(response.links.next)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription plan availabilities")
        }
    }

    func listSubscriptionPlanAvailabilityTerritories(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: ["plan_availability_id", "limit", "next_url"]
            )
            let availabilityID = try subscriptionPlanIdentifier(arguments, key: "plan_availability_id")
            let endpoint = "/v1/subscriptionPlanAvailabilities/\(try ASCPathSegment.encode(availabilityID))/availableTerritories"
            let query = [
                "fields[territories]": "currency",
                "limit": String(try subscriptionPlanLimit(arguments["limit"], maximum: 200))
            ]
            let response: ASCSubscriptionPlanTerritoriesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionPlanTerritoriesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionPlanTerritoriesResponse.self
                )
            }
            try validateSubscriptionPlanTerritoriesResponse(
                response,
                expectedPath: endpoint,
                context: "Apple subscription plan availability territories response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "territories": response.data.map(formatSubscriptionPlanTerritory),
                "count": response.data.count,
                "total": subscriptionPlanJSONSafe(response.meta?.paging?.total),
                "next_url": subscriptionPlanJSONSafe(response.links.next)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription plan availability territories")
        }
    }

    func listSubscriptionPricePointAdjustedEqualizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try subscriptionPlanArguments(
                params.arguments,
                allowed: [
                    "price_point_id",
                    "territory_ids",
                    "subscription_ids",
                    "upfront_price_point_ids",
                    "plan_types",
                    "limit",
                    "next_url"
                ]
            )
            let pricePointID = try subscriptionPlanIdentifier(arguments, key: "price_point_id")
            let endpoint = "/v1/subscriptionPricePoints/\(try ASCPathSegment.encode(pricePointID))/adjustedEqualizations"
            var query = subscriptionAdjustedEqualizationsQuery(
                limit: try subscriptionPlanLimit(arguments["limit"], maximum: 8000)
            )
            if let value = try subscriptionCatalogQueryValue(
                arguments["territory_ids"],
                field: "territory_ids"
            ) {
                try validateSubscriptionPlanQueryIdentifiers(value, field: "territory_ids")
                query["filter[territory]"] = value
            }
            if let value = try subscriptionCatalogQueryValue(
                arguments["subscription_ids"],
                field: "subscription_ids"
            ) {
                try validateSubscriptionPlanQueryIdentifiers(value, field: "subscription_ids")
                query["filter[subscription]"] = value
            }
            if let value = try subscriptionCatalogQueryValue(
                arguments["upfront_price_point_ids"],
                field: "upfront_price_point_ids"
            ) {
                try validateSubscriptionPlanQueryIdentifiers(value, field: "upfront_price_point_ids")
                query["filter[upfrontPricePointId]"] = value
            }
            if let value = try subscriptionCatalogQueryValue(
                arguments["plan_types"],
                field: "plan_types",
                allowedValues: Set(ASCSubscriptionPlanType.allCases.map(\.rawValue))
            ) {
                query["filter[planType]"] = value
            }

            let response: ASCSubscriptionAdjustedPricePointsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionAdjustedPricePointsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionAdjustedPricePointsResponse.self
                )
            }
            try validateSubscriptionAdjustedPricePointsResponse(
                response,
                expectedPath: endpoint,
                context: "Apple subscription price point adjusted equalizations response"
            )
            let territories = subscriptionPlanTerritoryIndex(response.included)
            return MCPResult.jsonObject([
                "success": true,
                "price_points": response.data.map {
                    formatSubscriptionAdjustedPricePoint($0, territories: territories)
                },
                "count": response.data.count,
                "total": subscriptionPlanJSONSafe(response.meta?.paging?.total),
                "next_url": subscriptionPlanJSONSafe(response.links.next)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription price point adjusted equalizations")
        }
    }

    private func subscriptionPlanArguments(
        _ arguments: [String: Value]?,
        allowed: Set<String>
    ) throws -> [String: Value] {
        let arguments = arguments ?? [:]
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw ASCError.parsing("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
        return arguments
    }

    private func subscriptionPlanIdentifier(
        _ arguments: [String: Value],
        key: String
    ) throws -> String {
        guard let value = arguments[key]?.stringValue,
              !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ASCError.parsing("\(key) must be a non-empty string without surrounding whitespace")
        }
        guard try ASCPathSegment.encode(value, field: key) == value else {
            throw ASCError.parsing("\(key) must be a canonical App Store Connect resource ID")
        }
        return value
    }

    private func subscriptionPlanType(_ value: Value?) throws -> ASCSubscriptionPlanType {
        guard let rawValue = value?.stringValue,
              let planType = ASCSubscriptionPlanType(rawValue: rawValue) else {
            throw ASCError.parsing("plan_type must be one of: MONTHLY, UPFRONT")
        }
        return planType
    }

    private func subscriptionPlanNullableBool(
        _ value: Value?
    ) throws -> NullableAttributeValue? {
        guard let value else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let bool = value.boolValue else {
            throw ASCError.parsing("available_in_new_territories must be a boolean or null")
        }
        return .bool(bool)
    }

    private func subscriptionPlanTerritoryIDs(
        _ value: Value?,
        required: Bool
    ) throws -> [String]? {
        guard let value else {
            if required {
                throw ASCError.parsing("territory_ids must be an array of unique territory IDs")
            }
            return nil
        }
        guard let values = value.arrayValue else {
            throw ASCError.parsing("territory_ids must be an array of unique territory IDs")
        }
        let ids = values.compactMap(\.stringValue)
        guard ids.count == values.count,
              ids.allSatisfy({
                  !$0.isEmpty &&
                  $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) &&
                  !$0.contains(",")
              }),
              Set(ids).count == ids.count else {
            throw ASCError.parsing(
                "territory_ids must contain unique non-empty strings without commas or surrounding whitespace"
            )
        }
        for id in ids {
            guard try ASCPathSegment.encode(id, field: "territory_ids") == id else {
                throw ASCError.parsing(
                    "territory_ids must contain canonical App Store Connect resource IDs"
                )
            }
        }
        return ids
    }

    private func validateSubscriptionPlanQueryIdentifiers(
        _ value: String,
        field: String
    ) throws {
        for identifier in value.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            guard try ASCPathSegment.encode(identifier, field: field) == identifier else {
                throw ASCError.parsing("\(field) must contain canonical App Store Connect resource IDs")
            }
        }
    }

    private func subscriptionPlanLimit(_ value: Value?, maximum: Int) throws -> Int {
        guard let value else {
            return 25
        }
        guard let limit = value.intValue, (1...maximum).contains(limit) else {
            throw ASCError.parsing("limit must be an integer from 1 through \(maximum)")
        }
        return limit
    }

    private func subscriptionPlanAvailabilityQuery() -> [String: String] {
        [
            "include": "availableTerritories",
            "fields[subscriptionPlanAvailabilities]": "availableInNewTerritories,planType,availableTerritories",
            "fields[territories]": "currency",
            "limit[availableTerritories]": "50"
        ]
    }

    private func subscriptionAdjustedEqualizationsQuery(limit: Int) -> [String: String] {
        [
            "include": "territory",
            "fields[subscriptionPricePoints]": "customerPrice,proceeds,proceedsYear2,territory,adjustedEqualizations",
            "fields[territories]": "currency",
            "limit": String(limit)
        ]
    }

    private func validateSubscriptionPlanAvailabilityResponse(
        _ response: ASCSubscriptionPlanAvailabilityResponse,
        expectedID: String? = nil,
        expectedPath: String,
        context: String
    ) throws {
        try validateSubscriptionDocumentSelfLink(
            response.links.`self`,
            expectedPath: expectedPath,
            context: context
        )
        try validateSubscriptionPlanAvailability(
            response.data,
            expectedID: expectedID,
            context: context
        )
        try validateSubscriptionPlanTerritories(
            response.included ?? [],
            context: "\(context) included territories"
        )
    }

    private func validateSubscriptionPlanAvailabilityCollectionResponse(
        _ response: ASCSubscriptionPlanAvailabilitiesResponse,
        expectedPath: String,
        context: String
    ) throws {
        try validateSubscriptionDocumentSelfLink(
            response.links.`self`,
            expectedPath: expectedPath,
            context: context
        )
        try validateSubscriptionResourceCollection(
            response.data.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionPlanAvailabilities",
            context: context
        )
        for availability in response.data {
            try validateSubscriptionPlanAvailabilityRelationships(
                availability,
                context: "\(context) resource '\(availability.id)'"
            )
        }
        try validateSubscriptionPagingInformation(
            response.meta,
            resourceCount: response.data.count,
            nextLink: response.links.next,
            validatesContinuation: true,
            context: context
        )
        try validateSubscriptionPlanTerritories(
            response.included ?? [],
            context: "\(context) included territories"
        )
    }

    private func validateSubscriptionPlanAvailability(
        _ availability: ASCSubscriptionPlanAvailability,
        expectedID: String?,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: availability.type,
            id: availability.id,
            expectedType: "subscriptionPlanAvailabilities",
            expectedID: expectedID,
            context: context
        )
        try validateSubscriptionPlanAvailabilityRelationships(
            availability,
            context: context
        )
    }

    private func validateSubscriptionPlanAvailabilityRelationships(
        _ availability: ASCSubscriptionPlanAvailability,
        context: String
    ) throws {
        try validateSubscriptionPagedRelationship(
            availability.relationships?.availableTerritories,
            expectedType: "territories",
            context: "\(context) available territories relationship"
        )
    }

    private func validateSubscriptionPlanTerritoriesResponse(
        _ response: ASCSubscriptionPlanTerritoriesResponse,
        expectedPath: String,
        context: String
    ) throws {
        try validateSubscriptionDocumentSelfLink(
            response.links.`self`,
            expectedPath: expectedPath,
            context: context
        )
        try validateSubscriptionPlanTerritories(response.data, context: context)
        try validateSubscriptionPagingInformation(
            response.meta,
            resourceCount: response.data.count,
            nextLink: response.links.next,
            validatesContinuation: true,
            context: context
        )
    }

    private func validateSubscriptionPlanTerritories(
        _ territories: [ASCTerritory],
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            territories.map { (type: $0.type, id: $0.id) },
            expectedType: "territories",
            context: context
        )
    }

    private func validateSubscriptionAdjustedPricePointsResponse(
        _ response: ASCSubscriptionAdjustedPricePointsResponse,
        expectedPath: String,
        context: String
    ) throws {
        try validateSubscriptionDocumentSelfLink(
            response.links.`self`,
            expectedPath: expectedPath,
            context: context
        )
        try validateSubscriptionResourceCollection(
            response.data.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionPricePoints",
            context: context
        )
        for pricePoint in response.data {
            if let territory = pricePoint.relationships?.territory?.data {
                try validateSubscriptionRelationshipIdentity(
                    territory,
                    expectedType: "territories",
                    context: "\(context) territory relationship"
                )
            }
        }
        try validateSubscriptionPagingInformation(
            response.meta,
            resourceCount: response.data.count,
            nextLink: response.links.next,
            validatesContinuation: true,
            context: context
        )
        try validateSubscriptionPlanTerritories(
            response.included ?? [],
            context: "\(context) included territories"
        )
    }

    private func formatSubscriptionPlanAvailability(
        _ availability: ASCSubscriptionPlanAvailability,
        included: [ASCTerritory]?
    ) -> [String: Any] {
        let territories = subscriptionPlanTerritoryIndex(included)
        let relationship = availability.relationships?.availableTerritories
        let identifiers = relationship?.data
        let includedCount = identifiers?.filter { territories[$0.id] != nil }.count
        let total = relationship?.meta?.paging?.total
        let nextCursor = relationship?.meta?.paging?.nextCursor
        let relationshipCount = identifiers?.count
        let truncated = relationshipCount.flatMap { count in
            nextCursor != nil ? true : total.map { $0 > count }
        }
        return [
            "id": availability.id,
            "type": availability.type,
            "plan_type": subscriptionPlanJSONSafe(availability.attributes?.planType?.rawValue),
            "available_in_new_territories": subscriptionPlanJSONSafe(
                availability.attributes?.availableInNewTerritories
            ),
            "available_territory_ids": subscriptionPlanJSONSafe(identifiers?.map(\.id)),
            "available_territories": subscriptionPlanJSONSafe(identifiers?.map { identifier in
                let territory = territories[identifier.id]
                return [
                    "id": identifier.id,
                    "type": identifier.type,
                    "currency": subscriptionPlanJSONSafe(territory?.attributes?.currency)
                ] as [String: Any]
            }),
            "available_territories_total": subscriptionPlanJSONSafe(total),
            "available_territories_limit": subscriptionPlanJSONSafe(
                relationship?.meta?.paging?.limit
            ),
            "available_territories_count": subscriptionPlanJSONSafe(relationshipCount),
            "available_territories_next_cursor": subscriptionPlanJSONSafe(nextCursor),
            "available_territories_included_count": subscriptionPlanJSONSafe(includedCount),
            "available_territories_truncated": subscriptionPlanJSONSafe(truncated),
            "available_territories_completeness_known": subscriptionPlanJSONSafe(
                relationshipCount.map { _ in total != nil || nextCursor != nil }
            )
        ]
    }

    private func formatSubscriptionPlanTerritory(_ territory: ASCTerritory) -> [String: Any] {
        [
            "id": territory.id,
            "type": territory.type,
            "currency": subscriptionPlanJSONSafe(territory.attributes?.currency)
        ]
    }

    private func formatSubscriptionAdjustedPricePoint(
        _ pricePoint: ASCSubscriptionAdjustedPricePoint,
        territories: [String: ASCTerritory]
    ) -> [String: Any] {
        let territoryID = pricePoint.relationships?.territory?.data?.id
        return [
            "id": pricePoint.id,
            "type": pricePoint.type,
            "territory_id": subscriptionPlanJSONSafe(territoryID),
            "currency": subscriptionPlanJSONSafe(
                territoryID.flatMap { territories[$0]?.attributes?.currency }
            ),
            "customer_price": subscriptionPlanJSONSafe(pricePoint.attributes?.customerPrice),
            "proceeds": subscriptionPlanJSONSafe(pricePoint.attributes?.proceeds),
            "proceeds_year2": subscriptionPlanJSONSafe(pricePoint.attributes?.proceedsYear2)
        ]
    }

    private func subscriptionPlanTerritoryIndex(
        _ territories: [ASCTerritory]?
    ) -> [String: ASCTerritory] {
        var result: [String: ASCTerritory] = [:]
        for territory in territories ?? [] {
            result[territory.id] = territory
        }
        return result
    }
}

private func subscriptionPlanJSONSafe<T>(_ value: T?) -> Any {
    switch value {
    case .some(let value): value
    case .none: NSNull()
    }
}
