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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = await httpClient.parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCWebhooksResponse.self)
            } else {
                var query = defaultListQuery(arguments: arguments)
                if arguments["include_app"]?.boolValue == true {
                    query["include"] = "app"
                }
                response = try await httpClient.get("/v1/apps/\(appID)/webhooks", parameters: query, as: ASCWebhooksResponse.self)
            }

            var result: [String: Any] = [
                "success": true,
                "webhooks": response.data.map(formatWebhook),
                "count": response.data.count
            ]
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
            let response = try await httpClient.get("/v1/webhooks/\(webhookID)", parameters: query, as: ASCWebhookResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "webhook": formatWebhook(response.data)
            ])
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
            return MCPResult.error("Parameter 'url' must be an absolute http/https URL")
        }
        guard validateEventTypes(eventTypes) else {
            return MCPResult.error("Parameter 'event_types' contains unsupported App Store Connect webhook event type")
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
            return MCPResult.error("Failed to create webhook: \(error.localizedDescription)")
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

        let eventTypes = parseEventTypes(arguments["event_types"])
        if let eventTypes, !validateEventTypes(eventTypes) {
            return MCPResult.error("Parameter 'event_types' contains unsupported App Store Connect webhook event type")
        }
        if let url = arguments["url"]?.stringValue, !validateWebhookURL(url) {
            return MCPResult.error("Parameter 'url' must be an absolute http/https URL")
        }

        let attributes = ASCWebhookUpdateRequest.Attributes(
            enabled: arguments["enabled"]?.boolValue,
            eventTypes: eventTypes,
            name: arguments["name"]?.stringValue,
            secret: arguments["secret"]?.stringValue,
            url: arguments["url"]?.stringValue
        )
        guard attributes.hasChanges else {
            return MCPResult.error("At least one update field is required: name, url, secret, event_types, enabled")
        }

        do {
            let request = ASCWebhookUpdateRequest(webhookID: webhookID, attributes: attributes)
            let response = try await httpClient.patch("/v1/webhooks/\(webhookID)", body: request, as: ASCWebhookResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "webhook": formatWebhook(response.data)
            ])
        } catch {
            return MCPResult.error("Failed to update webhook: \(error.localizedDescription)")
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
            _ = try await httpClient.delete("/v1/webhooks/\(webhookID)")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Webhook '\(webhookID)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete webhook: \(error.localizedDescription)")
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
            if let nextURL = arguments["next_url"]?.stringValue,
               let parsed = await httpClient.parsePaginationUrl(nextURL) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCWebhookDeliveriesResponse.self)
            } else {
                var query = defaultListQuery(arguments: arguments)
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
                response = try await httpClient.get("/v1/webhooks/\(webhookID)/deliveries", parameters: query, as: ASCWebhookDeliveriesResponse.self)
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
            return MCPResult.error("Failed to redeliver webhook delivery: \(error.localizedDescription)")
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
            return MCPResult.error("Failed to ping webhook: \(error.localizedDescription)")
        }
    }

    private func defaultListQuery(arguments: [String: Value]) -> [String: String] {
        let limit = arguments["limit"]?.intValue ?? 25
        return ["limit": String(min(max(limit, 1), 200))]
    }

    private func parseEventTypes(_ value: Value?) -> [String]? {
        value?.arrayValue?.compactMap(\.stringValue)
    }

    private func validateEventTypes(_ eventTypes: [String]) -> Bool {
        !eventTypes.isEmpty && eventTypes.allSatisfy { ASCWebhookEventTypes.all.contains($0) }
    }

    private func validateWebhookURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return false
        }
        return true
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
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
