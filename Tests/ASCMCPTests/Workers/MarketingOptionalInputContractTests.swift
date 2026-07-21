import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Marketing Optional Input Contract Tests")
struct MarketingOptionalInputContractTests {
    @Test("PPO collection filters use Apple explode-false CSV semantics")
    func ppoFiltersSerializeAsCSV() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/apps/app-1/appStoreVersionExperimentsV2?filter%5Bstate%5D=READY_FOR_REVIEW%2CIN_REVIEW&limit=25"},"meta":{"paging":{"limit":25,"total":0}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/appStoreVersions/version-1/appStoreVersionExperimentsV2?filter%5Bstate%5D=READY_FOR_REVIEW%2CIN_REVIEW&limit=25"},"meta":{"paging":{"limit":25,"total":0}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/appStoreVersionExperimentTreatments/treatment-1/appStoreVersionExperimentTreatmentLocalizations?filter%5Blocale%5D=en-US%2Cfr-FR&limit=25"},"meta":{"paging":{"limit":25,"total":0}}}"#
            )
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

        let versionExperiments = try await worker.handleTool(CallTool.Parameters(
            name: "ppo_list_version_experiments",
            arguments: [
                "version_id": .string("version-1"),
                "states": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")])
            ]
        ))
        #expect(versionExperiments.isError != true)

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
        #expect(optionalInputQuery(requests[1])["filter[state]"] == "READY_FOR_REVIEW,IN_REVIEW")
        #expect(optionalInputQuery(requests[2])["filter[locale]"] == "en-US,fr-FR")
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

        let versionExperiments = try #require(tools.first { $0.name == "ppo_list_version_experiments" })
        let versionExperimentSchema = try optionalInputObject(versionExperiments.inputSchema)
        let versionExperimentProperties = try optionalInputObject(versionExperimentSchema["properties"])
        let versionStates = try optionalInputObject(versionExperimentProperties["states"])
        #expect(versionStates["oneOf"]?.arrayValue?.count == 2)

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
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1","relationships":{"subscription":{"data":{"type":"subscriptions","id":"subscription-1"}}}},"included":[{"type":"subscriptions","id":"subscription-1","attributes":{"name":"Pro Annual","productId":"com.example.pro.annual"}}],"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/promotedPurchases?limit=25"},"meta":{"paging":{"limit":25,"total":0}}}"#
            )
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
        let detailRoot = try optionalInputObject(detail.structuredContent)
        let purchase = try optionalInputObject(detailRoot["promoted_purchase"])
        #expect(purchase["subscriptionId"] == .string("subscription-1"))
        #expect(purchase["inAppPurchaseId"] == .null)
        let linkedProduct = try optionalInputObject(purchase["linkedProduct"])
        #expect(linkedProduct["type"] == .string("subscriptions"))
        #expect(linkedProduct["id"] == .string("subscription-1"))
        #expect(linkedProduct["name"] == .string("Pro Annual"))
        #expect(linkedProduct["productId"] == .string("com.example.pro.annual"))

        let requests = await transport.recordedRequests()
        #expect(optionalInputQuery(requests[0])["include"] == "inAppPurchaseV2,subscription")
        #expect(optionalInputQuery(requests[1])["include"] == nil)
    }

    @Test("marketing manifests classify every remaining optional input exactly")
    func manifestsClassifyRemainingInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let include = "query:include:intentionallyOmitted"
        let previewLimit = "query:limit[appPreviews]:intentionallyOmitted"
        let screenshotLimit = "query:limit[appScreenshots]:intentionallyOmitted"
        let previewSetLimit = "query:limit[appPreviewSets]:intentionallyOmitted"
        let screenshotSetLimit = "query:limit[appScreenshotSets]:intentionallyOmitted"
        let experimentTreatmentLimit = "query:limit[appStoreVersionExperimentTreatments]:intentionallyOmitted"
        let treatmentLocalizationLimit = "query:limit[appStoreVersionExperimentTreatmentLocalizations]:intentionallyOmitted"
        let controlVersionLimit = "query:limit[controlVersions]:intentionallyOmitted"
        let pageVersionLimit = "query:limit[appCustomProductPageVersions]:intentionallyOmitted"
        let pageLocalizationLimit = "query:limit[appCustomProductPageLocalizations]:intentionallyOmitted"
        let keywordLimit = "query:limit[searchKeywords]:intentionallyOmitted"
        let expected: [String: Set<String>] = [
            "custom_pages_create": [
                "body:/data/relationships/appCustomProductPageVersions:internalControl"
            ],
            "custom_pages_create_version": [
                "body:/data/relationships/appCustomProductPageLocalizations:intentionallyOmitted"
            ],
            "custom_pages_get": [include, pageVersionLimit],
            "custom_pages_list": [include, pageVersionLimit],
            "custom_pages_get_localization": [include, previewSetLimit, screenshotSetLimit, keywordLimit],
            "custom_pages_list_localizations": [include, previewSetLimit, screenshotSetLimit, keywordLimit],
            "custom_pages_get_version": [include, pageLocalizationLimit],
            "custom_pages_list_versions": [include, pageLocalizationLimit],
            "ppo_create_treatment": ["body:/data/relationships/appStoreVersionExperiment:intentionallyOmitted"],
            "ppo_get_experiment": [include, experimentTreatmentLimit, controlVersionLimit],
            "ppo_get_treatment": [include, treatmentLocalizationLimit],
            "ppo_get_treatment_localization": [include, previewSetLimit, screenshotSetLimit],
            "ppo_list_experiments": [include, experimentTreatmentLimit, controlVersionLimit],
            "ppo_list_treatment_localizations": [include, previewSetLimit, screenshotSetLimit],
            "ppo_list_treatments": [include, treatmentLocalizationLimit],
            "ppo_list_version_experiments": [include, experimentTreatmentLimit, controlVersionLimit],
            "screenshots_create_preview_set": [
                "query:filter[appCustomProductPageLocalization]:intentionallyOmitted",
                "query:filter[appStoreVersionExperimentTreatmentLocalization]:intentionallyOmitted",
                "query:filter[appStoreVersionLocalization]:intentionallyOmitted",
                include,
                previewLimit
            ],
            "screenshots_create_set": [
                "query:filter[appCustomProductPageLocalization]:intentionallyOmitted",
                "query:filter[appStoreVersionExperimentTreatmentLocalization]:intentionallyOmitted",
                "query:filter[appStoreVersionLocalization]:intentionallyOmitted",
                include,
                screenshotLimit
            ],
            "screenshots_delete_preview_set": [include, previewLimit],
            "screenshots_delete_set": [include, screenshotLimit],
            "screenshots_get_preview_set": [include, previewLimit],
            "screenshots_get_set": [include, screenshotLimit],
            "screenshots_get": [include],
            "screenshots_get_preview": [include],
            "screenshots_list": [include],
            "screenshots_list_preview_sets": [include, previewLimit],
            "screenshots_list_previews": [include],
            "screenshots_list_sets": [include, screenshotLimit],
            "screenshots_reorder": [include],
            "screenshots_reorder_previews": [include],
            "screenshots_upload": [include],
            "screenshots_upload_batch": [include],
            "screenshots_upload_preview": [include],
            "promoted_get": ["query:include:internalControl"],
            "promoted_list": [include],
            "review_attachments_upload": [include]
        ]

        let prefixes = ["custom_pages_", "ppo_", "screenshots_", "promoted_", "review_attachments_"]
        let classifiedTools = Set(manifest.tools.compactMap { mapping -> String? in
            guard prefixes.contains(where: { mapping.tool.hasPrefix($0) }) else { return nil }
            let classifications = mapping.operations.flatMap {
                $0.optionalParameterClassifications ?? []
            }
            return classifications.isEmpty ? nil : mapping.tool
        })
        #expect(expected.count == 36)
        #expect(classifiedTools == Set(expected.keys))

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
                $0.reviewAtSpec == "4.4.1"
                    && !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }

        let experimentList = try #require(manifest.mapping(for: "ppo_list_experiments"))
        let states = try #require(experimentList.fields.first { $0.toolField == "states" })
        #expect(states.appleName == "filter[state]")
        let versionExperimentList = try #require(manifest.mapping(for: "ppo_list_version_experiments"))
        let versionStates = try #require(versionExperimentList.fields.first { $0.toolField == "states" })
        #expect(versionStates.appleName == "filter[state]")
        let localizationList = try #require(manifest.mapping(for: "ppo_list_treatment_localizations"))
        let locale = try #require(localizationList.fields.first { $0.toolField == "locale" })
        #expect(locale.appleName == "filter[locale]")
        let keywordList = try #require(manifest.mapping(for: "custom_pages_list_search_keywords"))
        let platform = try #require(keywordList.fields.first { $0.toolField == "platform" })
        let keywordLocale = try #require(keywordList.fields.first { $0.toolField == "locale" })
        #expect(platform.appleName == "filter[platform]")
        #expect(keywordLocale.appleName == "filter[locale]")
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
