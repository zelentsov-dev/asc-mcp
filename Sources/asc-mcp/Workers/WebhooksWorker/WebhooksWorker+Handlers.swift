import Foundation
import MCP

extension WebhooksWorker {
    /// Lists webhook notification configurations for an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional pagination/include values.
    /// - Returns: JSON object containing webhooks, count, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listWebhooks(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let response: ASCWebhooksResponse
            var query = try defaultListQuery(arguments: arguments)
            if arguments["include_app"]?.boolValue == true {
                query["include"] = "app"
            }
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appID))/webhooks",
                        query: query
                    ),
                    as: ASCWebhooksResponse.self
                )
            } else {
                response = try await httpClient.get("/v1/apps/\(try ASCPathSegment.encode(appID))/webhooks", parameters: query, as: ASCWebhooksResponse.self)
            }

            var result: [String: Any] = [
                "success": true,
                "webhooks": response.data.map(formatWebhook),
                "count": response.data.count
            ]
            appendIncluded(
                response.included,
                requested: arguments["include_app"]?.boolValue == true,
                to: &result
            )
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list webhooks: \(error.localizedDescription)")
        }
    }

    /// Gets one webhook notification configuration.
    /// - Parameter params: Tool parameters containing `webhook_id`.
    /// - Returns: JSON object containing the webhook resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getWebhook(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let webhookID = arguments["webhook_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'webhook_id' is missing")
        }

        do {
            var query: [String: String] = [:]
            if arguments["include_app"]?.boolValue == true {
                query["include"] = "app"
            }
            let response = try await httpClient.get("/v1/webhooks/\(try ASCPathSegment.encode(webhookID))", parameters: query, as: ASCWebhookResponse.self)
            var result: [String: Any] = [
                "success": true,
                "webhook": formatWebhook(response.data)
            ]
            appendIncluded(
                response.included,
                requested: arguments["include_app"]?.boolValue == true,
                to: &result
            )
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to get webhook: \(error.localizedDescription)")
        }
    }

    /// Creates a webhook notification configuration.
    /// - Parameter params: Tool parameters containing app, URL, secret, event type, and enabled settings.
    /// - Returns: JSON object containing the created webhook resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func createWebhook(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let url = arguments["url"]?.stringValue,
              let secret = arguments["secret"]?.stringValue,
              let eventTypes = parseEventTypes(arguments["event_types"]) else {
            return MCPResult.error("Required parameters: app_id, name, url, secret, event_types")
        }

        guard validateWebhookURL(url) else {
            return MCPResult.error(webhookURLValidationMessage)
        }
        guard validateEventTypes(eventTypes) else {
            return MCPResult.error("Parameter 'event_types' contains unsupported App Store Connect webhook event type")
        }
        guard validateWebhookSecret(secret) else {
            return MCPResult.error(webhookSecretValidationMessage)
        }

        do {
            let request = ASCWebhookCreateRequest(
                appID: appID,
                name: name,
                url: url,
                secret: secret,
                eventTypes: eventTypes,
                enabled: arguments["enabled"]?.boolValue ?? true
            )
            let response = try await httpClient.post("/v1/webhooks", body: request, as: ASCWebhookResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "webhook": formatWebhook(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to create webhook")
        }
    }

    /// Updates a webhook notification configuration.
    /// - Parameter params: Tool parameters containing `webhook_id` and at least one update field.
    /// - Returns: JSON object containing the updated webhook resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func updateWebhook(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let webhookID = arguments["webhook_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'webhook_id' is missing")
        }

        let attributes: ASCWebhookUpdateRequest.Attributes
        do {
            attributes = try webhookUpdateAttributes(arguments)
        } catch {
            return MCPResult.error(error)
        }
        guard attributes.hasChanges else {
            return MCPResult.error("At least one update field is required: name, url, secret, event_types, enabled")
        }

        do {
            let request = ASCWebhookUpdateRequest(webhookID: webhookID, attributes: attributes)
            let response = try await httpClient.patch("/v1/webhooks/\(try ASCPathSegment.encode(webhookID))", body: request, as: ASCWebhookResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "webhook": formatWebhook(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to update webhook")
        }
    }

    /// Deletes a webhook notification configuration.
    /// - Parameter params: Tool parameters containing `webhook_id`.
    /// - Returns: JSON confirmation.
    /// - Throws: Networking or API errors from App Store Connect.
    func deleteWebhook(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let webhookID = arguments["webhook_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'webhook_id' is missing")
        }

        do {
            _ = try await httpClient.delete("/v1/webhooks/\(try ASCPathSegment.encode(webhookID))")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Webhook '\(webhookID)' deleted"
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete webhook")
        }
    }

    /// Lists delivery attempts for a webhook.
    /// - Parameter params: Tool parameters containing `webhook_id` and optional filters.
    /// - Returns: JSON object containing delivery attempts, optional events, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listDeliveries(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let webhookID = arguments["webhook_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'webhook_id' is missing")
        }

        do {
            let response: ASCWebhookDeliveriesResponse
            var query = try defaultListQuery(arguments: arguments)
            if let deliveryState = arguments["delivery_state"]?.stringValue {
                query["filter[deliveryState]"] = deliveryState
            }
            if let createdAfter = arguments["created_after"]?.stringValue {
                query["filter[createdDateGreaterThanOrEqualTo]"] = createdAfter
            }
            if let createdBefore = arguments["created_before"]?.stringValue {
                query["filter[createdDateLessThan]"] = createdBefore
            }
            if arguments["include_event"]?.boolValue ?? true {
                query["include"] = "event"
            }
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(
                        path: "/v1/webhooks/\(try ASCPathSegment.encode(webhookID))/deliveries",
                        query: query
                    ),
                    as: ASCWebhookDeliveriesResponse.self
                )
            } else {
                response = try await httpClient.get("/v1/webhooks/\(try ASCPathSegment.encode(webhookID))/deliveries", parameters: query, as: ASCWebhookDeliveriesResponse.self)
            }

            var result: [String: Any] = [
                "success": true,
                "deliveries": response.data.map(formatDelivery),
                "events": response.included?.map(formatEvent) ?? [],
                "count": response.data.count
            ]
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list webhook deliveries: \(error.localizedDescription)")
        }
    }

    /// Creates a redelivery attempt from an existing webhook delivery.
    /// - Parameter params: Tool parameters containing `delivery_id`.
    /// - Returns: JSON object containing the new delivery resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func redeliver(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let deliveryID = arguments["delivery_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'delivery_id' is missing")
        }

        do {
            let request = ASCWebhookDeliveryCreateRequest(templateDeliveryID: deliveryID)
            let response = try await httpClient.post("/v1/webhookDeliveries", body: request, as: ASCWebhookDeliveryResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "delivery": formatDelivery(response.data),
                "events": response.included?.map(formatEvent) ?? []
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to redeliver webhook delivery")
        }
    }

    /// Sends a test ping through an existing webhook configuration.
    /// - Parameter params: Tool parameters containing `webhook_id`.
    /// - Returns: JSON object containing the ping resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func ping(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let webhookID = arguments["webhook_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'webhook_id' is missing")
        }

        do {
            let request = ASCWebhookPingCreateRequest(webhookID: webhookID)
            let response = try await httpClient.post("/v1/webhookPings", body: request, as: ASCWebhookPingResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "ping": [
                    "id": response.data.id,
                    "type": response.data.type
                ]
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to ping webhook")
        }
    }

    private func defaultListQuery(arguments: [String: Value]) throws -> [String: String] {
        guard let value = arguments["limit"] else {
            return ["limit": "25"]
        }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw ASCError.parsing("limit must be an integer from 1 through 200")
        }
        return ["limit": String(limit)]
    }

    private func parseEventTypes(_ value: Value?) -> [String]? {
        value?.arrayValue?.compactMap(\.stringValue)
    }

    private func validateEventTypes(_ eventTypes: [String]) -> Bool {
        !eventTypes.isEmpty && eventTypes.allSatisfy { ASCWebhookEventTypes.all.contains($0) }
    }

    private func webhookUpdateAttributes(
        _ arguments: [String: Value]
    ) throws -> ASCWebhookUpdateRequest.Attributes {
        var values: [String: JSONValue] = [:]

        if let enabled = arguments["enabled"] {
            if enabled.isNull {
                values["enabled"] = .null
            } else if let boolean = enabled.boolValue {
                values["enabled"] = .bool(boolean)
            } else {
                throw ASCError.parsing("Parameter 'enabled' must be a boolean or null")
            }
        }

        if let eventTypes = arguments["event_types"] {
            if eventTypes.isNull {
                values["eventTypes"] = .null
            } else {
                guard let array = eventTypes.arrayValue else {
                    throw ASCError.parsing("Parameter 'event_types' must be an array of strings or null")
                }
                let strings = array.compactMap(\.stringValue)
                guard strings.count == array.count,
                      validateEventTypes(strings),
                      Set(strings).count == strings.count else {
                    throw ASCError.parsing("Parameter 'event_types' must contain unique supported App Store Connect webhook event types")
                }
                values["eventTypes"] = .array(strings.map(JSONValue.string))
            }
        }

        for key in ["name", "secret", "url"] {
            guard let value = arguments[key] else { continue }
            if value.isNull {
                values[key] = .null
                continue
            }
            guard let string = value.stringValue else {
                throw ASCError.parsing("Parameter '\(key)' must be a string or null")
            }
            if key == "url", !validateWebhookURL(string) {
                throw ASCError.parsing(webhookURLValidationMessage)
            }
            if key == "secret", !validateWebhookSecret(string) {
                throw ASCError.parsing(webhookSecretValidationMessage)
            }
            values[key] = .string(string)
        }

        return ASCWebhookUpdateRequest.Attributes(values: values)
    }

    private func validateWebhookURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.url != nil else {
            return false
        }
        return true
    }

    private var webhookURLValidationMessage: String {
        "Parameter 'url' must be an absolute HTTPS URL with a non-empty host and no user, password, or fragment"
    }

    private func validateWebhookSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard trimmed.count >= Self.minimumWebhookSecretLength,
              Set(bytes).count >= 4 else {
            return false
        }

        let maximumPatternLength = min(16, bytes.count / 2)
        for patternLength in 1...maximumPatternLength where bytes.count.isMultiple(of: patternLength) {
            let repeats = bytes.indices.allSatisfy { index in
                bytes[index] == bytes[index % patternLength]
            }
            if repeats {
                return false
            }
        }
        return true
    }

    private var webhookSecretValidationMessage: String {
        "Parameter 'secret' must contain at least \(Self.minimumWebhookSecretLength) characters and must not be a low-diversity or repeated-pattern value"
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    private func appendIncluded(_ included: [JSONValue]?, requested: Bool, to result: inout [String: Any]) {
        if requested || included?.isEmpty == false {
            result["included"] = included?.map(\.asAny) ?? []
        }
    }

    private func formatWebhook(_ webhook: ASCWebhook) -> [String: Any] {
        [
            "id": webhook.id,
            "type": webhook.type,
            "enabled": (webhook.attributes?.enabled).jsonSafe,
            "eventTypes": webhook.attributes?.eventTypes ?? [],
            "name": (webhook.attributes?.name).jsonSafe,
            "url": (webhook.attributes?.url).jsonSafe,
            "appId": (webhook.relationships?.app?.data?.id).jsonSafe
        ]
    }

    private func formatDelivery(_ delivery: ASCWebhookDelivery) -> [String: Any] {
        [
            "id": delivery.id,
            "type": delivery.type,
            "createdDate": (delivery.attributes?.createdDate).jsonSafe,
            "sentDate": (delivery.attributes?.sentDate).jsonSafe,
            "deliveryState": (delivery.attributes?.deliveryState).jsonSafe,
            "errorMessage": (delivery.attributes?.errorMessage).jsonSafe,
            "redelivery": (delivery.attributes?.redelivery).jsonSafe,
            "requestUrl": (delivery.attributes?.request?.url).jsonSafe,
            "responseStatusCode": (delivery.attributes?.response?.httpStatusCode).jsonSafe,
            "responseBody": (delivery.attributes?.response?.body).jsonSafe,
            "eventId": (delivery.relationships?.event?.data?.id).jsonSafe
        ]
    }

    private func formatEvent(_ event: ASCWebhookEvent) -> [String: Any] {
        [
            "id": event.id,
            "type": event.type,
            "eventType": (event.attributes?.eventType).jsonSafe,
            "payload": (event.attributes?.payload).jsonSafe,
            "ping": (event.attributes?.ping).jsonSafe,
            "createdDate": (event.attributes?.createdDate).jsonSafe
        ]
    }
}
