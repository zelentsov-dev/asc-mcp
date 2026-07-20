import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("In-App Purchase Version Contract Tests")
struct InAppPurchaseVersionsContractTests {
    @Test("versioned tool schemas expose exact states, bounds, and nullable fields")
    func schemasExposeExactContracts() async throws {
        let worker = try await iapV4Worker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let names = Set(tools.map(\.name))
        let expected: Set<String> = [
            "iap_create_version",
            "iap_get_version",
            "iap_list_versions",
            "iap_list_version_localizations",
            "iap_create_version_localization",
            "iap_get_version_localization",
            "iap_update_version_localization",
            "iap_delete_version_localization",
            "iap_get_version_image",
            "iap_list_version_images",
            "iap_upload_version_image",
            "iap_get_version_image_resource",
            "iap_delete_version_image"
        ]
        #expect(expected.isSubset(of: names))
        for toolName in expected {
            let tool = try #require(tools.first { $0.name == toolName })
            #expect(try iapV4InputSchema(tool)["additionalProperties"] == .bool(false))
        }

        let list = try #require(tools.first { $0.name == "iap_list_versions" })
        let properties = try iapV4SchemaProperties(list)
        let limit = try iapV4ValueObject(properties["limit"])
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
        #expect(limit["default"] == .int(25))
        let listID = try iapV4ValueObject(properties["iap_id"])
        #expect(listID["minLength"] == .int(1))
        #expect(listID["pattern"] == .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))
        for toolName in ["iap_list_versions", "iap_list_version_localizations", "iap_list_version_images"] {
            let listTool = try #require(tools.first { $0.name == toolName })
            let listProperties = try iapV4SchemaProperties(listTool)
            let nextURL = try iapV4ValueObject(listProperties["next_url"])
            #expect(nextURL["minLength"] == .int(1))
            #expect(nextURL["format"] == .string("uri-reference"))
        }
        let imageList = try #require(tools.first { $0.name == "iap_list_version_images" })
        let imageListLimit = try iapV4ValueObject(try iapV4SchemaProperties(imageList)["limit"])
        #expect(imageListLimit["default"] == .int(25))
        let filter = try iapV4ValueObject(properties["filter_state"])
        guard case .array(let alternatives)? = filter["oneOf"],
              let scalar = alternatives.first,
              case .object(let scalarSchema) = scalar,
              case .array(let stateValues)? = scalarSchema["enum"] else {
            throw IAPV4TestFailure.expectedObject
        }
        #expect(Set(stateValues.compactMap(\.stringValue)) == Set(InAppPurchasesWorker.iapVersionStates))

        let update = try #require(tools.first { $0.name == "iap_update_version_localization" })
        let updateProperties = try iapV4SchemaProperties(update)
        for field in ["name", "description"] {
            let schema = try iapV4ValueObject(updateProperties[field])
            guard case .array(let types)? = schema["type"] else {
                throw IAPV4TestFailure.expectedObject
            }
            #expect(types == [.string("string"), .string("null")])
        }
        let updateName = try iapV4ValueObject(updateProperties["name"])
        #expect(updateName["minLength"] == .int(2))
        #expect(updateName["maxLength"] == .int(30))
        let updateDescription = try iapV4ValueObject(updateProperties["description"])
        #expect(updateDescription["maxLength"] == .int(45))
        let updateSchema = try iapV4InputSchema(update)
        #expect(updateSchema["minProperties"] == .int(2))
        guard case .array(let updateAlternatives)? = updateSchema["anyOf"] else {
            throw IAPV4TestFailure.expectedObject
        }
        let alternativeFields = try updateAlternatives.map { alternative -> String in
            let schema = try iapV4ValueObject(alternative)
            guard case .array(let required)? = schema["required"],
                  required.count == 1,
                  let field = required.first?.stringValue else {
                throw IAPV4TestFailure.expectedObject
            }
            return field
        }
        #expect(Set(alternativeFields) == ["name", "description"])
        let publishedUpdateSchema = try iapV4InputSchema(ToolMetadataPolicy.apply(to: update))
        #expect(publishedUpdateSchema["minProperties"] == .int(2))
        #expect(publishedUpdateSchema["anyOf"] == nil)

        let createLocalization = try #require(tools.first { $0.name == "iap_create_version_localization" })
        let createLocalizationProperties = try iapV4SchemaProperties(createLocalization)
        let locale = try iapV4ValueObject(createLocalizationProperties["locale"])
        #expect(locale["minLength"] == .int(2))
        #expect(locale["pattern"] == .string(#"^[a-z]{2,3}(-([A-Z]{2}|[A-Z][a-z]{3}))?$"#))
        let createName = try iapV4ValueObject(createLocalizationProperties["name"])
        #expect(createName["minLength"] == .int(2))
        #expect(createName["maxLength"] == .int(30))

        let upload = try #require(tools.first { $0.name == "iap_upload_version_image" })
        let uploadProperties = try iapV4SchemaProperties(upload)
        let filePath = try iapV4ValueObject(uploadProperties["file_path"])
        #expect(filePath["minLength"] == .int(1))
        #expect(filePath["pattern"] == .string(#"^/"#))
        #expect(filePath["description"]?.stringValue?.contains("1024x1024") == true)

        let localizationDelete = try #require(tools.first { $0.name == "iap_delete_version_localization" })
        #expect(Set(try iapV4RequiredFields(localizationDelete)) == ["localization_id", "confirm_localization_id"])
        let imageDelete = try #require(tools.first { $0.name == "iap_delete_version_image" })
        #expect(Set(try iapV4RequiredFields(imageDelete)) == ["image_id", "confirm_image_id"])
    }

    @Test("every versioned tool rejects missing required input", arguments: [
        "iap_create_version",
        "iap_get_version",
        "iap_list_versions",
        "iap_list_version_localizations",
        "iap_create_version_localization",
        "iap_get_version_localization",
        "iap_update_version_localization",
        "iap_delete_version_localization",
        "iap_get_version_image",
        "iap_list_version_images",
        "iap_upload_version_image",
        "iap_get_version_image_resource",
        "iap_delete_version_image"
    ])
    func versionedToolsRejectMissingInput(_ toolName: String) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(name: toolName, arguments: nil))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("versioned tools reject unknown arguments before transport")
    func versionedToolsRejectUnknownArguments() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version",
            arguments: [
                "version_id": .string("iap-version-1"),
                "versionId": .string("typo")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version creation uses the exact JSON API relationship")
    func createVersionUsesExactRelationship() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: iapV4VersionResponse())
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create_version",
            arguments: ["iap_id": .string("iap-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/inAppPurchaseVersions")
        let body = try iapV4JSONBody(request)
        let data = try iapV4Object(body["data"])
        let relationships = try iapV4Object(data["relationships"])
        let purchase = try iapV4Object(relationships["inAppPurchase"])
        let linkage = try iapV4Object(purchase["data"])
        #expect(data["type"] as? String == "inAppPurchaseVersions")
        #expect(linkage["type"] as? String == "inAppPurchases")
        #expect(linkage["id"] as? String == "iap-1")

        let payload = try iapV4ValueObject(result.structuredContent)
        let version = try iapV4ValueObject(payload["version"])
        #expect(version["id"] == .string("iap-version-1"))
        #expect(version["version"] == .int(3))
        #expect(version["state"] == .string("PREPARE_FOR_SUBMISSION"))
    }

    @Test("accepted create responses with an invalid status or document are committed unverified", arguments: [
        IAPV4AcceptedMutationCase(
            tool: "iap_create_version",
            arguments: ["iap_id": .string("iap-1")],
            statusCode: 200,
            responseBody: iapV4VersionResponse()
        ),
        IAPV4AcceptedMutationCase(
            tool: "iap_create_version",
            arguments: ["iap_id": .string("iap-1")],
            statusCode: 201,
            responseBody: #"{"data":{"type":"subscriptionOfferCodes","id":"iap-version-1"},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
        ),
        IAPV4AcceptedMutationCase(
            tool: "iap_create_version_localization",
            arguments: [
                "version_id": .string("iap-version-1"),
                "locale": .string("en-US"),
                "name": .string("Premium")
            ],
            statusCode: 201,
            responseBody: #"{"data":{"type":"inAppPurchaseLocalizations","id":"loc-1"}}"#
        )
    ])
    fileprivate func acceptedCreateFailuresAreCommittedUnverified(
        _ testCase: IAPV4AcceptedMutationCase
    ) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: testCase.responseBody)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.tool,
            arguments: testCase.arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        let details = try iapV4ValueObject(payload["details"])
        #expect(details["inspectionRequired"] == .bool(true))
    }

    @Test("version get uses the version resource path")
    func getVersionUsesResourcePath() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: iapV4VersionResponse())
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/inAppPurchaseVersions/iap-version-1")
    }

    @Test("reads reject malformed JSON API identity and required links", arguments: [
        IAPV4InvalidReadCase(
            tool: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseVersions","id":"other-version"},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version_localization",
            arguments: ["localization_id": .string("loc-1")],
            responseBody: #"{"data":{"type":"subscriptionLocalizations","id":"loc-1"},"links":{"self":"https://api.example.test/v2/inAppPurchaseLocalizations/loc-1"}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version_image_resource",
            arguments: ["image_id": .string("image-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseImages","id":" image-1"},"links":{"self":"https://api.example.test/v2/inAppPurchaseImages/image-1"}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"},"links":{}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"},"links":{"self":" "}}"#
        ),
        IAPV4InvalidReadCase(
            tool: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")],
            responseBody: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/other-version"}}"#
        )
    ])
    fileprivate func readsRejectMalformedIdentityAndLinks(_ testCase: IAPV4InvalidReadCase) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: testCase.responseBody)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.tool,
            arguments: testCase.arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version relationship pages disclose truncation instead of implying complete ID arrays")
    func versionRelationshipPagesDiscloseTruncation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1","relationships":{"images":{"data":[{"type":"inAppPurchaseImages","id":"image-1"}],"meta":{"paging":{"total":3,"limit":1,"nextCursor":"next-image"}}},"localizations":{"data":[{"type":"inAppPurchaseLocalizations","id":"loc-1"},{"type":"inAppPurchaseLocalizations","id":"loc-2"}],"meta":{"paging":{"total":2,"limit":2}}}}},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version",
            arguments: ["version_id": .string("iap-version-1")]
        ))

        #expect(result.isError != true)
        let payload = try iapV4ValueObject(result.structuredContent)
        let version = try iapV4ValueObject(payload["version"])
        let images = try iapV4ValueObject(version["images_page"])
        #expect(images["count"] == .int(1))
        #expect(images["total"] == .int(3))
        #expect(images["limit"] == .int(1))
        #expect(images["next_cursor"] == .string("next-image"))
        #expect(images["truncated"] == .bool(true))
        #expect(images["completeness_known"] == .bool(true))
        let localizations = try iapV4ValueObject(version["localizations_page"])
        #expect(localizations["count"] == .int(2))
        #expect(localizations["total"] == .int(2))
        #expect(localizations["truncated"] == .bool(false))
    }

    @Test("version relationship projection preserves absent omitted-data and known-empty states")
    func relationshipProjectionPreservesTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1","relationships":{"images":{},"localizations":{}}},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1","relationships":{"images":{"data":[]},"localizations":{"data":[]}}},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
            )
        ])
        let worker = try await iapV4Worker(transport)
        var results: [CallTool.Result] = []
        for _ in 0..<3 {
            results.append(try await worker.handleTool(CallTool.Parameters(
                name: "iap_get_version",
                arguments: ["version_id": .string("iap-version-1")]
            )))
        }

        let absent = try iapV4ValueObject(try iapV4ValueObject(results[0].structuredContent)["version"])
        #expect(absent["image_ids"] == nil)
        #expect(absent["localization_ids"] == nil)
        #expect(absent["images_page"] == nil)
        #expect(absent["localizations_page"] == nil)

        let omittedData = try iapV4ValueObject(try iapV4ValueObject(results[1].structuredContent)["version"])
        #expect(omittedData["image_ids"] == nil)
        #expect(omittedData["localization_ids"] == nil)
        let omittedImagesPage = try iapV4ValueObject(omittedData["images_page"])
        #expect(omittedImagesPage["data_returned"] == .bool(false))
        #expect(omittedImagesPage["completeness_known"] == .bool(false))
        #expect(omittedImagesPage["ids"] == nil)
        #expect(omittedImagesPage["count"] == nil)

        let empty = try iapV4ValueObject(try iapV4ValueObject(results[2].structuredContent)["version"])
        #expect(empty["image_ids"] == .array([]))
        #expect(empty["localization_ids"] == .array([]))
        let emptyImagesPage = try iapV4ValueObject(empty["images_page"])
        #expect(emptyImagesPage["data_returned"] == .bool(true))
        #expect(emptyImagesPage["ids"] == .array([]))
        #expect(emptyImagesPage["count"] == .int(0))
    }

    @Test("collections reject duplicate identities and a mismatched owner")
    func collectionsRejectDuplicateIdentitiesAndMismatchedOwner() async throws {
        let versionsTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"inAppPurchaseVersions","id":"version-1","relationships":{"inAppPurchase":{"data":{"type":"inAppPurchases","id":"iap-1"}}}},{"type":"inAppPurchaseVersions","id":"version-1","relationships":{"inAppPurchase":{"data":{"type":"inAppPurchases","id":"iap-1"}}}}],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/versions?limit=25"}}"#)
        ])
        let versionsWorker = try await iapV4Worker(versionsTransport)

        let versions = try await versionsWorker.handleTool(CallTool.Parameters(
            name: "iap_list_versions",
            arguments: ["iap_id": .string("iap-1")]
        ))

        #expect(versions.isError == true)
        #expect(await versionsTransport.requestCount() == 1)

        let localizationsTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[{"type":"inAppPurchaseLocalizations","id":"loc-1","relationships":{"version":{"data":{"type":"inAppPurchaseVersions","id":"other-version"}}}}],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/version-1/localizations?limit=25"}}"#)
        ])
        let localizationsWorker = try await iapV4Worker(localizationsTransport)

        let localizations = try await localizationsWorker.handleTool(CallTool.Parameters(
            name: "iap_list_version_localizations",
            arguments: ["version_id": .string("version-1")]
        ))

        #expect(localizations.isError == true)
        #expect(await localizationsTransport.requestCount() == 1)
    }

    @Test("version list projects total and preserves exact filters")
    func listVersionsProjectsTotalAndFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "inAppPurchaseVersions",
                "id": "iap-version-1",
                "attributes": {"version": 3, "state": "READY_FOR_REVIEW"},
                "relationships": {"inAppPurchase":{"data":{"type":"inAppPurchases","id":"iap-1"}}}
              }],
              "links": {
                "self": "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=READY_FOR_REVIEW%2CREJECTED&limit=100",
                "next": "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=READY_FOR_REVIEW%2CREJECTED&limit=100&cursor=next"
              },
              "meta": {"paging": {"total": 7, "limit": 100, "nextCursor": "next"}}
            }
            """)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_versions",
            arguments: [
                "iap_id": .string("iap-1"),
                "filter_state": .array([.string("READY_FOR_REVIEW"), .string("REJECTED")]),
                "limit": .int(100)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v2/inAppPurchases/iap-1/versions")
        let query = iapV4Query(request)
        #expect(query["filter[state]"] == "READY_FOR_REVIEW,REJECTED")
        #expect(query["limit"] == "100")
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(7))
        #expect(payload["next_url"] == .string("https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=READY_FOR_REVIEW%2CREJECTED&limit=100&cursor=next"))
    }

    @Test("top-level collections reject malformed or contradictory paging metadata")
    func topLevelCollectionsRejectInvalidPagingMetadata() async throws {
        let cases: [(String, [String: Value], String)] = [
            (
                "iap_list_versions",
                ["iap_id": .string("iap-1")],
                iapV4VersionCollectionResponse(meta: "{}")
            ),
            (
                "iap_list_version_localizations",
                ["version_id": .string("version-1")],
                iapV4LocalizationCollectionResponse(meta: #"{"paging":{}}"#)
            ),
            (
                "iap_list_versions",
                ["iap_id": .string("iap-1")],
                iapV4VersionCollectionResponse(meta: #"{"paging":{"limit":0}}"#)
            ),
            (
                "iap_list_versions",
                ["iap_id": .string("iap-1")],
                iapV4VersionCollectionResponse(
                    meta: #"{"paging":{"total":2,"limit":1}}"#,
                    count: 2
                )
            ),
            (
                "iap_list_version_localizations",
                ["version_id": .string("version-1")],
                iapV4LocalizationCollectionResponse(meta: #"{"paging":{"total":-1,"limit":25}}"#)
            ),
            (
                "iap_list_version_localizations",
                ["version_id": .string("version-1")],
                iapV4LocalizationCollectionResponse(meta: #"{"paging":{"total":0,"limit":25}}"#)
            ),
            (
                "iap_list_versions",
                ["iap_id": .string("iap-1")],
                iapV4VersionCollectionResponse(
                    meta: #"{"paging":{"limit":25,"nextCursor":""}}"#,
                    count: 0
                )
            ),
            (
                "iap_list_version_localizations",
                ["version_id": .string("version-1")],
                iapV4LocalizationCollectionResponse(
                    meta: #"{"paging":{"limit":25,"nextCursor":"cursor-without-link"}}"#,
                    count: 0
                )
            )
        ]

        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await iapV4Worker(transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: tool,
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("nested image relationships reject malformed or contradictory paging metadata")
    func nestedRelationshipsRejectInvalidPagingMetadata() async throws {
        let cases: [(String, Int)] = [
            ("{}", 1),
            (#"{"paging":{}}"#, 1),
            (#"{"paging":{"limit":0}}"#, 1),
            (#"{"paging":{"total":2,"limit":1}}"#, 2),
            (#"{"paging":{"total":-1,"limit":25}}"#, 1),
            (#"{"paging":{"total":0,"limit":25}}"#, 1),
            (#"{"paging":{"limit":25,"nextCursor":""}}"#, 1)
        ]

        for (meta, count) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: iapV4VersionRelationshipResponse(meta: meta, count: count))
            ])
            let worker = try await iapV4Worker(transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "iap_get_version",
                arguments: ["version_id": .string("iap-version-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("version list rejects invalid filter and limit before transport", arguments: [
        IAPV4InvalidListArguments(arguments: ["iap_id": .string("iap-1"), "filter_state": .string("UNKNOWN")]),
        IAPV4InvalidListArguments(arguments: ["iap_id": .string("iap-1"), "filter_state": .array([.string("REJECTED"), .string("REJECTED")])]),
        IAPV4InvalidListArguments(arguments: ["iap_id": .string("iap-1"), "filter_state": .string("REJECTED,APPROVED")]),
        IAPV4InvalidListArguments(arguments: ["iap_id": .string("iap-1"), "limit": .int(0)]),
        IAPV4InvalidListArguments(arguments: ["iap_id": .string("iap-1"), "limit": .int(201)])
    ])
    fileprivate func listVersionsRejectsInvalidArguments(_ testCase: IAPV4InvalidListArguments) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_versions",
            arguments: testCase.arguments
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version pagination rejects changed scope before transport", arguments: [
        "https://example.invalid/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next",
        "https://api.example.test/v2/inAppPurchases/iap-2/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next",
        "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=APPROVED&limit=25&cursor=next",
        "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=50&cursor=next",
        "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=",
        "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=a&cursor=b",
        "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next&include=images"
    ])
    func versionPaginationRejectsChangedScope(_ nextURL: String) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_versions",
            arguments: [
                "iap_id": .string("iap-1"),
                "filter_state": .string("REJECTED"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version pagination follows a full validated continuation")
    func versionPaginationFollowsValidatedContinuation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next"},"meta":{"paging":{"total":0,"limit":25}}}"#)
        ])
        let worker = try await iapV4Worker(transport)
        let nextURL = "https://api.example.test/v2/inAppPurchases/iap-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_versions",
            arguments: [
                "iap_id": .string("iap-1"),
                "filter_state": .string("REJECTED"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(iapV4Query(request)["cursor"] == "next")
    }

    @Test("create localization preserves description omission value and null", arguments: [
        IAPV4NullableCase.omitted,
        IAPV4NullableCase.value,
        IAPV4NullableCase.null
    ])
    fileprivate func createLocalizationPreservesTriState(_ nullableCase: IAPV4NullableCase) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: iapV4LocalizationResponse())
        ])
        let worker = try await iapV4Worker(transport)
        var arguments: [String: Value] = [
            "version_id": .string("iap-version-1"),
            "locale": .string("en-US"),
            "name": .string("Premium")
        ]
        nullableCase.apply(to: &arguments, key: "description")

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_create_version_localization",
            arguments: arguments
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v2/inAppPurchaseLocalizations")
        let body = try iapV4JSONBody(request)
        let data = try iapV4Object(body["data"])
        let attributes = try iapV4Object(data["attributes"])
        let relationships = try iapV4Object(data["relationships"])
        let version = try iapV4Object(relationships["version"])
        let linkage = try iapV4Object(version["data"])
        #expect(data["type"] as? String == "inAppPurchaseLocalizations")
        #expect(attributes["locale"] as? String == "en-US")
        #expect(attributes["name"] as? String == "Premium")
        nullableCase.expect(in: attributes, key: "description")
        #expect(linkage["type"] as? String == "inAppPurchaseVersions")
        #expect(linkage["id"] as? String == "iap-version-1")
    }

    @Test("update localization preserves omitted value and null independently")
    func updateLocalizationPreservesTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: iapV4LocalizationResponse())
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update_version_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "name": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v2/inAppPurchaseLocalizations/loc-1")
        let body = try iapV4JSONBody(request)
        let attributes = try iapV4Object(try iapV4Object(body["data"])["attributes"])
        #expect(attributes.keys.contains("name"))
        #expect(attributes["name"] is NSNull)
        #expect(attributes.keys.contains("description") == false)
    }

    @Test("accepted localization update with invalid status or identity is committed unverified", arguments: [
        IAPV4UpdateResponseCase(statusCode: 202, responseBody: iapV4LocalizationResponse()),
        IAPV4UpdateResponseCase(
            statusCode: 200,
            responseBody: #"{"data":{"type":"inAppPurchaseLocalizations","id":"other-loc"},"links":{"self":"https://api.example.test/v2/inAppPurchaseLocalizations/loc-1"}}"#
        )
    ])
    fileprivate func invalidAcceptedUpdateIsCommittedUnverified(
        _ testCase: IAPV4UpdateResponseCase
    ) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: testCase.responseBody)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update_version_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "name": .null,
                "description": .string("Copy")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        let details = try iapV4ValueObject(payload["details"])
        #expect(details["localization_id"] == .string("loc-1"))
        #expect(details["name"] == .null)
        #expect(details["description"] == .string("Copy"))
    }

    @Test("localization update network failure is outcome unknown after one request")
    func updateNetworkFailureIsOutcomeUnknown() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update_version_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "name": .null,
                "description": .string("Copy")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        let details = try iapV4ValueObject(payload["details"])
        #expect(details["localization_id"] == .string("loc-1"))
        #expect(details["name"] == .null)
        #expect(details["description"] == .string("Copy"))
    }

    @Test("update localization requires a meaningful field")
    func updateLocalizationRequiresField() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_update_version_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization display names shorter than two characters are rejected before transport")
    func localizationNamesEnforceAppleMinimum() async throws {
        let createTransport = TestHTTPTransport(responses: [])
        let createWorker = try await iapV4Worker(createTransport)
        let create = try await createWorker.handleTool(CallTool.Parameters(
            name: "iap_create_version_localization",
            arguments: [
                "version_id": .string("iap-version-1"),
                "locale": .string("en-US"),
                "name": .string("A")
            ]
        ))

        let updateTransport = TestHTTPTransport(responses: [])
        let updateWorker = try await iapV4Worker(updateTransport)
        let update = try await updateWorker.handleTool(CallTool.Parameters(
            name: "iap_update_version_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "name": .string("")
            ]
        ))

        #expect(create.isError == true)
        #expect(update.isError == true)
        #expect(await createTransport.requestCount() == 0)
        #expect(await updateTransport.requestCount() == 0)
    }

    @Test("version localization list uses strict pagination and total")
    func localizationListUsesStrictPaginationAndTotal() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {"data":[],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/localizations?limit=75","next":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/localizations?limit=75&cursor=next"},"meta":{"paging":{"total":4,"limit":75,"nextCursor":"next"}}}
            """)
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_version_localizations",
            arguments: ["version_id": .string("iap-version-1"), "limit": .int(75)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/inAppPurchaseVersions/iap-version-1/localizations")
        #expect(iapV4Query(request)["limit"] == "75")
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["total"] == .int(4))
    }

    @Test("localization resource get and delete use v2 paths")
    func localizationGetAndDeleteUseV2Paths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: iapV4LocalizationResponse()),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await iapV4Worker(transport)

        let get = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))
        let delete = try await worker.handleTool(CallTool.Parameters(
            name: "iap_delete_version_localization",
            arguments: [
                "localization_id": .string("loc-1"),
                "confirm_localization_id": .string("loc-1")
            ]
        ))

        #expect(get.isError != true)
        #expect(delete.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/inAppPurchaseLocalizations/loc-1",
            "/v2/inAppPurchaseLocalizations/loc-1"
        ])
    }

    @Test("versioned deletes require exact confirmation before transport", arguments: IAPV4DeleteTarget.allCases)
    fileprivate func deletesRequireExactConfirmation(_ target: IAPV4DeleteTarget) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let missing = try await worker.handleTool(CallTool.Parameters(
            name: target.tool,
            arguments: [target.idField: .string(target.id)]
        ))
        let mismatched = try await worker.handleTool(CallTool.Parameters(
            name: target.tool,
            arguments: [
                target.idField: .string(target.id),
                target.confirmationField: .string("other-id")
            ]
        ))

        #expect(missing.isError == true)
        #expect(mismatched.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("versioned deletes classify exact HTTP outcomes without an ambiguous retry", arguments: [
        IAPV4DeleteResponseCase(target: .localization, statusCode: 204, expectedState: "confirmed"),
        IAPV4DeleteResponseCase(target: .localization, statusCode: 202, expectedState: "committed_unverified"),
        IAPV4DeleteResponseCase(target: .localization, statusCode: 500, expectedState: "commit_unknown"),
        IAPV4DeleteResponseCase(target: .image, statusCode: 204, expectedState: "confirmed"),
        IAPV4DeleteResponseCase(target: .image, statusCode: 202, expectedState: "committed_unverified"),
        IAPV4DeleteResponseCase(target: .image, statusCode: 500, expectedState: "commit_unknown")
    ])
    fileprivate func deletesClassifyExactHTTPOutcomes(_ testCase: IAPV4DeleteResponseCase) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: testCase.statusCode, body: "")
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: testCase.target.tool,
            arguments: [
                testCase.target.idField: .string(testCase.target.id),
                testCase.target.confirmationField: .string(testCase.target.id)
            ]
        ))

        #expect(await transport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        if testCase.expectedState == "confirmed" {
            #expect(result.isError != true)
            #expect(payload["deletionState"] == .string("confirmed"))
            #expect(payload["outcomeUnknown"] == .bool(false))
            #expect(payload["retrySafe"] == .bool(false))
        } else {
            #expect(result.isError == true)
            #expect(payload["retrySafe"] == .bool(false))
            let details = try iapV4ValueObject(payload["details"])
            #expect(details["deletionState"] == .string(testCase.expectedState))
            #expect(details[testCase.target.idField] == .string(testCase.target.id))
            if testCase.expectedState == "committed_unverified" {
                #expect(payload["operationCommitState"] == .string("committed_unverified"))
                #expect(payload["operationCommitted"] == .bool(true))
                #expect(payload["outcomeUnknown"] == .bool(false))
            } else {
                #expect(payload["operationCommitState"] == .string("unknown"))
                #expect(payload["outcomeUnknown"] == .bool(true))
            }
        }
    }

    @Test("versioned delete network failure is commit unknown after one request")
    func deleteNetworkFailureIsCommitUnknown() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: IAPV4DeleteTarget.image.tool,
            arguments: [
                IAPV4DeleteTarget.image.idField: .string(IAPV4DeleteTarget.image.id),
                IAPV4DeleteTarget.image.confirmationField: .string(IAPV4DeleteTarget.image.id)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("singular version image and v2 image resource use distinct exact paths")
    func imageGettersUseExactPaths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: iapV4ImageResponse(
                    state: "COMPLETE",
                    selfPath: "/v1/inAppPurchaseVersions/iap-version-1/image"
                )
            ),
            .init(statusCode: 200, body: iapV4ImageResponse(state: "COMPLETE")),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await iapV4Worker(transport)

        let related = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version_image",
            arguments: ["version_id": .string("iap-version-1")]
        ))
        let resource = try await worker.handleTool(CallTool.Parameters(
            name: "iap_get_version_image_resource",
            arguments: ["image_id": .string("image-1")]
        ))
        let delete = try await worker.handleTool(CallTool.Parameters(
            name: "iap_delete_version_image",
            arguments: [
                "image_id": .string("image-1"),
                "confirm_image_id": .string("image-1")
            ]
        ))

        #expect(related.isError != true)
        #expect(resource.isError != true)
        #expect(delete.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/inAppPurchaseVersions/iap-version-1/image",
            "/v2/inAppPurchaseImages/image-1",
            "/v2/inAppPurchaseImages/image-1"
        ])
        let payload = try iapV4ValueObject(resource.structuredContent)
        let image = try iapV4ValueObject(payload["image"])
        #expect(image["delivery_state"] == .string("COMPLETE"))
        #expect(image["file_name"] == .string("image.png"))
        #expect(image["asset_token"] == nil)
        #expect(image["upload_operations"] == nil)
    }

    @Test("version image list enumerates the plural relationship without exposing upload credentials")
    func imageListUsesExactPluralPathAndRedactsTransferFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","assetToken":"private-upload-token","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk","length":5,"offset":0,"requestHeaders":[]}],"assetDeliveryState":{"state":"AWAITING_UPLOAD"}}}],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/images?limit=25"},"meta":{"paging":{"total":1,"limit":25}}}"#
            )
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_version_images",
            arguments: ["version_id": .string("iap-version-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/inAppPurchaseVersions/iap-version-1/images")
        #expect(iapV4Query(request)["limit"] == "25")
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(1))
        guard case .array(let images)? = payload["images"], let first = images.first else {
            throw IAPV4TestFailure.expectedObject
        }
        let image = try iapV4ValueObject(first)
        #expect(image["id"] == .string("image-1"))
        #expect(image["asset_token"] == nil)
        #expect(image["upload_operations"] == nil)
    }

    @Test("version image list follows only an exact continuation scope")
    func imageListValidatesContinuationScope() async throws {
        let validURL = "https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/images?limit=25&cursor=next"
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/images?limit=25&cursor=next"},"meta":{"paging":{"total":0,"limit":25}}}"#
            )
        ])
        let worker = try await iapV4Worker(transport)

        let valid = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_version_images",
            arguments: [
                "version_id": .string("iap-version-1"),
                "next_url": .string(validURL)
            ]
        ))

        #expect(valid.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/inAppPurchaseVersions/iap-version-1/images")
        #expect(iapV4Query(request)["limit"] == "25")
        #expect(iapV4Query(request)["cursor"] == "next")

        for invalidURL in [
            "https://api.example.test/v1/inAppPurchaseVersions/other-version/images?limit=25&cursor=next",
            "https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/images?limit=50&cursor=next"
        ] {
            let invalidTransport = TestHTTPTransport(responses: [])
            let invalidWorker = try await iapV4Worker(invalidTransport)
            let invalid = try await invalidWorker.handleTool(CallTool.Parameters(
                name: "iap_list_version_images",
                arguments: [
                    "version_id": .string("iap-version-1"),
                    "next_url": .string(invalidURL)
                ]
            ))

            #expect(invalid.isError == true)
            #expect(await invalidTransport.requestCount() == 0)
        }
    }

    @Test("version image list rejects duplicate resource identities")
    func imageListRejectsDuplicateResources() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"inAppPurchaseImages","id":"image-1"},{"type":"inAppPurchaseImages","id":"image-1"}],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1/images?limit=25"},"meta":{"paging":{"total":2,"limit":25}}}"#
            )
        ])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_list_version_images",
            arguments: ["version_id": .string("iap-version-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("version image upload rejects relative paths before snapshot or transport")
    func versionImageUploadRejectsRelativeFilePath() async throws {
        #expect(FileManager.default.fileExists(atPath: "Package.swift"))
        let transport = TestHTTPTransport(responses: [])
        let worker = try await iapV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_version_image",
            arguments: [
                "version_id": .string("iap-version-1"),
                "file_path": .string("Package.swift")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version image upload refuses mismatched or non-transferable reservations")
    func versionImageUploadValidatesReservationBeforeTransfer() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iap-version-image-validation-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let invalidReservations = [
            iapV4ImageResponse(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileSize: 6,
                fileName: fileURL.lastPathComponent
            ),
            iapV4ImageResponse(
                state: "COMPLETE",
                includeUploadOperation: true,
                fileName: fileURL.lastPathComponent
            ),
            iapV4ImageResponse(
                state: "AWAITING_UPLOAD",
                fileName: fileURL.lastPathComponent
            )
        ]

        for reservation in invalidReservations {
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: reservation),
                .init(statusCode: 204, body: "")
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: apiTransport,
                maxRetries: 1
            )
            let worker = InAppPurchasesWorker(
                httpClient: client,
                uploadService: UploadService(transport: uploadTransport, batchSize: 1),
                deliveryPollAttempts: 1,
                deliveryPollIntervalNanoseconds: 0
            )

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "iap_upload_version_image",
                arguments: [
                    "version_id": .string("iap-version-1"),
                    "file_path": .string(fileURL.path)
                ]
            ))

            #expect(result.isError == true)
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("unknown image reservation directs recovery to the plural version collection")
    func unknownImageReservationUsesPluralInspectionTool() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iap-version-image-unknown-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService(),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_version_image",
            arguments: [
                "version_id": .string("iap-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.requestCount() == 1)
        let payload = try iapV4ValueObject(result.structuredContent)
        #expect(payload["sourceFileChecksumReceipt"]?.stringValue?.count == 32)
        let fingerprint = try iapV4ValueObject(payload["reservationFingerprint"])
        #expect(fingerprint["file_name"] == .string(fileURL.lastPathComponent))
        #expect(fingerprint["file_size"] == .int(5))
        #expect(fingerprint["checksum"] == payload["sourceFileChecksumReceipt"])
        let inspection = try iapV4ValueObject(payload["inspection"])
        #expect(inspection["tool"] == .string("iap_list_version_images"))
        #expect(inspection["continue_with_next_url"] == .bool(true))
        #expect(inspection["next_url_argument"] == .string("next_url"))
        let arguments = try iapV4ValueObject(inspection["arguments"])
        #expect(arguments["version_id"] == .string("iap-version-1"))
        #expect(arguments["limit"] == .int(200))
        let candidateMatch = try iapV4ValueObject(inspection["candidate_match"])
        #expect(candidateMatch["fingerprint_key"] == .string("reservationFingerprint"))
        #expect(candidateMatch["candidate_fields"] == .array([.string("file_name"), .string("file_size")]))
        #expect(candidateMatch["require_unique_match_before_retry"] == .bool(true))
    }

    @Test("retained image cleanup guidance carries exact delete confirmation")
    func retainedImageCleanupIncludesConfirmationID() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iap-version-image-retained-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: iapV4ImageResponse(
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true,
                    fileName: fileURL.lastPathComponent
                )
            ),
            .init(
                statusCode: 202,
                body: iapV4ImageResponse(
                    state: "AWAITING_UPLOAD",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_version_image",
            arguments: [
                "version_id": .string("iap-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError == true)
        let payload = try iapV4ValueObject(result.structuredContent)
        let cleanup = try iapV4ValueObject(payload["cleanup"])
        #expect(cleanup["tool"] == .string("iap_delete_version_image"))
        let arguments = try iapV4ValueObject(cleanup["arguments"])
        #expect(arguments["image_id"] == .string("image-1"))
        #expect(arguments["confirm_image_id"] == .string("image-1"))
    }

    @Test("version image upload reserves transfers commits and projects terminal state")
    func versionImageUploadUsesHardenedTransaction() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iap-version-image-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: iapV4ImageResponse(
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true,
                    fileName: fileURL.lastPathComponent
                )
            ),
            .init(
                statusCode: 200,
                body: iapV4ImageResponse(
                    state: "COMPLETE",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_version_image",
            arguments: [
                "version_id": .string("iap-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/inAppPurchaseImages",
            "/v2/inAppPurchaseImages/image-1"
        ])
        let reservation = try iapV4Object(try iapV4JSONBody(requests[0])["data"])
        let attributes = try iapV4Object(reservation["attributes"])
        let relationships = try iapV4Object(reservation["relationships"])
        let version = try iapV4Object(relationships["version"])
        let linkage = try iapV4Object(version["data"])
        #expect(reservation["type"] as? String == "inAppPurchaseImages")
        #expect(attributes["fileName"] as? String == fileURL.lastPathComponent)
        #expect(attributes["fileSize"] as? Int == 5)
        #expect(linkage["type"] as? String == "inAppPurchaseVersions")
        #expect(linkage["id"] as? String == "iap-version-1")
        let commit = try iapV4Object(try iapV4JSONBody(requests[1])["data"])
        let commitAttributes = try iapV4Object(commit["attributes"])
        #expect(commit["type"] as? String == "inAppPurchaseImages")
        #expect(commit["id"] as? String == "image-1")
        #expect(commitAttributes["uploaded"] as? Bool == true)
        #expect(commitAttributes.keys.contains("sourceFileChecksum") == false)
        let uploadRequest = try #require(await uploadTransport.recordedRequests().first)
        #expect(uploadRequest.httpBody == Data("hello".utf8))
        let payload = try iapV4ValueObject(result.structuredContent)
        let image = try iapV4ValueObject(payload["image"])
        #expect(image["delivery_state"] == .string("COMPLETE"))
        #expect(image["asset_token"] == nil)
        #expect(image["upload_operations"] == nil)
    }
}

private struct IAPV4InvalidListArguments: Sendable, CustomTestStringConvertible {
    let arguments: [String: Value]
    var testDescription: String { String(describing: arguments) }
}

private struct IAPV4InvalidReadCase: Sendable, CustomTestStringConvertible {
    let tool: String
    let arguments: [String: Value]
    let responseBody: String
    var testDescription: String { tool }
}

private struct IAPV4AcceptedMutationCase: Sendable, CustomTestStringConvertible {
    let tool: String
    let arguments: [String: Value]
    let statusCode: Int
    let responseBody: String
    var testDescription: String { "\(tool)-\(statusCode)" }
}

private struct IAPV4UpdateResponseCase: Sendable, CustomTestStringConvertible {
    let statusCode: Int
    let responseBody: String
    var testDescription: String { "update-\(statusCode)" }
}

private enum IAPV4DeleteTarget: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case localization
    case image

    var testDescription: String { rawValue }

    var tool: String {
        switch self {
        case .localization: "iap_delete_version_localization"
        case .image: "iap_delete_version_image"
        }
    }

    var idField: String {
        switch self {
        case .localization: "localization_id"
        case .image: "image_id"
        }
    }

    var confirmationField: String {
        switch self {
        case .localization: "confirm_localization_id"
        case .image: "confirm_image_id"
        }
    }

    var id: String {
        switch self {
        case .localization: "loc-1"
        case .image: "image-1"
        }
    }
}

private struct IAPV4DeleteResponseCase: Sendable, CustomTestStringConvertible {
    let target: IAPV4DeleteTarget
    let statusCode: Int
    let expectedState: String
    var testDescription: String { "\(target.rawValue)-\(statusCode)" }
}

private enum IAPV4NullableCase: String, Sendable, CustomTestStringConvertible {
    case omitted
    case value
    case null

    var testDescription: String { rawValue }

    func apply(to arguments: inout [String: Value], key: String) {
        switch self {
        case .omitted:
            break
        case .value:
            arguments[key] = .string("Localized copy")
        case .null:
            arguments[key] = .null
        }
    }

    func expect(in attributes: [String: Any], key: String) {
        switch self {
        case .omitted:
            #expect(attributes.keys.contains(key) == false)
        case .value:
            #expect(attributes[key] as? String == "Localized copy")
        case .null:
            #expect(attributes[key] is NSNull)
        }
    }
}

private func iapV4Worker(_ transport: TestHTTPTransport) async throws -> InAppPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return InAppPurchasesWorker(
        httpClient: client,
        uploadService: UploadService(),
        deliveryPollAttempts: 1,
        deliveryPollIntervalNanoseconds: 0
    )
}

private func iapV4VersionResponse() -> String {
    #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1","attributes":{"version":3,"state":"PREPARE_FOR_SUBMISSION"},"relationships":{"inAppPurchase":{"data":{"type":"inAppPurchases","id":"iap-1"}},"image":{"data":{"type":"inAppPurchaseImages","id":"image-1"}},"images":{"data":[{"type":"inAppPurchaseImages","id":"image-1"}]},"localizations":{"data":[{"type":"inAppPurchaseLocalizations","id":"loc-1"}]}}},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
}

private func iapV4LocalizationResponse() -> String {
    #"{"data":{"type":"inAppPurchaseLocalizations","id":"loc-1","attributes":{"locale":"en-US","name":"Premium","description":"Localized copy"},"relationships":{"version":{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1"}}}},"links":{"self":"https://api.example.test/v2/inAppPurchaseLocalizations/loc-1"}}"#
}

private func iapV4ImageResponse(
    state: String,
    includeUploadOperation: Bool = false,
    selfPath: String = "/v2/inAppPurchaseImages/image-1",
    fileSize: Int = 5,
    fileName: String = "image.png"
) -> String {
    let operations = includeUploadOperation
        ? #", "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk","length":5,"offset":0,"requestHeaders":[]}]"#
        : ""
    return #"{"data":{"type":"inAppPurchaseImages","id":"image-1","attributes":{"fileSize":\#(fileSize),"fileName":"\#(fileName)","assetToken":"private-upload-token","assetDeliveryState":{"state":"\#(state)"}\#(operations)}},"links":{"self":"https://api.example.test\#(selfPath)"}}"#
}

private func iapV4VersionCollectionResponse(meta: String, count: Int = 1) -> String {
    let resources = (0..<count).map { index in
        #"{"type":"inAppPurchaseVersions","id":"version-\#(index + 1)","relationships":{"inAppPurchase":{"data":{"type":"inAppPurchases","id":"iap-1"}}}}"#
    }.joined(separator: ",")
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v2/inAppPurchases/iap-1/versions?limit=25"},"meta":\#(meta)}"#
}

private func iapV4LocalizationCollectionResponse(meta: String, count: Int = 1) -> String {
    let resources = (0..<count).map { index in
        #"{"type":"inAppPurchaseLocalizations","id":"loc-\#(index + 1)","relationships":{"version":{"data":{"type":"inAppPurchaseVersions","id":"version-1"}}}}"#
    }.joined(separator: ",")
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/version-1/localizations?limit=25"},"meta":\#(meta)}"#
}

private func iapV4VersionRelationshipResponse(meta: String, count: Int) -> String {
    let resources = (0..<count).map { index in
        #"{"type":"inAppPurchaseImages","id":"image-\#(index + 1)"}"#
    }.joined(separator: ",")
    return #"{"data":{"type":"inAppPurchaseVersions","id":"iap-version-1","relationships":{"images":{"data":[\#(resources)],"meta":\#(meta)}}},"links":{"self":"https://api.example.test/v1/inAppPurchaseVersions/iap-version-1"}}"#
}

private func iapV4Query(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: URLComponents(
        url: request.url ?? URL(string: "https://invalid")!,
        resolvingAgainstBaseURL: false
    )?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
}

private func iapV4JSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw IAPV4TestFailure.expectedObject
    }
    return object
}

private func iapV4Object(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw IAPV4TestFailure.expectedObject
    }
    return object
}

private func iapV4ValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw IAPV4TestFailure.expectedObject
    }
    return object
}

private func iapV4SchemaProperties(_ tool: Tool) throws -> [String: Value] {
    let root = try iapV4InputSchema(tool)
    guard case .object(let properties)? = root["properties"] else {
        throw IAPV4TestFailure.expectedObject
    }
    return properties
}

private func iapV4InputSchema(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let root) = tool.inputSchema else {
        throw IAPV4TestFailure.expectedObject
    }
    return root
}

private func iapV4RequiredFields(_ tool: Tool) throws -> [String] {
    guard case .object(let root) = tool.inputSchema,
          case .array(let required)? = root["required"] else {
        throw IAPV4TestFailure.expectedObject
    }
    return required.compactMap(\.stringValue)
}

private enum IAPV4TestFailure: Error {
    case expectedObject
}
