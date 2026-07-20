import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Commerce Create Recovery Contract Tests")
struct CommerceCreateRecoveryContractTests {
    @Test("all non-idempotent commerce creates expose deterministic recovery after transport, decode, or identity ambiguity")
    func createAmbiguityRecovery() async throws {
        for testCase in commerceCreateRecoveryCases {
            let failures: [(body: String?, outcome: String)] = [
                (nil, "unknown"),
                (#"{"data": "#, "committed_unverified"),
                (#"{"data":{"type":"unexpectedResources","id":"created-1"},"links":{"self":"https://api.example.test/resource"}}"#, "committed_unverified"),
                ("{\"data\":{\"type\":\"\(testCase.expectedResponseType)\",\"id\":\"\"},\"links\":{\"self\":\"https://api.example.test/resource\"}}", "committed_unverified"),
                ("{\"data\":{\"type\":\"\(testCase.expectedResponseType)\",\"id\":\"bad/id\"},\"links\":{\"self\":\"https://api.example.test/resource\"}}", "committed_unverified")
            ]
            for failure in failures {
                let responses: [TestHTTPTransport.Response]
                if let responseBody = failure.body {
                    responses = [.init(statusCode: 201, body: responseBody)]
                } else {
                    responses = []
                }
                let transport = TestHTTPTransport(responses: responses)
                let result = try await callCommerceCreate(testCase, transport: transport)

                #expect(result.isError == true, "Expected ambiguous write error from \(testCase.tool)")
                #expect(await transport.requestCount() == 1, "Expected one POST from \(testCase.tool)")
                let payload = try commerceRecoveryObject(result.structuredContent)
                let details = try commerceRecoveryObject(payload["details"])
                #expect(details["operation"] == .string(testCase.tool))
                #expect(details["write_outcome"] == .string(failure.outcome))
                #expect(details["operationCommitState"] == .string(failure.outcome))
                #expect(details["retrySafe"] == .bool(false))
                #expect(details["inspectionRequired"] == .bool(true))
                if failure.outcome == "committed_unverified" {
                    #expect(details["operationCommitted"] == .bool(true))
                    #expect(details["outcomeUnknown"] == .bool(false))
                } else {
                    #expect(details["operationCommitted"] == nil)
                    #expect(details["outcomeUnknown"] == .bool(true))
                }
                for (key, value) in testCase.identifiers {
                    #expect(details[key] == value, "Missing recovery identifier \(key) from \(testCase.tool)")
                }

                let recovery = try commerceRecoveryObject(details["recovery"])
                let list = try commerceRecoveryObject(recovery["list_candidates"])
                #expect(list["tool"] == .string(testCase.listTool))
                #expect(list["arguments"] == .object(testCase.listArguments))
                #expect(list["continue_with_next_url"] == .bool(true))
                let match = try commerceRecoveryObject(recovery["match_requested"])
                #expect(match["identifiers"] == .object(testCase.identifiers))
                let get = try commerceRecoveryObject(recovery["get_candidate"])
                #expect(get["tool"] == .string(testCase.getTool))
                #expect(get["id_argument"] == .string(testCase.getIDArgument))
                #expect(get["id_source"] == .string(testCase.listResultIDPath))
                #expect(get["after"] == .string("list_candidates"))
            }
        }
    }

    @Test("deterministic commerce create 4xx responses are rejected without duplicate-write recovery")
    func deterministicClientRejectionsRemainRejected() async throws {
        for testCase in commerceCreateRecoveryCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 422, body: commerceRecoveryAPIError(status: 422))
            ])
            let result = try await callCommerceCreate(testCase, transport: transport)

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
            let payload = try commerceRecoveryObject(result.structuredContent)
            let details = try commerceRecoveryObject(payload["details"])
            #expect(details["write_outcome"] == .string("rejected"))
            #expect(details["operationCommitState"] == .string("rejected"))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["outcomeUnknown"] == nil)
            #expect(details["operationCommitted"] == nil)
            #expect(details["recovery"] == nil)
            let cause = try commerceRecoveryObject(details["cause"])
            #expect(cause["type"] == .string("api"))
            #expect(cause["statusCode"] == .int(422))
            #expect(cause["errors"] != nil)
        }
    }

    @Test("request failure classification separates rejected and unknown outcomes")
    func requestFailureClassification() throws {
        for statusCode in [400, 401, 403, 404, 409, 422, 429] {
            let error = ASCError.api("rejected", statusCode)
            #expect(ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            ) == .rejected)
            let details = try commerceRecoveryObject(commerceFailureDetails(for: error, phase: .request))
            #expect(details["write_outcome"] == .string("rejected"))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["recovery"] == nil)
            #expect(details["cause"] == error.structuredValue)
        }

        let ambiguousErrors: [Error] = [
            ASCError.network("connection lost"),
            ASCError.api("timeout", 408),
            ASCError.api("server failure", 500),
            ASCError.api("server unavailable", 503),
            CancellationError()
        ]
        for error in ambiguousErrors {
            #expect(ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            ) == .outcomeUnknown)
            let details = try commerceRecoveryObject(commerceFailureDetails(for: error, phase: .request))
            #expect(details["write_outcome"] == .string("unknown"))
            #expect(details["outcomeUnknown"] == .bool(true))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["recovery"] != nil)
        }
    }

    @Test("accepted but invalid create responses remain committed and unverified")
    func acceptedResponseFailureClassification() throws {
        let failures: [Error] = [
            ASCError.parsing("malformed JSON:API document"),
            ASCError.api("unexpected successful status", 202),
            DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "missing required data"
            ))
        ]

        for error in failures {
            #expect(ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .acceptedResponse
            ) == .committedUnverified)
            let details = try commerceRecoveryObject(
                commerceFailureDetails(for: error, phase: .acceptedResponse)
            )
            #expect(details["write_outcome"] == .string("committed_unverified"))
            #expect(details["operationCommitState"] == .string("committed_unverified"))
            #expect(details["operationCommitted"] == .bool(true))
            #expect(details["outcomeUnknown"] == .bool(false))
            #expect(details["inspectionRequired"] == .bool(true))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["recovery"] != nil)
        }

        try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
            201,
            expectedStatusCode: 201,
            context: "Create response"
        )
        for statusCode in [200, 202, 204] {
            #expect(throws: ASCError.self) {
                try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                    statusCode,
                    expectedStatusCode: 201,
                    context: "Create response"
                )
            }
        }
    }

    @Test("JSON API identity validation requires canonical type and id")
    func resourceIdentityValidation() throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: "subscriptionVersions",
            id: "resource-1._~",
            expectedType: "subscriptionVersions",
            expectedID: "resource-1._~",
            context: "Subscription version response"
        )

        #expect(throws: ASCError.self) {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: "unexpectedResources",
                id: "resource-1",
                expectedType: "subscriptionVersions",
                context: "Subscription version response"
            )
        }
        for invalidID in ["", " resource-1", "resource 1", "bad/id", "bad%2Fid", ".", ".."] {
            #expect(throws: ASCError.self) {
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: "subscriptionVersions",
                    id: invalidID,
                    expectedType: "subscriptionVersions",
                    context: "Subscription version response"
                )
            }
        }
        #expect(throws: ASCError.self) {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: "subscriptionVersions",
                id: "resource-2",
                expectedType: "subscriptionVersions",
                expectedID: "resource-1",
                context: "Subscription version response"
            )
        }
    }

    @Test("preflight failures are not mislabeled as ambiguous Apple writes")
    func preflightFailureIsNotAmbiguous() async throws {
        let transport = TestHTTPTransport(responses: [])
        let result = try await callCommerceCreate(
            CommerceCreateRecoveryCase(
                worker: .iap,
                tool: "iap_create_version",
                arguments: ["iap_id": .string("bad/id")],
                identifiers: [:],
                expectedResponseType: "inAppPurchaseVersions",
                listTool: "",
                listArguments: [:],
                getTool: "",
                getIDArgument: "",
                listResultIDPath: ""
            ),
            transport: transport
        )

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        let payload = try commerceRecoveryObject(result.structuredContent)
        let details = try commerceRecoveryObject(payload["details"])
        #expect(details["type"] == .string("parsing"))
        #expect(details["message"] == .string(
            "Invalid requested iap_id resource ID for an App Store Connect URL: must not contain path, query, or fragment separators"
        ))
        #expect(payload["operationCommitState"] == nil)
        #expect(payload["outcomeUnknown"] == nil)
        #expect(payload["retrySafe"] == nil)
    }
}

private enum CommerceCreateWorker: Sendable {
    case iap
    case subscriptions
}

private struct CommerceCreateRecoveryCase: Sendable {
    let worker: CommerceCreateWorker
    let tool: String
    let arguments: [String: Value]
    let identifiers: [String: Value]
    let expectedResponseType: String
    let listTool: String
    let listArguments: [String: Value]
    let getTool: String
    let getIDArgument: String
    let listResultIDPath: String
}

private let commerceCreateRecoveryCases: [CommerceCreateRecoveryCase] = [
    CommerceCreateRecoveryCase(
        worker: .iap,
        tool: "iap_create_version",
        arguments: ["iap_id": .string("iap-1")],
        identifiers: ["iap_id": .string("iap-1")],
        expectedResponseType: "inAppPurchaseVersions",
        listTool: "iap_list_versions",
        listArguments: ["iap_id": .string("iap-1"), "limit": .int(200)],
        getTool: "iap_get_version",
        getIDArgument: "version_id",
        listResultIDPath: "versions[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .iap,
        tool: "iap_create_version_localization",
        arguments: [
            "version_id": .string("iap-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium"),
            "description": .null
        ],
        identifiers: [
            "version_id": .string("iap-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium"),
            "description": .null
        ],
        expectedResponseType: "inAppPurchaseLocalizations",
        listTool: "iap_list_version_localizations",
        listArguments: ["version_id": .string("iap-version-1"), "limit": .int(200)],
        getTool: "iap_get_version_localization",
        getIDArgument: "localization_id",
        listResultIDPath: "localizations[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .subscriptions,
        tool: "subscriptions_create_version",
        arguments: ["subscription_id": .string("subscription-1")],
        identifiers: ["subscription_id": .string("subscription-1")],
        expectedResponseType: "subscriptionVersions",
        listTool: "subscriptions_list_versions",
        listArguments: ["subscription_id": .string("subscription-1"), "limit": .int(200)],
        getTool: "subscriptions_get_version",
        getIDArgument: "version_id",
        listResultIDPath: "versions[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .subscriptions,
        tool: "subscriptions_create_version_localization",
        arguments: [
            "version_id": .string("subscription-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium"),
            "description": .string("Localized copy")
        ],
        identifiers: [
            "version_id": .string("subscription-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium"),
            "description": .string("Localized copy")
        ],
        expectedResponseType: "subscriptionLocalizations",
        listTool: "subscriptions_list_version_localizations",
        listArguments: ["version_id": .string("subscription-version-1"), "limit": .int(200)],
        getTool: "subscriptions_get_version_localization",
        getIDArgument: "localization_id",
        listResultIDPath: "localizations[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .subscriptions,
        tool: "subscriptions_create_group_version",
        arguments: ["group_id": .string("group-1")],
        identifiers: ["group_id": .string("group-1")],
        expectedResponseType: "subscriptionGroupVersions",
        listTool: "subscriptions_list_group_versions",
        listArguments: ["group_id": .string("group-1"), "limit": .int(200)],
        getTool: "subscriptions_get_group_version",
        getIDArgument: "version_id",
        listResultIDPath: "versions[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .subscriptions,
        tool: "subscriptions_create_group_version_localization",
        arguments: [
            "version_id": .string("group-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium Plans"),
            "custom_app_name": .null
        ],
        identifiers: [
            "version_id": .string("group-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium Plans"),
            "custom_app_name": .null
        ],
        expectedResponseType: "subscriptionGroupLocalizations",
        listTool: "subscriptions_list_group_version_localizations",
        listArguments: ["version_id": .string("group-version-1"), "limit": .int(200)],
        getTool: "subscriptions_get_group_version_localization",
        getIDArgument: "localization_id",
        listResultIDPath: "localizations[].id"
    ),
    CommerceCreateRecoveryCase(
        worker: .subscriptions,
        tool: "subscriptions_create_plan_availability",
        arguments: [
            "subscription_id": .string("subscription-1"),
            "plan_type": .string("MONTHLY"),
            "territory_ids": .array([.string("USA"), .string("GBR")]),
            "available_in_new_territories": .bool(true)
        ],
        identifiers: [
            "subscription_id": .string("subscription-1"),
            "plan_type": .string("MONTHLY"),
            "territory_ids": .array([.string("USA"), .string("GBR")]),
            "available_in_new_territories": .bool(true)
        ],
        expectedResponseType: "subscriptionPlanAvailabilities",
        listTool: "subscriptions_list_plan_availabilities",
        listArguments: ["subscription_id": .string("subscription-1"), "limit": .int(200)],
        getTool: "subscriptions_get_plan_availability",
        getIDArgument: "plan_availability_id",
        listResultIDPath: "plan_availabilities[].id"
    )
]

private func callCommerceCreate(
    _ testCase: CommerceCreateRecoveryCase,
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let parameters = CallTool.Parameters(name: testCase.tool, arguments: testCase.arguments)
    switch testCase.worker {
    case .iap:
        return try await InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(parameters)
    case .subscriptions:
        return try await SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService(),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        ).handleTool(parameters)
    }
}

private func commerceRecoveryObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw CommerceCreateRecoveryTestFailure.expectedObject
    }
    return object
}

private enum CommerceCreateRecoveryTestFailure: Error {
    case expectedObject
}

private func commerceFailureDetails(
    for error: Error,
    phase: ASCNonIdempotentWriteFailurePhase
) -> Value {
    ASCNonIdempotentWriteRecovery.failureDetails(
        for: error,
        phase: phase,
        operation: "subscriptions_create_version",
        identifiers: ["subscription_id": .string("subscription-1")],
        listTool: "subscriptions_list_versions",
        listArguments: ["subscription_id": .string("subscription-1"), "limit": .int(200)],
        getTool: "subscriptions_get_version",
        getIDArgument: "version_id",
        listResultIDPath: "versions[].id",
        matchingFields: ["subscription_id"]
    )
}

private func commerceRecoveryAPIError(status: Int) -> String {
    #"{"errors":[{"status":"\#(status)","code":"INVALID","title":"Invalid request","detail":"Invalid request"}]}"#
}
