import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Review Submissions Worker Contract Tests")
struct ReviewSubmissionsWorkerContractTests {
    @Test("manifest records exact Apple 4.4.1 operation lineage and clears implemented waivers")
    func manifestLineage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "review_submissions" }
        )
        #expect(worker.tools.count == 9)

        let expected: [String: Set<String>] = [
            "review_submissions_list": ["reviewSubmissions_getCollection"],
            "review_submissions_get": ["reviewSubmissions_getInstance"],
            "review_submissions_create": ["reviewSubmissions_createInstance"],
            "review_submissions_list_items": ["reviewSubmissions_items_getToManyRelated"],
            "review_submissions_add_item": ["reviewSubmissionItems_createInstance"],
            "review_submissions_update_item": ["reviewSubmissionItems_updateInstance"],
            "review_submissions_remove_item": ["reviewSubmissionItems_deleteInstance"],
            "review_submissions_submit": ["reviewSubmissions_updateInstance"],
            "review_submissions_cancel": ["reviewSubmissions_updateInstance"]
        ]
        for (tool, operationIDs) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(Set(mapping.operations.map(\.operationID)) == operationIDs)
        }

        let implemented = Set(expected.values.flatMap { $0 })
        #expect(manifest.index.waivers.allSatisfy { waiver in
            guard let operationID = waiver.operationID else { return true }
            return !implemented.contains(operationID)
        })
        #expect(manifest.index.waivers.contains {
            $0.operationID == "reviewSubmissions_items_getToManyRelationship"
        })
    }

    @Test("worker exposes exactly the nine workflow tools with bounded schemas")
    func toolSchemas() async throws {
        let worker = ReviewSubmissionsWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()

        #expect(tools.count == 9)
        #expect(Set(tools.map(\.name)) == [
            "review_submissions_list",
            "review_submissions_get",
            "review_submissions_create",
            "review_submissions_list_items",
            "review_submissions_add_item",
            "review_submissions_update_item",
            "review_submissions_remove_item",
            "review_submissions_submit",
            "review_submissions_cancel"
        ])

        let list = try reviewSubmissionProperties(
            try #require(tools.first { $0.name == "review_submissions_list" })
        )
        #expect(list["limit"]?.objectValue?["maximum"] == .int(200))
        #expect(list["item_limit"]?.objectValue?["maximum"] == .int(50))
        #expect(list["states"]?.objectValue?["oneOf"]?.arrayValue?.count == 2)
        #expect(list["platforms"]?.objectValue?["oneOf"]?.arrayValue?.count == 2)
        #expect(list["next_url"]?.objectValue?["format"] == .string("uri-reference"))

        let create = try reviewSubmissionProperties(
            try #require(tools.first { $0.name == "review_submissions_create" })
        )
        #expect(
            create["platform"]?.objectValue?["type"] ==
                .array([.string("string"), .string("null")])
        )

        let addTool = try #require(tools.first { $0.name == "review_submissions_add_item" })
        let add = try reviewSubmissionProperties(addTool)
        #expect(Set(add.keys).isSuperset(of: reviewSubmissionTypedIDFields))
        #expect(add.keys.allSatisfy { !$0.contains("game_center") })
        #expect(add["submission_id"]?.objectValue?["pattern"] == .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))
        guard case .object(let addSchema) = addTool.inputSchema else {
            throw ReviewSubmissionTestFailure.expectedObject
        }
        #expect(addSchema["minProperties"] == .int(2))
        #expect(addSchema["maxProperties"] == .int(2))
        guard case .object(let publishedAddSchema) = ToolMetadataPolicy.apply(to: addTool).inputSchema else {
            throw ReviewSubmissionTestFailure.expectedObject
        }
        #expect(publishedAddSchema["minProperties"] == .int(2))
        #expect(publishedAddSchema["maxProperties"] == .int(2))

        let update = try reviewSubmissionProperties(
            try #require(tools.first { $0.name == "review_submissions_update_item" })
        )
        #expect(update["submission_id"] != nil)
        #expect(update["resolved"]?.objectValue?["type"] == .array([.string("boolean"), .string("null")]))
        #expect(update["removed"]?.objectValue?["type"] == .array([.string("boolean"), .string("null")]))

        let remove = try reviewSubmissionProperties(
            try #require(tools.first { $0.name == "review_submissions_remove_item" })
        )
        #expect(Set(remove.keys) == ["submission_id", "item_id", "confirm_item_id"])

        let listItems = try reviewSubmissionProperties(
            try #require(tools.first { $0.name == "review_submissions_list_items" })
        )
        #expect(listItems["next_url"]?.objectValue?["format"] == .string("uri-reference"))
    }

    @Test("direct calls enforce the canonical identifier pattern published by every schema")
    func canonicalIdentifierRuntimeParity() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        for identifier in ["bad id", "идентификатор", "bad%2Fid"] {
            let result = try await worker.handleTool(.init(
                name: "review_submissions_get",
                arguments: ["submission_id": .string(identifier)]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("create preserves omitted explicit null and every Apple platform")
    func createPlatformContract() async throws {
        let cases: [(Value?, Any?)] = [
            (nil, nil),
            (.null, NSNull()),
            (.string("IOS"), "IOS"),
            (.string("MAC_OS"), "MAC_OS"),
            (.string("TV_OS"), "TV_OS"),
            (.string("VISION_OS"), "VISION_OS")
        ]

        for (input, expected) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: reviewSubmissionBody(id: "sub-created"))
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            var arguments: [String: Value] = ["app_id": .string("app-1")]
            arguments["platform"] = input

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_create",
                arguments: arguments
            ))

            #expect(result.isError != true)
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/reviewSubmissions")
            let body = try reviewSubmissionRequestBody(request)
            let data = try #require(body["data"] as? [String: Any])
            let relationships = try #require(data["relationships"] as? [String: Any])
            let app = try #require(relationships["app"] as? [String: Any])
            let appData = try #require(app["data"] as? [String: Any])
            #expect(data["type"] as? String == "reviewSubmissions")
            #expect(appData["type"] as? String == "apps")
            #expect(appData["id"] as? String == "app-1")

            let attributes = data["attributes"] as? [String: Any]
            if expected == nil {
                #expect(attributes == nil)
            } else if expected is NSNull {
                #expect(attributes?["platform"] is NSNull)
            } else {
                #expect(attributes?["platform"] as? String == expected as? String)
            }
        }
    }

    @Test("list sends exact filters and projects ownership total actors and recovery")
    func listQueryAndProjection() async throws {
        let nextURL = reviewSubmissionURL(
            path: "/v1/reviewSubmissions",
            query: reviewSubmissionListQuery(
                appID: "app-1",
                states: "READY_FOR_REVIEW,UNRESOLVED_ISSUES",
                platforms: "IOS,MAC_OS",
                includes: "app,items,submittedByActor",
                itemLimit: 17,
                limit: 125
            ).merging(["cursor": "next-page"]) { _, new in new }
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionsListBody(nextURL: nextURL))
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_list",
            arguments: [
                "app_id": .string("app-1"),
                "states": .string("READY_FOR_REVIEW, UNRESOLVED_ISSUES"),
                "platforms": .array([.string("IOS"), .string("MAC_OS")]),
                "include": .array([.string("items"), .string("submittedByActor")]),
                "item_limit": .int(17),
                "limit": .int(125)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/reviewSubmissions")
        #expect(try reviewSubmissionQuery(request) == reviewSubmissionListQuery(
            appID: "app-1",
            states: "READY_FOR_REVIEW,UNRESOLVED_ISSUES",
            platforms: "IOS,MAC_OS",
            includes: "app,items,submittedByActor",
            itemLimit: 17,
            limit: 125
        ))

        let payload = try reviewSubmissionObject(result.structuredContent)
        #expect(payload["app_id"] == .string("app-1"))
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(4))
        #expect(payload["next_url"] == .string(nextURL))
        let submission = try reviewSubmissionObject(
            try #require(payload["submissions"]?.arrayValue?.first)
        )
        #expect(submission["id"] == .string("sub-1"))
        #expect(submission["state"] == .string("UNRESOLVED_ISSUES"))
        #expect(submission["app_id"] == .string("app-1"))
        #expect(submission["item_ids"] == .array([.string("item-1")]))
        let recovery = try reviewSubmissionObject(submission["recovery"])
        #expect(recovery["inspect_tool"] == .string("review_submissions_get"))
        #expect(recovery["submit_tool"] == .string("review_submissions_submit"))
        #expect(payload["actors"]?.arrayValue?.count == 1)
        #expect(payload["included_items"]?.arrayValue?.count == 1)
    }

    @Test("get uses exact recovery projection and actor fields")
    func getProjection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-1", includeContext: true))
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_get",
            arguments: [
                "submission_id": .string("sub-1"),
                "include": .string("items,lastUpdatedByActor"),
                "item_limit": .int(12)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/reviewSubmissions/sub-1")
        let query = try reviewSubmissionQuery(request)
        #expect(query["include"] == "items,lastUpdatedByActor")
        #expect(query["limit[items]"] == "12")
        #expect(query["fields[actors]"] == reviewSubmissionActorFields)

        let payload = try reviewSubmissionObject(result.structuredContent)
        let submission = try reviewSubmissionObject(payload["submission"])
        #expect(submission["submitted_by_actor_id"] == .string("actor-1"))
        #expect(submission["last_updated_by_actor_id"] == .string("actor-2"))
        #expect(payload["actors"]?.arrayValue?.count == 2)
    }

    @Test("included item relationship reports truncation and strict full-list recovery")
    func submissionItemRelationshipTruncation() async throws {
        let body = """
        {
          "data": {
            "type": "reviewSubmissions",
            "id": "sub-1",
            "relationships": {
              "items": {
                "data": [
                  {"type":"reviewSubmissionItems","id":"item-1"},
                  {"type":"reviewSubmissionItems","id":"item-2"}
                ],
                "meta": {"paging":{"total":75,"limit":50}}
              }
            }
          },
          "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}
        }
        """
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "review_submissions_get",
            arguments: ["submission_id": .string("sub-1")]
        ))

        #expect(result.isError != true)
        let payload = try reviewSubmissionObject(result.structuredContent)
        let submission = try reviewSubmissionObject(payload["submission"])
        #expect(submission["item_included_count"] == .int(2))
        #expect(submission["item_total"] == .int(75))
        #expect(submission["item_limit"] == .int(50))
        #expect(submission["items_truncated"] == .bool(true))
        #expect(submission["items_complete"] == .bool(false))
        let inspection = try reviewSubmissionObject(submission["items_inspection"])
        #expect(inspection["tool"] == .string("review_submissions_list_items"))
        #expect(inspection["continue_with_next_url"] == .bool(true))
        let arguments = try reviewSubmissionObject(inspection["arguments"])
        #expect(arguments["submission_id"] == .string("sub-1"))
        #expect(arguments["limit"] == .int(200))
    }

    @Test("submission item projection preserves unknown and known-empty relationship states")
    func submissionItemRelationshipTriState() async throws {
        let bodies = [
            (
                #"{"data":{"type":"reviewSubmissions","id":"sub-1"},"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}}"#,
                Value.null,
                Value.null
            ),
            (
                #"{"data":{"type":"reviewSubmissions","id":"sub-1","relationships":{"items":{"data":[]}}},"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}}"#,
                Value.array([]),
                Value.int(0)
            )
        ]

        for (body, expectedIDs, expectedCount) in bodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "review_submissions_get",
                arguments: ["submission_id": .string("sub-1")]
            ))

            #expect(result.isError != true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let submission = try reviewSubmissionObject(payload["submission"])
            #expect(submission["item_ids"] == expectedIDs)
            #expect(submission["item_included_count"] == expectedCount)
            #expect(submission["items_truncated"] == .null)
            #expect(submission["items_complete"] == .null)
            #expect(submission["items_completeness_known"] == .bool(false))
        }
    }

    @Test("nested item cursor proves truncation without a relationship total")
    func submissionItemRelationshipCursorCompleteness() async throws {
        let body = #"{"data":{"type":"reviewSubmissions","id":"sub-1","relationships":{"items":{"data":[{"type":"reviewSubmissionItems","id":"item-1"}],"meta":{"paging":{"limit":50,"nextCursor":"next-items"}}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}}"#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "review_submissions_get",
            arguments: ["submission_id": .string("sub-1")]
        ))

        #expect(result.isError != true)
        let payload = try reviewSubmissionObject(result.structuredContent)
        let submission = try reviewSubmissionObject(payload["submission"])
        #expect(submission["item_next_cursor"] == .string("next-items"))
        #expect(submission["items_truncated"] == .bool(true))
        #expect(submission["items_complete"] == .bool(false))
        #expect(submission["items_completeness_known"] == .bool(true))
        #expect(submission["items_inspection"] != nil)
    }

    @Test("nested item relationship rejects an empty paging cursor")
    func submissionItemRelationshipRejectsEmptyCursor() async throws {
        let body = #"{"data":{"type":"reviewSubmissions","id":"sub-1","relationships":{"items":{"data":[],"meta":{"paging":{"limit":50,"nextCursor":" "}}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}}"#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "review_submissions_get",
            arguments: ["submission_id": .string("sub-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("top-level and nested paging limits cannot be below decoded item counts")
    func pagingMetaBounds() async throws {
        let nested = """
        {
          "data": {
            "type": "reviewSubmissions",
            "id": "sub-1",
            "relationships": {
              "items": {
                "data": [
                  {"type":"reviewSubmissionItems","id":"item-1"},
                  {"type":"reviewSubmissionItems","id":"item-2"}
                ],
                "meta": {"paging":{"total":2,"limit":1}}
              }
            }
          },
          "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1"}
        }
        """
        let topLevel = """
        {
          "data": [
            {"type":"reviewSubmissionItems","id":"item-1"},
            {"type":"reviewSubmissionItems","id":"item-2"}
          ],
          "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items"},
          "meta": {"paging":{"total":2,"limit":1}}
        }
        """
        let cases: [(String, [String: Value], String)] = [
            ("review_submissions_get", ["submission_id": .string("sub-1")], nested),
            ("review_submissions_list_items", ["submission_id": .string("sub-1")], topLevel)
        ]
        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let details = try reviewSubmissionObject(payload["details"])
            #expect(details["type"] == .string("parsing"))
        }
    }

    @Test("public collections bind Apple page counts and paging metadata to the requested limit")
    func publicCollectionRequestedLimitBounds() async throws {
        let listBody = """
        {
          "data": [
            {"type":"reviewSubmissions","id":"sub-1","relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}},
            {"type":"reviewSubmissions","id":"sub-2","relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}
          ],
          "links": {"self":"https://api.example.test/v1/reviewSubmissions"},
          "meta": {"paging":{"total":2,"limit":2}}
        }
        """
        let itemBody = """
        {
          "data": [
            {"type":"reviewSubmissionItems","id":"item-1"},
            {"type":"reviewSubmissionItems","id":"item-2"}
          ],
          "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items"},
          "meta": {"paging":{"total":2,"limit":2}}
        }
        """
        let cases: [(String, [String: Value], String)] = [
            ("review_submissions_list", ["app_id": .string("app-1"), "limit": .int(1)], listBody),
            ("review_submissions_list_items", ["submission_id": .string("sub-1"), "limit": .int(1)], itemBody)
        ]
        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
        }
    }

    @Test("public collections reject response next links outside the originating scope")
    func publicCollectionResponseNextScope() async throws {
        let listBody = """
        {
          "data": [],
          "links": {
            "self":"https://api.example.test/v1/reviewSubmissions",
            "next":"https://evil.example/v1/reviewSubmissions?cursor=next"
          },
          "meta": {"paging":{"total":0,"limit":25,"nextCursor":"next"}}
        }
        """
        let itemBody = """
        {
          "data": [],
          "links": {
            "self":"https://api.example.test/v1/reviewSubmissions/sub-1/items",
            "next":"https://api.example.test/v1/reviewSubmissions/sub-2/items?cursor=next"
          },
          "meta": {"paging":{"total":0,"limit":25,"nextCursor":"next"}}
        }
        """
        let cases: [(String, [String: Value], String)] = [
            ("review_submissions_list", ["app_id": .string("app-1")], listBody),
            ("review_submissions_list_items", ["submission_id": .string("sub-1")], itemBody)
        ]
        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
        }
    }

    @Test("public collections reject missing-next and empty paging cursors")
    func publicCursorNextConsistency() async throws {
        let listBody = """
        {
          "data": [],
          "links": {"self":"https://api.example.test/v1/reviewSubmissions"},
          "meta": {"paging":{"total":0,"limit":25,"nextCursor":"cursor-1"}}
        }
        """
        var itemQuery = reviewSubmissionItemListQuery(limit: 25)
        itemQuery["cursor"] = "page-2"
        let itemNext = reviewSubmissionURL(
            path: "/v1/reviewSubmissions/sub-1/items",
            query: itemQuery
        )
        let itemBody = """
        {
          "data": [],
          "links": {
            "self":"https://api.example.test/v1/reviewSubmissions/sub-1/items",
            "next":"\(itemNext)"
          },
          "meta": {"paging":{"total":0,"limit":25,"nextCursor":" "}}
        }
        """
        let cases: [(String, [String: Value], String)] = [
            ("review_submissions_list", ["app_id": .string("app-1")], listBody),
            ("review_submissions_list_items", ["submission_id": .string("sub-1")], itemBody)
        ]
        for (tool, arguments, body) in cases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let details = try reviewSubmissionObject(payload["details"])
            #expect(details["type"] == .string("parsing"))
        }
    }

    @Test("all eight supported item relations encode exact Apple JSON API keys and types")
    func addItemRelationBodies() async throws {
        let cases: [(String, String, String)] = [
            ("app_store_version_id", "appStoreVersion", "appStoreVersions"),
            ("app_custom_product_page_version_id", "appCustomProductPageVersion", "appCustomProductPageVersions"),
            ("app_store_version_experiment_v2_id", "appStoreVersionExperimentV2", "appStoreVersionExperiments"),
            ("app_event_id", "appEvent", "appEvents"),
            ("background_asset_version_id", "backgroundAssetVersion", "backgroundAssetVersions"),
            ("in_app_purchase_version_id", "inAppPurchaseVersion", "inAppPurchaseVersions"),
            ("subscription_version_id", "subscriptionVersion", "subscriptionVersions"),
            ("subscription_group_version_id", "subscriptionGroupVersion", "subscriptionGroupVersions")
        ]

        for (toolField, relationshipName, resourceType) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 201,
                    body: reviewSubmissionItemBody(
                        id: "item-1",
                        relationshipName: relationshipName,
                        resourceType: resourceType,
                        resourceID: "resource-1"
                    )
                )
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_add_item",
                arguments: [
                    "submission_id": .string("sub-1"),
                    toolField: .string("resource-1")
                ]
            ))

            #expect(result.isError != true, "Expected relation \(relationshipName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/reviewSubmissionItems")
            let body = try reviewSubmissionRequestBody(request)
            let data = try #require(body["data"] as? [String: Any])
            let relationships = try #require(data["relationships"] as? [String: Any])
            #expect(data["type"] as? String == "reviewSubmissionItems")
            #expect(Set(relationships.keys) == ["reviewSubmission", relationshipName])
            let reviewSubmission = try reviewSubmissionRelationshipData(relationships["reviewSubmission"])
            #expect(reviewSubmission["type"] as? String == "reviewSubmissions")
            #expect(reviewSubmission["id"] as? String == "sub-1")
            let resource = try reviewSubmissionRelationshipData(relationships[relationshipName])
            #expect(resource["type"] as? String == resourceType)
            #expect(resource["id"] as? String == "resource-1")

            let payload = try reviewSubmissionObject(result.structuredContent)
            let item = try reviewSubmissionObject(payload["item"])
            #expect(item["resource_type"] == .string(relationshipName))
            #expect(item["resource_id"] == .string("resource-1"))
            #expect(item["resource_jsonapi_type"] == .string(resourceType))
        }
    }

    @Test("add item reports an unconfirmed write when Apple does not echo the exact resource identity")
    func addItemRejectsUnconfirmedResponseIdentity() async throws {
        let mismatchedBodies = [
            #"{"data":{"type":"appEvents","id":"item-1","relationships":{"appEvent":{"data":{"type":"appEvents","id":"event-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"","relationships":{"appEvent":{"data":{"type":"appEvents","id":"event-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"bad/id","relationships":{"appEvent":{"data":{"type":"appEvents","id":"event-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1"},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"subscriptionVersion":{"data":{"type":"subscriptionVersions","id":"event-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"appEvent":{"data":{"type":"appStoreVersions","id":"event-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"appEvent":{"data":{"type":"appEvents","id":"event-2"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#,
            #"{"data":{"type":"reviewSubmissionItems","id":"item-1","relationships":{"appEvent":{"data":{"type":"appEvents","id":"event-1"}},"subscriptionVersion":{"data":{"type":"subscriptionVersions","id":"subscription-1"}}}},"links":{"self":"https://api.example.test/v1/reviewSubmissionItems/item-1"}}"#
        ]

        for body in mismatchedBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: body)
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_add_item",
                arguments: [
                    "submission_id": .string("sub-1"),
                    "app_event_id": .string("event-1")
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
            let payload = try reviewSubmissionObject(result.structuredContent)
            #expect(payload["item"] == nil)
            #expect(payload["operation"] == .string("add_item"))
            #expect(payload["write_outcome"] == .string("committed_unverified"))
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["retrySafe"] == .bool(false))
            #expect(payload["submission_id"] == .string("sub-1"))
            #expect(payload["resource_type"] == .string("appEvent"))
            #expect(payload["resource_id"] == .string("event-1"))
            let inspection = try reviewSubmissionObject(payload["inspection"])
            #expect(inspection["continue_with_next_url"] == .bool(true))
        }
    }

    @Test("add item rejects missing multiple malformed legacy and scoped relations before network")
    func addItemValidation() async throws {
        let invalidArguments: [[String: Value]] = [
            ["submission_id": .string("sub-1")],
            [
                "submission_id": .string("sub-1"),
                "app_store_version_id": .string("version-1"),
                "subscription_version_id": .string("subscription-1")
            ],
            ["submission_id": .string("sub-1"), "app_store_version_id": .string("  ")],
            ["submission_id": .string("sub-1"), "app_store_version_id": .string(" version-1 ")],
            ["submission_id": .string("sub-1"), "app_store_version_id": .string("bad/id")],
            ["submission_id": .string("sub-1"), "app_store_version_id": .int(1)],
            ["submission_id": .string("sub-1"), "app_store_version_experiment_id": .string("legacy-1")],
            ["submission_id": .string("sub-1"), "game_center_achievement_version_id": .string("gc-1")],
            ["submission_id": .string("sub-1"), "resource_type": .string("gameCenterChallengeVersions")]
        ]

        for arguments in invalidArguments {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_add_item",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("item update preserves Boolean null and omission exactly")
    func itemUpdateTriState() async throws {
        let cases: [([String: Value], [String: ReviewSubmissionJSONKind], [String])] = [
            (["resolved": .bool(true)], ["resolved": .boolean], ["removed"]),
            (["removed": .bool(false)], ["removed": .boolean], ["resolved"]),
            (["resolved": .null], ["resolved": .null], ["removed"]),
            (["removed": .null], ["removed": .null], ["resolved"]),
            (["resolved": .bool(false), "removed": .null], ["resolved": .boolean, "removed": .null], [])
        ]

        for (updates, expectedTypes, omitted) in cases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])),
                .init(statusCode: 200, body: reviewSubmissionItemBody(id: "item-1"))
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            var arguments = updates
            arguments["submission_id"] = .string("sub-1")
            arguments["item_id"] = .string("item-1")

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_update_item",
                arguments: arguments
            ))

            #expect(result.isError != true)
            let requests = await transport.recordedRequests()
            #expect(requests.map(\.httpMethod) == ["GET", "PATCH"])
            let request = try #require(requests.last)
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/v1/reviewSubmissionItems/item-1")
            let body = try reviewSubmissionRequestBody(request)
            let data = try #require(body["data"] as? [String: Any])
            let attributes = try #require(data["attributes"] as? [String: Any])
            #expect(data["type"] as? String == "reviewSubmissionItems")
            #expect(data["id"] as? String == "item-1")
            for (field, kind) in expectedTypes {
                if kind == .boolean {
                    #expect(attributes[field] is Bool)
                } else {
                    #expect(attributes[field] is NSNull)
                }
            }
            for field in omitted {
                #expect(attributes[field] == nil)
            }
        }

        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        let missing = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_update_item",
            arguments: ["submission_id": .string("sub-1"), "item_id": .string("item-1")]
        ))
        #expect(missing.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("remove submit and cancel use exact methods paths and transition bodies")
    func transitionAndRemovalContracts() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-1", state: "WAITING_FOR_REVIEW")),
            .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-1", state: "CANCELING"))
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let remove = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_remove_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "confirm_item_id": .string("item-1")
            ]
        ))
        let submit = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_submit",
            arguments: ["submission_id": .string("sub-1")]
        ))
        let cancel = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_cancel",
            arguments: ["submission_id": .string("sub-1")]
        ))

        #expect(remove.isError != true)
        #expect(submit.isError != true)
        #expect(cancel.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "DELETE", "PATCH", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/reviewSubmissions/sub-1/items",
            "/v1/reviewSubmissionItems/item-1",
            "/v1/reviewSubmissions/sub-1",
            "/v1/reviewSubmissions/sub-1"
        ])

        let submitData = try #require(
            try reviewSubmissionRequestBody(requests[2])["data"] as? [String: Any]
        )
        let submitAttributes = try #require(submitData["attributes"] as? [String: Any])
        #expect(submitAttributes["submitted"] as? Bool == true)
        #expect(submitAttributes["canceled"] == nil)
        #expect(submitAttributes["platform"] == nil)

        let cancelData = try #require(
            try reviewSubmissionRequestBody(requests[3])["data"] as? [String: Any]
        )
        let cancelAttributes = try #require(cancelData["attributes"] as? [String: Any])
        #expect(cancelAttributes["canceled"] as? Bool == true)
        #expect(cancelAttributes["submitted"] == nil)
        #expect(cancelAttributes["platform"] == nil)
    }

    @Test("write failures retain known identifiers and deterministic recovery steps")
    func writeFailureRecoveryDetails() async throws {
        let cases: [(
            tool: String,
            arguments: [String: Value],
            operation: String,
            identifiers: [String: Value],
            recoveryKey: String
        )] = [
            (
                "review_submissions_create",
                ["app_id": .string("app-1")],
                "create",
                ["app_id": .string("app-1")],
                "list_submissions"
            ),
            (
                "review_submissions_add_item",
                [
                    "submission_id": .string("sub-1"),
                    "app_event_id": .string("event-1")
                ],
                "add_item",
                [
                    "submission_id": .string("sub-1"),
                    "resource_type": .string("appEvent"),
                    "resource_id": .string("event-1")
                ],
                "list_items"
            ),
            (
                "review_submissions_update_item",
                [
                    "submission_id": .string("sub-1"),
                    "item_id": .string("item-1"),
                    "resolved": .bool(true),
                    "removed": .null
                ],
                "update_item",
                [
                    "submission_id": .string("sub-1"),
                    "item_id": .string("item-1"),
                    "resolved": .bool(true),
                    "removed": .null
                ],
                "inspect_parent"
            ),
            (
                "review_submissions_remove_item",
                [
                    "submission_id": .string("sub-1"),
                    "item_id": .string("item-1"),
                    "confirm_item_id": .string("item-1")
                ],
                "remove_item",
                ["submission_id": .string("sub-1"), "item_id": .string("item-1")],
                "inspection"
            ),
            (
                "review_submissions_submit",
                ["submission_id": .string("sub-1")],
                "submit",
                ["submission_id": .string("sub-1")],
                "inspect_submission"
            ),
            (
                "review_submissions_cancel",
                ["submission_id": .string("sub-1")],
                "cancel",
                ["submission_id": .string("sub-1")],
                "inspect_submission"
            )
        ]

        for testCase in cases {
            var responses: [TestHTTPTransport.Response] = []
            if testCase.tool == "review_submissions_update_item" ||
                testCase.tool == "review_submissions_remove_item" {
                responses.append(.init(
                    statusCode: 200,
                    body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])
                ))
            }
            responses.append(.init(
                statusCode: 409,
                body: #"{"errors":[{"status":"409","code":"ENTITY_ERROR.CONFLICT","title":"Conflict","detail":"Write not confirmed"}]}"#
            ))
            let transport = TestHTTPTransport(responses: responses)
            let worker = try await makeReviewSubmissionsWorker(transport: transport)

            let result = try await worker.handleTool(CallTool.Parameters(
                name: testCase.tool,
                arguments: testCase.arguments
            ))

            #expect(result.isError == true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let details = try reviewSubmissionObject(payload["details"])
            #expect(details["operation"] == .string(testCase.operation))
            for (key, value) in testCase.identifiers {
                #expect(details[key] == value)
            }
            let cause = try reviewSubmissionObject(details["cause"])
            #expect(cause["type"] == .string("api"))
            #expect(cause["statusCode"] == .int(409))
            if testCase.tool == "review_submissions_remove_item" {
                #expect(details["deletionState"] == .string("rejected"))
                #expect(details["operationCommitState"] == .string("rejected"))
                #expect(details["retrySafe"] == .bool(true))
                let inspection = try reviewSubmissionObject(details[testCase.recoveryKey])
                let inspectionArguments = try reviewSubmissionObject(inspection["arguments"])
                #expect(inspectionArguments["submission_id"] == .string("sub-1"))
                #expect(inspectionArguments["limit"] == .int(200))
                #expect(inspection["continue_with_next_url"] == .bool(true))
            } else {
                #expect(details["write_outcome"] == .string("rejected"))
                #expect(details["operationCommitState"] == .string("rejected"))
                #expect(details["retrySafe"] == .bool(false))
                #expect(details["inspection"] != nil)
            }
            if testCase.tool == "review_submissions_update_item" {
                let retry = try reviewSubmissionObject(details["retry"])
                #expect(retry["tool"] == .string("review_submissions_update_item"))
                let retryArguments = try reviewSubmissionObject(retry["arguments"])
                #expect(retryArguments["submission_id"] == .string("sub-1"))
                #expect(retryArguments["item_id"] == .string("item-1"))
                #expect(retryArguments["resolved"] == .bool(true))
                #expect(retryArguments["removed"] == .null)
            }
        }
    }

    @Test("list items includes only supported compound resources and projects every resource identity")
    func listItemsContract() async throws {
        let nextURL = reviewSubmissionURL(
            path: "/v1/reviewSubmissions/sub-1/items",
            query: reviewSubmissionItemListQuery(limit: 75).merging(["cursor": "item-next"]) { _, new in new }
        )
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionItemsListBody(nextURL: nextURL))
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_list_items",
            arguments: ["submission_id": .string("sub-1"), "limit": .int(75)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/reviewSubmissions/sub-1/items")
        let query = try reviewSubmissionQuery(request)
        #expect(query == reviewSubmissionItemListQuery(limit: 75))
        #expect(query["fields[reviewSubmissionItems]"]?.contains("gameCenterAchievementVersion") == true)
        #expect(query["include"]?.contains("gameCenter") == false)
        #expect(query["include"]?.contains("appStoreVersionExperimentV2") == true)
        #expect(query["include"]?.contains("appStoreVersionExperiment,") == false)

        let payload = try reviewSubmissionObject(result.structuredContent)
        #expect(payload["submission_id"] == .string("sub-1"))
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(1))
        #expect(payload["next_url"] == .string(nextURL))
        let item = try reviewSubmissionObject(try #require(payload["items"]?.arrayValue?.first))
        #expect(item["resource_type"] == .string("subscriptionVersion"))
        #expect(item["resource_id"] == .string("subscription-version-1"))
    }

    @Test("list items retains legacy PPO and scoped Game Center resource identities")
    func listItemsRetainsEveryIdentity() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMixedItemsBody())
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_list_items",
            arguments: ["submission_id": .string("sub-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try reviewSubmissionQuery(request)
        #expect(query["fields[reviewSubmissionItems]"] == reviewSubmissionItemFields)
        #expect(query["include"] == reviewSubmissionSupportedIncludes)
        #expect(query["include"]?.contains("gameCenter") == false)
        #expect(query["include"]?.contains("appStoreVersionExperiment,") == false)

        let payload = try reviewSubmissionObject(result.structuredContent)
        let items = try #require(payload["items"]?.arrayValue)
        #expect(items.count == 2)

        let legacy = try reviewSubmissionObject(items[0])
        #expect(legacy["resource_type"] == .string("appStoreVersionExperiment"))
        #expect(legacy["resource_id"] == .string("legacy-experiment-1"))
        let legacyRelations = try #require(legacy["relations"]?.arrayValue)
        let legacyRelation = try reviewSubmissionObject(legacyRelations[0])
        #expect(legacyRelation["scoped"] == .bool(false))

        let gameCenter = try reviewSubmissionObject(items[1])
        #expect(gameCenter["resource_type"] == .string("gameCenterAchievementVersion"))
        #expect(gameCenter["resource_id"] == .string("achievement-version-1"))
        let gameCenterRelations = try #require(gameCenter["relations"]?.arrayValue)
        let gameCenterRelation = try reviewSubmissionObject(gameCenterRelations[0])
        #expect(gameCenterRelation["scoped"] == .bool(true))
    }

    @Test("CSV and array filters reject empty duplicate comma and unsupported values before network")
    func listFilterValidation() async throws {
        let invalid: [(String, Value)] = [
            ("states", .string("READY_FOR_REVIEW,")),
            ("states", .string("READY_FOR_REVIEW,READY_FOR_REVIEW")),
            ("states", .array([.string("READY_FOR_REVIEW,IN_REVIEW")])),
            ("states", .array([.string("READY_FOR_REVIEW"), .int(1)])),
            ("states", .string("UNKNOWN")),
            ("platforms", .string("IOS,IOS")),
            ("platforms", .array([.string("IOS,MAC_OS")])),
            ("include", .string("items,items")),
            ("include", .string("gameCenterAchievementVersion"))
        ]

        for (field, value) in invalid {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_list",
                arguments: ["app_id": .string("app-1"), field: value]
            ))
            #expect(result.isError == true, "Expected invalid \(field): \(value)")
            #expect(await transport.requestCount() == 0)
        }

        for arguments in [
            ["app_id": Value.string("app-1"), "limit": .int(0)],
            ["app_id": Value.string("app-1"), "limit": .int(201)],
            ["app_id": Value.string("app-1"), "item_limit": .int(51)]
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "review_submissions_list",
                arguments: arguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        let platformTransport = TestHTTPTransport(responses: [])
        let platformWorker = try await makeReviewSubmissionsWorker(transport: platformTransport)
        let invalidPlatform = try await platformWorker.handleTool(CallTool.Parameters(
            name: "review_submissions_create",
            arguments: ["app_id": .string("app-1"), "platform": .string("ANDROID")]
        ))
        #expect(invalidPlatform.isError == true)
        #expect(await platformTransport.requestCount() == 0)
    }

    @Test("Apple document links are required and accepted-response decode failures are committed unverified")
    func requiredDocumentLinks() async throws {
        let readCases: [(String, [String: Value], String)] = [
            (
                "review_submissions_list",
                ["app_id": .string("app-1")],
                #"{"data":[]}"#
            ),
            (
                "review_submissions_get",
                ["submission_id": .string("sub-1")],
                #"{"data":{"type":"reviewSubmissions","id":"sub-1"}}"#
            ),
            (
                "review_submissions_list_items",
                ["submission_id": .string("sub-1")],
                #"{"data":[]}"#
            )
        ]
        for (tool, arguments, body) in readCases {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let details = try reviewSubmissionObject(payload["details"])
            #expect(details["type"] == .string("parsing"))
        }

        for platform in [Value.string("IOS"), .null] {
            let createTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: #"{"data":{"type":"reviewSubmissions","id":"sub-1"}}"#)
            ])
            let createWorker = try await makeReviewSubmissionsWorker(transport: createTransport)
            let create = try await createWorker.handleTool(.init(
                name: "review_submissions_create",
                arguments: ["app_id": .string("app-1"), "platform": platform]
            ))
            #expect(create.isError == true)
            let createPayload = try reviewSubmissionObject(create.structuredContent)
            #expect(createPayload["operationCommitState"] == .string("committed_unverified"))
            #expect(createPayload["operationCommitted"] == .bool(true))
            #expect(createPayload["retrySafe"] == .bool(false))
            #expect(createPayload["platform"] == platform)
            let cause = try reviewSubmissionObject(createPayload["cause"])
            #expect(cause["type"] == .string("mutation_unverified"))
            #expect(cause["method"] == .string("POST"))
            #expect(cause["expectedStatusCode"] == .int(201))
            #expect(cause["statusCode"] == .int(201))
            #expect(try reviewSubmissionObject(cause["cause"])["type"] == .string("parsing"))
            let inspection = try reviewSubmissionObject(createPayload["inspection"])
            let arguments = try reviewSubmissionObject(inspection["arguments"])
            if platform == .string("IOS") {
                #expect(arguments["platforms"] == .string("IOS"))
            } else {
                #expect(arguments["platforms"] == nil)
            }
        }

        let networkTransport = TestHTTPTransport(responses: [])
        let networkWorker = try await makeReviewSubmissionsWorker(transport: networkTransport)
        let network = try await networkWorker.handleTool(.init(
            name: "review_submissions_create",
            arguments: ["app_id": .string("app-1"), "platform": .string("MAC_OS")]
        ))
        #expect(network.isError == true)
        let networkDetails = try reviewSubmissionObject(
            try reviewSubmissionObject(network.structuredContent)["details"]
        )
        #expect(networkDetails["write_outcome"] == .string("unknown"))
        #expect(networkDetails["platform"] == .string("MAC_OS"))
        let networkCause = try reviewSubmissionObject(networkDetails["cause"])
        #expect(networkCause["type"] == .string("mutation_unknown"))
        #expect(networkCause["method"] == .string("POST"))
        #expect(networkCause["outcomeUnknown"] == .bool(true))
        let networkInspection = try reviewSubmissionObject(networkDetails["inspection"])
        let networkArguments = try reviewSubmissionObject(networkInspection["arguments"])
        #expect(networkArguments["platforms"] == .string("MAC_OS"))
    }

    @Test("reads reject wrong types noncanonical IDs requested-ID drift and wrong ownership")
    func strictReadIdentityValidation() async throws {
        let getBodies = [
            reviewSubmissionBody(id: "sub-2"),
            reviewSubmissionBody(id: "bad/id"),
            reviewSubmissionBody(id: "sub-1").replacingOccurrences(
                of: #"https://api.example.test/v1/reviewSubmissions/sub-1"#,
                with: #"banana"#
            ),
            reviewSubmissionBody(id: "sub-1").replacingOccurrences(
                of: #""type": "reviewSubmissions""#,
                with: #""type": "apps""#
            )
        ]
        for body in getBodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "review_submissions_get",
                arguments: ["submission_id": .string("sub-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
            let payload = try reviewSubmissionObject(result.structuredContent)
            let details = try reviewSubmissionObject(payload["details"])
            #expect(details["type"] == .string("parsing"))
        }

        let listBody = reviewSubmissionsListBody(nextURL: "https://api.example.test/v1/reviewSubmissions")
            .replacingOccurrences(of: #""type":"apps","id":"app-1""#, with: #""type":"apps","id":"app-2""#)
        let listTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: listBody)])
        let listWorker = try await makeReviewSubmissionsWorker(transport: listTransport)
        let list = try await listWorker.handleTool(.init(
            name: "review_submissions_list",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(list.isError == true)

        let itemBody = reviewSubmissionItemsListBody(nextURL: "https://api.example.test/v1/reviewSubmissions/sub-1/items")
            .replacingOccurrences(of: #""type":"subscriptionVersions""#, with: #""type":"apps""#)
        let itemTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: itemBody)])
        let itemWorker = try await makeReviewSubmissionsWorker(transport: itemTransport)
        let items = try await itemWorker.handleTool(.init(
            name: "review_submissions_list_items",
            arguments: ["submission_id": .string("sub-1")]
        ))
        #expect(items.isError == true)
    }

    @Test("successful mutation responses must preserve requested identity")
    func mutationIdentityValidation() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewSubmissionBody(id: "bad/id"))
        ])
        let createWorker = try await makeReviewSubmissionsWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "review_submissions_create",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(create.isError == true)
        let createPayload = try reviewSubmissionObject(create.structuredContent)
        #expect(createPayload["operationCommitState"] == .string("committed_unverified"))
        let createCause = try reviewSubmissionObject(createPayload["cause"])
        #expect(createCause["type"] == .string("mutation_unverified"))
        #expect(createCause["method"] == .string("POST"))
        #expect(createCause["expectedStatusCode"] == .int(201))
        #expect(createCause["statusCode"] == .int(201))

        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])),
            .init(statusCode: 200, body: reviewSubmissionItemBody(id: "item-2"))
        ])
        let updateWorker = try await makeReviewSubmissionsWorker(transport: updateTransport)
        let update = try await updateWorker.handleTool(.init(
            name: "review_submissions_update_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "resolved": .bool(false),
                "removed": .null
            ]
        ))
        #expect(update.isError == true)
        let updatePayload = try reviewSubmissionObject(update.structuredContent)
        #expect(updatePayload["operationCommitState"] == .string("committed_unverified"))
        #expect(updatePayload["submission_id"] == .string("sub-1"))
        #expect(updatePayload["item_id"] == .string("item-1"))
        #expect(updatePayload["resolved"] == .bool(false))
        #expect(updatePayload["removed"] == .null)

        let updateNetworkTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"]))
        ])
        let updateNetworkWorker = try await makeReviewSubmissionsWorker(transport: updateNetworkTransport)
        let updateNetwork = try await updateNetworkWorker.handleTool(.init(
            name: "review_submissions_update_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "resolved": .null,
                "removed": .bool(true)
            ]
        ))
        let updateNetworkDetails = try reviewSubmissionObject(
            try reviewSubmissionObject(updateNetwork.structuredContent)["details"]
        )
        #expect(updateNetworkDetails["write_outcome"] == .string("unknown"))
        #expect(updateNetworkDetails["resolved"] == .null)
        #expect(updateNetworkDetails["removed"] == .bool(true))

        for tool in ["review_submissions_submit", "review_submissions_cancel"] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-2"))
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: tool,
                arguments: ["submission_id": .string("sub-1")]
            ))
            #expect(result.isError == true)
            let payload = try reviewSubmissionObject(result.structuredContent)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["operationCommitted"] == .bool(true))
            #expect(payload["retrySafe"] == .bool(false))
        }
    }

    @Test("mutation success receipts require Apple's exact 201 and 200 statuses")
    func exactMutationSuccessStatuses() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-1"))
        ])
        let createWorker = try await makeReviewSubmissionsWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "review_submissions_create",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(create.isError == true)
        #expect(try reviewSubmissionObject(create.structuredContent)["operationCommitState"] == .string("committed_unverified"))

        let addTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: reviewSubmissionItemBody(
                    id: "item-1",
                    relationshipName: "appEvent",
                    resourceType: "appEvents",
                    resourceID: "event-1"
                )
            )
        ])
        let addWorker = try await makeReviewSubmissionsWorker(transport: addTransport)
        let add = try await addWorker.handleTool(.init(
            name: "review_submissions_add_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "app_event_id": .string("event-1")
            ]
        ))
        #expect(add.isError == true)
        #expect(try reviewSubmissionObject(add.structuredContent)["operationCommitState"] == .string("committed_unverified"))

        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])),
            .init(statusCode: 201, body: reviewSubmissionItemBody(id: "item-1"))
        ])
        let updateWorker = try await makeReviewSubmissionsWorker(transport: updateTransport)
        let update = try await updateWorker.handleTool(.init(
            name: "review_submissions_update_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "resolved": .bool(true)
            ]
        ))
        #expect(update.isError == true)
        #expect(try reviewSubmissionObject(update.structuredContent)["operationCommitState"] == .string("committed_unverified"))

        for tool in ["review_submissions_submit", "review_submissions_cancel"] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: reviewSubmissionBody(id: "sub-1"))
            ])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: tool,
                arguments: ["submission_id": .string("sub-1")]
            ))
            #expect(result.isError == true)
            #expect(try reviewSubmissionObject(result.structuredContent)["operationCommitState"] == .string("committed_unverified"))
        }
    }

    @Test("update and delete prove exact parent membership through every strict page")
    func mutationMembershipPreflight() async throws {
        let noTargetTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: []))
        ])
        let noTargetWorker = try await makeReviewSubmissionsWorker(transport: noTargetTransport)
        let wrongParent = try await noTargetWorker.handleTool(.init(
            name: "review_submissions_remove_item",
            arguments: reviewSubmissionRemoveArguments()
        ))
        #expect(wrongParent.isError == true)
        #expect(await noTargetTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        let wrongParentDetails = try reviewSubmissionObject(
            try reviewSubmissionObject(wrongParent.structuredContent)["details"]
        )
        #expect(wrongParentDetails["mutationAttempted"] == .bool(false))

        let wrongSelfTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: reviewSubmissionMembershipBody(
                    itemIDs: ["item-1"],
                    selfPath: "/v1/reviewSubmissions/sub-2/items"
                )
            )
        ])
        let wrongSelfWorker = try await makeReviewSubmissionsWorker(transport: wrongSelfTransport)
        let wrongSelf = try await wrongSelfWorker.handleTool(.init(
            name: "review_submissions_update_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "resolved": .bool(true)
            ]
        ))
        #expect(wrongSelf.isError == true)
        #expect(await wrongSelfTransport.recordedRequests().map(\.httpMethod) == ["GET"])

        let incompleteTotalTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: reviewSubmissionMembershipBody(
                    itemIDs: ["item-1"],
                    total: 2,
                    limit: 200
                )
            )
        ])
        let incompleteTotalWorker = try await makeReviewSubmissionsWorker(transport: incompleteTotalTransport)
        let incompleteTotal = try await incompleteTotalWorker.handleTool(.init(
            name: "review_submissions_remove_item",
            arguments: reviewSubmissionRemoveArguments()
        ))
        #expect(incompleteTotal.isError == true)
        #expect(await incompleteTotalTransport.recordedRequests().map(\.httpMethod) == ["GET"])

        var continuationQuery = reviewSubmissionItemListQuery(limit: 200)
        continuationQuery["cursor"] = "page-2"
        let nextURL = reviewSubmissionURL(
            path: "/v1/reviewSubmissions/sub-1/items",
            query: continuationQuery
        )
        let laterPageTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: [], nextURL: nextURL)),
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])),
            .init(statusCode: 204, body: "")
        ])
        let laterPageWorker = try await makeReviewSubmissionsWorker(transport: laterPageTransport)
        let laterPage = try await laterPageWorker.handleTool(.init(
            name: "review_submissions_remove_item",
            arguments: reviewSubmissionRemoveArguments()
        ))
        #expect(laterPage.isError != true)
        let laterRequests = await laterPageTransport.recordedRequests()
        #expect(laterRequests.map(\.httpMethod) == ["GET", "GET", "DELETE"])
        #expect(try reviewSubmissionQuery(laterRequests[1]) == continuationQuery)

        let belowCumulativeTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: reviewSubmissionMembershipBody(
                    itemIDs: ["item-1"],
                    nextURL: nextURL,
                    total: 1,
                    limit: 200
                )
            ),
            .init(
                statusCode: 200,
                body: reviewSubmissionMembershipBody(
                    itemIDs: ["item-2"],
                    total: 1,
                    limit: 200
                )
            )
        ])
        let belowCumulativeWorker = try await makeReviewSubmissionsWorker(transport: belowCumulativeTransport)
        let belowCumulative = try await belowCumulativeWorker.handleTool(.init(
            name: "review_submissions_remove_item",
            arguments: reviewSubmissionRemoveArguments()
        ))
        #expect(belowCumulative.isError == true)
        #expect(await belowCumulativeTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])

        let duplicateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"], nextURL: nextURL)),
            .init(statusCode: 200, body: reviewSubmissionMembershipBody(itemIDs: ["item-1"]))
        ])
        let duplicateWorker = try await makeReviewSubmissionsWorker(transport: duplicateTransport)
        let duplicate = try await duplicateWorker.handleTool(.init(
            name: "review_submissions_update_item",
            arguments: [
                "submission_id": .string("sub-1"),
                "item_id": .string("item-1"),
                "resolved": .bool(true)
            ]
        ))
        #expect(duplicate.isError == true)
        #expect(await duplicateTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])
    }

    @Test("delete requires exact confirmation and classifies ambiguous and unverified outcomes without retry")
    func safeDeleteSemantics() async throws {
        for arguments in [
            ["submission_id": Value.string("sub-1"), "item_id": .string("item-1")],
            ["submission_id": Value.string("sub-1"), "item_id": .string("item-1"), "confirm_item_id": .string("item-2")],
            ["submission_id": Value.string("sub-1"), "item_id": .string(" item-1 "), "confirm_item_id": .string(" item-1 ")],
            ["submission_id": Value.string("sub-1"), "item_id": .string("bad/id"), "confirm_item_id": .string("bad/id")]
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "review_submissions_remove_item",
                arguments: arguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        let cases: [(Int?, String)] = [
            (nil, "unknown"),
            (408, "unknown"),
            (500, "unknown"),
            (200, "committed_unverified")
        ]
        for (statusCode, expectedState) in cases {
            var responses = [
                TestHTTPTransport.Response(
                    statusCode: 200,
                    body: reviewSubmissionMembershipBody(itemIDs: ["item-1"])
                )
            ]
            if let statusCode {
                responses.append(.init(statusCode: statusCode, body: ""))
            }
            let transport = TestHTTPTransport(responses: responses)
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "review_submissions_remove_item",
                arguments: reviewSubmissionRemoveArguments()
            ))
            #expect(result.isError == true)
            let requests = await transport.recordedRequests()
            #expect(requests.filter { $0.httpMethod == "DELETE" }.count == 1)
            let details = try reviewSubmissionObject(
                try reviewSubmissionObject(result.structuredContent)["details"]
            )
            #expect(details["deletionState"] == .string(expectedState))
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["submission_id"] == .string("sub-1"))
            #expect(details["item_id"] == .string("item-1"))
            let inspection = try reviewSubmissionObject(details["inspection"])
            #expect(inspection["continue_with_next_url"] == .bool(true))
        }
    }

    @Test("transported Apple errors retain structured status and error details")
    func structuredASCErrorPreservation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 403,
                body: #"{"errors":[{"status":"403","code":"FORBIDDEN.REQUIRED_AGREEMENTS_MISSING","title":"Forbidden","detail":"Agreement required"}]}"#
            )
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)
        let result = try await worker.handleTool(.init(
            name: "review_submissions_get",
            arguments: ["submission_id": .string("sub-1")]
        ))
        #expect(result.isError == true)
        let payload = try reviewSubmissionObject(result.structuredContent)
        let details = try reviewSubmissionObject(payload["details"])
        #expect(details["type"] == .string("api"))
        #expect(details["statusCode"] == .int(403))
        #expect(details["errors"]?.arrayValue?.count == 1)
    }

    @Test("list continuation preserves every originating query and ownership value")
    func strictListContinuationMatrix() async throws {
        let arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "states": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")]),
            "platforms": .string("IOS,MAC_OS"),
            "include": .string("items,submittedByActor"),
            "item_limit": .int(18),
            "limit": .int(90)
        ]
        let required = reviewSubmissionListQuery(
            appID: "app-1",
            states: "READY_FOR_REVIEW,IN_REVIEW",
            platforms: "IOS,MAC_OS",
            includes: "app,items,submittedByActor",
            itemLimit: 18,
            limit: 90
        )
        var validQuery = required
        validQuery["cursor"] = "next"

        let validTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/reviewSubmissions"}}"#
            )
        ])
        let validWorker = try await makeReviewSubmissionsWorker(transport: validTransport)
        var validArguments = arguments
        validArguments["next_url"] = .string(reviewSubmissionURL(path: "/v1/reviewSubmissions", query: validQuery))
        let validResult = try await validWorker.handleTool(CallTool.Parameters(
            name: "review_submissions_list",
            arguments: validArguments
        ))
        #expect(validResult.isError != true)
        #expect(try reviewSubmissionQuery(try #require(await validTransport.recordedRequests().first)) == validQuery)

        for key in required.keys {
            for mutation in ReviewSubmissionQueryMutation.allCases {
                var query = validQuery
                switch mutation {
                case .missing:
                    query.removeValue(forKey: key)
                case .changed:
                    query[key] = "drift"
                }
                try await expectRejectedReviewSubmissionContinuation(
                    tool: "review_submissions_list",
                    arguments: arguments,
                    path: "/v1/reviewSubmissions",
                    query: query
                )
            }
        }

        var ownershipMismatch = validQuery
        ownershipMismatch["filter[app]"] = "another-app"
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list",
            arguments: arguments,
            path: "/v1/reviewSubmissions",
            query: ownershipMismatch
        )

        for cursor in [String?.none, .some(""), .some(" ")] {
            var query = required
            query["cursor"] = cursor
            try await expectRejectedReviewSubmissionContinuation(
                tool: "review_submissions_list",
                arguments: arguments,
                path: "/v1/reviewSubmissions",
                query: query
            )
        }

        var injected = validQuery
        injected["filter[unexpected]"] = "value"
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list",
            arguments: arguments,
            path: "/v1/reviewSubmissions",
            query: injected
        )

        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list",
            arguments: arguments,
            path: "/v1/apps/app-1/reviewSubmissions",
            query: validQuery
        )
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list",
            arguments: arguments,
            path: "/v1/reviewSubmissions",
            query: validQuery,
            host: "other.example.test"
        )

        let duplicate = reviewSubmissionURL(path: "/v1/reviewSubmissions", query: validQuery) + "&cursor=duplicate"
        let duplicateTransport = TestHTTPTransport(responses: [])
        let duplicateWorker = try await makeReviewSubmissionsWorker(transport: duplicateTransport)
        var duplicateArguments = arguments
        duplicateArguments["next_url"] = .string(duplicate)
        let duplicateResult = try await duplicateWorker.handleTool(CallTool.Parameters(
            name: "review_submissions_list",
            arguments: duplicateArguments
        ))
        #expect(duplicateResult.isError == true)
        #expect(await duplicateTransport.requestCount() == 0)
    }

    @Test("item continuation rejects another parent changed query missing cursor and injection")
    func strictItemContinuationMatrix() async throws {
        let arguments: [String: Value] = [
            "submission_id": .string("sub-1"),
            "limit": .int(60)
        ]
        let required = reviewSubmissionItemListQuery(limit: 60)
        var valid = required
        valid["cursor"] = "next"

        let validTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items"}}"#
            )
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: validTransport)
        var validArguments = arguments
        validArguments["next_url"] = .string(reviewSubmissionURL(
            path: "/v1/reviewSubmissions/sub-1/items",
            query: valid
        ))
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_list_items",
            arguments: validArguments
        ))
        #expect(result.isError != true)

        var changed = valid
        changed["limit"] = "1"
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list_items",
            arguments: arguments,
            path: "/v1/reviewSubmissions/sub-1/items",
            query: changed
        )
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list_items",
            arguments: arguments,
            path: "/v1/reviewSubmissions/sub-2/items",
            query: valid
        )
        var noCursor = required
        noCursor.removeValue(forKey: "cursor")
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list_items",
            arguments: arguments,
            path: "/v1/reviewSubmissions/sub-1/items",
            query: noCursor
        )
        var injection = valid
        injection["include"] = "gameCenterAchievementVersion"
        try await expectRejectedReviewSubmissionContinuation(
            tool: "review_submissions_list_items",
            arguments: arguments,
            path: "/v1/reviewSubmissions/sub-1/items",
            query: injection
        )
    }

    @Test("create add failure inspect and item list provide a complete recovery chain")
    func partialFailureRecovery() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewSubmissionBody(id: "sub-recover")),
            .init(
                statusCode: 409,
                body: #"{"errors":[{"status":"409","code":"ENTITY_ERROR.RELATIONSHIP.INVALID","title":"Conflict","detail":"Item already exists"}]}"#
            ),
            .init(statusCode: 200, body: reviewSubmissionBody(id: "sub-recover", includeContext: true)),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://api.example.test/v1/reviewSubmissions/sub-recover/items"},"meta":{"paging":{"total":0,"limit":25}}}"#
            )
        ])
        let worker = try await makeReviewSubmissionsWorker(transport: transport)

        let create = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_create",
            arguments: ["app_id": .string("app-1")]
        ))
        let createPayload = try reviewSubmissionObject(create.structuredContent)
        let created = try reviewSubmissionObject(createPayload["submission"])
        let recovery = try reviewSubmissionObject(created["recovery"])
        #expect(recovery["submission_id"] == .string("sub-recover"))
        #expect(recovery["add_item_tool"] == .string("review_submissions_add_item"))

        let failedAdd = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_add_item",
            arguments: [
                "submission_id": .string("sub-recover"),
                "app_store_version_id": .string("version-1")
            ]
        ))
        #expect(failedAdd.isError == true)

        let inspect = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_get",
            arguments: ["submission_id": .string("sub-recover")]
        ))
        #expect(inspect.isError != true)
        let inspectPayload = try reviewSubmissionObject(inspect.structuredContent)
        let inspected = try reviewSubmissionObject(inspectPayload["submission"])
        #expect(inspected["id"] == .string("sub-recover"))

        let items = try await worker.handleTool(CallTool.Parameters(
            name: "review_submissions_list_items",
            arguments: ["submission_id": .string("sub-recover")]
        ))
        #expect(items.isError != true)
        let itemsPayload = try reviewSubmissionObject(items.structuredContent)
        #expect(itemsPayload["total"] == .int(0))
        #expect(itemsPayload["count"] == .int(0))

        #expect(await transport.recordedRequests().map(\.httpMethod) == ["POST", "POST", "GET", "GET"])
    }

    @Test("every tool rejects unknown direct-call parameters before network")
    func unknownParameters() async throws {
        let cases: [(String, [String: Value])] = [
            ("review_submissions_list", ["app_id": .string("app-1")]),
            ("review_submissions_get", ["submission_id": .string("sub-1")]),
            ("review_submissions_create", ["app_id": .string("app-1")]),
            ("review_submissions_list_items", ["submission_id": .string("sub-1")]),
            (
                "review_submissions_add_item",
                ["submission_id": .string("sub-1"), "app_event_id": .string("event-1")]
            ),
            (
                "review_submissions_update_item",
                [
                    "submission_id": .string("sub-1"),
                    "item_id": .string("item-1"),
                    "resolved": .bool(true)
                ]
            ),
            (
                "review_submissions_remove_item",
                reviewSubmissionRemoveArguments()
            ),
            ("review_submissions_submit", ["submission_id": .string("sub-1")]),
            ("review_submissions_cancel", ["submission_id": .string("sub-1")])
        ]

        for (tool, baseArguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeReviewSubmissionsWorker(transport: transport)
            var arguments = baseArguments
            arguments["typo_parameter"] = .bool(true)
            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
            let payload = try reviewSubmissionObject(result.structuredContent)
            #expect(payload["error"]?.stringValue?.contains("typo_parameter") == true)
        }
    }

    @Test("missing required parameters fail all nine handlers without network")
    func missingParameters() async throws {
        let worker = ReviewSubmissionsWorker(httpClient: try await TestFactory.makeHTTPClient())
        for name in [
            "review_submissions_list",
            "review_submissions_get",
            "review_submissions_create",
            "review_submissions_list_items",
            "review_submissions_add_item",
            "review_submissions_update_item",
            "review_submissions_remove_item",
            "review_submissions_submit",
            "review_submissions_cancel"
        ] {
            let result = try await worker.handleTool(CallTool.Parameters(name: name, arguments: nil))
            #expect(result.isError == true, "Expected missing parameter error from \(name)")
        }
    }
}

private let reviewSubmissionTypedIDFields: Set<String> = [
    "app_store_version_id",
    "app_custom_product_page_version_id",
    "app_store_version_experiment_v2_id",
    "app_event_id",
    "background_asset_version_id",
    "in_app_purchase_version_id",
    "subscription_version_id",
    "subscription_group_version_id"
]

private let reviewSubmissionFields =
    "platform,submittedDate,state,app,items,appStoreVersionForReview,submittedByActor,lastUpdatedByActor"
private let reviewSubmissionItemFields =
    "state,appStoreVersion,appCustomProductPageVersion,appStoreVersionExperiment,appStoreVersionExperimentV2,appEvent,backgroundAssetVersion,gameCenterAchievementVersion,gameCenterActivityVersion,gameCenterChallengeVersion,gameCenterLeaderboardSetVersion,gameCenterLeaderboardVersion,inAppPurchaseVersion,subscriptionVersion,subscriptionGroupVersion"
private let reviewSubmissionAppVersionFields =
    "platform,versionString,appStoreState,appVersionState,reviewType,releaseType,createdDate"
private let reviewSubmissionActorFields = "actorType,userFirstName,userLastName,userEmail,apiKeyId"
private let reviewSubmissionSupportedIncludes =
    "appStoreVersion,appCustomProductPageVersion,appStoreVersionExperimentV2,appEvent,backgroundAssetVersion,inAppPurchaseVersion,subscriptionVersion,subscriptionGroupVersion"

private func makeReviewSubmissionsWorker(
    transport: TestHTTPTransport
) async throws -> ReviewSubmissionsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ReviewSubmissionsWorker(httpClient: client)
}

private func reviewSubmissionRemoveArguments() -> [String: Value] {
    [
        "submission_id": .string("sub-1"),
        "item_id": .string("item-1"),
        "confirm_item_id": .string("item-1")
    ]
}

private func reviewSubmissionProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        Issue.record("Expected object properties for \(tool.name)")
        throw ReviewSubmissionTestFailure.expectedObject
    }
    return properties
}

private func reviewSubmissionObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw ReviewSubmissionTestFailure.expectedObject
    }
    return object
}

private func reviewSubmissionRequestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func reviewSubmissionRelationshipData(_ value: Any?) throws -> [String: Any] {
    let relationship = try #require(value as? [String: Any])
    return try #require(relationship["data"] as? [String: Any])
}

private func reviewSubmissionQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func reviewSubmissionListQuery(
    appID: String,
    states: String? = nil,
    platforms: String? = nil,
    includes: String = "app,items,appStoreVersionForReview,submittedByActor,lastUpdatedByActor",
    itemLimit: Int = 50,
    limit: Int = 25
) -> [String: String] {
    var query: [String: String] = [
        "fields[reviewSubmissions]": reviewSubmissionFields,
        "fields[apps]": "name,bundleId,sku,primaryLocale",
        "fields[reviewSubmissionItems]": reviewSubmissionItemFields,
        "fields[appStoreVersions]": reviewSubmissionAppVersionFields,
        "fields[actors]": reviewSubmissionActorFields,
        "include": includes,
        "limit[items]": String(itemLimit),
        "filter[app]": appID,
        "limit": String(limit)
    ]
    query["filter[state]"] = states
    query["filter[platform]"] = platforms
    return query
}

private func reviewSubmissionItemListQuery(limit: Int) -> [String: String] {
    [
        "fields[reviewSubmissionItems]": reviewSubmissionItemFields,
        "fields[appStoreVersions]": reviewSubmissionAppVersionFields,
        "fields[appCustomProductPageVersions]": "version,state,deepLink",
        "fields[appStoreVersionExperiments]": "name,trafficProportion,state,reviewRequired,startDate,endDate,platform",
        "fields[appEvents]": "referenceName,badge,eventState,deepLink,purchaseRequirement,primaryLocale,priority,purpose",
        "fields[backgroundAssetVersions]": "createdDate,platforms,state,stateDetails,version,locale",
        "fields[inAppPurchaseVersions]": "version,state",
        "fields[subscriptionVersions]": "version,state",
        "fields[subscriptionGroupVersions]": "version,state",
        "include": reviewSubmissionSupportedIncludes,
        "limit": String(limit)
    ]
}

private func reviewSubmissionURL(
    path: String,
    query: [String: String],
    host: String = "api.example.test"
) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    return components.url!.absoluteString
}

private func expectRejectedReviewSubmissionContinuation(
    tool: String,
    arguments: [String: Value],
    path: String,
    query: [String: String],
    host: String = "api.example.test"
) async throws {
    let transport = TestHTTPTransport(responses: [])
    let worker = try await makeReviewSubmissionsWorker(transport: transport)
    var nextArguments = arguments
    nextArguments["next_url"] = .string(reviewSubmissionURL(path: path, query: query, host: host))
    let result = try await worker.handleTool(CallTool.Parameters(
        name: tool,
        arguments: nextArguments
    ))
    #expect(result.isError == true)
    #expect(await transport.requestCount() == 0)
}

private func reviewSubmissionBody(
    id: String,
    state: String = "UNRESOLVED_ISSUES",
    includeContext: Bool = false
) -> String {
    let included = includeContext
        ? """
          ,"included":[
            {"type":"actors","id":"actor-1","attributes":{"actorType":"USER","userFirstName":"Ada"}},
            {"type":"actors","id":"actor-2","attributes":{"actorType":"API_KEY","apiKeyId":"key-1"}},
            {"type":"reviewSubmissionItems","id":"item-1","attributes":{"state":"REJECTED"},"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"version-1"}}}}
          ]
          """
        : ""
    return """
    {
      "data": {
        "type": "reviewSubmissions",
        "id": "\(id)",
        "attributes": {
          "platform": "IOS",
          "submittedDate": "2026-07-20T09:30:00Z",
          "state": "\(state)"
        },
        "relationships": {
          "app": {"data":{"type":"apps","id":"app-1"}},
          "items": {"data":[{"type":"reviewSubmissionItems","id":"item-1"}]},
          "appStoreVersionForReview": {"data":{"type":"appStoreVersions","id":"version-1"}},
          "submittedByActor": {"data":{"type":"actors","id":"actor-1"}},
          "lastUpdatedByActor": {"data":{"type":"actors","id":"actor-2"}}
        },
        "links": {"self":"https://api.example.test/v1/reviewSubmissions/\(id)"}
      },
      "links": {"self":"https://api.example.test/v1/reviewSubmissions/\(id)"}
      \(included)
    }
    """
}

private func reviewSubmissionsListBody(nextURL: String) -> String {
    """
    {
      "data": [
        {
          "type": "reviewSubmissions",
          "id": "sub-1",
          "attributes": {"platform":"IOS","submittedDate":"2026-07-20T09:30:00Z","state":"UNRESOLVED_ISSUES"},
          "relationships": {
            "app": {"data":{"type":"apps","id":"app-1"}},
            "items": {"data":[{"type":"reviewSubmissionItems","id":"item-1"}]},
            "appStoreVersionForReview": {"data":{"type":"appStoreVersions","id":"version-1"}},
            "submittedByActor": {"data":{"type":"actors","id":"actor-1"}},
            "lastUpdatedByActor": {"data":{"type":"actors","id":"actor-1"}}
          }
        }
      ],
      "included": [
        {"type":"actors","id":"actor-1","attributes":{"actorType":"USER","userFirstName":"Ada"}},
        {"type":"reviewSubmissionItems","id":"item-1","attributes":{"state":"REJECTED"}}
      ],
      "links": {"self":"https://api.example.test/v1/reviewSubmissions","next":"\(nextURL)"},
      "meta": {"paging":{"total":4,"limit":125}}
    }
    """
}

private func reviewSubmissionItemBody(
    id: String,
    relationshipName: String? = nil,
    resourceType: String = "appStoreVersions",
    resourceID: String = "version-1"
) -> String {
    let relationship = relationshipName.map {
        ",\"relationships\":{\"\($0)\":{\"data\":{\"type\":\"\(resourceType)\",\"id\":\"\(resourceID)\"}}}"
    } ?? ""
    return "{\"data\":{\"type\":\"reviewSubmissionItems\",\"id\":\"\(id)\",\"attributes\":{\"state\":\"READY_FOR_REVIEW\"}\(relationship)},\"links\":{\"self\":\"https://api.example.test/v1/reviewSubmissionItems/\(id)\"}}"
}

private func reviewSubmissionItemsListBody(nextURL: String) -> String {
    """
    {
      "data": [
        {
          "type": "reviewSubmissionItems",
          "id": "item-1",
          "attributes": {"state":"READY_FOR_REVIEW"},
          "relationships": {
            "subscriptionVersion": {"data":{"type":"subscriptionVersions","id":"subscription-version-1"}}
          }
        }
      ],
      "included": [
        {"type":"subscriptionVersions","id":"subscription-version-1","attributes":{"version":2,"state":"PREPARE_FOR_SUBMISSION"}}
      ],
      "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items","next":"\(nextURL)"},
      "meta": {"paging":{"total":1,"limit":75}}
    }
    """
}

private func reviewSubmissionMembershipBody(
    itemIDs: [String],
    nextURL: String? = nil,
    total: Int? = nil,
    limit: Int? = nil,
    selfPath: String = "/v1/reviewSubmissions/sub-1/items"
) -> String {
    let items = itemIDs.map { id in
        "{\"type\":\"reviewSubmissionItems\",\"id\":\"\(id)\",\"attributes\":{\"state\":\"READY_FOR_REVIEW\"}}"
    }.joined(separator: ",")
    let next = nextURL.map { ",\"next\":\"\($0)\"" } ?? ""
    let meta: String
    if let limit {
        let total = total.map { ",\"total\":\($0)" } ?? ""
        meta = ",\"meta\":{\"paging\":{\"limit\":\(limit)\(total)}}"
    } else {
        meta = ""
    }
    return "{\"data\":[\(items)],\"links\":{\"self\":\"https://api.example.test\(selfPath)\"\(next)}\(meta)}"
}

private func reviewSubmissionMixedItemsBody() -> String {
    """
    {
      "data": [
        {
          "type": "reviewSubmissionItems",
          "id": "item-legacy",
          "attributes": {"state":"READY_FOR_REVIEW"},
          "relationships": {
            "appStoreVersionExperiment": {"data":{"type":"appStoreVersionExperiments","id":"legacy-experiment-1"}}
          }
        },
        {
          "type": "reviewSubmissionItems",
          "id": "item-game-center",
          "attributes": {"state":"READY_FOR_REVIEW"},
          "relationships": {
            "gameCenterAchievementVersion": {"data":{"type":"gameCenterAchievementVersions","id":"achievement-version-1"}}
          }
        }
      ],
      "links": {"self":"https://api.example.test/v1/reviewSubmissions/sub-1/items"},
      "meta": {"paging":{"total":2,"limit":25}}
    }
    """
}

private enum ReviewSubmissionQueryMutation: CaseIterable {
    case missing
    case changed
}

private enum ReviewSubmissionJSONKind: Equatable {
    case boolean
    case null
}

private enum ReviewSubmissionTestFailure: Error {
    case expectedObject
}

private extension Value {
    var objectValue: [String: Value]? {
        guard case .object(let object) = self else { return nil }
        return object
    }
}
