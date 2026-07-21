import Foundation
import MCP

// MARK: - Tool Handlers
extension AppEventsWorker {

    /// Lists in-app events for an app
    /// - Returns: JSON array of app events with attributes and pagination
    /// - Throws: ASCError on API failures
    func listAppEvents(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let path = "/v1/apps/\(try ASCPathSegment.encode(appId))/appEvents"
            var queryParams = [
                "limit": String(try boundedLimit(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25))
            ]
            if let states = try stringList(
                arguments["event_states"],
                field: "event_states",
                allowedValues: allowedEventStates
            ) {
                queryParams["filter[eventState]"] = states.joined(separator: ",")
            }
            if let eventIDs = try stringList(arguments["event_ids"], field: "event_ids") {
                queryParams["filter[id]"] = eventIDs.joined(separator: ",")
            }
            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: ["localizations"]
            ) {
                queryParams["include"] = includes.joined(separator: ",")
            }
            if arguments["localizations_limit"] != nil {
                queryParams["limit[localizations]"] = String(
                    try boundedLimit(
                        arguments["localizations_limit"],
                        field: "localizations_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }

            let response: ASCAppEventsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: queryParams),
                    as: ASCAppEventsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: queryParams,
                    as: ASCAppEventsResponse.self
                )
            }

            let events = response.data.map { formatAppEvent($0) }

            var result: [String: Any] = [
                "success": true,
                "app_events": events,
                "count": events.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            appendIncludedResources(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list app events: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific app event
    /// - Returns: JSON with event details and optionally included localizations
    /// - Throws: ASCError on API failures
    func getAppEvent(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eventIdValue = arguments["event_id"],
              let eventId = eventIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: ["localizations"]
            ) {
                queryParams["include"] = includes.joined(separator: ",")
            }
            if arguments["localizations_limit"] != nil {
                queryParams["limit[localizations]"] = String(
                    try boundedLimit(
                        arguments["localizations_limit"],
                        field: "localizations_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }

            let response: ASCAppEventResponse = try await httpClient.get(
                "/v1/appEvents/\(try ASCPathSegment.encode(eventId))",
                parameters: queryParams,
                as: ASCAppEventResponse.self
            )

            var result: [String: Any] = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ]

            if let included = response.included {
                var localizations: [[String: Any]] = []
                var unknown: [Any] = []
                for resource in included {
                    switch resource {
                    case .localization(let localization):
                        localizations.append(formatLocalization(localization))
                    case .unknown(let value):
                        unknown.append(value.asAny)
                    }
                }
                if !localizations.isEmpty {
                    result["localizations"] = localizations
                }
                if !unknown.isEmpty {
                    result["included_unknown"] = unknown
                }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to get app event: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new in-app event
    /// - Returns: JSON with created event details
    /// - Throws: ASCError on API failures
    func createAppEvent(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let refNameValue = arguments["reference_name"],
              let referenceName = refNameValue.stringValue,
              !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !referenceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: app_id, reference_name")],
                isError: true
            )
        }

        if let primaryLocale = arguments["primary_locale"]?.stringValue {
            let errors = ASCMetadataValidator.validateLocale(primaryLocale, field: "primary_locale")
            if !errors.isEmpty {
                return ASCMetadataValidator.errorResult(errors)
            }
        }

        do {
            let request = CreateAppEventRequest(
                data: CreateAppEventRequest.CreateAppEventData(
                    attributes: CreateAppEventRequest.CreateAppEventAttributes(
                        referenceName: referenceName,
                        badge: try nullableStringValue(
                            arguments["badge"],
                            field: "badge",
                            allowedValues: allowedEventBadges
                        ),
                        deepLink: try nullableAbsoluteURIValue(arguments["deep_link"], field: "deep_link"),
                        purchaseRequirement: try nullableStringValue(
                            arguments["purchase_requirement"],
                            field: "purchase_requirement"
                        ),
                        primaryLocale: try nullableStringValue(arguments["primary_locale"], field: "primary_locale"),
                        priority: try nullableStringValue(
                            arguments["priority"],
                            field: "priority",
                            allowedValues: ["HIGH", "NORMAL"]
                        ),
                        purpose: try nullableStringValue(
                            arguments["purpose"],
                            field: "purpose",
                            allowedValues: allowedEventPurposes
                        ),
                        territorySchedules: try territorySchedules(arguments["territory_schedules"])
                    ),
                    relationships: CreateAppEventRequest.CreateAppEventRelationships(
                        app: CreateAppEventRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCAppEventResponse = try await httpClient.post(
                "/v1/appEvents",
                body: request,
                as: ASCAppEventResponse.self
            )
            try validateAcceptedAppEventMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appEvents",
                method: "POST",
                statusCode: 201,
                context: "Apple app event create response"
            )

            let result = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create app event")
        }
    }

    /// Updates an existing in-app event
    /// - Returns: JSON with updated event details
    /// - Throws: ASCError on API failures
    func updateAppEvent(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eventIdValue = arguments["event_id"],
              let eventId = eventIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        if let primaryLocale = arguments["primary_locale"]?.stringValue {
            let errors = ASCMetadataValidator.validateLocale(primaryLocale, field: "primary_locale")
            if !errors.isEmpty {
                return ASCMetadataValidator.errorResult(errors)
            }
        }

        do {
            let attributes = UpdateAppEventRequest.UpdateAppEventAttributes(
                referenceName: try nullableStringValue(arguments["reference_name"], field: "reference_name"),
                badge: try nullableStringValue(
                    arguments["badge"],
                    field: "badge",
                    allowedValues: allowedEventBadges
                ),
                deepLink: try nullableAbsoluteURIValue(arguments["deep_link"], field: "deep_link"),
                purchaseRequirement: try nullableStringValue(
                    arguments["purchase_requirement"],
                    field: "purchase_requirement"
                ),
                primaryLocale: try nullableStringValue(arguments["primary_locale"], field: "primary_locale"),
                priority: try nullableStringValue(
                    arguments["priority"],
                    field: "priority",
                    allowedValues: ["HIGH", "NORMAL"]
                ),
                purpose: try nullableStringValue(
                    arguments["purpose"],
                    field: "purpose",
                    allowedValues: allowedEventPurposes
                ),
                territorySchedules: try territorySchedules(arguments["territory_schedules"])
            )
            guard attributes.hasChanges else {
                return MCPResult.error("At least one app event update field is required")
            }

            let request = UpdateAppEventRequest(
                data: UpdateAppEventRequest.UpdateAppEventData(
                    id: eventId,
                    attributes: attributes
                )
            )

            let response: ASCAppEventResponse = try await httpClient.patch(
                "/v1/appEvents/\(try ASCPathSegment.encode(eventId))",
                body: request,
                as: ASCAppEventResponse.self
            )
            try validateAcceptedAppEventMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appEvents",
                expectedID: eventId,
                method: "PATCH",
                statusCode: 200,
                context: "Apple app event update response"
            )

            let result = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update app event")
        }
    }

    /// Deletes an in-app event
    /// - Returns: JSON confirmation
    /// - Throws: ASCError on API failures
    func deleteAppEvent(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eventIdValue = arguments["event_id"],
              let eventId = eventIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appEvents/\(try ASCPathSegment.encode(eventId))")

            let result = [
                "success": true,
                "message": "App event '\(eventId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete app event")
        }
    }

    /// Lists localizations for an in-app event
    /// - Returns: JSON array of localizations with locale, name, descriptions
    /// - Throws: ASCError on API failures
    func listAppEventLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eventIdValue = arguments["event_id"],
              let eventId = eventIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            let path = "/v1/appEvents/\(try ASCPathSegment.encode(eventId))/localizations"
            var query = [
                "limit": String(try boundedLimit(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25))
            ]
            if let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: ["appEvent", "appEventScreenshots", "appEventVideoClips"]
            ) {
                query["include"] = includes.joined(separator: ",")
            }
            if arguments["screenshots_limit"] != nil {
                query["limit[appEventScreenshots]"] = String(
                    try boundedLimit(
                        arguments["screenshots_limit"],
                        field: "screenshots_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }
            if arguments["video_clips_limit"] != nil {
                query["limit[appEventVideoClips]"] = String(
                    try boundedLimit(
                        arguments["video_clips_limit"],
                        field: "video_clips_limit",
                        maximum: 50,
                        defaultValue: 50
                    )
                )
            }

            let response: ASCAppEventLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCAppEventLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCAppEventLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let included = response.included, !included.isEmpty {
                result["included"] = included.map(\.asAny)
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Failed to list app event localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Localization CRUD

    /// Creates a localization for an in-app event
    /// - Returns: JSON with created localization details
    /// - Throws: ASCError on API failures
    func createAppEventLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let eventId = arguments["event_id"]?.stringValue,
              let locale = arguments["locale"]?.stringValue,
              !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameters: event_id, locale")],
                isError: true
            )
        }

        let validationErrors = validateLocalizationArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            let name = try nullableStringValue(arguments["name"], field: "name")
            let shortDescription = try nullableStringValue(
                arguments["short_description"],
                field: "short_description"
            )
            let longDescription = try nullableStringValue(
                arguments["long_description"],
                field: "long_description"
            )
            let request = CreateAppEventLocalizationRequest(
                data: CreateAppEventLocalizationRequest.CreateData(
                    attributes: CreateAppEventLocalizationRequest.Attributes(
                        locale: locale,
                        name: name,
                        shortDescription: shortDescription,
                        longDescription: longDescription
                    ),
                    relationships: CreateAppEventLocalizationRequest.Relationships(
                        appEvent: CreateAppEventLocalizationRequest.AppEventRelationship(
                            data: ASCResourceIdentifier(type: "appEvents", id: eventId)
                        )
                    )
                )
            )

            let response: ASCAppEventLocalizationSingleResponse = try await httpClient.post(
                "/v1/appEventLocalizations",
                body: request,
                as: ASCAppEventLocalizationSingleResponse.self
            )
            try validateAcceptedAppEventMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appEventLocalizations",
                method: "POST",
                statusCode: 201,
                context: "Apple app event localization create response"
            )

            let result: [String: Any] = [
                "success": true,
                "localization": formatLocalization(response.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create app event localization")
        }
    }

    /// Updates an existing app event localization
    /// - Returns: JSON with updated localization details
    /// - Throws: ASCError on API failures
    func updateAppEventLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        let validationErrors = validateLocalizationArguments(arguments)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            let attributes = UpdateAppEventLocalizationRequest.Attributes(
                name: try nullableStringValue(arguments["name"], field: "name"),
                shortDescription: try nullableStringValue(
                    arguments["short_description"],
                    field: "short_description"
                ),
                longDescription: try nullableStringValue(
                    arguments["long_description"],
                    field: "long_description"
                )
            )
            guard attributes.hasChanges else {
                return MCPResult.error("At least one localization update field is required")
            }

            let request = UpdateAppEventLocalizationRequest(
                data: UpdateAppEventLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: attributes
                )
            )

            let response: ASCAppEventLocalizationSingleResponse = try await httpClient.patch(
                "/v1/appEventLocalizations/\(try ASCPathSegment.encode(localizationId))",
                body: request,
                as: ASCAppEventLocalizationSingleResponse.self
            )
            try validateAcceptedAppEventMutationResource(
                type: response.data.type,
                id: response.data.id,
                expectedType: "appEventLocalizations",
                expectedID: localizationId,
                method: "PATCH",
                statusCode: 200,
                context: "Apple app event localization update response"
            )

            let result: [String: Any] = [
                "success": true,
                "localization": formatLocalization(response.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update app event localization")
        }
    }

    /// Deletes an app event localization
    /// - Returns: JSON confirmation of deletion
    /// - Throws: ASCError on API failures
    func deleteAppEventLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appEventLocalizations/\(try ASCPathSegment.encode(localizationId))")

            let result: [String: Any] = [
                "success": true,
                "message": "App event localization '\(localizationId)' deleted"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete app event localization")
        }
    }

    // MARK: - Formatting

    private func formatAppEvent(_ event: ASCAppEvent) -> [String: Any] {
        var result: [String: Any] = [
            "id": event.id,
            "type": event.type
        ]

        if let attrs = event.attributes {
            result["referenceName"] = attrs.referenceName.jsonSafe
            result["badge"] = attrs.badge.jsonSafe
            result["deepLink"] = attrs.deepLink.jsonSafe
            result["purchaseRequirement"] = attrs.purchaseRequirement.jsonSafe
            result["primaryLocale"] = attrs.primaryLocale.jsonSafe
            result["priority"] = attrs.priority.jsonSafe
            result["purpose"] = attrs.purpose.jsonSafe
            result["eventState"] = attrs.eventState.jsonSafe

            if let schedules = attrs.territorySchedules {
                result["territorySchedules"] = schedules.map { formatSchedule($0) }
            }
            if let archivedSchedules = attrs.archivedTerritorySchedules {
                result["archivedTerritorySchedules"] = archivedSchedules.map { formatSchedule($0) }
            }
        }
        if let localizationIDs = event.relationships?.localizations?.data {
            result["localizationIds"] = localizationIDs.map(\.id)
        }

        return result
    }

    private func formatSchedule(_ schedule: TerritorySchedule) -> [String: Any] {
        return [
            "territories": schedule.territories.jsonSafe,
            "publishStart": schedule.publishStart.jsonSafe,
            "eventStart": schedule.eventStart.jsonSafe,
            "eventEnd": schedule.eventEnd.jsonSafe
        ]
    }

    private func formatLocalization(_ loc: ASCAppEventLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": loc.id,
            "type": loc.type,
            "locale": (loc.attributes?.locale).jsonSafe,
            "name": (loc.attributes?.name).jsonSafe,
            "shortDescription": (loc.attributes?.shortDescription).jsonSafe,
            "longDescription": (loc.attributes?.longDescription).jsonSafe
        ]
        if let appEventID = loc.relationships?.appEvent?.data?.id {
            result["appEventId"] = appEventID
        }
        if let screenshotIDs = loc.relationships?.appEventScreenshots?.data {
            result["screenshotIds"] = screenshotIDs.map(\.id)
        }
        if let videoClipIDs = loc.relationships?.appEventVideoClips?.data {
            result["videoClipIds"] = videoClipIDs.map(\.id)
        }
        return result
    }

    private var allowedEventStates: Set<String> {
        [
            "DRAFT",
            "READY_FOR_REVIEW",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
            "REJECTED",
            "ACCEPTED",
            "APPROVED",
            "PUBLISHED",
            "PAST",
            "ARCHIVED"
        ]
    }

    private var allowedEventBadges: Set<String> {
        ["LIVE_EVENT", "PREMIERE", "CHALLENGE", "COMPETITION", "NEW_SEASON", "MAJOR_UPDATE", "SPECIAL_EVENT"]
    }

    private var allowedEventPurposes: Set<String> {
        ["APPROPRIATE_FOR_ALL_USERS", "ATTRACT_NEW_USERS", "KEEP_ACTIVE_USERS_INFORMED", "BRING_BACK_LAPSED_USERS"]
    }

    private func boundedLimit(
        _ value: Value?,
        field: String,
        maximum: Int,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let limit = value.intValue, (1...maximum).contains(limit) else {
            throw AppEventArgumentError("'\(field)' must be an integer between 1 and \(maximum)")
        }
        return limit
    }

    private func validateAcceptedAppEventMutationResource(
        type: String,
        id: String,
        expectedType: String,
        expectedID: String? = nil,
        method: String,
        statusCode: Int,
        context: String
    ) throws {
        do {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: type,
                id: id,
                expectedType: expectedType,
                expectedID: expectedID,
                context: context
            )
        } catch {
            let cause = error as? ASCError ?? .parsing(Redactor.redact(error.localizedDescription))
            throw ASCError.mutationCommittedUnverified(
                method: method,
                expectedStatusCode: statusCode,
                actualStatusCode: statusCode,
                cause: cause
            )
        }
    }

    private func stringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else if let array = value.arrayValue {
            let parsed = array.compactMap(\.stringValue)
            guard parsed.count == array.count else {
                throw AppEventArgumentError("'\(field)' must contain only strings")
            }
            values = parsed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw AppEventArgumentError("'\(field)' must be a string or array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw AppEventArgumentError("'\(field)' must contain at least one non-empty value")
        }
        guard Set(values).count == values.count else {
            throw AppEventArgumentError("'\(field)' must not contain duplicate values")
        }
        if let allowedValues,
           let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw AppEventArgumentError(
                "Unsupported \(field) value '\(invalid)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return values
    }

    private func nullableStringValue(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> AppEventNullable<String>? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppEventArgumentError("'\(field)' must be a string or null")
        }
        if let allowedValues, !allowedValues.contains(string) {
            throw AppEventArgumentError(
                "'\(field)' must be null or one of: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return .value(string)
    }

    private func nullableAbsoluteURIValue(
        _ value: Value?,
        field: String
    ) throws -> AppEventNullable<String>? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppEventArgumentError("'\(field)' must be an absolute URI or null")
        }
        let schemePattern = "^[A-Za-z][A-Za-z0-9+.-]*$"
        guard !string.isEmpty,
              string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: string),
              let scheme = components.scheme,
              scheme.range(of: schemePattern, options: .regularExpression) != nil,
              URL(string: string)?.scheme == scheme else {
            throw AppEventArgumentError("'\(field)' must be an absolute URI or null")
        }
        return .value(string)
    }

    private func territorySchedules(
        _ value: Value?
    ) throws -> AppEventNullable<[TerritorySchedule]>? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        if let encoded = value.stringValue {
            guard let data = encoded.data(using: .utf8),
                  let rawSchedules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw AppEventArgumentError("'territory_schedules' must be a JSON array of schedule objects")
            }
            return .value(try rawSchedules.enumerated().map { index, schedule in
                try territorySchedule(from: schedule, index: index)
            })
        }
        guard let rawSchedules = value.arrayValue else {
            throw AppEventArgumentError("'territory_schedules' must be an array, JSON array string, or null")
        }
        return .value(try rawSchedules.enumerated().map { index, schedule in
            guard let object = schedule.objectValue else {
                throw AppEventArgumentError("territory_schedules[\(index)] must be an object")
            }
            return try territorySchedule(from: object, index: index)
        })
    }

    private func territorySchedule(from object: [String: Value], index: Int) throws -> TerritorySchedule {
        let allowedKeys: Set<String> = ["territories", "publishStart", "eventStart", "eventEnd"]
        if let unknown = object.keys.first(where: { !allowedKeys.contains($0) }) {
            throw AppEventArgumentError("territory_schedules[\(index)] contains unsupported field '\(unknown)'")
        }

        let territories: [String]?
        if let value = object["territories"] {
            guard let array = value.arrayValue else {
                throw AppEventArgumentError("territory_schedules[\(index)].territories must be an array of strings")
            }
            let parsed = array.compactMap(\.stringValue)
            guard parsed.count == array.count,
                  parsed.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw AppEventArgumentError("territory_schedules[\(index)].territories must contain only non-empty strings")
            }
            territories = parsed
        } else {
            territories = nil
        }

        return TerritorySchedule(
            territories: territories,
            publishStart: try optionalScheduleString(object["publishStart"], field: "publishStart", index: index),
            eventStart: try optionalScheduleString(object["eventStart"], field: "eventStart", index: index),
            eventEnd: try optionalScheduleString(object["eventEnd"], field: "eventEnd", index: index)
        )
    }

    private func territorySchedule(from object: [String: Any], index: Int) throws -> TerritorySchedule {
        let allowedKeys: Set<String> = ["territories", "publishStart", "eventStart", "eventEnd"]
        if let unknown = object.keys.first(where: { !allowedKeys.contains($0) }) {
            throw AppEventArgumentError("territory_schedules[\(index)] contains unsupported field '\(unknown)'")
        }

        let territories: [String]?
        if let value = object["territories"] {
            guard let array = value as? [Any],
                  array.allSatisfy({
                      guard let string = $0 as? String else { return false }
                      return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else {
                throw AppEventArgumentError("territory_schedules[\(index)].territories must be an array of non-empty strings")
            }
            territories = array.compactMap { $0 as? String }
        } else {
            territories = nil
        }

        return TerritorySchedule(
            territories: territories,
            publishStart: try optionalScheduleString(object["publishStart"], field: "publishStart", index: index),
            eventStart: try optionalScheduleString(object["eventStart"], field: "eventStart", index: index),
            eventEnd: try optionalScheduleString(object["eventEnd"], field: "eventEnd", index: index)
        )
    }

    private func optionalScheduleString(_ value: Value?, field: String, index: Int) throws -> String? {
        guard let value else { return nil }
        guard let string = value.stringValue else {
            throw AppEventArgumentError("territory_schedules[\(index)].\(field) must be a string")
        }
        guard isISO8601DateTime(string) else {
            throw AppEventArgumentError("territory_schedules[\(index)].\(field) must use ISO 8601 date-time format")
        }
        return string
    }

    private func optionalScheduleString(_ value: Any?, field: String, index: Int) throws -> String? {
        guard let value else { return nil }
        guard let string = value as? String else {
            throw AppEventArgumentError("territory_schedules[\(index)].\(field) must be a string")
        }
        guard isISO8601DateTime(string) else {
            throw AppEventArgumentError("territory_schedules[\(index)].\(field) must use ISO 8601 date-time format")
        }
        return string
    }

    private func isISO8601DateTime(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if formatter.date(from: value) != nil {
            return true
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }

    private func validateLocalizationArguments(
        _ arguments: [String: Value],
        locale: String? = nil
    ) -> [ASCMetadataValidator.FieldError] {
        var errors: [ASCMetadataValidator.FieldError] = []
        if let locale {
            errors += ASCMetadataValidator.validateLocale(locale)
        }
        var fields: [String: String] = [:]
        for key in ["name", "short_description", "long_description"] {
            if let value = arguments[key]?.stringValue {
                fields[key] = value
            }
        }
        errors += ASCMetadataValidator.validateTextFields(
            fields,
            limits: [
                "name": 30,
                "short_description": 120,
                "long_description": 500
            ]
        )
        return errors
    }

    private func appendIncludedResources(
        _ included: [ASCAppEventIncludedResource]?,
        to result: inout [String: Any]
    ) {
        guard let included else { return }
        var localizations: [[String: Any]] = []
        var unknown: [Any] = []
        for resource in included {
            switch resource {
            case .localization(let localization):
                localizations.append(formatLocalization(localization))
            case .unknown(let value):
                unknown.append(value.asAny)
            }
        }
        if !localizations.isEmpty { result["included_localizations"] = localizations }
        if !unknown.isEmpty { result["included_unknown"] = unknown }
    }
}

private struct AppEventArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
