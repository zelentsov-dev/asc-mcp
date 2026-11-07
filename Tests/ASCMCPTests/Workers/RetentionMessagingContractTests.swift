import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Retention Messaging Contract Tests")
struct RetentionMessagingContractTests {
    // MARK: - 1. Retention Messages, Versions, and Linked Subscriptions

    @Test("retention messages CRUD, versions CRUD, and linked subscriptions")
    func retentionMessagesAndVersionsCRUD() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionMessages","id":"msg-1","attributes":{"referenceName":"Stay With Us"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"versions":{"data":[{"type":"retentionMessageVersions","id":"ver-1"}]},"subscriptions":{"data":[{"type":"subscriptions","id":"sub-1"}]}}}],"included":[{"type":"retentionMessageVersions","id":"ver-1","attributes":{"version":1,"state":"READY_FOR_REVIEW"}},{"type":"subscriptions","id":"sub-1","attributes":{"name":"Pro Monthly","productId":"com.example.pro","state":"APPROVED","subscriptionPeriod":"ONE_MONTH"}}],"links":{"self":"https://api.example.test/v1/apps/app-1/retentionMessages"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessages","id":"msg-1","attributes":{"referenceName":"Stay With Us"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}},"versions":{"data":[{"type":"retentionMessageVersions","id":"ver-1"}]}}}}"#
            ),
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionMessages","id":"msg-2","attributes":{"referenceName":"Win Back At Cancel"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
            ),
            .init(statusCode: 204, body: ""),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionMessageVersions","id":"ver-1","attributes":{"version":1,"state":"READY_FOR_REVIEW"},"relationships":{"retentionMessage":{"data":{"type":"retentionMessages","id":"msg-1"}},"localizations":{"data":[{"type":"retentionMessageLocalizations","id":"loc-1"}]}}}],"included":[{"type":"retentionMessageLocalizations","id":"loc-1","attributes":{"locale":"en-US","header":"Stay with Pro","body":"Keep all your features."}}],"links":{"self":"https://api.example.test/v1/retentionMessages/msg-1/versions"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessageVersions","id":"ver-1","attributes":{"version":1,"state":"READY_FOR_REVIEW"},"relationships":{"retentionMessage":{"data":{"type":"retentionMessages","id":"msg-1"}}}}}"#
            ),
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionMessageVersions","id":"ver-2","attributes":{"version":2,"state":"PREPARE_FOR_SUBMISSION"},"relationships":{"retentionMessage":{"data":{"type":"retentionMessages","id":"msg-1"}}}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"subscriptions","id":"sub-1","attributes":{"name":"Pro Monthly","productId":"com.example.pro","state":"APPROVED","subscriptionPeriod":"ONE_MONTH"}}],"links":{"self":"https://api.example.test/v1/retentionMessages/msg-1/subscriptions"}}"#
            )
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        let listed = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_messages",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(listed.isError != true)
        let listedPayload = try object(listed.structuredContent)
        #expect(listedPayload["count"] == .int(1))
        let firstMessage = try object(try #require(listedPayload["retention_messages"]?.arrayValue?.first))
        #expect(firstMessage["id"] == .string("msg-1"))
        #expect(firstMessage["referenceName"] == .string("Stay With Us"))

        let fetched = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_message",
            arguments: ["retention_message_id": .string("msg-1")]
        ))
        #expect(fetched.isError != true)
        let fetchedMessage = try object(try object(fetched.structuredContent)["retention_message"])
        #expect(fetchedMessage["id"] == .string("msg-1"))

        let created = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message",
            arguments: ["app_id": .string("app-1"), "reference_name": .string("Win Back At Cancel")]
        ))
        #expect(created.isError != true)
        let createdMessage = try object(try object(created.structuredContent)["retention_message"])
        #expect(createdMessage["id"] == .string("msg-2"))

        let deleted = try await worker.handleTool(.init(
            name: "subscriptions_delete_retention_message",
            arguments: ["retention_message_id": .string("msg-2")]
        ))
        #expect(deleted.isError != true)

        let listedVersions = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_message_versions",
            arguments: ["retention_message_id": .string("msg-1")]
        ))
        #expect(listedVersions.isError != true)
        let versionsPayload = try object(listedVersions.structuredContent)
        #expect(versionsPayload["count"] == .int(1))

        let fetchedVersion = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_message_version",
            arguments: ["version_id": .string("ver-1")]
        ))
        #expect(fetchedVersion.isError != true)
        #expect(try object(try object(fetchedVersion.structuredContent)["version"])["id"] == .string("ver-1"))

        let createdVersion = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_version",
            arguments: ["retention_message_id": .string("msg-1")]
        ))
        #expect(createdVersion.isError != true)
        #expect(try object(try object(createdVersion.structuredContent)["version"])["version"] == .int(2))

        let linkedSubscriptions = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_message_subscriptions",
            arguments: ["retention_message_id": .string("msg-1")]
        ))
        #expect(linkedSubscriptions.isError != true)
        #expect(try object(linkedSubscriptions.structuredContent)["count"] == .int(1))

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "DELETE", "GET", "GET", "POST", "GET"])
        #expect(requests[0].url?.path == "/v1/apps/app-1/retentionMessages")
        #expect(requests[2].url?.path == "/v1/retentionMessages")
        #expect(requests[3].url?.path == "/v1/retentionMessages/msg-2")
        #expect(requests[4].url?.path == "/v1/retentionMessages/msg-1/versions")
        #expect(requests[6].url?.path == "/v1/retentionMessageVersions")
        #expect(requests[7].url?.path == "/v1/retentionMessages/msg-1/subscriptions")
    }

    // MARK: - 2. Retention Message Localizations & Validation

    @Test("retention message localizations enforce header, body, emoji, and price mention validation")
    func retentionMessageLocalizationValidationAndCRUD() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionMessageLocalizations","id":"loc-1","attributes":{"locale":"en-US","header":"Special retention offer","body":"Save $4.99 when you stay subscribed."},"relationships":{"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"ver-1"}}}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionMessageLocalizations","id":"loc-1","attributes":{"locale":"en-US","header":"Special retention offer","body":"Save $4.99 when you stay subscribed."}}],"links":{"self":"https://api.example.test/v1/retentionMessageVersions/ver-1/localizations"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessageLocalizations","id":"loc-1","attributes":{"locale":"en-US","header":"Special retention offer","body":"Save $4.99 when you stay subscribed."}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessageLocalizations","id":"loc-1","attributes":{"locale":"en-US","header":"Stay with Pro","body":"Keep unlimited cloud sync."}}}"#
            ),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        // Header > 66 characters rejected before network access
        let longHeader = String(repeating: "A", count: 67)
        let headerError = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_localization",
            arguments: [
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "header": .string(longHeader),
                "body": .string("Keep unlimited cloud sync.")
            ]
        ))
        #expect(headerError.isError == true)

        // Body > 144 characters rejected before network access
        let longBody = String(repeating: "B", count: 145)
        let bodyError = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_localization",
            arguments: [
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "header": .string("Stay with Pro"),
                "body": .string(longBody)
            ]
        ))
        #expect(bodyError.isError == true)

        // Emoji rejected before network access
        let emojiError = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_localization",
            arguments: [
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "header": .string("Stay with Pro 🎉"),
                "body": .string("Keep unlimited cloud sync.")
            ]
        ))
        #expect(emojiError.isError == true)

        // Price/currency/discount mentions rejected by default before network access
        for priceText in ["Save $4.99 today", "Get 50% off your next renewal", "Only €9,99 per month"] {
            let priceError = try await worker.handleTool(.init(
                name: "subscriptions_create_retention_message_localization",
                arguments: [
                    "version_id": .string("ver-1"),
                    "locale": .string("en-US"),
                    "header": .string("Special retention offer"),
                    "body": .string(priceText)
                ]
            ))
            #expect(priceError.isError == true, "Expected price string '\(priceText)' to be rejected by default")
        }
        #expect(await transport.requestCount() == 0)

        // Allowed when allow_price_mentions == true
        let created = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_localization",
            arguments: [
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "header": .string("Special retention offer"),
                "body": .string("Save $4.99 when you stay subscribed."),
                "allow_price_mentions": .bool(true)
            ]
        ))
        #expect(created.isError != true)
        #expect(try object(try object(created.structuredContent)["localization"])["id"] == .string("loc-1"))

        let listed = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_message_localizations",
            arguments: ["version_id": .string("ver-1")]
        ))
        #expect(listed.isError != true)
        #expect(try object(listed.structuredContent)["count"] == .int(1))

        let fetched = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_message_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))
        #expect(fetched.isError != true)

        let updated = try await worker.handleTool(.init(
            name: "subscriptions_update_retention_message_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "header": .string("Stay with Pro"),
                "body": .string("Keep unlimited cloud sync.")
            ]
        ))
        #expect(updated.isError != true)
        #expect(try object(try object(updated.structuredContent)["localization"])["header"] == .string("Stay with Pro"))

        let deleted = try await worker.handleTool(.init(
            name: "subscriptions_delete_retention_message_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))
        #expect(deleted.isError != true)
        #expect(await transport.requestCount() == 5)
    }

    // MARK: - 3. Retention Offers & Inline Prices

    @Test("retention offers CRUD, inline price relationships, and eligibility rules")
    func retentionOffersAndInlinePrices() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":{"minimum":3,"maximum":12},"customerEligibilityWaitBetweenOffersInMonths":6,"startDate":"2026-11-01","endDate":"2027-11-01","targetSubscriptionPlanType":"MONTHLY"},"relationships":{"prices":{"data":[{"type":"retentionOfferPrices","id":"rop-1"}]}}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":{"minimum":3,"maximum":12},"customerEligibilityWaitBetweenOffersInMonths":6}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionOffers"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionMessageOffers"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"endDate":null}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOfferPrices","id":"rop-1","relationships":{"territory":{"data":{"type":"territories","id":"USA"}},"subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"pp-usa-1"}}}}],"included":[{"type":"subscriptionPricePoints","id":"pp-usa-1","attributes":{"customerPrice":"4.99","proceeds":"3.49","proceedsYear2":"4.24"}},{"type":"territories","id":"USA","attributes":{"currency":"USD"}}],"links":{"self":"https://api.example.test/v1/retentionOffers/ro-1/prices"}}"#
            ),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        // Invalid wait_between_offers_months rejected before network access
        let invalidWait = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Bad Wait"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("ONE_MONTH"),
                "periods": .int(1),
                "eligibility_duration_type": .string("AT_LEAST"),
                "eligibility_duration_min": .int(3),
                "wait_between_offers_months": .int(5),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(invalidWait.isError == true)
        #expect(await transport.requestCount() == 0)

        let created = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Loyal 6M Offer"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("THREE_MONTHS"),
                "periods": .int(3),
                "eligibility_duration_type": .string("RANGE"),
                "eligibility_duration_min": .int(3),
                "eligibility_duration_max": .int(12),
                "wait_between_offers_months": .int(6),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(created.isError != true)

        let createRequest = try #require(await transport.recordedRequests().first)
        let createBody = try jsonObject(from: try #require(createRequest.httpBody))
        let included = try #require(createBody["included"] as? [[String: Any]])
        #expect(included.count == 1)
        #expect(included[0]["type"] as? String == "retentionOfferPrices")
        let relationships = try #require(included[0]["relationships"] as? [String: Any])
        let pricePointRel = try #require((relationships["subscriptionPricePoint"] as? [String: Any])?["data"] as? [String: Any])
        #expect(pricePointRel["type"] as? String == "subscriptionPricePoints")
        #expect(pricePointRel["id"] as? String == "pp-usa-1")
        let territoryRel = try #require((relationships["territory"] as? [String: Any])?["data"] as? [String: Any])
        #expect(territoryRel["type"] as? String == "territories")
        #expect(territoryRel["id"] as? String == "USA")

        // List all retention offers vs message_offers_only: true
        let listedAll = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_offers",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        #expect(listedAll.isError != true)

        let listedMessageOnly = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_offers",
            arguments: ["subscription_id": .string("sub-1"), "message_offers_only": .bool(true)]
        ))
        #expect(listedMessageOnly.isError != true)

        let fetched = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_offer",
            arguments: ["offer_id": .string("ro-1")]
        ))
        #expect(fetched.isError != true)

        let updated = try await worker.handleTool(.init(
            name: "subscriptions_update_retention_offer",
            arguments: ["offer_id": .string("ro-1"), "wait_between_offers_months": .int(12)]
        ))
        #expect(updated.isError != true)

        let prices = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_offer_prices",
            arguments: ["offer_id": .string("ro-1"), "territory": .string("USA,GBR")]
        ))
        #expect(prices.isError != true)
        #expect(try object(prices.structuredContent)["count"] == .int(1))

        let deleted = try await worker.handleTool(.init(
            name: "subscriptions_delete_retention_offer",
            arguments: ["offer_id": .string("ro-1")]
        ))
        #expect(deleted.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests[1].url?.path == "/v1/subscriptions/sub-1/retentionOffers")
        #expect(requests[2].url?.path == "/v1/subscriptions/sub-1/retentionMessageOffers")
        #expect(requests[5].url?.path == "/v1/retentionOffers/ro-1/prices")
    }

    // MARK: - 4. Subscription Retention Relationships

    @Test("subscription retention message and offer relationships handle null data, clear, POST, and DELETE")
    func subscriptionRetentionRelationships() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":null}"#),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessages","id":"msg-1","attributes":{"referenceName":"Stay With Us"}}}"#
            ),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        let emptyResult = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_message_for_subscription",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        #expect(emptyResult.isError != true)
        let emptyPayload = try object(emptyResult.structuredContent)
        #expect(emptyPayload["has_retention_message"] == .bool(false))

        let populatedResult = try await worker.handleTool(.init(
            name: "subscriptions_get_retention_message_for_subscription",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        #expect(populatedResult.isError != true)
        let populatedPayload = try object(populatedResult.structuredContent)
        #expect(populatedPayload["has_retention_message"] == .bool(true))
        #expect(try object(populatedPayload["retention_message"])["id"] == .string("msg-1"))

        let assigned = try await worker.handleTool(.init(
            name: "subscriptions_set_retention_message",
            arguments: ["subscription_id": .string("sub-1"), "retention_message_id": .string("msg-1")]
        ))
        #expect(assigned.isError != true)

        let cleared = try await worker.handleTool(.init(
            name: "subscriptions_set_retention_message",
            arguments: ["subscription_id": .string("sub-1"), "clear": .bool(true)]
        ))
        #expect(cleared.isError != true)

        let addedOffers = try await worker.handleTool(.init(
            name: "subscriptions_add_retention_message_offers",
            arguments: ["subscription_id": .string("sub-1"), "offer_ids": .array([.string("ro-1"), .string("ro-2")])]
        ))
        #expect(addedOffers.isError != true)

        let removedOffers = try await worker.handleTool(.init(
            name: "subscriptions_remove_retention_message_offers",
            arguments: ["subscription_id": .string("sub-1"), "offer_ids": .array([.string("ro-1")])]
        ))
        #expect(removedOffers.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests[2].httpMethod == "PATCH")
        #expect(requests[2].url?.path == "/v1/subscriptions/sub-1/relationships/retentionMessage")
        let assignBody = try jsonObject(from: try #require(requests[2].httpBody))
        #expect((assignBody["data"] as? [String: Any])?["id"] as? String == "msg-1")

        let clearBody = try jsonObject(from: try #require(requests[3].httpBody))
        #expect(clearBody["data"] is NSNull)

        #expect(requests[4].httpMethod == "POST")
        #expect(requests[4].url?.path == "/v1/subscriptions/sub-1/relationships/retentionMessageOffers")
        #expect(requests[5].httpMethod == "DELETE")
        #expect(requests[5].url?.path == "/v1/subscriptions/sub-1/relationships/retentionMessageOffers")
        let removeBody = try #require(requests[5].httpBody)
        let removeData = try #require(try jsonObject(from: removeBody)["data"] as? [[String: Any]])
        #expect(removeData.count == 1)
        #expect(removeData[0]["id"] as? String == "ro-1")
    }

    // MARK: - 5. AssetsWorker Retention Message Version Placement Support

    @Test("AssetsWorker reads to-one retentionMessageVersion placement and rejects video and reordering")
    func assetsWorkerRetentionMessageVersionSupport() async throws {
        let versionDoc = #"{"data":{"type":"retentionMessageVersions","id":"ver-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"},"relationships":{"retentionMessage":{"data":{"type":"retentionMessages","id":"msg-1"}}}}}"#
        let appMessagesDoc = #"{"data":[{"type":"retentionMessages","id":"msg-1","attributes":{"referenceName":"Stay With Us"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}]}"#
        let placementDoc = #"{"data":{"type":"appAssetLibraryPlacements","id":"pl-1","attributes":{"placementType":"retentionImage","placementGroup":"retentionGroup"},"relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"img-1"}},"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"ver-1"}}}}}"#

        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionDoc),
            .init(statusCode: 200, body: appMessagesDoc),
            .init(statusCode: 200, body: #"{"data":null}"#),
            .init(statusCode: 200, body: versionDoc),
            .init(statusCode: 200, body: appMessagesDoc),
            .init(statusCode: 200, body: placementDoc)
        ])
        let root = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/.build/asset-retention-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.appstoreconnect.apple.com",
            transport: transport,
            maxRetries: 1
        )
        let worker = AssetsWorker(
            httpClient: client,
            companiesManager: try TestFactory.makeCompaniesManager(),
            uploadService: UploadService(),
            store: AssetOperationStore(root: root)
        )

        // Empty to-one placement returns 0 items
        let emptyList = try await worker.handleTool(.init(
            name: "assets_list_placements",
            arguments: [
                "app_id": .string("app-1"),
                "target_type": .string("retentionMessageVersion"),
                "target_id": .string("ver-1")
            ]
        ))
        #expect(emptyList.isError != true)
        #expect(try object(emptyList.structuredContent)["count"] == .int(0))

        // Populated to-one placement returns 1 item
        let populatedList = try await worker.handleTool(.init(
            name: "assets_list_placements",
            arguments: [
                "app_id": .string("app-1"),
                "target_type": .string("retentionMessageVersion"),
                "target_id": .string("ver-1")
            ]
        ))
        #expect(populatedList.isError != true)
        #expect(try object(populatedList.structuredContent)["count"] == .int(1))

        // Rejects video placement on retentionMessageVersion before network access
        let beforeCount = await transport.requestCount()
        let videoError = try await worker.handleTool(.init(
            name: "assets_prepare_change",
            arguments: [
                "app_id": .string("app-1"),
                "action": .string("create_placement"),
                "asset_kind": .string("video"),
                "asset_id": .string("vid-1"),
                "target_type": .string("retentionMessageVersion"),
                "target_id": .string("ver-1"),
                "placement_type": .string("retentionImage"),
                "placement_group": .string("retentionGroup")
            ]
        ))
        #expect(videoError.isError == true)

        // Rejects reorder_placements on retentionMessageVersion before network access
        let reorderError = try await worker.handleTool(.init(
            name: "assets_prepare_change",
            arguments: [
                "app_id": .string("app-1"),
                "action": .string("reorder_placements"),
                "target_type": .string("retentionMessageVersion"),
                "target_id": .string("ver-1"),
                "placement_group": .string("retentionGroup"),
                "ordered_placement_ids": .array([.string("pl-1")])
            ]
        ))
        #expect(reorderError.isError == true)
        #expect(await transport.requestCount() == beforeCount)
    }

    // MARK: - 6. ReviewSubmissionsWorker Retention Message Version Support

    @Test("ReviewSubmissionsWorker adds and projects retentionMessageVersion items")
    func reviewSubmissionsRetentionMessageVersionSupport() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"reviewSubmissionItems","id":"item-ret-1","attributes":{"state":"READY_FOR_REVIEW"},"relationships":{"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"ver-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-ret-1"}}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = ReviewSubmissionsWorker(httpClient: client)

        let added = try await worker.handleTool(.init(
            name: "review_submissions_add_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "retention_message_version_id": .string("ver-1")
            ]
        ))
        #expect(added.isError != true)
        let item = try object(try object(added.structuredContent)["item"])
        #expect(item["id"] == .string("item-ret-1"))
        #expect(item["resource_type"] == .string("retentionMessageVersion"))
        #expect(item["resource_jsonapi_type"] == .string("retentionMessageVersions"))
        #expect(item["resource_id"] == .string("ver-1"))
    }
}

private func makeSubscriptionsWorker(transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let dict) = value else {
        throw NSError(domain: "RetentionMessagingContractTests", code: 1)
    }
    return dict
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
