import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Webhooks Worker Tests")
struct WebhooksWorkerTests {
    @Test("missing required parameters return isError")
    func missingRequiredParametersReturnErrors() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let list = try await worker.handleTool(CallTool.Parameters(name: "webhooks_list", arguments: nil))
        let get = try await worker.handleTool(CallTool.Parameters(name: "webhooks_get", arguments: nil))
        let create = try await worker.handleTool(CallTool.Parameters(name: "webhooks_create", arguments: nil))
        let update = try await worker.handleTool(CallTool.Parameters(name: "webhooks_update", arguments: nil))
        let delete = try await worker.handleTool(CallTool.Parameters(name: "webhooks_delete", arguments: nil))
        let deliveries = try await worker.handleTool(CallTool.Parameters(name: "webhooks_list_deliveries", arguments: nil))
        let redeliver = try await worker.handleTool(CallTool.Parameters(name: "webhooks_redeliver", arguments: nil))
        let ping = try await worker.handleTool(CallTool.Parameters(name: "webhooks_ping", arguments: nil))

        #expect(list.isError == true)
        #expect(get.isError == true)
        #expect(create.isError == true)
        #expect(update.isError == true)
        #expect(delete.isError == true)
        #expect(deliveries.isError == true)
        #expect(redeliver.isError == true)
        #expect(ping.isError == true)
    }

    @Test("create validates URL and event types before network calls")
    func createValidatesURLAndEventTypes() async throws {
        let worker = WebhooksWorker(httpClient: try await TestFactory.makeHTTPClient())

        let badURL = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("123"),
                    "name": .string("Demo"),
                    "url": .string("not-a-url"),
                    "secret": .string("super-secret"),
                    "event_types": .array([.string("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED")])
                ]
            )
        )
        #expect(badURL.isError == true)

        let badEvent = try await worker.handleTool(
            CallTool.Parameters(
                name: "webhooks_create",
                arguments: [
                    "app_id": .string("123"),
                    "name": .string("Demo"),
                    "url": .string("https://example.com/webhook"),
                    "secret": .string("super-secret"),
                    "event_types": .array([.string("UNKNOWN_EVENT")])
                ]
            )
        )
        #expect(badEvent.isError == true)
    }

    @Test("request models encode Apple OpenAPI JSON API shape")
    func requestModelsEncodeAppleShape() throws {
        let create = ASCWebhookCreateRequest(
            appID: "app-1",
            name: "Release events",
            url: "https://example.com/webhook",
            secret: "secret",
            eventTypes: ["APP_STORE_VERSION_APP_VERSION_STATE_UPDATED"],
            enabled: true
        )

        let createJSON = try jsonObject(create)
        let createData = try #require(createJSON["data"] as? [String: Any])
        let createAttributes = try #require(createData["attributes"] as? [String: Any])
        let createRelationships = try #require(createData["relationships"] as? [String: Any])

        #expect(createData["type"] as? String == "webhooks")
        #expect(createAttributes["enabled"] as? Bool == true)
        #expect(createAttributes["name"] as? String == "Release events")
        #expect(createAttributes["secret"] as? String == "secret")
        #expect(createRelationships["app"] != nil)

        let update = ASCWebhookUpdateRequest(
            webhookID: "webhook-1",
            attributes: .init(
                enabled: false,
                eventTypes: nil,
                name: nil,
                secret: nil,
                url: nil
            )
        )
        let updateJSON = try jsonObject(update)
        let updateData = try #require(updateJSON["data"] as? [String: Any])
        let updateAttributes = try #require(updateData["attributes"] as? [String: Any])

        #expect(updateData["id"] as? String == "webhook-1")
        #expect(updateData["type"] as? String == "webhooks")
        #expect(updateAttributes["enabled"] as? Bool == false)
        #expect(updateAttributes["name"] == nil)

        let redelivery = ASCWebhookDeliveryCreateRequest(templateDeliveryID: "delivery-1")
        let redeliveryJSON = try jsonObject(redelivery)
        let redeliveryData = try #require(redeliveryJSON["data"] as? [String: Any])
        #expect(redeliveryData["type"] as? String == "webhookDeliveries")

        let ping = ASCWebhookPingCreateRequest(webhookID: "webhook-1")
        let pingJSON = try jsonObject(ping)
        let pingData = try #require(pingJSON["data"] as? [String: Any])
        #expect(pingData["type"] as? String == "webhookPings")
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
