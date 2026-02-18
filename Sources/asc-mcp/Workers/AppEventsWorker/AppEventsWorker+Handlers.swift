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
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppEventsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppEventsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/appEvents",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list app events: \(error.localizedDescription)")],
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
                content: [.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            var queryParams: [String: String] = [:]

            if let include = arguments["include"]?.stringValue {
                queryParams["include"] = include
            }

            let response: ASCAppEventResponse = try await httpClient.get(
                "/v1/appEvents/\(eventId)",
                parameters: queryParams,
                as: ASCAppEventResponse.self
            )

            var result: [String: Any] = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ]

            // Include localizations if present
            if let included = response.included {
                let localizations = included.compactMap { resource -> [String: Any]? in
                    if case .localization(let loc) = resource {
                        return formatLocalization(loc)
                    }
                    return nil
                }
                if !localizations.isEmpty {
                    result["localizations"] = localizations
                }
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get app event: \(error.localizedDescription)")],
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
              let referenceName = refNameValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: app_id, reference_name")],
                isError: true
            )
        }

        do {
            // Parse territory_schedules JSON string if provided
            var schedules: [TerritorySchedule]?
            if let schedulesJson = arguments["territory_schedules"]?.stringValue,
               let data = schedulesJson.data(using: .utf8) {
                schedules = try? JSONDecoder().decode([TerritorySchedule].self, from: data)
            }

            let request = CreateAppEventRequest(
                data: CreateAppEventRequest.CreateAppEventData(
                    attributes: CreateAppEventRequest.CreateAppEventAttributes(
                        referenceName: referenceName,
                        badge: arguments["badge"]?.stringValue,
                        deepLink: arguments["deep_link"]?.stringValue,
                        purchaseRequirement: arguments["purchase_requirement"]?.stringValue,
                        purpose: arguments["purpose"]?.stringValue,
                        territorySchedules: schedules
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

            let result = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create app event: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            // Parse territory_schedules JSON string if provided
            var schedules: [TerritorySchedule]?
            if let schedulesJson = arguments["territory_schedules"]?.stringValue,
               let data = schedulesJson.data(using: .utf8) {
                schedules = try? JSONDecoder().decode([TerritorySchedule].self, from: data)
            }

            let request = UpdateAppEventRequest(
                data: UpdateAppEventRequest.UpdateAppEventData(
                    id: eventId,
                    attributes: UpdateAppEventRequest.UpdateAppEventAttributes(
                        referenceName: arguments["reference_name"]?.stringValue,
                        badge: arguments["badge"]?.stringValue,
                        deepLink: arguments["deep_link"]?.stringValue,
                        purchaseRequirement: arguments["purchase_requirement"]?.stringValue,
                        purpose: arguments["purpose"]?.stringValue,
                        territorySchedules: schedules
                    )
                )
            )

            let response: ASCAppEventResponse = try await httpClient.patch(
                "/v1/appEvents/\(eventId)",
                body: request,
                as: ASCAppEventResponse.self
            )

            let result = [
                "success": true,
                "app_event": formatAppEvent(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update app event: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appEvents/\(eventId)")

            let result = [
                "success": true,
                "message": "App event '\(eventId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to delete app event: \(error.localizedDescription)")],
                isError: true
            )
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
                content: [.text("Required parameter 'event_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppEventLocalizationsResponse = try await httpClient.get(
                "/v1/appEvents/\(eventId)/localizations",
                parameters: [:],
                as: ASCAppEventLocalizationsResponse.self
            )

            let localizations = response.data.map { formatLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list app event localizations: \(error.localizedDescription)")],
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
              let locale = arguments["locale"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters: event_id, locale")],
                isError: true
            )
        }

        do {
            let request = CreateAppEventLocalizationRequest(
                data: CreateAppEventLocalizationRequest.CreateData(
                    attributes: CreateAppEventLocalizationRequest.Attributes(
                        locale: locale,
                        name: arguments["name"]?.stringValue,
                        shortDescription: arguments["short_description"]?.stringValue,
                        longDescription: arguments["long_description"]?.stringValue
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

            let result: [String: Any] = [
                "success": true,
                "localization": formatLocalization(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create app event localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an existing app event localization
    /// - Returns: JSON with updated localization details
    /// - Throws: ASCError on API failures
    func updateAppEventLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateAppEventLocalizationRequest(
                data: UpdateAppEventLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateAppEventLocalizationRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        shortDescription: arguments["short_description"]?.stringValue,
                        longDescription: arguments["long_description"]?.stringValue
                    )
                )
            )

            let response: ASCAppEventLocalizationSingleResponse = try await httpClient.patch(
                "/v1/appEventLocalizations/\(localizationId)",
                body: request,
                as: ASCAppEventLocalizationSingleResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "localization": formatLocalization(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update app event localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an app event localization
    /// - Returns: JSON confirmation of deletion
    /// - Throws: ASCError on API failures
    func deleteAppEventLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appEventLocalizations/\(localizationId)")

            let result: [String: Any] = [
                "success": true,
                "message": "App event localization '\(localizationId)' deleted"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to delete app event localization: \(error.localizedDescription)")],
                isError: true
            )
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
            result["purpose"] = attrs.purpose.jsonSafe
            result["eventState"] = attrs.eventState.jsonSafe

            if let schedules = attrs.territorySchedules {
                result["territorySchedules"] = schedules.map { formatSchedule($0) }
            }
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
        return [
            "id": loc.id,
            "type": loc.type,
            "locale": loc.attributes?.locale.jsonSafe ?? NSNull(),
            "name": loc.attributes?.name.jsonSafe ?? NSNull(),
            "shortDescription": loc.attributes?.shortDescription.jsonSafe ?? NSNull(),
            "longDescription": loc.attributes?.longDescription.jsonSafe ?? NSNull()
        ]
    }
}
