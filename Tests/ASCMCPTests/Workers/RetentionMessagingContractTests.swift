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
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":6,"customerEligibilityWaitBetweenOffersInMonths":6,"targetSubscriptionPlanType":"MONTHLY"},"relationships":{"prices":{"data":[{"type":"retentionOfferPrices","id":"rop-1"}]}}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":6,"customerEligibilityWaitBetweenOffersInMonths":6,"targetSubscriptionPlanType":"MONTHLY"}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionOffers"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":6}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionMessageOffers"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":6,"customerEligibilityWaitBetweenOffersInMonths":6,"targetSubscriptionPlanType":"MONTHLY"}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionOffers","id":"ro-1","attributes":{"referenceName":"Loyal 6M Offer","offerId":"LOYAL6M","duration":"THREE_MONTHS","offerMode":"PAY_AS_YOU_GO","periodCount":3,"customerEligibilityPaidSubscriptionDurationInMonths":12,"customerEligibilityWaitBetweenOffersInMonths":null,"targetSubscriptionPlanType":"MONTHLY"}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"retentionOfferPrices","id":"rop-1","relationships":{"territory":{"data":{"type":"territories","id":"USA"}},"subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"pp-usa-1"}}}}],"included":[{"type":"subscriptionPricePoints","id":"pp-usa-1","attributes":{"customerPrice":"4.99","proceeds":"3.49","proceedsYear2":"4.24"}},{"type":"territories","id":"USA","attributes":{"currency":"USD"}}],"links":{"self":"https://api.example.test/v1/retentionOffers/ro-1/prices"}}"#
            ),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        // Invalid wait_between_offers_months (< 2) rejected before network access
        let invalidWait = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Bad Wait"),
                "offer_id": .string("BADWAIT"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("ONE_MONTH"),
                "period_count": .int(1),
                "eligibility_duration_months": .int(6),
                "wait_between_offers_months": .int(1),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(invalidWait.isError == true)

        // Invalid eligibility_duration_months (25 not in 1...24, 36, 48, 60) rejected before network access
        let invalidEligibility = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Bad Eligibility"),
                "offer_id": .string("BADELIG"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("ONE_MONTH"),
                "period_count": .int(1),
                "eligibility_duration_months": .int(25),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(invalidEligibility.isError == true)
        #expect(await transport.requestCount() == 0)

        let created = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("Loyal 6M Offer"),
                "offer_id": .string("LOYAL6M"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("THREE_MONTHS"),
                "period_count": .int(3),
                "eligibility_duration_months": .int(6),
                "wait_between_offers_months": .int(6),
                "target_subscription_plan_type": .string("MONTHLY"),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(created.isError != true)
        let createdOffer = try object(try object(created.structuredContent)["offer"])
        #expect(createdOffer["offerId"] == .string("LOYAL6M"))
        #expect(createdOffer["periodCount"] == .int(3))
        #expect(createdOffer["customerEligibilityPaidSubscriptionDurationInMonths"] == .int(6))
        #expect(createdOffer["customerEligibilityWaitBetweenOffersInMonths"] == .int(6))
        #expect(createdOffer["targetSubscriptionPlanType"] == .string("MONTHLY"))

        let createRequest = try #require(await transport.recordedRequests().first)
        let createBody = try jsonObject(from: try #require(createRequest.httpBody))
        let createData = try #require(createBody["data"] as? [String: Any])
        let createAttributes = try #require(createData["attributes"] as? [String: Any])
        #expect(createAttributes["referenceName"] as? String == "Loyal 6M Offer")
        #expect(createAttributes["offerId"] as? String == "LOYAL6M")
        #expect(createAttributes["duration"] as? String == "THREE_MONTHS")
        #expect(createAttributes["offerMode"] as? String == "PAY_AS_YOU_GO")
        #expect(createAttributes["periodCount"] as? Int == 3)
        #expect(createAttributes["customerEligibilityPaidSubscriptionDurationInMonths"] as? Int == 6)
        #expect(createAttributes["customerEligibilityWaitBetweenOffersInMonths"] as? Int == 6)
        #expect(createAttributes["targetSubscriptionPlanType"] as? String == "MONTHLY")
        #expect(createAttributes["periods"] == nil)
        #expect(createAttributes["eligibilitySubscriberDurationType"] == nil)
        #expect(createAttributes["eligibilitySubscriberDurationInMonths"] == nil)
        #expect(createAttributes["waitBetweenOffersInMonths"] == nil)

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
        let fetchedOffer = try object(try object(fetched.structuredContent)["offer"])
        #expect(fetchedOffer["referenceName"] == .string("Loyal 6M Offer"))
        #expect(fetchedOffer["offerId"] == .string("LOYAL6M"))
        #expect(fetchedOffer["duration"] == .string("THREE_MONTHS"))
        #expect(fetchedOffer["offerMode"] == .string("PAY_AS_YOU_GO"))
        #expect(fetchedOffer["periodCount"] == .int(3))
        #expect(fetchedOffer["customerEligibilityPaidSubscriptionDurationInMonths"] == .int(6))
        #expect(fetchedOffer["customerEligibilityWaitBetweenOffersInMonths"] == .int(6))
        #expect(fetchedOffer["targetSubscriptionPlanType"] == .string("MONTHLY"))

        let updated = try await worker.handleTool(.init(
            name: "subscriptions_update_retention_offer",
            arguments: [
                "offer_id": .string("ro-1"),
                "eligibility_duration_months": .int(12),
                "wait_between_offers_months": .null
            ]
        ))
        #expect(updated.isError != true)
        let updatedOffer = try object(try object(updated.structuredContent)["offer"])
        #expect(updatedOffer["customerEligibilityPaidSubscriptionDurationInMonths"] == .int(12))

        let prices = try await worker.handleTool(.init(
            name: "subscriptions_list_retention_offer_prices",
            arguments: ["offer_id": .string("ro-1"), "territory": .string("USA,GBR")]
        ))
        #expect(prices.isError != true)
        let pricesPayload = try object(prices.structuredContent)
        #expect(pricesPayload["count"] == .int(1))
        let firstPrice = try object(try #require(pricesPayload["prices"]?.arrayValue?.first))
        #expect(firstPrice["id"] == .string("rop-1"))
        #expect(firstPrice["territoryId"] == .string("USA"))
        #expect(firstPrice["territory_id"] == .string("USA"))
        #expect(firstPrice["subscriptionPricePointId"] == .string("pp-usa-1"))
        #expect(firstPrice["subscription_price_point_id"] == .string("pp-usa-1"))
        #expect(firstPrice["price_point_id"] == .string("pp-usa-1"))
        #expect(firstPrice["currency"] == .string("USD"))
        #expect(firstPrice["customerPrice"] == .string("4.99"))
        #expect(firstPrice["customer_price"] == .string("4.99"))
        #expect(firstPrice["proceeds"] == .string("3.49"))
        #expect(firstPrice["proceedsYear2"] == .string("4.24"))
        #expect(firstPrice["proceeds_year2"] == .string("4.24"))

        let deleted = try await worker.handleTool(.init(
            name: "subscriptions_delete_retention_offer",
            arguments: ["offer_id": .string("ro-1")]
        ))
        #expect(deleted.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests[1].url?.path == "/v1/subscriptions/sub-1/retentionOffers")
        #expect(requests[2].url?.path == "/v1/subscriptions/sub-1/retentionMessageOffers")
        let patchBody = try jsonObject(from: try #require(requests[4].httpBody))
        let patchAttributes = try #require((patchBody["data"] as? [String: Any])?["attributes"] as? [String: Any])
        #expect(patchAttributes["customerEligibilityPaidSubscriptionDurationInMonths"] as? Int == 12)
        #expect(patchAttributes["customerEligibilityWaitBetweenOffersInMonths"] is NSNull)
        #expect(patchAttributes["eligibilitySubscriberDurationType"] == nil)
        #expect(patchAttributes["eligibilitySubscriberDurationInMonths"] == nil)
        #expect(patchAttributes["waitBetweenOffersInMonths"] == nil)
        #expect(requests[5].url?.path == "/v1/retentionOffers/ro-1/prices")
        let pricesRequestURL = try #require(requests[5].url)
        let pricesQueryItems = try #require(URLComponents(url: pricesRequestURL, resolvingAgainstBaseURL: false)?.queryItems)
        let pricesQuery = Dictionary(uniqueKeysWithValues: pricesQueryItems.map { ($0.name, $0.value ?? "") })
        #expect(pricesQuery["filter[territory]"] == "USA,GBR")
        #expect(pricesQuery["include"] == "territory,subscriptionPricePoint")
        #expect(pricesQuery["fields[retentionOfferPrices]"] == "territory,subscriptionPricePoint")
        #expect(pricesQuery["fields[subscriptionPricePoints]"] == "customerPrice,proceeds,proceedsYear2,territory")
        #expect(pricesQuery["fields[territories]"] == "currency")
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

    @Test("AssetsWorker reads to-one retentionMessageVersion placement across multiple pages and rejects foreign app, video, and reordering")
    func assetsWorkerRetentionMessageVersionSupport() async throws {
        let versionDoc = #"{"data":{"type":"retentionMessageVersions","id":"ver-1","attributes":{"version":1,"state":"PREPARE_FOR_SUBMISSION"},"relationships":{"retentionMessage":{"data":{"type":"retentionMessages","id":"msg-1"}}}}}"#
        let appMessagesPage1Doc = #"{"data":[{"type":"retentionMessages","id":"msg-other-1","attributes":{"referenceName":"Other 1"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}},{"type":"retentionMessages","id":"msg-other-2","attributes":{"referenceName":"Other 2"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/retentionMessages?limit=200","next":"https://api.appstoreconnect.apple.com/v1/apps/app-1/retentionMessages?cursor=page-2&limit=200"},"meta":{"paging":{"total":3,"limit":200}}}"#
        let appMessagesPage2Doc = #"{"data":[{"type":"retentionMessages","id":"msg-1","attributes":{"referenceName":"Stay With Us"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-1/retentionMessages?cursor=page-2&limit=200"},"meta":{"paging":{"total":3,"limit":200}}}"#
        let foreignMessagesPage1Doc = #"{"data":[{"type":"retentionMessages","id":"msg-foreign-1","attributes":{"referenceName":"Foreign 1"},"relationships":{"app":{"data":{"type":"apps","id":"app-foreign"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-foreign/retentionMessages?limit=200","next":"https://api.appstoreconnect.apple.com/v1/apps/app-foreign/retentionMessages?cursor=page-2&limit=200"},"meta":{"paging":{"total":2,"limit":200}}}"#
        let foreignMessagesPage2Doc = #"{"data":[{"type":"retentionMessages","id":"msg-foreign-2","attributes":{"referenceName":"Foreign 2"},"relationships":{"app":{"data":{"type":"apps","id":"app-foreign"}}}}],"links":{"self":"https://api.appstoreconnect.apple.com/v1/apps/app-foreign/retentionMessages?cursor=page-2&limit=200"},"meta":{"paging":{"total":2,"limit":200}}}"#
        let placementDoc = #"{"data":{"type":"appAssetLibraryPlacements","id":"pl-1","attributes":{"placementType":"retentionImage","placementGroup":"retentionGroup"},"relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"img-1"}},"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"ver-1"}}}}}"#

        let transport = TestHTTPTransport(responses: [
            // 1. Own app (app-1) with target message on page 2 -> empty to-one placement
            .init(statusCode: 200, body: versionDoc),
            .init(statusCode: 200, body: appMessagesPage1Doc),
            .init(statusCode: 200, body: appMessagesPage2Doc),
            .init(statusCode: 200, body: #"{"data":null}"#),
            // 2. Own app (app-1) with target message on page 2 -> populated to-one placement
            .init(statusCode: 200, body: versionDoc),
            .init(statusCode: 200, body: appMessagesPage1Doc),
            .init(statusCode: 200, body: appMessagesPage2Doc),
            .init(statusCode: 200, body: placementDoc),
            // 3. Foreign app (app-foreign) -> rejected after scanning pages without msg-1
            .init(statusCode: 200, body: versionDoc),
            .init(statusCode: 200, body: foreignMessagesPage1Doc),
            .init(statusCode: 200, body: foreignMessagesPage2Doc)
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

        // Empty to-one placement returns 0 items when target retention message is on page 2
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

        // Populated to-one placement returns 1 item when target retention message is on page 2
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

        // Foreign app is rejected when target retention message is not among its retention messages
        let foreignRejected = try await worker.handleTool(.init(
            name: "assets_list_placements",
            arguments: [
                "app_id": .string("app-foreign"),
                "target_type": .string("retentionMessageVersion"),
                "target_id": .string("ver-1")
            ]
        ))
        #expect(foreignRejected.isError == true)

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

        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 11)
        #expect(recorded[1].url?.path == "/v1/apps/app-1/retentionMessages")
        #expect(recorded[1].url?.query?.contains("filter") != true)
        #expect(recorded[2].url?.path == "/v1/apps/app-1/retentionMessages")
        #expect(recorded[2].url?.query?.contains("cursor=page-2") == true)
        #expect(recorded[2].url?.query?.contains("filter") != true)
        #expect(recorded[9].url?.path == "/v1/apps/app-foreign/retentionMessages")
        #expect(recorded[10].url?.path == "/v1/apps/app-foreign/retentionMessages")
        #expect(recorded[10].url?.query?.contains("cursor=page-2") == true)
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

    // MARK: - 7. Retention List Pagination (All 14 Combinations + Scope Rejections)

    @Test("retention list handlers support absolute and root-relative next_url across all 7 endpoints and reject out-of-scope pagination links")
    func retentionListPaginationAllCombinationsAndRejections() async throws {
        let messagesDoc = #"{"data":[{"type":"retentionMessages","id":"msg-2","attributes":{"referenceName":"Page 2"}}],"links":{"self":"https://api.example.test/v1/apps/app-1/retentionMessages?cursor=page-2"}}"#
        let versionsDoc = #"{"data":[{"type":"retentionMessageVersions","id":"ver-2","attributes":{"version":2,"state":"READY_FOR_REVIEW"}}],"links":{"self":"https://api.example.test/v1/retentionMessages/msg-1/versions?cursor=page-2"}}"#
        let localizationsDoc = #"{"data":[{"type":"retentionMessageLocalizations","id":"loc-2","attributes":{"locale":"ja","header":"継続特典","body":"すべての機能を引き続きご利用いただけます。"}}],"links":{"self":"https://api.example.test/v1/retentionMessageVersions/ver-1/localizations?cursor=page-2"}}"#
        let subscriptionsDoc = #"{"data":[{"type":"subscriptions","id":"sub-2","attributes":{"name":"Pro Annual","productId":"com.example.annual","state":"APPROVED","subscriptionPeriod":"ONE_YEAR"}}],"links":{"self":"https://api.example.test/v1/retentionMessages/msg-1/subscriptions?cursor=page-2"}}"#
        let offersDoc = #"{"data":[{"type":"retentionOffers","id":"ro-2","attributes":{"referenceName":"Page 2 Offer","offerId":"OFFER2","duration":"ONE_MONTH","offerMode":"PAY_AS_YOU_GO","periodCount":1,"customerEligibilityPaidSubscriptionDurationInMonths":6}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionOffers?cursor=page-2"}}"#
        let messageOffersDoc = #"{"data":[{"type":"retentionOffers","id":"ro-3","attributes":{"referenceName":"Page 2 Message Offer","offerId":"MSGOFFER2","duration":"ONE_MONTH","offerMode":"PAY_AS_YOU_GO","periodCount":1,"customerEligibilityPaidSubscriptionDurationInMonths":6}}],"links":{"self":"https://api.example.test/v1/subscriptions/sub-1/retentionMessageOffers?cursor=page-2"}}"#
        let pricesDoc = #"{"data":[{"type":"retentionOfferPrices","id":"rop-2","relationships":{"territory":{"data":{"type":"territories","id":"USA"}},"subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"pp-usa-2"}}}}],"included":[{"type":"subscriptionPricePoints","id":"pp-usa-2","attributes":{"customerPrice":"2.99","proceeds":"2.10","proceedsYear2":"2.54"}},{"type":"territories","id":"USA","attributes":{"currency":"USD"}}],"links":{"self":"https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2"}}"#

        // 1. Negative checks before any HTTP I/O
        let negativeTransport = TestHTTPTransport(responses: [])
        let negativeWorker = try await makeSubscriptionsWorker(transport: negativeTransport)

        let negativeCases: [(String, [String: Value])] = [
            // Wrong parent ID
            (
                "subscriptions_list_retention_messages",
                ["app_id": .string("app-1"), "next_url": .string("https://api.example.test/v1/apps/app-other/retentionMessages?cursor=page-2")]
            ),
            // Wrong endpoint (retentionOffers when message_offers_only is true)
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(true),
                    "next_url": .string("https://api.example.test/v1/subscriptions/sub-1/retentionOffers?cursor=page-2")
                ]
            ),
            // Wrong endpoint (retentionMessageOffers when message_offers_only is false)
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(false),
                    "next_url": .string("/v1/subscriptions/sub-1/retentionMessageOffers?cursor=page-2")
                ]
            ),
            // Missing cursor
            (
                "subscriptions_list_retention_message_versions",
                ["retention_message_id": .string("msg-1"), "next_url": .string("https://api.example.test/v1/retentionMessages/msg-1/versions?limit=10")]
            ),
            // Empty cursor
            (
                "subscriptions_list_retention_message_localizations",
                ["version_id": .string("ver-1"), "next_url": .string("/v1/retentionMessageVersions/ver-1/localizations?cursor=")]
            ),
            // Unrequested filter[territory] when territory argument was omitted
            (
                "subscriptions_list_retention_offer_prices",
                ["offer_id": .string("ro-1"), "next_url": .string("https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2&filter%5Bterritory%5D=USA")]
            ),
            // Changed filter[territory] when territory argument was provided
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "territory": .string("USA"),
                    "next_url": .string("https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2&filter%5Bterritory%5D=GBR")
                ]
            ),
            // Missing filter[territory] in next_url when territory argument was provided
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "territory": .string("USA"),
                    "next_url": .string("/v1/retentionOffers/ro-1/prices?cursor=page-2")
                ]
            ),
            // Tampered include in next_url
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "next_url": .string("https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2&include=subscription")
                ]
            )
        ]

        for (toolName, arguments) in negativeCases {
            let result = try await negativeWorker.handleTool(.init(name: toolName, arguments: arguments))
            #expect(result.isError == true, "Expected \(toolName) with \(arguments) to be rejected before HTTP I/O")
        }
        #expect(await negativeTransport.requestCount() == 0)

        // 2. Positive checks across all 14 combinations (7 endpoints x absolute + root-relative) plus filtered prices
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: messagesDoc),
            .init(statusCode: 200, body: messagesDoc),
            .init(statusCode: 200, body: versionsDoc),
            .init(statusCode: 200, body: versionsDoc),
            .init(statusCode: 200, body: localizationsDoc),
            .init(statusCode: 200, body: localizationsDoc),
            .init(statusCode: 200, body: subscriptionsDoc),
            .init(statusCode: 200, body: subscriptionsDoc),
            .init(statusCode: 200, body: offersDoc),
            .init(statusCode: 200, body: offersDoc),
            .init(statusCode: 200, body: messageOffersDoc),
            .init(statusCode: 200, body: messageOffersDoc),
            .init(statusCode: 200, body: pricesDoc),
            .init(statusCode: 200, body: pricesDoc),
            .init(statusCode: 200, body: pricesDoc)
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        let positiveCases: [(String, [String: Value], String)] = [
            // 1-2: subscriptions_list_retention_messages
            (
                "subscriptions_list_retention_messages",
                ["app_id": .string("app-1"), "next_url": .string("https://api.example.test/v1/apps/app-1/retentionMessages?cursor=page-2")],
                "/v1/apps/app-1/retentionMessages"
            ),
            (
                "subscriptions_list_retention_messages",
                ["app_id": .string("app-1"), "next_url": .string("/v1/apps/app-1/retentionMessages?cursor=page-2")],
                "/v1/apps/app-1/retentionMessages"
            ),
            // 3-4: subscriptions_list_retention_message_versions
            (
                "subscriptions_list_retention_message_versions",
                ["retention_message_id": .string("msg-1"), "next_url": .string("https://api.example.test/v1/retentionMessages/msg-1/versions?cursor=page-2")],
                "/v1/retentionMessages/msg-1/versions"
            ),
            (
                "subscriptions_list_retention_message_versions",
                ["retention_message_id": .string("msg-1"), "next_url": .string("/v1/retentionMessages/msg-1/versions?cursor=page-2")],
                "/v1/retentionMessages/msg-1/versions"
            ),
            // 5-6: subscriptions_list_retention_message_localizations
            (
                "subscriptions_list_retention_message_localizations",
                ["version_id": .string("ver-1"), "next_url": .string("https://api.example.test/v1/retentionMessageVersions/ver-1/localizations?cursor=page-2")],
                "/v1/retentionMessageVersions/ver-1/localizations"
            ),
            (
                "subscriptions_list_retention_message_localizations",
                ["version_id": .string("ver-1"), "next_url": .string("/v1/retentionMessageVersions/ver-1/localizations?cursor=page-2")],
                "/v1/retentionMessageVersions/ver-1/localizations"
            ),
            // 7-8: subscriptions_list_retention_message_subscriptions
            (
                "subscriptions_list_retention_message_subscriptions",
                ["retention_message_id": .string("msg-1"), "next_url": .string("https://api.example.test/v1/retentionMessages/msg-1/subscriptions?cursor=page-2")],
                "/v1/retentionMessages/msg-1/subscriptions"
            ),
            (
                "subscriptions_list_retention_message_subscriptions",
                ["retention_message_id": .string("msg-1"), "next_url": .string("/v1/retentionMessages/msg-1/subscriptions?cursor=page-2")],
                "/v1/retentionMessages/msg-1/subscriptions"
            ),
            // 9-10: subscriptions_list_retention_offers (message_offers_only: false)
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(false),
                    "next_url": .string("https://api.example.test/v1/subscriptions/sub-1/retentionOffers?cursor=page-2")
                ],
                "/v1/subscriptions/sub-1/retentionOffers"
            ),
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(false),
                    "next_url": .string("/v1/subscriptions/sub-1/retentionOffers?cursor=page-2")
                ],
                "/v1/subscriptions/sub-1/retentionOffers"
            ),
            // 11-12: subscriptions_list_retention_offers (message_offers_only: true)
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(true),
                    "next_url": .string("https://api.example.test/v1/subscriptions/sub-1/retentionMessageOffers?cursor=page-2")
                ],
                "/v1/subscriptions/sub-1/retentionMessageOffers"
            ),
            (
                "subscriptions_list_retention_offers",
                [
                    "subscription_id": .string("sub-1"),
                    "message_offers_only": .bool(true),
                    "next_url": .string("/v1/subscriptions/sub-1/retentionMessageOffers?cursor=page-2")
                ],
                "/v1/subscriptions/sub-1/retentionMessageOffers"
            ),
            // 13-14: subscriptions_list_retention_offer_prices (absolute with full query + root-relative minimal query)
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "next_url": .string("https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2&include=territory,subscriptionPricePoint&fields%5BretentionOfferPrices%5D=territory,subscriptionPricePoint&fields%5BsubscriptionPricePoints%5D=customerPrice,proceeds,proceedsYear2,territory&fields%5Bterritories%5D=currency")
                ],
                "/v1/retentionOffers/ro-1/prices"
            ),
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "next_url": .string("/v1/retentionOffers/ro-1/prices?cursor=page-2")
                ],
                "/v1/retentionOffers/ro-1/prices"
            ),
            // 15: subscriptions_list_retention_offer_prices with territory filter preserved in next_url
            (
                "subscriptions_list_retention_offer_prices",
                [
                    "offer_id": .string("ro-1"),
                    "territory": .string("USA,GBR"),
                    "next_url": .string("https://api.example.test/v1/retentionOffers/ro-1/prices?cursor=page-2&filter%5Bterritory%5D=GBR,USA")
                ],
                "/v1/retentionOffers/ro-1/prices"
            )
        ]

        for (index, (toolName, arguments, _)) in positiveCases.enumerated() {
            let result = try await worker.handleTool(.init(name: toolName, arguments: arguments))
            #expect(result.isError != true, "Case \(index) (\(toolName)) failed: \(result.content)")
            let payload = try object(result.structuredContent)
            #expect(payload["count"] == .int(1))
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == 15)
        for (index, (_, _, expectedPath)) in positiveCases.enumerated() {
            #expect(requests[index].url?.path == expectedPath)
            #expect(requests[index].url?.query?.contains("cursor=page-2") == true)
        }
    }

    // MARK: - 8. Plane 2 CJK Ideographs vs Emoji Validation

    @Test("retention copy and reference_name validation accepts Plane 2 CJK ideographs and rejects emojis")
    func plane2CJKAcceptedAndEmojisRejected() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionMessageLocalizations","id":"loc-ja-1","attributes":{"locale":"ja","header":"𠮷野の便利な機能を継続","body":"𠮟咤激励の機能も引き続きご利用いただけます。"},"relationships":{"retentionMessageVersion":{"data":{"type":"retentionMessageVersions","id":"ver-1"}}}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"retentionMessageLocalizations","id":"loc-ja-1","attributes":{"locale":"ja","header":"𠮷野の便利な機能を継続","body":"𠮟咤激励の機能も引き続きご利用いただけます。"}}}"#
            ),
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionMessages","id":"msg-ja-1","attributes":{"referenceName":"𠮷野キャンペーン"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
            ),
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"retentionOffers","id":"ro-ja-1","attributes":{"referenceName":"𠮷野キャンペーン","offerId":"YOSHINO1","duration":"ONE_MONTH","offerMode":"PAY_AS_YOU_GO","periodCount":1,"customerEligibilityPaidSubscriptionDurationInMonths":6}}}"#
            )
        ])
        let worker = try await makeSubscriptionsWorker(transport: transport)

        // Real emojis rejected before network access
        for emojiHeader in ["キャンペーン🎉", "特典🔥", "継続✨", "限定❤️", "夏休み☀️"] {
            let rejected = try await worker.handleTool(.init(
                name: "subscriptions_create_retention_message_localization",
                arguments: [
                    "version_id": .string("ver-1"),
                    "locale": .string("ja"),
                    "header": .string(emojiHeader),
                    "body": .string("引き続きご利用いただけます。")
                ]
            ))
            #expect(rejected.isError == true, "Expected emoji header '\(emojiHeader)' to be rejected")
        }

        let rejectedMessageRef = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("キャンペーン🔥")
            ]
        ))
        #expect(rejectedMessageRef.isError == true)

        let rejectedOfferRef = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("キャンペーン🔥"),
                "offer_id": .string("YOSHINO1"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("ONE_MONTH"),
                "period_count": .int(1),
                "eligibility_duration_months": .int(6),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(rejectedOfferRef.isError == true)
        #expect(await transport.requestCount() == 0)

        // Plane 2 CJK Unified Ideographs Extension B (𠮷 U+20BB7, 𠮟 U+20B9F) accepted
        let createdLoc = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message_localization",
            arguments: [
                "version_id": .string("ver-1"),
                "locale": .string("ja"),
                "header": .string("𠮷野の便利な機能を継続"),
                "body": .string("𠮟咤激励の機能も引き続きご利用いただけます。")
            ]
        ))
        #expect(createdLoc.isError != true)
        let locPayload = try object(try object(createdLoc.structuredContent)["localization"])
        #expect(locPayload["header"] == .string("𠮷野の便利な機能を継続"))
        #expect(locPayload["body"] == .string("𠮟咤激励の機能も引き続きご利用いただけます。"))

        let updatedLoc = try await worker.handleTool(.init(
            name: "subscriptions_update_retention_message_localization",
            arguments: [
                "localization_id": .string("loc-ja-1"),
                "header": .string("𠮷野の便利な機能を継続"),
                "body": .string("𠮟咤激励の機能も引き続きご利用いただけます。")
            ]
        ))
        #expect(updatedLoc.isError != true)

        let createdMessage = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_message",
            arguments: [
                "app_id": .string("app-1"),
                "reference_name": .string("𠮷野キャンペーン")
            ]
        ))
        #expect(createdMessage.isError != true)

        let createdOffer = try await worker.handleTool(.init(
            name: "subscriptions_create_retention_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "reference_name": .string("𠮷野キャンペーン"),
                "offer_id": .string("YOSHINO1"),
                "offer_mode": .string("PAY_AS_YOU_GO"),
                "duration": .string("ONE_MONTH"),
                "period_count": .int(1),
                "eligibility_duration_months": .int(6),
                "price_point_ids": .array([.string("pp-usa-1")]),
                "territory_ids": .array([.string("USA")])
            ]
        ))
        #expect(createdOffer.isError != true)
        #expect(await transport.requestCount() == 4)
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
