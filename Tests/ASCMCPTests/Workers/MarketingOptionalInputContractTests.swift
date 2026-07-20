import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Marketing Optional Input Contract Tests")
struct MarketingOptionalInputContractTests {
    @Test("PPO collection filters use Apple explode-false CSV semantics")
    func ppoFiltersSerializeAsCSV() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let worker = try await optionalInputPPOWorker(transport)

        let experiments = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_experiments",
            arguments: [
                "app_id": .string("app-1"),
                "states": .array([.string("READY_FOR_REVIEW"), .string("RUNNING")])
            ]
        ))
        #expect(experiments.isError == true)
        #expect(await transport.requestCount() == 0)

        let validExperiments = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_experiments",
            arguments: [
                "app_id": .string("app-1"),
                "states": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")])
            ]
        ))
        #expect(validExperiments.isError != true)

        let localizations = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_treatment_localizations",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .array([.string("en-US"), .string("fr-FR")])
            ]
        ))
        #expect(localizations.isError != true)

        let requests = await transport.recordedRequests()
        #expect(optionalInputQuery(requests[0])["filter[state]"] == "READY_FOR_REVIEW,IN_REVIEW")
        #expect(optionalInputQuery(requests[1])["filter[locale]"] == "en-US,fr-FR")
    }

    @Test("PPO filter schemas expose scalar-or-array inputs and reject malformed values")
    func ppoFilterSchemasAndValidation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await optionalInputPPOWorker(transport)
        let tools = await worker.getTools()

        let experiments = try #require(tools.first { $0.name == "ppo_list_experiments" })
        let experimentSchema = try optionalInputObject(experiments.inputSchema)
        let experimentProperties = try optionalInputObject(experimentSchema["properties"])
        let states = try optionalInputObject(experimentProperties["states"])
        #expect(states["oneOf"]?.arrayValue?.count == 2)

        let localizations = try #require(tools.first { $0.name == "ppo_list_treatment_localizations" })
        let localizationSchema = try optionalInputObject(localizations.inputSchema)
        let localizationProperties = try optionalInputObject(localizationSchema["properties"])
        let locale = try optionalInputObject(localizationProperties["locale"])
        #expect(locale["oneOf"]?.arrayValue?.count == 2)

        let duplicateLocale = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_treatment_localizations",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .array([.string("en-US"), .string("en-US")])
            ]
        ))
        let commaLocale = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_treatment_localizations",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .string("en-US,fr-FR")
            ]
        ))
        let whitespaceLocale = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_treatment_localizations",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .string(" en-US ")
            ]
        ))
        #expect(duplicateLocale.isError == true)
        #expect(commaLocale.isError == true)
        #expect(whitespaceLocale.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("Promoted detail controls include while collection stays relationship-only")
    func promotedIncludeContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1","relationships":{"subscription":{"data":{"type":"subscriptions","id":"subscription-1"}}}}}"#
            ),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = PromotedPurchasesWorker(httpClient: client, uploadService: UploadService())

        let detail = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_get",
            arguments: ["promoted_purchase_id": .string("promoted-1")]
        ))
        let list = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_list",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(detail.isError != true)
        #expect(list.isError != true)

        let requests = await transport.recordedRequests()
        #expect(optionalInputQuery(requests[0])["include"] == "inAppPurchaseV2,subscription")
        #expect(optionalInputQuery(requests[1])["include"] == nil)
    }

    @Test("PPO and promoted manifests classify every remaining optional input")
    func manifestsClassifyRemainingInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let expected: [String: Set<String>] = [
            "ppo_create_treatment": ["body:/data/relationships/appStoreVersionExperiment:intentionallyOmitted"],
            "ppo_get_experiment": [
                "query:include:intentionallyOmitted",
                "query:limit[appStoreVersionExperimentTreatments]:intentionallyOmitted",
                "query:limit[controlVersions]:intentionallyOmitted"
            ],
            "ppo_list_experiments": [
                "query:include:intentionallyOmitted",
                "query:limit[appStoreVersionExperimentTreatments]:intentionallyOmitted",
                "query:limit[controlVersions]:intentionallyOmitted"
            ],
            "ppo_list_treatment_localizations": [
                "query:include:intentionallyOmitted",
                "query:limit[appPreviewSets]:intentionallyOmitted",
                "query:limit[appScreenshotSets]:intentionallyOmitted"
            ],
            "ppo_list_treatments": [
                "query:include:intentionallyOmitted",
                "query:limit[appStoreVersionExperimentTreatmentLocalizations]:intentionallyOmitted"
            ],
            "promoted_get": ["query:include:internalControl"],
            "promoted_list": ["query:include:intentionallyOmitted"]
        ]

        for (tool, identities) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            let allClassifications = mapping.operations.flatMap {
                $0.optionalParameterClassifications ?? []
            }
            let classifications = Set(allClassifications.map {
                    "\($0.location):\($0.appleName):\($0.disposition.rawValue)"
            })
            #expect(classifications == identities)
            #expect(allClassifications.allSatisfy {
                $0.reviewAtSpec == "4.4.1" && $0.reason.contains("Apple")
            })
        }

        let experimentList = try #require(manifest.mapping(for: "ppo_list_experiments"))
        let states = try #require(experimentList.fields.first { $0.toolField == "states" })
        #expect(states.appleName == "filter[state]")
        let localizationList = try #require(manifest.mapping(for: "ppo_list_treatment_localizations"))
        let locale = try #require(localizationList.fields.first { $0.toolField == "locale" })
        #expect(locale.appleName == "filter[locale]")
    }
}

private func optionalInputPPOWorker(_ transport: TestHTTPTransport) async throws -> ProductPageOptimizationWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ProductPageOptimizationWorker(httpClient: client)
}

private func optionalInputQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        .queryItems?
        .compactMap { item in item.value.map { (item.name, $0) } } ?? [])
}

private func optionalInputObject(_ value: Value?) throws -> [String: Value] {
    guard let object = value?.objectValue else {
        throw OptionalInputContractError.invalidObject
    }
    return object
}

private enum OptionalInputContractError: Error {
    case invalidObject
}
