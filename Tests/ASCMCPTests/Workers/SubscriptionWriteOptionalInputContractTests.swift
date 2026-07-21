import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscription Write Optional Input Contracts")
struct SubscriptionWriteOptionalInputContractTests {
    @Test("write schemas expose nullable Apple 4.4.1 inputs")
    func schemasExposeNullableInputs() async throws {
        let worker = try await subscriptionOptionalWorker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let intro = try #require(tools.first { $0.name == "subscriptions_create_intro_offer" })
        let introProperties = try subscriptionOptionalProperties(intro)
        #expect(try subscriptionOptionalTypes(introProperties["start_date"]) == ["null", "string"])
        #expect(try subscriptionOptionalTypes(introProperties["end_date"]) == ["null", "string"])
        #expect(try subscriptionOptionalEnum(introProperties["target_subscription_plan_type"]) == [.null, .string("MONTHLY"), .string("UPFRONT")])

        let price = try #require(tools.first { $0.name == "subscriptions_create_price" })
        let priceSchema = try subscriptionOptionalObject(price.inputSchema)
        let priceProperties = try subscriptionOptionalProperties(price)
        #expect(Set(try subscriptionOptionalArray(priceSchema["required"]).compactMap(\.stringValue)) == ["subscription_id", "price_point_id"])
        #expect(try subscriptionOptionalTypes(priceProperties["plan_type"]) == ["null", "string"])
        #expect(try subscriptionOptionalEnum(priceProperties["plan_type"]) == [.null, .string("MONTHLY"), .string("UPFRONT")])
        #expect(try subscriptionOptionalTypes(priceProperties["preserve_current_price"]) == ["boolean", "null"])

        let create = try #require(tools.first { $0.name == "subscriptions_create" })
        let createSchema = try subscriptionOptionalObject(create.inputSchema)
        let createProperties = try subscriptionOptionalProperties(create)
        #expect(Set(try subscriptionOptionalArray(createSchema["required"]).compactMap(\.stringValue)) == ["group_id", "name", "product_id"])
        #expect(try subscriptionOptionalTypes(createProperties["subscription_period"]) == ["null", "string"])
        #expect(try subscriptionOptionalTypes(createProperties["family_sharable"]) == ["boolean", "null"])
        #expect(try subscriptionOptionalTypes(createProperties["group_level"]) == ["integer", "null"])
        #expect(try subscriptionOptionalTypes(createProperties["review_note"]) == ["null", "string"])

        let update = try #require(tools.first { $0.name == "subscriptions_update" })
        let updateSchema = try subscriptionOptionalObject(update.inputSchema)
        let updateProperties = try subscriptionOptionalProperties(update)
        #expect(updateSchema["minProperties"] == .int(2))
        #expect(updateSchema["additionalProperties"] == .bool(false))
        #expect(try subscriptionOptionalTypes(updateProperties["name"]) == ["null", "string"])
        #expect(try subscriptionOptionalTypes(updateProperties["family_sharable"]) == ["boolean", "null"])
        #expect(try subscriptionOptionalTypes(updateProperties["group_level"]) == ["integer", "null"])
        #expect(try subscriptionOptionalTypes(updateProperties["review_note"]) == ["null", "string"])
        #expect(try subscriptionOptionalTypes(updateProperties["subscription_period"]) == ["null", "string"])
        #expect(try subscriptionOptionalEnum(updateProperties["subscription_period"]) == [
            .null,
            .string("ONE_MONTH"),
            .string("ONE_WEEK"),
            .string("ONE_YEAR"),
            .string("SIX_MONTHS"),
            .string("THREE_MONTHS"),
            .string("TWO_MONTHS")
        ])

        for (toolName, field) in [
            ("subscriptions_update_intro_offer", "end_date"),
            ("subscriptions_update_offer_code", "active"),
            ("subscriptions_update_custom_code", "active")
        ] {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try subscriptionOptionalObject(tool.inputSchema)
            let properties = try subscriptionOptionalProperties(tool)
            #expect(Set(try subscriptionOptionalArray(root["required"]).compactMap(\.stringValue)).contains(field))
            #expect(try subscriptionOptionalTypes(properties[field]).contains("null"))
        }
    }

    @Test("introductory offer preserves concrete and null optional attributes")
    func introductoryOfferPreservesTriState() async throws {
        let response = #"{"data":{"type":"subscriptionIntroductoryOffers","id":"intro-1","attributes":{"duration":"ONE_MONTH","offerMode":"FREE_TRIAL","numberOfPeriods":1,"startDate":"2026-08-01","endDate":"2026-12-31","targetSubscriptionPlanType":"MONTHLY"}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: response),
            .init(statusCode: 201, body: response),
            .init(statusCode: 201, body: response)
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let concrete = try await worker.handleTool(.init(
            name: "subscriptions_create_intro_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "number_of_periods": .int(1),
                "start_date": .string("2026-08-01"),
                "end_date": .string("2026-12-31"),
                "target_subscription_plan_type": .string("MONTHLY")
            ]
        ))
        #expect(concrete.isError != true)

        let cleared = try await worker.handleTool(.init(
            name: "subscriptions_create_intro_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "number_of_periods": .int(1),
                "start_date": .null,
                "end_date": .null,
                "target_subscription_plan_type": .null
            ]
        ))
        #expect(cleared.isError != true)

        let omitted = try await worker.handleTool(.init(
            name: "subscriptions_create_intro_offer",
            arguments: [
                "subscription_id": .string("sub-1"),
                "duration": .string("ONE_MONTH"),
                "offer_mode": .string("FREE_TRIAL"),
                "number_of_periods": .int(1)
            ]
        ))
        #expect(omitted.isError != true)

        let recordedBodies = await transport.recordedBodyStrings()
        let bodies = try recordedBodies.map(subscriptionOptionalBody)
        let concreteAttributes = try subscriptionOptionalAttributes(bodies[0])
        #expect(concreteAttributes["startDate"] as? String == "2026-08-01")
        #expect(concreteAttributes["endDate"] as? String == "2026-12-31")
        #expect(concreteAttributes["targetSubscriptionPlanType"] as? String == "MONTHLY")
        let concreteResult = try subscriptionOptionalResultObject(concrete)
        let concreteOffer = try #require(concreteResult["introductory_offer"] as? [String: Any])
        #expect(concreteOffer["startDate"] as? String == "2026-08-01")
        #expect(concreteOffer["endDate"] as? String == "2026-12-31")
        #expect(concreteOffer["targetSubscriptionPlanType"] as? String == "MONTHLY")
        let clearedAttributes = try subscriptionOptionalAttributes(bodies[1])
        #expect(clearedAttributes["startDate"] is NSNull)
        #expect(clearedAttributes["endDate"] is NSNull)
        #expect(clearedAttributes["targetSubscriptionPlanType"] is NSNull)
        let omittedAttributes = try subscriptionOptionalAttributes(bodies[2])
        #expect(omittedAttributes["startDate"] == nil)
        #expect(omittedAttributes["endDate"] == nil)
        #expect(omittedAttributes["targetSubscriptionPlanType"] == nil)
    }

    @Test("subscription creation preserves omitted and explicit null optional attributes")
    func subscriptionCreationPreservesTriState() async throws {
        let response = #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{"name":"Premium","productId":"premium"}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: response),
            .init(statusCode: 201, body: response)
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let omitted = try await worker.handleTool(.init(
            name: "subscriptions_create",
            arguments: [
                "group_id": .string("group-1"),
                "name": .string("Premium"),
                "product_id": .string("premium")
            ]
        ))
        let cleared = try await worker.handleTool(.init(
            name: "subscriptions_create",
            arguments: [
                "group_id": .string("group-1"),
                "name": .string("Premium"),
                "product_id": .string("premium"),
                "subscription_period": .null,
                "family_sharable": .null,
                "group_level": .null,
                "review_note": .null
            ]
        ))
        let invalid = try await worker.handleTool(.init(
            name: "subscriptions_create",
            arguments: [
                "group_id": .string("group-1"),
                "name": .string("Premium"),
                "product_id": .string("premium"),
                "subscription_period": .string("DAILY")
            ]
        ))

        #expect(omitted.isError != true)
        #expect(cleared.isError != true)
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 2)
        let bodyStrings = await transport.recordedBodyStrings()
        let bodies = try bodyStrings.map(subscriptionOptionalBody)
        let omittedAttributes = try subscriptionOptionalAttributes(bodies[0])
        #expect(omittedAttributes["subscriptionPeriod"] == nil)
        #expect(omittedAttributes["familySharable"] == nil)
        #expect(omittedAttributes["groupLevel"] == nil)
        #expect(omittedAttributes["reviewNote"] == nil)
        let clearedAttributes = try subscriptionOptionalAttributes(bodies[1])
        #expect(clearedAttributes["subscriptionPeriod"] is NSNull)
        #expect(clearedAttributes["familySharable"] is NSNull)
        #expect(clearedAttributes["groupLevel"] is NSNull)
        #expect(clearedAttributes["reviewNote"] is NSNull)
    }

    @Test("subscription price preserves plan, preservation flag, and explicit null date")
    func subscriptionPricePreservesTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"subscriptionPrices","id":"price-1","attributes":{}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"subscriptionPrices","id":"price-1","attributes":{}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"subscriptionPrices","id":"price-1","attributes":{}}}"#)
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "start_date": .string("2026-08-01"),
                "plan_type": .string("UPFRONT"),
                "preserve_current_price": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        let attributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(body))
        #expect(attributes["startDate"] as? String == "2026-08-01")
        #expect(attributes["planType"] as? String == "UPFRONT")
        #expect(attributes["preserveCurrentPrice"] as? Bool == true)

        let cleared = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "start_date": .null,
                "plan_type": .null,
                "preserve_current_price": .null
            ]
        ))
        #expect(cleared.isError != true)
        let clearedBodies = await transport.recordedBodyStrings()
        let clearedBody = try subscriptionOptionalBody(clearedBodies[1])
        let clearedAttributes = try subscriptionOptionalAttributes(clearedBody)
        #expect(clearedAttributes["startDate"] is NSNull)
        #expect(clearedAttributes["planType"] is NSNull)
        #expect(clearedAttributes["preserveCurrentPrice"] is NSNull)

        let omitted = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "price_point_id": .string("point-1")
            ]
        ))
        #expect(omitted.isError != true)
        let omittedBody = try #require(await transport.recordedBodyStrings().last)
        let parsedOmittedBody = try subscriptionOptionalBody(omittedBody)
        let omittedAttributes = try subscriptionOptionalAttributes(parsedOmittedBody)
        #expect(omittedAttributes.isEmpty)
        let omittedRelationships = try subscriptionOptionalRelationships(parsedOmittedBody)
        #expect(Set(omittedRelationships.keys) == ["subscription", "subscriptionPricePoint"])
    }

    @Test("introductory offer list requests and projects the target plan type")
    func introductoryOfferListProjectsTargetPlanType() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"subscriptionIntroductoryOffers","id":"intro-1","attributes":{"startDate":"2026-08-01","endDate":null,"targetSubscriptionPlanType":"UPFRONT","duration":"ONE_MONTH","offerMode":"PAY_UP_FRONT","numberOfPeriods":1}}]}"#
            )
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_list_intro_offers",
            arguments: ["subscription_id": .string("sub-1")]
        ))

        #expect(result.isError != true)
        let root = try subscriptionOptionalObject(result.structuredContent)
        let offers = try subscriptionOptionalArray(root["introductory_offers"])
        let offer = try subscriptionOptionalObject(try #require(offers.first))
        #expect(offer["target_subscription_plan_type"] == .string("UPFRONT"))
        #expect(offer["start_date"] == .string("2026-08-01"))
        #expect(offer["end_date"] == .null)

        let request = try #require(await transport.recordedRequests().first)
        let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(
            query["fields[subscriptionIntroductoryOffers]"] ==
                "startDate,endDate,targetSubscriptionPlanType,duration,offerMode,numberOfPeriods,territory,subscriptionPricePoint"
        )
    }

    @Test("introductory offer and price reject malformed optional inputs before transport")
    func malformedOptionalInputsDoNotReachTransport() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionOptionalWorker(transport)
        let introBase: [String: Value] = [
            "subscription_id": .string("sub-1"),
            "duration": .string("ONE_MONTH"),
            "offer_mode": .string("FREE_TRIAL"),
            "number_of_periods": .int(1)
        ]
        var invalidDate = introBase
        invalidDate["start_date"] = .string("2026-02-30")
        var reversedDates = introBase
        reversedDates["start_date"] = .string("2026-12-31")
        reversedDates["end_date"] = .string("2026-08-01")
        var invalidTargetPlan = introBase
        invalidTargetPlan["target_subscription_plan_type"] = .string("ANNUAL")

        var introResults: [CallTool.Result] = []
        for arguments in [invalidDate, reversedDates, invalidTargetPlan] {
            introResults.append(try await worker.handleTool(.init(
                name: "subscriptions_create_intro_offer",
                arguments: arguments
            )))
        }
        let invalidPricePlan = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "plan_type": .string("ANNUAL")
            ]
        ))
        let invalidPriceDate = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "start_date": .string("2026-02-30")
            ]
        ))
        let invalidPreservation = try await worker.handleTool(.init(
            name: "subscriptions_create_price",
            arguments: [
                "subscription_id": .string("sub-1"),
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1"),
                "preserve_current_price": .string("true")
            ]
        ))

        #expect(introResults.allSatisfy { $0.isError == true })
        #expect(invalidPricePlan.isError == true)
        #expect(invalidPriceDate.isError == true)
        #expect(invalidPreservation.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("subscription update preserves period null and rejects no-op or malformed writes")
    func subscriptionUpdateValidatesBeforeTransport() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{}}}"#)
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let noOp = try await worker.handleTool(.init(
            name: "subscriptions_update",
            arguments: ["subscription_id": .string("sub-1")]
        ))
        let invalid = try await worker.handleTool(.init(
            name: "subscriptions_update",
            arguments: ["subscription_id": .string("sub-1"), "subscription_period": .string("DAILY")]
        ))
        #expect(noOp.isError == true)
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 0)

        let clear = try await worker.handleTool(.init(
            name: "subscriptions_update",
            arguments: [
                "subscription_id": .string("sub-1"),
                "name": .null,
                "family_sharable": .null,
                "group_level": .null,
                "review_note": .null,
                "subscription_period": .null
            ]
        ))
        #expect(clear.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        let clearAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(body))
        #expect(clearAttributes["name"] is NSNull)
        #expect(clearAttributes["familySharable"] is NSNull)
        #expect(clearAttributes["groupLevel"] is NSNull)
        #expect(clearAttributes["reviewNote"] is NSNull)
        #expect(clearAttributes["subscriptionPeriod"] is NSNull)

        let concrete = try await worker.handleTool(.init(
            name: "subscriptions_update",
            arguments: ["subscription_id": .string("sub-1"), "subscription_period": .string("ONE_MONTH")]
        ))
        #expect(concrete.isError != true)
        let concreteBodies = await transport.recordedBodyStrings()
        let concreteBody = try subscriptionOptionalBody(concreteBodies[1])
        let concreteAttributes = try subscriptionOptionalAttributes(concreteBody)
        #expect(concreteAttributes["subscriptionPeriod"] as? String == "ONE_MONTH")

        let omitted = try await worker.handleTool(.init(
            name: "subscriptions_update",
            arguments: ["subscription_id": .string("sub-1"), "name": .string("Premium")]
        ))
        #expect(omitted.isError != true)
        let omittedBody = try #require(await transport.recordedBodyStrings().last)
        let omittedAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(omittedBody))
        #expect(omittedAttributes["subscriptionPeriod"] == nil)
    }

    @Test("introductory and code updates preserve explicit null and reject no-op")
    func commerceUpdatesPreserveExplicitNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptionIntroductoryOffers","id":"intro-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptionOfferCodes","id":"offer-1","attributes":{}}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"subscriptionOfferCodeCustomCodes","id":"custom-1","attributes":{}}}"#)
        ])
        let worker = try await subscriptionOptionalWorker(transport)

        let intro = try await worker.handleTool(.init(
            name: "subscriptions_update_intro_offer",
            arguments: ["intro_offer_id": .string("intro-1"), "end_date": .null]
        ))
        let offer = try await worker.handleTool(.init(
            name: "subscriptions_update_offer_code",
            arguments: ["offer_code_id": .string("offer-1"), "active": .null]
        ))
        let custom = try await worker.handleTool(.init(
            name: "subscriptions_update_custom_code",
            arguments: ["custom_code_id": .string("custom-1"), "active": .null]
        ))
        let missingIntro = try await worker.handleTool(.init(
            name: "subscriptions_update_intro_offer",
            arguments: ["intro_offer_id": .string("intro-1")]
        ))
        let missingOffer = try await worker.handleTool(.init(
            name: "subscriptions_update_offer_code",
            arguments: ["offer_code_id": .string("offer-1")]
        ))
        let missingCustom = try await worker.handleTool(.init(
            name: "subscriptions_update_custom_code",
            arguments: ["custom_code_id": .string("custom-1")]
        ))

        #expect(intro.isError != true)
        #expect(offer.isError != true)
        #expect(custom.isError != true)
        #expect(missingIntro.isError == true)
        #expect(missingOffer.isError == true)
        #expect(missingCustom.isError == true)
        #expect(await transport.requestCount() == 3)
        let bodies = await transport.recordedBodyStrings()
        let introAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(bodies[0]))
        let offerAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(bodies[1]))
        let customAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(bodies[2]))
        #expect(introAttributes["endDate"] is NSNull)
        #expect(offerAttributes["active"] is NSNull)
        #expect(customAttributes["active"] is NSNull)
    }

    @Test("manifest classifies nullable subscription write inputs")
    func manifestClassifiesOptionalWriteInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: (bound: Set<String>, omitted: Set<String>)] = [
            "subscriptions_create": (
                [
                    "/data/attributes/subscriptionPeriod",
                    "/data/attributes/familySharable",
                    "/data/attributes/groupLevel",
                    "/data/attributes/reviewNote"
                ],
                []
            ),
            "subscriptions_create_intro_offer": (
                [
                    "/data/attributes/startDate",
                    "/data/attributes/endDate",
                    "/data/attributes/targetSubscriptionPlanType"
                ],
                ["/included"]
            ),
            "subscriptions_create_price": (
                [
                    "/data/relationships/territory/data/id",
                    "/data/attributes/planType",
                    "/data/attributes/preserveCurrentPrice"
                ],
                []
            ),
            "subscriptions_update": (
                [
                    "/data/attributes/name",
                    "/data/attributes/familySharable",
                    "/data/attributes/groupLevel",
                    "/data/attributes/reviewNote",
                    "/data/attributes/subscriptionPeriod"
                ],
                [
                    "/data/relationships/introductoryOffers",
                    "/data/relationships/prices",
                    "/data/relationships/promotionalOffers",
                    "/included"
                ]
            ),
            "subscriptions_update_intro_offer": (
                ["/data/attributes/endDate"],
                []
            ),
            "subscriptions_update_offer_code": (
                ["/data/attributes/active"],
                []
            ),
            "subscriptions_update_custom_code": (
                ["/data/attributes/active"],
                []
            )
        ]

        for (toolName, expectation) in expected {
            let mapping = try #require(manifest.mapping(for: toolName))
            let boundPointers: [String] = mapping.fields.compactMap { $0.jsonPointer }
            let bound = Set(boundPointers)
            #expect(expectation.bound.isSubset(of: bound))
            var omittedNames = Set<String>()
            var omittedReviewsAreCurrent = true
            for operation in mapping.operations {
                for classification in operation.optionalParameterClassifications ?? [] {
                    guard classification.location == "body",
                          classification.disposition == .intentionallyOmitted else {
                        continue
                    }
                    omittedNames.insert(classification.appleName)
                    omittedReviewsAreCurrent = omittedReviewsAreCurrent
                        && classification.reviewAtSpec == "4.4.1"
                        && !classification.reason.isEmpty
                }
            }
            #expect(omittedNames == expectation.omitted)
            #expect(omittedReviewsAreCurrent)
        }
    }
}

private func subscriptionOptionalWorker(_ transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func subscriptionOptionalProperties(_ tool: Tool) throws -> [String: Value] {
    try subscriptionOptionalObject(try subscriptionOptionalObject(tool.inputSchema)["properties"])
}

private func subscriptionOptionalTypes(_ value: Value?) throws -> [String] {
    try subscriptionOptionalArray(try subscriptionOptionalObject(value)["type"])
        .compactMap(\.stringValue)
        .sorted()
}

private func subscriptionOptionalEnum(_ value: Value?) throws -> [Value] {
    try subscriptionOptionalArray(try subscriptionOptionalObject(value)["enum"])
        .sorted { String(describing: $0) < String(describing: $1) }
}

private func subscriptionOptionalObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw SubscriptionWriteOptionalTestError.expectedObject
    }
    return object
}

private func subscriptionOptionalArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw SubscriptionWriteOptionalTestError.expectedArray
    }
    return array
}

private func subscriptionOptionalBody(_ body: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
}

private func subscriptionOptionalAttributes(_ body: [String: Any]) throws -> [String: Any] {
    let data = try #require(body["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func subscriptionOptionalRelationships(_ body: [String: Any]) throws -> [String: Any] {
    let data = try #require(body["data"] as? [String: Any])
    return try #require(data["relationships"] as? [String: Any])
}

private func subscriptionOptionalResultObject(_ result: CallTool.Result) throws -> [String: Any] {
    let text = result.content.compactMap { content in
        if case .text(let text, _, _) = content { return text }
        return nil
    }.joined(separator: "\n")
    return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private enum SubscriptionWriteOptionalTestError: Error {
    case expectedObject
    case expectedArray
}
