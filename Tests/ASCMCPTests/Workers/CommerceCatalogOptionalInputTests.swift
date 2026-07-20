import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Commerce Catalog Optional Input Tests")
struct CommerceCatalogOptionalInputTests {
    @Test("catalog schemas expose Apple 4.4.1 filters, sort, and localization limits")
    func schemasExposeCatalogControls() async throws {
        let transport = TestHTTPTransport(responses: [])
        let iap = try await commerceIAPWorker(transport)
        let subscriptions = try await commerceSubscriptionsWorker(transport)

        let iapTools = Dictionary(uniqueKeysWithValues: await iap.getTools().map { ($0.name, $0) })
        let subscriptionTools = Dictionary(uniqueKeysWithValues: await subscriptions.getTools().map { ($0.name, $0) })

        for toolName in ["iap_list", "iap_inventory"] {
            let properties = try commerceProperties(try #require(iapTools[toolName]))
            for field in ["filter_name", "filter_product_id", "filter_state", "filter_type", "sort"] {
                #expect(try commerceArray(try commerceObject(properties[field])["oneOf"]).count == 2)
            }
        }

        let iapGroups = try commerceProperties(try #require(iapTools["iap_list_subscriptions"]))
        for field in ["filter_reference_name", "filter_subscription_state", "sort"] {
            #expect(try commerceArray(try commerceObject(iapGroups[field])["oneOf"]).count == 2)
        }

        let subscriptionList = try commerceProperties(try #require(subscriptionTools["subscriptions_list"]))
        for field in ["filter_name", "filter_product_id", "filter_state", "sort"] {
            #expect(try commerceArray(try commerceObject(subscriptionList[field])["oneOf"]).count == 2)
        }

        let subscriptionGroups = try commerceProperties(try #require(subscriptionTools["subscriptions_list_groups"]))
        for field in ["filter_reference_name", "filter_subscription_state", "sort"] {
            #expect(try commerceArray(try commerceObject(subscriptionGroups[field])["oneOf"]).count == 2)
        }

        for (tools, toolName) in [
            (iapTools, "iap_list_localizations"),
            (subscriptionTools, "subscriptions_list_localizations")
        ] {
            let limit = try commerceObject(try commerceProperties(try #require(tools[toolName]))["limit"])
            #expect(limit["minimum"] == .int(1))
            #expect(limit["maximum"] == .int(200))
        }
    }

    @Test("IAP list sends scalar-or-array discovery controls with Apple names")
    func iapListForwardsCatalogControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await commerceIAPWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "iap_list",
            arguments: [
                "app_id": .string("app-1"),
                "filter_name": .array([.string("Coins"), .string("Pro")]),
                "filter_product_id": .string("com.example.pro"),
                "filter_state": .array([.string("READY_TO_SUBMIT"), .string("APPROVED")]),
                "filter_type": .string("NON_CONSUMABLE"),
                "sort": .array([.string("name"), .string("-inAppPurchaseType")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/apps/app-1/inAppPurchasesV2")
        let query = commerceQuery(request)
        #expect(query["filter[name]"] == "Coins,Pro")
        #expect(query["filter[productId]"] == "com.example.pro")
        #expect(query["filter[state]"] == "READY_TO_SUBMIT,APPROVED")
        #expect(query["filter[inAppPurchaseType]"] == "NON_CONSUMABLE")
        #expect(query["sort"] == "name,-inAppPurchaseType")
    }

    @Test("IAP inventory combines discovery controls with its fixed projection")
    func iapInventoryForwardsCatalogControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"included":[]}"#)
        ])
        let worker = try await commerceIAPWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "iap_inventory",
            arguments: [
                "app_id": .string("app-1"),
                "filter_name": .string("Premium"),
                "filter_product_id": .array([.string("premium.monthly"), .string("premium.yearly")]),
                "filter_state": .string("APPROVED"),
                "filter_type": .array([.string("CONSUMABLE"), .string("NON_CONSUMABLE")]),
                "sort": .string("-name")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/apps/app-1/inAppPurchasesV2")
        let query = commerceQuery(request)
        #expect(query["filter[name]"] == "Premium")
        #expect(query["filter[productId]"] == "premium.monthly,premium.yearly")
        #expect(query["filter[state]"] == "APPROVED")
        #expect(query["filter[inAppPurchaseType]"] == "CONSUMABLE,NON_CONSUMABLE")
        #expect(query["sort"] == "-name")
        #expect(query["include"] == "inAppPurchaseLocalizations,iapPriceSchedule,inAppPurchaseAvailability,promotedPurchase,offerCodes")
    }

    @Test("both subscription group listings use the same Apple discovery contract")
    func groupListingsForwardCatalogControls() async throws {
        let iapTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let subscriptionTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"included":[]}"#)
        ])
        let iap = try await commerceIAPWorker(iapTransport)
        let subscriptions = try await commerceSubscriptionsWorker(subscriptionTransport)
        let arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "filter_reference_name": .array([.string("Primary"), .string("Legacy")]),
            "filter_subscription_state": .array([.string("READY_TO_SUBMIT"), .string("APPROVED")]),
            "sort": .string("-referenceName")
        ]

        let iapResult = try await iap.handleTool(.init(name: "iap_list_subscriptions", arguments: arguments))
        let subscriptionResult = try await subscriptions.handleTool(.init(name: "subscriptions_list_groups", arguments: arguments))

        #expect(iapResult.isError != true)
        #expect(subscriptionResult.isError != true)
        for request in [
            try #require(await iapTransport.recordedRequests().first),
            try #require(await subscriptionTransport.recordedRequests().first)
        ] {
            #expect(request.url?.path == "/v1/apps/app-1/subscriptionGroups")
            let query = commerceQuery(request)
            #expect(query["filter[referenceName]"] == "Primary,Legacy")
            #expect(query["filter[subscriptions.state]"] == "READY_TO_SUBMIT,APPROVED")
            #expect(query["sort"] == "-referenceName")
        }
    }

    @Test("subscription list sends Apple filters and sort")
    func subscriptionListForwardsCatalogControls() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await commerceSubscriptionsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_list",
            arguments: [
                "group_id": .string("group-1"),
                "filter_name": .string("Premium"),
                "filter_product_id": .array([.string("premium.monthly"), .string("premium.yearly")]),
                "filter_state": .array([.string("READY_TO_SUBMIT"), .string("APPROVED")]),
                "sort": .string("-name")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/subscriptionGroups/group-1/subscriptions")
        let query = commerceQuery(request)
        #expect(query["filter[name]"] == "Premium")
        #expect(query["filter[productId]"] == "premium.monthly,premium.yearly")
        #expect(query["filter[state]"] == "READY_TO_SUBMIT,APPROVED")
        #expect(query["sort"] == "-name")
    }

    @Test("localization lists send a bounded Apple limit")
    func localizationListsForwardLimit() async throws {
        let iapTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let subscriptionTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let iap = try await commerceIAPWorker(iapTransport)
        let subscriptions = try await commerceSubscriptionsWorker(subscriptionTransport)

        let iapResult = try await iap.handleTool(.init(
            name: "iap_list_localizations",
            arguments: ["iap_id": .string("iap-1"), "limit": .int(200)]
        ))
        let subscriptionResult = try await subscriptions.handleTool(.init(
            name: "subscriptions_list_localizations",
            arguments: ["subscription_id": .string("sub-1"), "limit": .int(200)]
        ))

        #expect(iapResult.isError != true)
        #expect(subscriptionResult.isError != true)
        let iapRequest = try #require(await iapTransport.recordedRequests().first)
        let subscriptionRequest = try #require(await subscriptionTransport.recordedRequests().first)
        #expect(iapRequest.url?.path == "/v2/inAppPurchases/iap-1/inAppPurchaseLocalizations")
        #expect(subscriptionRequest.url?.path == "/v1/subscriptions/sub-1/subscriptionLocalizations")
        #expect(commerceQuery(iapRequest)["limit"] == "200")
        #expect(commerceQuery(subscriptionRequest)["limit"] == "200")
    }

    @Test("invalid catalog arrays fail before network access")
    func invalidCatalogArraysFailLocally() async throws {
        let iapTransport = TestHTTPTransport(responses: [])
        let subscriptionTransport = TestHTTPTransport(responses: [])
        let iap = try await commerceIAPWorker(iapTransport)
        let subscriptions = try await commerceSubscriptionsWorker(subscriptionTransport)

        let invalidState = try await iap.handleTool(.init(
            name: "iap_list",
            arguments: ["app_id": .string("app-1"), "filter_state": .array([.string("UNKNOWN")])]
        ))
        let duplicateName = try await subscriptions.handleTool(.init(
            name: "subscriptions_list",
            arguments: ["group_id": .string("group-1"), "filter_name": .array([.string("Pro"), .string("Pro")])]
        ))

        #expect(invalidState.isError == true)
        #expect(duplicateName.isError == true)
        #expect(await iapTransport.requestCount() == 0)
        #expect(await subscriptionTransport.requestCount() == 0)
    }

    @Test("catalog pagination rejects repeated filter drift before network access")
    func catalogPaginationRejectsFilterDrift() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await commerceSubscriptionsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "subscriptions_list_groups",
            arguments: [
                "app_id": .string("app-1"),
                "filter_reference_name": .string("Primary"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/subscriptionGroups?filter%5BreferenceName%5D=Other&cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("commerce manifest classifies every audited input outside pricing summary")
    func manifestRecordsAuditedInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expectedBindings = [
            ("iap_list", "apps_inAppPurchasesV2_getToManyRelated", "filter_name", "filter[name]"),
            ("iap_list", "apps_inAppPurchasesV2_getToManyRelated", "filter_product_id", "filter[productId]"),
            ("iap_list", "apps_inAppPurchasesV2_getToManyRelated", "sort", "sort"),
            ("iap_inventory", "apps_inAppPurchasesV2_getToManyRelated", "filter_name", "filter[name]"),
            ("iap_inventory", "apps_inAppPurchasesV2_getToManyRelated", "filter_product_id", "filter[productId]"),
            ("iap_inventory", "apps_inAppPurchasesV2_getToManyRelated", "filter_state", "filter[state]"),
            ("iap_inventory", "apps_inAppPurchasesV2_getToManyRelated", "filter_type", "filter[inAppPurchaseType]"),
            ("iap_inventory", "apps_inAppPurchasesV2_getToManyRelated", "sort", "sort"),
            ("iap_list_subscriptions", "apps_subscriptionGroups_getToManyRelated", "filter_reference_name", "filter[referenceName]"),
            ("iap_list_subscriptions", "apps_subscriptionGroups_getToManyRelated", "filter_subscription_state", "filter[subscriptions.state]"),
            ("iap_list_subscriptions", "apps_subscriptionGroups_getToManyRelated", "sort", "sort"),
            ("subscriptions_list_groups", "apps_subscriptionGroups_getToManyRelated", "filter_reference_name", "filter[referenceName]"),
            ("subscriptions_list_groups", "apps_subscriptionGroups_getToManyRelated", "filter_subscription_state", "filter[subscriptions.state]"),
            ("subscriptions_list_groups", "apps_subscriptionGroups_getToManyRelated", "sort", "sort"),
            ("subscriptions_list", "subscriptionGroups_subscriptions_getToManyRelated", "filter_name", "filter[name]"),
            ("subscriptions_list", "subscriptionGroups_subscriptions_getToManyRelated", "filter_product_id", "filter[productId]"),
            ("subscriptions_list", "subscriptionGroups_subscriptions_getToManyRelated", "filter_state", "filter[state]"),
            ("subscriptions_list", "subscriptionGroups_subscriptions_getToManyRelated", "sort", "sort"),
            ("iap_list_localizations", "inAppPurchasesV2_inAppPurchaseLocalizations_getToManyRelated", "limit", "limit"),
            ("subscriptions_list_localizations", "subscriptions_subscriptionLocalizations_getToManyRelated", "limit", "limit"),
            ("iap_get_availability", "inAppPurchaseAvailabilities_getInstance", "include_territories", "include"),
            ("iap_get_availability", "inAppPurchaseAvailabilities_getInstance", "territory_limit", "limit[availableTerritories]")
        ]

        for (toolName, operationID, toolField, appleName) in expectedBindings {
            let mapping = try #require(manifest.mapping(for: toolName))
            let field = try #require(mapping.fields.first {
                $0.operationID == operationID && $0.toolField == toolField && $0.appleName == appleName
            })
            #expect(field.location == "query")
            #expect(field.sourceKind == (toolName == "iap_get_availability" ? .derived : .parameter))
        }

        let commerceWorkers = manifest.workers.filter { ["iap", "subscriptions"].contains($0.workerKey) }
        let classifications = commerceWorkers
            .flatMap(\.tools)
            .filter { $0.tool != "subscriptions_pricing_summary" }
            .flatMap(\.operations)
            .flatMap { $0.optionalParameterClassifications ?? [] }
        #expect(classifications.count == 147)
        #expect(classifications.filter { $0.disposition == .internalControl }.count == 31)
        #expect(classifications.filter { $0.disposition == .intentionallyOmitted }.count == 116)
        #expect(classifications.allSatisfy { $0.reviewAtSpec == "4.4.1" && !$0.reason.isEmpty })
    }
}

private func commerceIAPWorker(_ transport: TestHTTPTransport) async throws -> InAppPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
}

private func commerceSubscriptionsWorker(_ transport: TestHTTPTransport) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return SubscriptionsWorker(httpClient: client, uploadService: UploadService())
}

private func commerceProperties(_ tool: Tool) throws -> [String: Value] {
    let schema = try commerceObject(tool.inputSchema)
    return try commerceObject(schema["properties"])
}

private func commerceObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw CommerceCatalogTestFailure.expectedObject
    }
    return object
}

private func commerceArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw CommerceCatalogTestFailure.expectedArray
    }
    return array
}

private func commerceQuery(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private enum CommerceCatalogTestFailure: Error {
    case expectedObject
    case expectedArray
}
