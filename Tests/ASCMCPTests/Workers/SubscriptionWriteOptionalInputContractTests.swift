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
        let priceProperties = try subscriptionOptionalProperties(price)
        #expect(try subscriptionOptionalTypes(priceProperties["plan_type"]) == ["null", "string"])
        #expect(try subscriptionOptionalEnum(priceProperties["plan_type"]) == [.null, .string("MONTHLY"), .string("UPFRONT")])
        #expect(try subscriptionOptionalTypes(priceProperties["preserve_current_price"]) == ["boolean", "null"])

        let update = try #require(tools.first { $0.name == "subscriptions_update" })
        let updateSchema = try subscriptionOptionalObject(update.inputSchema)
        let updateProperties = try subscriptionOptionalProperties(update)
        #expect(updateSchema["minProperties"] == .int(2))
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
                "territory_id": .string("USA"),
                "price_point_id": .string("point-1")
            ]
        ))
        #expect(omitted.isError != true)
        let omittedBody = try #require(await transport.recordedBodyStrings().last)
        let omittedAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(omittedBody))
        #expect(omittedAttributes.isEmpty)
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
            arguments: ["subscription_id": .string("sub-1"), "subscription_period": .null]
        ))
        #expect(clear.isError != true)
        let body = try #require(await transport.recordedBodyStrings().first)
        let clearAttributes = try subscriptionOptionalAttributes(subscriptionOptionalBody(body))
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

    @Test("manifest classifies all eleven optional write inputs")
    func manifestClassifiesOptionalWriteInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: (bound: Set<String>, omitted: Set<String>)] = [
            "subscriptions_create_intro_offer": (
                [
                    "/data/attributes/startDate",
                    "/data/attributes/endDate",
                    "/data/attributes/targetSubscriptionPlanType"
                ],
                ["/included"]
            ),
            "subscriptions_create_price": (
                ["/data/attributes/planType", "/data/attributes/preserveCurrentPrice"],
                []
            ),
            "subscriptions_update": (
                ["/data/attributes/subscriptionPeriod"],
                [
                    "/data/relationships/introductoryOffers",
                    "/data/relationships/prices",
                    "/data/relationships/promotionalOffers",
                    "/included"
                ]
            )
        ]

        for (toolName, expectation) in expected {
            let mapping = try #require(manifest.mapping(for: toolName))
            let bound = Set(mapping.fields.compactMap(\.jsonPointer))
            #expect(expectation.bound.isSubset(of: bound))
            let omitted = mapping.operations.flatMap { $0.optionalParameterClassifications ?? [] }
                .filter { $0.location == "body" && $0.disposition == .intentionallyOmitted }
            #expect(Set(omitted.map(\.appleName)) == expectation.omitted)
            #expect(omitted.allSatisfy { $0.reviewAtSpec == "4.4.1" && !$0.reason.isEmpty })
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
