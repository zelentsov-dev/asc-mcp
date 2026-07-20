import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Subscription Version Contract Tests")
struct SubscriptionVersionsContractTests {
    static let expectedTools: Set<String> = [
        "subscriptions_create_version",
        "subscriptions_get_version",
        "subscriptions_list_versions",
        "subscriptions_list_version_localizations",
        "subscriptions_create_version_localization",
        "subscriptions_get_version_localization",
        "subscriptions_update_version_localization",
        "subscriptions_delete_version_localization",
        "subscriptions_list_version_images",
        "subscriptions_upload_version_image",
        "subscriptions_get_version_image",
        "subscriptions_delete_version_image",
        "subscriptions_create_group_version",
        "subscriptions_get_group_version",
        "subscriptions_list_group_versions",
        "subscriptions_list_group_version_localizations",
        "subscriptions_create_group_version_localization",
        "subscriptions_get_group_version_localization",
        "subscriptions_update_group_version_localization",
        "subscriptions_delete_group_version_localization"
    ]

    @Test("versioned schemas expose exact states bounds and nullable fields")
    func schemasExposeExactContracts() async throws {
        let worker = try await subscriptionV4Worker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        #expect(Self.expectedTools.isSubset(of: Set(tools.map(\.name))))

        for toolName in ["subscriptions_list_versions", "subscriptions_list_group_versions"] {
            let tool = try #require(tools.first { $0.name == toolName })
            let properties = try subscriptionV4SchemaProperties(tool)
            let limit = try subscriptionV4ValueObject(properties["limit"])
            #expect(limit["minimum"] == .int(1))
            #expect(limit["maximum"] == .int(200))
            #expect(limit["default"] == .int(25))
            let nextURL = try subscriptionV4ValueObject(properties["next_url"])
            #expect(nextURL["format"] == .string("uri-reference"))
            #expect(nextURL["description"]?.stringValue?.contains("default 25") == true)
            let filter = try subscriptionV4ValueObject(properties["filter_state"])
            guard case .array(let alternatives)? = filter["oneOf"],
                  let scalar = alternatives.first,
                  case .object(let scalarSchema) = scalar,
                  case .array(let stateValues)? = scalarSchema["enum"] else {
                throw SubscriptionV4TestFailure.expectedObject
            }
            #expect(Set(stateValues.compactMap(\.stringValue)) == Set(SubscriptionsWorker.subscriptionVersionStates))
        }

        let nullableFields: [(String, [String])] = [
            ("subscriptions_create_version_localization", ["description"]),
            ("subscriptions_update_version_localization", ["name", "description"]),
            ("subscriptions_create_group_version_localization", ["custom_app_name"]),
            ("subscriptions_update_group_version_localization", ["name", "custom_app_name"])
        ]
        for (toolName, fields) in nullableFields {
            let tool = try #require(tools.first { $0.name == toolName })
            let properties = try subscriptionV4SchemaProperties(tool)
            for field in fields {
                let schema = try subscriptionV4ValueObject(properties[field])
                guard case .array(let types)? = schema["type"] else {
                    throw SubscriptionV4TestFailure.expectedObject
                }
                #expect(types == [.string("string"), .string("null")])
            }
        }
        for toolName in [
            "subscriptions_update_version_localization",
            "subscriptions_update_group_version_localization"
        ] {
            let tool = try #require(tools.first { $0.name == toolName })
            guard case .object(let schema) = tool.inputSchema,
                  case .object(let publishedSchema) = ToolMetadataPolicy.apply(to: tool).inputSchema else {
                throw SubscriptionV4TestFailure.expectedObject
            }
            #expect(schema["minProperties"] == .int(2))
            #expect(publishedSchema["minProperties"] == .int(2))
        }
        for toolName in [
            "subscriptions_create_version_localization",
            "subscriptions_create_group_version_localization"
        ] {
            let properties = try subscriptionV4SchemaProperties(try #require(tools.first { $0.name == toolName }))
            let locale = try subscriptionV4ValueObject(properties["locale"])
            #expect(locale["pattern"] == .string(#"^[a-z]{2,3}(-([A-Z]{2}|[A-Z][a-z]{3}))?$"#))
        }
        let createLocalization = try subscriptionV4SchemaProperties(
            try #require(tools.first { $0.name == "subscriptions_create_version_localization" })
        )
        #expect(try subscriptionV4ValueObject(createLocalization["name"])["minLength"] == .int(1))
        #expect(try subscriptionV4ValueObject(createLocalization["version_id"])["pattern"] == .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))

        let upload = try subscriptionV4SchemaProperties(
            try #require(tools.first { $0.name == "subscriptions_upload_version_image" })
        )
        let filePath = try subscriptionV4ValueObject(upload["file_path"])
        #expect(filePath["pattern"] == .string(#"^/"#))
        #expect(filePath["description"]?.stringValue?.contains("1024x1024") == true)
        #expect(filePath["description"]?.stringValue?.contains("JPG or PNG") == true)
        #expect(filePath["description"]?.stringValue?.contains("72 dpi") == true)
        #expect(filePath["description"]?.stringValue?.contains("RGB") == true)
        #expect(filePath["description"]?.stringValue?.contains("flattened") == true)

        let confirmations = [
            ("subscriptions_delete_version_localization", "confirm_localization_id"),
            ("subscriptions_delete_version_image", "confirm_image_id"),
            ("subscriptions_delete_group_version_localization", "confirm_localization_id")
        ]
        for (toolName, confirmationField) in confirmations {
            let tool = try #require(tools.first { $0.name == toolName })
            guard case .object(let schema) = tool.inputSchema,
                  case .array(let required)? = schema["required"] else {
                throw SubscriptionV4TestFailure.expectedObject
            }
            #expect(schema["additionalProperties"] == .bool(false))
            #expect(required.contains(.string(confirmationField)))
        }

        for toolName in Self.expectedTools {
            let tool = try #require(tools.first { $0.name == toolName })
            guard case .object(let schema) = tool.inputSchema else {
                throw SubscriptionV4TestFailure.expectedObject
            }
            #expect(schema["additionalProperties"] == .bool(false))
        }
    }

    @Test("every versioned subscription tool rejects missing required input", arguments: Array(Self.expectedTools).sorted())
    func toolsRejectMissingInput(_ toolName: String) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(name: toolName, arguments: nil))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("versioned response models require document links and links.self")
    func responseModelsRequireDocumentLinksSelf() {
        let bodies = [
            #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1"},"links":{}}"#
        ]

        for body in bodies {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    ASCSubscriptionVersionResponse.self,
                    from: Data(body.utf8)
                )
            }
        }
    }

    @Test("version creation encodes exact subscription and group relationships")
    func versionCreationUsesExactRelationships() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: subscriptionV4VersionResponse()),
            .init(statusCode: 201, body: subscriptionV4GroupVersionResponse())
        ])
        let worker = try await subscriptionV4Worker(transport)

        let subscriptionResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_version",
            arguments: ["subscription_id": .string("subscription-1")]
        ))
        let groupResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_group_version",
            arguments: ["group_id": .string("group-1")]
        ))

        #expect(subscriptionResult.isError != true)
        #expect(groupResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "POST"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/subscriptionVersions",
            "/v1/subscriptionGroupVersions"
        ])

        let subscriptionData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[0])["data"])
        let subscriptionRelationships = try subscriptionV4Object(subscriptionData["relationships"])
        let subscriptionLink = try subscriptionV4Object(try subscriptionV4Object(subscriptionRelationships["subscription"])["data"])
        #expect(subscriptionData["type"] as? String == "subscriptionVersions")
        #expect(subscriptionLink["type"] as? String == "subscriptions")
        #expect(subscriptionLink["id"] as? String == "subscription-1")

        let groupData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[1])["data"])
        let groupRelationships = try subscriptionV4Object(groupData["relationships"])
        let groupLink = try subscriptionV4Object(try subscriptionV4Object(groupRelationships["subscriptionGroup"])["data"])
        #expect(groupData["type"] as? String == "subscriptionGroupVersions")
        #expect(groupLink["type"] as? String == "subscriptionGroups")
        #expect(groupLink["id"] as? String == "group-1")
    }

    @Test("version getters use exact resource paths and project relationships")
    func versionGettersUseExactPaths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionV4VersionResponse()),
            .init(statusCode: 200, body: subscriptionV4GroupVersionResponse())
        ])
        let worker = try await subscriptionV4Worker(transport)

        let subscriptionResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version",
            arguments: ["version_id": .string("subscription-version-1")]
        ))
        let groupResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_group_version",
            arguments: ["version_id": .string("group-version-1")]
        ))

        #expect(subscriptionResult.isError != true)
        #expect(groupResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/subscriptionVersions/subscription-version-1",
            "/v1/subscriptionGroupVersions/group-version-1"
        ])
        let subscriptionPayload = try subscriptionV4ValueObject(subscriptionResult.structuredContent)
        let subscriptionVersion = try subscriptionV4ValueObject(subscriptionPayload["version"])
        #expect(subscriptionVersion["subscription_id"] == .string("subscription-1"))
        #expect(subscriptionVersion["image_ids"] == .array([.string("image-1")]))
        let imagesPage = try subscriptionV4ValueObject(subscriptionVersion["images_page"])
        #expect(imagesPage["count"] == .int(1))
        #expect(imagesPage["total"] == .null)
        #expect(imagesPage["limit"] == .int(1))
        #expect(imagesPage["next_cursor"] == .string("next-image"))
        #expect(imagesPage["truncated"] == .bool(true))
        #expect(imagesPage["completeness_known"] == .bool(true))
        let groupPayload = try subscriptionV4ValueObject(groupResult.structuredContent)
        let groupVersion = try subscriptionV4ValueObject(groupPayload["version"])
        #expect(groupVersion["group_id"] == .string("group-1"))
        let localizationsPage = try subscriptionV4ValueObject(groupVersion["localizations_page"])
        #expect(localizationsPage["total"] == .int(1))
        #expect(localizationsPage["truncated"] == .bool(false))
    }

    @Test("relationship pages preserve absent linkage data instead of reporting an empty page")
    func relationshipPagesPreserveUnknownVersusEmpty() async throws {
        let unknownBody = #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1","relationships":{"images":{"meta":{"paging":{"total":2,"limit":25}}}}},"links":{"self":"/v1/subscriptionVersions/subscription-version-1"}}"#
        let emptyBody = #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1","relationships":{"images":{"data":[],"meta":{"paging":{"total":0,"limit":25}}}}},"links":{"self":"/v1/subscriptionVersions/subscription-version-1"}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: unknownBody),
            .init(statusCode: 200, body: emptyBody)
        ])
        let worker = try await subscriptionV4Worker(transport)

        let unknown = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version",
            arguments: ["version_id": .string("subscription-version-1")]
        ))
        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version",
            arguments: ["version_id": .string("subscription-version-1")]
        ))

        #expect(unknown.isError != true)
        #expect(empty.isError != true)
        let unknownPage = try subscriptionV4ValueObject(
            try subscriptionV4ValueObject(
                try subscriptionV4ValueObject(unknown.structuredContent)["version"]
            )["images_page"]
        )
        #expect(unknownPage["ids"] == .null)
        #expect(unknownPage["count"] == .null)
        #expect(unknownPage["total"] == .int(2))
        #expect(unknownPage["truncated"] == .null)
        #expect(unknownPage["completeness_known"] == .bool(false))

        let emptyPage = try subscriptionV4ValueObject(
            try subscriptionV4ValueObject(
                try subscriptionV4ValueObject(empty.structuredContent)["version"]
            )["images_page"]
        )
        #expect(emptyPage["ids"] == .array([]))
        #expect(emptyPage["count"] == .int(0))
        #expect(emptyPage["truncated"] == .bool(false))
        #expect(emptyPage["completeness_known"] == .bool(true))
    }

    @Test("subscription and group version lists preserve filters totals and bounds")
    func versionListsUseExactFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionV4VersionsResponse()),
            .init(statusCode: 200, body: subscriptionV4GroupVersionsResponse())
        ])
        let worker = try await subscriptionV4Worker(transport)

        let subscriptionResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_versions",
            arguments: [
                "subscription_id": .string("subscription-1"),
                "filter_state": .array([.string("READY_FOR_REVIEW"), .string("REJECTED")]),
                "limit": .int(100)
            ]
        ))
        let groupResult = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_group_versions",
            arguments: [
                "group_id": .string("group-1"),
                "filter_state": .string("APPROVED"),
                "limit": .int(50)
            ]
        ))

        #expect(subscriptionResult.isError != true)
        #expect(groupResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/subscriptions/subscription-1/versions",
            "/v1/subscriptionGroups/group-1/versions"
        ])
        #expect(subscriptionV4Query(requests[0])["filter[state]"] == "READY_FOR_REVIEW,REJECTED")
        #expect(subscriptionV4Query(requests[0])["limit"] == "100")
        #expect(subscriptionV4Query(requests[1])["filter[state]"] == "APPROVED")
        #expect(subscriptionV4Query(requests[1])["limit"] == "50")
        #expect(try subscriptionV4ValueObject(subscriptionResult.structuredContent)["total"] == .int(3))
        #expect(try subscriptionV4ValueObject(groupResult.structuredContent)["total"] == .int(2))
    }

    @Test("version lists reject invalid states limits and changed pagination scope", arguments: [
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["filter_state": .string("UNKNOWN")]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["filter_state": .array([.string("REJECTED"), .string("REJECTED")])]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["filter_state": .string("REJECTED,APPROVED")]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["limit": .int(0)]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_group_versions", parent: "group_id", arguments: ["limit": .int(201)]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["next_url": .string("https://example.invalid/v1/subscriptions/subscription-1/versions?limit=25&cursor=next")]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["next_url": .string("https://api.example.test/v1/subscriptions/subscription-2/versions?limit=25&cursor=next")]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["next_url": .string("https://api.example.test/v1/subscriptions/subscription-1/versions?limit=50&cursor=next")]),
        SubscriptionV4InvalidList(tool: "subscriptions_list_versions", parent: "subscription_id", arguments: ["next_url": .string("https://api.example.test/v1/subscriptions/subscription-1/versions?limit=25&cursor=a&cursor=b")])
    ])
    fileprivate func versionListsRejectInvalidArguments(_ testCase: SubscriptionV4InvalidList) async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionV4Worker(transport)
        var arguments = testCase.arguments
        arguments[testCase.parent] = .string(testCase.parent == "group_id" ? "group-1" : "subscription-1")

        let result = try await worker.handleTool(CallTool.Parameters(name: testCase.tool, arguments: arguments))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("validated pagination follows the exact subscription version scope")
    func validatedPaginationFollowsExactScope() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next"},"meta":{"paging":{"total":0,"limit":25}}}"#)
        ])
        let worker = try await subscriptionV4Worker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_versions",
            arguments: [
                "subscription_id": .string("subscription-1"),
                "filter_state": .string("REJECTED"),
                "next_url": .string("/v1/subscriptions/subscription-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.absoluteString == "https://api.example.test/v1/subscriptions/subscription-1/versions?filter%5Bstate%5D=REJECTED&limit=25&cursor=next")
    }

    @Test("subscription localization v2 create update get and delete preserve nullable semantics")
    func subscriptionLocalizationLifecycleUsesV2() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: subscriptionV4LocalizationResponse()),
            .init(statusCode: 200, body: subscriptionV4LocalizationResponse()),
            .init(statusCode: 200, body: subscriptionV4LocalizationResponse()),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await subscriptionV4Worker(transport)

        let create = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_version_localization",
            arguments: [
                "version_id": .string("subscription-version-1"),
                "locale": .string("en-US"),
                "name": .string("Premium"),
                "description": .null
            ]
        ))
        let update = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_version_localization",
            arguments: [
                "localization_id": .string("localization-1"),
                "name": .string("Premium Plus"),
                "description": .null
            ]
        ))
        let get = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version_localization",
            arguments: ["localization_id": .string("localization-1")]
        ))
        let delete = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_delete_version_localization",
            arguments: [
                "localization_id": .string("localization-1"),
                "confirm_localization_id": .string("localization-1")
            ]
        ))

        #expect([create, update, get, delete].allSatisfy { $0.isError != true })
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/subscriptionLocalizations",
            "/v2/subscriptionLocalizations/localization-1",
            "/v2/subscriptionLocalizations/localization-1",
            "/v2/subscriptionLocalizations/localization-1"
        ])
        let createData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[0])["data"])
        let createAttributes = try subscriptionV4Object(createData["attributes"])
        let createRelationships = try subscriptionV4Object(createData["relationships"])
        let versionLink = try subscriptionV4Object(try subscriptionV4Object(createRelationships["version"])["data"])
        #expect(createData["type"] as? String == "subscriptionLocalizations")
        #expect(createAttributes["description"] is NSNull)
        #expect(versionLink["type"] as? String == "subscriptionVersions")
        #expect(versionLink["id"] as? String == "subscription-version-1")
        let updateData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[1])["data"])
        let updateAttributes = try subscriptionV4Object(updateData["attributes"])
        #expect(updateData["id"] as? String == "localization-1")
        #expect(updateAttributes["name"] as? String == "Premium Plus")
        #expect(updateAttributes["description"] is NSNull)
    }

    @Test("group localization v2 lifecycle encodes custom app name and version linkage")
    func groupLocalizationLifecycleUsesV2() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: subscriptionV4GroupLocalizationResponse()),
            .init(statusCode: 200, body: subscriptionV4GroupLocalizationResponse()),
            .init(statusCode: 200, body: subscriptionV4GroupLocalizationResponse()),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await subscriptionV4Worker(transport)

        let create = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_create_group_version_localization",
            arguments: [
                "version_id": .string("group-version-1"),
                "locale": .string("en-US"),
                "name": .string("Premium Plans"),
                "custom_app_name": .string("Example Pro")
            ]
        ))
        let update = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_group_version_localization",
            arguments: [
                "localization_id": .string("group-localization-1"),
                "custom_app_name": .null
            ]
        ))
        let get = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_group_version_localization",
            arguments: ["localization_id": .string("group-localization-1")]
        ))
        let delete = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_delete_group_version_localization",
            arguments: [
                "localization_id": .string("group-localization-1"),
                "confirm_localization_id": .string("group-localization-1")
            ]
        ))

        #expect([create, update, get, delete].allSatisfy { $0.isError != true })
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/subscriptionGroupLocalizations",
            "/v2/subscriptionGroupLocalizations/group-localization-1",
            "/v2/subscriptionGroupLocalizations/group-localization-1",
            "/v2/subscriptionGroupLocalizations/group-localization-1"
        ])
        let createData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[0])["data"])
        let attributes = try subscriptionV4Object(createData["attributes"])
        let relationships = try subscriptionV4Object(createData["relationships"])
        let versionLink = try subscriptionV4Object(try subscriptionV4Object(relationships["version"])["data"])
        #expect(attributes["customAppName"] as? String == "Example Pro")
        #expect(versionLink["type"] as? String == "subscriptionGroupVersions")
        #expect(versionLink["id"] as? String == "group-version-1")
        let updateData = try subscriptionV4Object(try subscriptionV4JSONBody(requests[1])["data"])
        #expect(try subscriptionV4Object(updateData["attributes"])["customAppName"] is NSNull)
    }

    @Test("localization and image lists use version-owned relationship paths")
    func relationshipListsUseVersionPaths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionV4LocalizationsResponse()),
            .init(statusCode: 200, body: subscriptionV4GroupLocalizationsResponse()),
            .init(statusCode: 200, body: subscriptionV4ImagesResponse())
        ])
        let worker = try await subscriptionV4Worker(transport)

        let subscriptionLocalizations = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_version_localizations",
            arguments: ["version_id": .string("subscription-version-1"), "limit": .int(200)]
        ))
        let groupLocalizations = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_group_version_localizations",
            arguments: ["version_id": .string("group-version-1")]
        ))
        let images = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_list_version_images",
            arguments: ["version_id": .string("subscription-version-1")]
        ))

        #expect([subscriptionLocalizations, groupLocalizations, images].allSatisfy { $0.isError != true })
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path } == [
            "/v1/subscriptionVersions/subscription-version-1/localizations",
            "/v1/subscriptionGroupVersions/group-version-1/localizations",
            "/v1/subscriptionVersions/subscription-version-1/images"
        ])
        #expect(subscriptionV4Query(requests[0])["limit"] == "200")
        #expect(subscriptionV4Query(requests[1])["limit"] == "25")
        #expect(subscriptionV4Query(requests[2])["limit"] == "25")
    }

    @Test("version image get and delete use v2 resource paths")
    func imageResourcesUseV2() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: subscriptionV4ImageResponse(state: "COMPLETE")),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await subscriptionV4Worker(transport)

        let get = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version_image",
            arguments: ["image_id": .string("image-1")]
        ))
        let delete = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_delete_version_image",
            arguments: [
                "image_id": .string("image-1"),
                "confirm_image_id": .string("image-1")
            ]
        ))

        #expect(get.isError != true)
        #expect(delete.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "DELETE"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/subscriptionImages/image-1",
            "/v2/subscriptionImages/image-1"
        ])
        let payload = try subscriptionV4ValueObject(get.structuredContent)
        let image = try subscriptionV4ValueObject(payload["image"])
        #expect(image["delivery_state"] == .string("COMPLETE"))
        #expect(image["asset_token"] == nil)
    }

    @Test("versioned responses require exact identity path and coherent relationship paging")
    func responsesRequireExactIdentityAndPath() async throws {
        let invalidBodies = [
            #"{"data":{"type":"unexpectedResources","id":"subscription-version-1"},"links":{"self":"/v1/subscriptionVersions/subscription-version-1"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"other-version"},"links":{"self":"/v1/subscriptionVersions/other-version"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"bad/id"},"links":{"self":"/v1/subscriptionVersions/bad%2Fid"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1"},"links":{"self":"/v1/subscriptionVersions/sibling-version"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1"}}"#,
            #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1","relationships":{"images":{"data":[{"type":"subscriptionImages","id":"image-1"}],"meta":{"paging":{"total":0,"limit":1}}}}},"links":{"self":"/v1/subscriptionVersions/subscription-version-1"}}"#
        ]

        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await subscriptionV4Worker(transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_get_version",
                arguments: ["version_id": .string("subscription-version-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }

        let relativeTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1"},"links":{"self":"/v1/subscriptionVersions/subscription-version-1"}}"#
            )
        ])
        let relativeWorker = try await subscriptionV4Worker(relativeTransport)
        let relativeResult = try await relativeWorker.handleTool(CallTool.Parameters(
            name: "subscriptions_get_version",
            arguments: ["version_id": .string("subscription-version-1")]
        ))
        #expect(relativeResult.isError != true)
    }

    @Test("versioned collections reject duplicate identities and sibling-parent self links")
    func collectionsRejectDuplicatesAndSiblingParents() async throws {
        let invalidBodies = [
            #"{"data":[{"type":"subscriptionVersions","id":"version-1"},{"type":"subscriptionVersions","id":"version-1"}],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-2/versions?limit=25"}}"#,
            #"{"data":[{"type":"subscriptionVersions","id":"version-1"}],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"},"meta":{"paging":{"total":0,"limit":1}}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"},"meta":{}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"},"meta":{"paging":{"total":0}}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"},"meta":{"paging":{"total":0,"limit":0}}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25"},"meta":{"paging":{"total":0,"limit":25,"nextCursor":"next"}}}"#,
            #"{"data":[],"links":{"self":"/v1/subscriptions/subscription-1/versions?limit=25","next":" "},"meta":{"paging":{"total":0,"limit":25}}}"#
        ]

        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await subscriptionV4Worker(transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_list_versions",
                arguments: ["subscription_id": .string("subscription-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("versioned handlers reject unknown arguments and noncanonical IDs before transport")
    func handlersRejectUnknownArgumentsAndNoncanonicalIDs() async throws {
        let calls: [(String, [String: Value])] = [
            ("subscriptions_get_version", ["version_id": .string("bad/id")]),
            ("subscriptions_get_version_localization", ["localization_id": .string("localization-1"), "extra": .bool(true)]),
            ("subscriptions_list_version_images", ["version_id": .string(" version-1")]),
            ("subscriptions_create_group_version", ["group_id": .string("group%2F1")]),
            ("subscriptions_delete_version_image", ["image_id": .string("image-1"), "confirm_image_id": .string("image-1"), "extra": .bool(true)]),
            ("subscriptions_upload_version_image", ["version_id": .string("version-1"), "file_path": .string("relative/image.png")]),
            ("subscriptions_create_version_localization", ["version_id": .string("version-1"), "locale": .string("EN_us"), "name": .string("Premium")]),
            ("subscriptions_create_group_version_localization", ["version_id": .string("version-1"), "locale": .string("en-US"), "name": .string("Premium 😀")]),
            ("subscriptions_update_version_localization", ["localization_id": .string("localization-1"), "description": .string("Copy 🚀")]),
            ("subscriptions_create_version_localization", ["version_id": .string("version-1"), "locale": .string("en-US"), "name": .string("Tier\nName")]),
            ("subscriptions_update_version_localization", ["localization_id": .string("localization-1"), "name": .string("<b>Tier</b>")]),
            ("subscriptions_create_group_version_localization", ["version_id": .string("version-1"), "locale": .string("en-US"), "name": .string("Plan\u{0007}Name")]),
            ("subscriptions_update_group_version_localization", ["localization_id": .string("group-localization-1"), "name": .string("<strong>Plans</strong>")])
        ]
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionV4Worker(transport)

        for (tool, arguments) in calls {
            let result = try await worker.handleTool(CallTool.Parameters(name: tool, arguments: arguments))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization PATCH recovery preserves exact requested tri-state values")
    func localizationPatchRecoveryPreservesRequestedValues() async throws {
        let acceptedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 202, body: subscriptionV4LocalizationResponse())
        ])
        let acceptedWorker = try await subscriptionV4Worker(acceptedTransport)
        let accepted = try await acceptedWorker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_version_localization",
            arguments: [
                "localization_id": .string("localization-1"),
                "name": .null,
                "description": .string("Exact copy")
            ]
        ))
        #expect(accepted.isError == true)
        #expect(await acceptedTransport.requestCount() == 1)
        let acceptedPayload = try subscriptionV4ValueObject(accepted.structuredContent)
        #expect(acceptedPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(acceptedPayload["operationCommitted"] == .bool(true))
        #expect(acceptedPayload["retrySafe"] == .bool(false))
        let acceptedDetails = try subscriptionV4ValueObject(acceptedPayload["details"])
        #expect(acceptedDetails["name"] == .null)
        #expect(acceptedDetails["description"] == .string("Exact copy"))
        #expect(acceptedDetails["requestedArguments"] == .object([
            "localization_id": .string("localization-1"),
            "name": .null,
            "description": .string("Exact copy")
        ]))

        let unknownTransport = TestHTTPTransport(responses: [])
        let unknownWorker = try await subscriptionV4Worker(unknownTransport)
        let unknown = try await unknownWorker.handleTool(CallTool.Parameters(
            name: "subscriptions_update_group_version_localization",
            arguments: [
                "localization_id": .string("group-localization-1"),
                "custom_app_name": .null
            ]
        ))
        #expect(unknown.isError == true)
        #expect(await unknownTransport.requestCount() == 1)
        let unknownPayload = try subscriptionV4ValueObject(unknown.structuredContent)
        #expect(unknownPayload["operationCommitState"] == .string("unknown"))
        #expect(unknownPayload["outcomeUnknown"] == .bool(true))
        #expect(unknownPayload["retrySafe"] == .bool(false))
        let unknownDetails = try subscriptionV4ValueObject(unknownPayload["details"])
        #expect(unknownDetails["custom_app_name"] == .null)
        #expect(unknownDetails["name"] == nil)
    }

    @Test("versioned deletes require exact confirmation before transport")
    func deletesRequireExactConfirmation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionV4Worker(transport)

        for target in SubscriptionV4DeleteTarget.allCases {
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
            let noncanonical = try await worker.handleTool(CallTool.Parameters(
                name: target.tool,
                arguments: [
                    target.idField: .string("bad/id"),
                    target.confirmationField: .string("bad/id")
                ]
            ))
            #expect(missing.isError == true)
            #expect(mismatched.isError == true)
            #expect(noncanonical.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("versioned deletes classify exact HTTP outcomes after one attempt")
    func deletesClassifyExactHTTPOutcomes() async throws {
        let cases: [(Int, String)] = [
            (204, "confirmed"),
            (202, "committed_unverified"),
            (408, "commit_unknown"),
            (500, "commit_unknown"),
            (403, "rejected")
        ]

        for target in SubscriptionV4DeleteTarget.allCases {
            for (statusCode, expectedState) in cases {
                let transport = TestHTTPTransport(responses: [
                    .init(statusCode: statusCode, body: "")
                ])
                let worker = try await subscriptionV4Worker(transport, maxRetries: 3)
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: target.tool,
                    arguments: [
                        target.idField: .string(target.id),
                        target.confirmationField: .string(target.id)
                    ]
                ))

                #expect(await transport.requestCount() == 1)
                let payload = try subscriptionV4ValueObject(result.structuredContent)
                #expect(payload["retrySafe"] == .bool(false))
                if expectedState == "confirmed" {
                    #expect(result.isError != true)
                    #expect(payload["deletionState"] == .string("confirmed"))
                } else {
                    #expect(result.isError == true)
                    let details = try subscriptionV4ValueObject(payload["details"])
                    #expect(details["deletionState"] == .string(expectedState))
                    #expect(details[target.idField] == .string(target.id))
                    if expectedState == "committed_unverified" {
                        #expect(payload["operationCommitState"] == .string("committed_unverified"))
                        #expect(payload["operationCommitted"] == .bool(true))
                        #expect(payload["outcomeUnknown"] == .bool(false))
                    } else if expectedState == "commit_unknown" {
                        #expect(payload["operationCommitState"] == .string("unknown"))
                        #expect(payload["outcomeUnknown"] == .bool(true))
                    } else {
                        #expect(payload["operationCommitState"] == .string("rejected"))
                        #expect(payload["outcomeUnknown"] == .bool(false))
                    }
                }
            }
        }
    }

    @Test("versioned delete network failure is commit unknown after one request")
    func deleteNetworkFailureIsCommitUnknown() async throws {
        let target = SubscriptionV4DeleteTarget.image
        let transport = TestHTTPTransport(responses: [])
        let worker = try await subscriptionV4Worker(transport, maxRetries: 3)
        let result = try await worker.handleTool(CallTool.Parameters(
            name: target.tool,
            arguments: [
                target.idField: .string(target.id),
                target.confirmationField: .string(target.id)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        let payload = try subscriptionV4ValueObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("version image upload reserves transfers commits without legacy checksum")
    func imageUploadUsesV2Transaction() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subscription-version-image-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: subscriptionV4ImageResponse(
                    state: "AWAITING_UPLOAD",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(statusCode: 200, body: subscriptionV4ImageResponse(state: "COMPLETE"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService(transport: uploadTransport, batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_version_image",
            arguments: [
                "version_id": .string("subscription-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v2/subscriptionImages",
            "/v2/subscriptionImages/image-1"
        ])
        let reservation = try subscriptionV4Object(try subscriptionV4JSONBody(requests[0])["data"])
        let reservationAttributes = try subscriptionV4Object(reservation["attributes"])
        let relationships = try subscriptionV4Object(reservation["relationships"])
        let versionLink = try subscriptionV4Object(try subscriptionV4Object(relationships["version"])["data"])
        #expect(reservation["type"] as? String == "subscriptionImages")
        #expect(reservationAttributes["fileName"] as? String == fileURL.lastPathComponent)
        #expect(reservationAttributes["fileSize"] as? Int == 5)
        #expect(versionLink["type"] as? String == "subscriptionVersions")
        #expect(versionLink["id"] as? String == "subscription-version-1")
        let commit = try subscriptionV4Object(try subscriptionV4JSONBody(requests[1])["data"])
        let commitAttributes = try subscriptionV4Object(commit["attributes"])
        #expect(commit["id"] as? String == "image-1")
        #expect(commitAttributes["uploaded"] as? Bool == true)
        #expect(commitAttributes.keys.contains("sourceFileChecksum") == false)
        let uploadRequest = try #require(await uploadTransport.recordedRequests().first)
        #expect(uploadRequest.httpBody == Data("hello".utf8))
    }

    @Test("version image upload rejects reservation snapshot or state mismatch before transfer")
    func imageUploadRejectsUnsafeReservationBeforeTransfer() async throws {
        let cases: [(fileName: String?, fileSize: Int, state: String)] = [
            ("different.png", 5, "AWAITING_UPLOAD"),
            (nil, 6, "AWAITING_UPLOAD"),
            (nil, 5, "COMPLETE")
        ]

        for testCase in cases {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("subscription-version-reservation-\(UUID().uuidString).png")
            try Data("hello".utf8).write(to: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let apiTransport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 201,
                    body: subscriptionV4ImageResponse(
                        state: testCase.state,
                        fileName: testCase.fileName ?? fileURL.lastPathComponent,
                        fileSize: testCase.fileSize,
                        includeUploadOperation: true
                    )
                ),
                .init(statusCode: 204, body: "")
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: apiTransport,
                maxRetries: 1
            )
            let worker = SubscriptionsWorker(
                httpClient: client,
                uploadService: UploadService(transport: uploadTransport, batchSize: 1),
                deliveryPollAttempts: 1,
                deliveryPollIntervalNanoseconds: 0
            )

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "subscriptions_upload_version_image",
                arguments: [
                    "version_id": .string("subscription-version-1"),
                    "file_path": .string(fileURL.path)
                ]
            ))

            #expect(result.isError == true)
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("ambiguous version image reservation recovery scans every list page")
    func imageUploadAmbiguousReservationIncludesPaginationGuidance() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subscription-version-ambiguous-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 3
        )
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService(transport: TestHTTPTransport(responses: []), batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_version_image",
            arguments: [
                "version_id": .string("subscription-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.requestCount() == 1)
        let payload = try subscriptionV4ValueObject(result.structuredContent)
        let fingerprint = try subscriptionV4ValueObject(payload["reservationFingerprint"])
        #expect(fingerprint["file_name"] == .string(fileURL.lastPathComponent))
        #expect(fingerprint["file_size"] == .int(5))
        #expect(fingerprint["checksum"] == .string("5d41402abc4b2a76b9719d911017c592"))
        let inspection = try subscriptionV4ValueObject(payload["inspection"])
        #expect(inspection["tool"] == .string("subscriptions_list_version_images"))
        #expect(inspection["continue_with_next_url"] == .bool(true))
        #expect(inspection["next_url_argument"] == .string("next_url"))
        #expect(try subscriptionV4ValueObject(inspection["arguments"]) == [
            "version_id": .string("subscription-version-1"),
            "limit": .int(200)
        ])
        let candidateMatch = try subscriptionV4ValueObject(inspection["candidate_match"])
        #expect(candidateMatch["fingerprint_key"] == .string("reservationFingerprint"))
        #expect(candidateMatch["candidate_fields"] == .array([
            .string("file_name"),
            .string("file_size")
        ]))
        #expect(candidateMatch["require_unique_match_before_retry"] == .bool(true))
    }

    @Test("version image upload cleanup guidance satisfies confirmed delete schema")
    func imageUploadCleanupGuidanceIncludesConfirmation() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subscription-version-cleanup-\(UUID().uuidString).png")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: subscriptionV4ImageResponse(
                    state: "AWAITING_UPLOAD",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(
                statusCode: 403,
                body: #"{"errors":[{"status":"403","code":"FORBIDDEN","title":"Forbidden","detail":"Denied"}]}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService(transport: TestHTTPTransport(responses: []), batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_version_image",
            arguments: [
                "version_id": .string("subscription-version-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
        let payload = try subscriptionV4ValueObject(result.structuredContent)
        let cleanup = try subscriptionV4ValueObject(payload["cleanup"])
        #expect(cleanup["tool"] == .string("subscriptions_delete_version_image"))
        #expect(cleanup["arguments"] == .object([
            "image_id": .string("image-1"),
            "confirm_image_id": .string("image-1")
        ]))
    }
}

private struct SubscriptionV4InvalidList: Sendable, CustomTestStringConvertible {
    let tool: String
    let parent: String
    let arguments: [String: Value]
    var testDescription: String { "\(tool): \(arguments)" }
}

private enum SubscriptionV4DeleteTarget: CaseIterable, Sendable {
    case localization
    case image
    case groupLocalization

    var tool: String {
        switch self {
        case .localization: "subscriptions_delete_version_localization"
        case .image: "subscriptions_delete_version_image"
        case .groupLocalization: "subscriptions_delete_group_version_localization"
        }
    }

    var idField: String {
        switch self {
        case .image: "image_id"
        case .localization, .groupLocalization: "localization_id"
        }
    }

    var confirmationField: String {
        switch self {
        case .image: "confirm_image_id"
        case .localization, .groupLocalization: "confirm_localization_id"
        }
    }

    var id: String {
        switch self {
        case .localization: "localization-1"
        case .image: "image-1"
        case .groupLocalization: "group-localization-1"
        }
    }
}

private func subscriptionV4Worker(
    _ transport: TestHTTPTransport,
    maxRetries: Int = 1
) async throws -> SubscriptionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: maxRetries
    )
    return SubscriptionsWorker(
        httpClient: client,
        uploadService: UploadService(),
        deliveryPollAttempts: 1,
        deliveryPollIntervalNanoseconds: 0
    )
}

private func subscriptionV4VersionResponse() -> String {
    #"{"data":{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":4,"state":"READY_FOR_REVIEW"},"relationships":{"subscription":{"data":{"type":"subscriptions","id":"subscription-1"}},"image":{"data":{"type":"subscriptionImages","id":"image-1"}},"images":{"data":[{"type":"subscriptionImages","id":"image-1"}],"meta":{"paging":{"limit":1,"nextCursor":"next-image"}}},"localizations":{"data":[{"type":"subscriptionLocalizations","id":"localization-1"}],"meta":{"paging":{"total":1,"limit":1}}}}},"links":{"self":"https://api.example.test/v1/subscriptionVersions/subscription-version-1"}}"#
}

private func subscriptionV4VersionsResponse() -> String {
    #"{"data":[{"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":4,"state":"READY_FOR_REVIEW"}}],"links":{"self":"https://api.example.test/v1/subscriptions/subscription-1/versions?filter%5Bstate%5D=READY_FOR_REVIEW%2CREJECTED&limit=100","next":"https://api.example.test/v1/subscriptions/subscription-1/versions?filter%5Bstate%5D=READY_FOR_REVIEW%2CREJECTED&limit=100&cursor=next"},"meta":{"paging":{"total":3,"limit":100}}}"#
}

private func subscriptionV4GroupVersionResponse() -> String {
    #"{"data":{"type":"subscriptionGroupVersions","id":"group-version-1","attributes":{"version":2,"state":"APPROVED"},"relationships":{"subscriptionGroup":{"data":{"type":"subscriptionGroups","id":"group-1"}},"localizations":{"data":[{"type":"subscriptionGroupLocalizations","id":"group-localization-1"}],"meta":{"paging":{"total":1,"limit":1}}}}},"links":{"self":"https://api.example.test/v1/subscriptionGroupVersions/group-version-1"}}"#
}

private func subscriptionV4GroupVersionsResponse() -> String {
    #"{"data":[{"type":"subscriptionGroupVersions","id":"group-version-1","attributes":{"version":2,"state":"APPROVED"}}],"links":{"self":"https://api.example.test/v1/subscriptionGroups/group-1/versions?filter%5Bstate%5D=APPROVED&limit=50"},"meta":{"paging":{"total":2,"limit":50}}}"#
}

private func subscriptionV4LocalizationResponse() -> String {
    #"{"data":{"type":"subscriptionLocalizations","id":"localization-1","attributes":{"locale":"en-US","name":"Premium","description":"Localized copy"},"relationships":{"version":{"data":{"type":"subscriptionVersions","id":"subscription-version-1"}}}},"links":{"self":"https://api.example.test/v2/subscriptionLocalizations/localization-1"}}"#
}

private func subscriptionV4LocalizationsResponse() -> String {
    #"{"data":[{"type":"subscriptionLocalizations","id":"localization-1","attributes":{"locale":"en-US","name":"Premium","description":"Localized copy"}}],"links":{"self":"https://api.example.test/v1/subscriptionVersions/subscription-version-1/localizations?limit=200"},"meta":{"paging":{"total":1,"limit":200}}}"#
}

private func subscriptionV4GroupLocalizationResponse() -> String {
    #"{"data":{"type":"subscriptionGroupLocalizations","id":"group-localization-1","attributes":{"locale":"en-US","name":"Premium Plans","customAppName":"Example Pro"},"relationships":{"version":{"data":{"type":"subscriptionGroupVersions","id":"group-version-1"}}}},"links":{"self":"https://api.example.test/v2/subscriptionGroupLocalizations/group-localization-1"}}"#
}

private func subscriptionV4GroupLocalizationsResponse() -> String {
    #"{"data":[{"type":"subscriptionGroupLocalizations","id":"group-localization-1","attributes":{"locale":"en-US","name":"Premium Plans","customAppName":"Example Pro"}}],"links":{"self":"https://api.example.test/v1/subscriptionGroupVersions/group-version-1/localizations?limit=25"},"meta":{"paging":{"total":1,"limit":25}}}"#
}

private func subscriptionV4ImageResponse(
    state: String,
    fileName: String = "image.png",
    fileSize: Int = 5,
    includeUploadOperation: Bool = false
) -> String {
    let operations = includeUploadOperation
        ? #", "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk","length":5,"offset":0,"requestHeaders":[]}]"#
        : ""
    return #"{"data":{"type":"subscriptionImages","id":"image-1","attributes":{"fileSize":\#(fileSize),"fileName":"\#(fileName)","assetToken":"token-1","assetDeliveryState":{"state":"\#(state)"}\#(operations)}},"links":{"self":"https://api.example.test/v2/subscriptionImages/image-1"}}"#
}

private func subscriptionV4ImagesResponse() -> String {
    #"{"data":[{"type":"subscriptionImages","id":"image-1","attributes":{"fileSize":5,"fileName":"image.png","assetToken":"token-1","assetDeliveryState":{"state":"COMPLETE"}}}],"links":{"self":"https://api.example.test/v1/subscriptionVersions/subscription-version-1/images?limit=25"},"meta":{"paging":{"total":1,"limit":25}}}"#
}

private func subscriptionV4Query(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: URLComponents(
        url: request.url ?? URL(string: "https://invalid")!,
        resolvingAgainstBaseURL: false
    )?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
}

private func subscriptionV4JSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw SubscriptionV4TestFailure.expectedObject
    }
    return object
}

private func subscriptionV4Object(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw SubscriptionV4TestFailure.expectedObject
    }
    return object
}

private func subscriptionV4ValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw SubscriptionV4TestFailure.expectedObject
    }
    return object
}

private func subscriptionV4SchemaProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let root) = tool.inputSchema,
          case .object(let properties)? = root["properties"] else {
        throw SubscriptionV4TestFailure.expectedObject
    }
    return properties
}

private enum SubscriptionV4TestFailure: Error {
    case expectedObject
}
