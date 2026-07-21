import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Promoted Purchases v3.19 Contract Tests")
struct PromotedV319ContractTests {
    @Test("schema exposes JSON-array reorder and exact delete confirmation")
    func schemasExposeSafeMutationContracts() async throws {
        let worker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(TestHTTPTransport(responses: [])),
            uploadService: UploadService()
        )
        let tools = await worker.getTools()
        #expect(tools.count == 10)
        #expect(Set(tools.map(\.name)).contains("promoted_reorder"))

        for tool in tools {
            let schema = try promotedV319Object(tool.inputSchema)
            #expect(schema["additionalProperties"] == .bool(false))
        }

        let reorder = try #require(tools.first { $0.name == "promoted_reorder" })
        let reorderSchema = try promotedV319Object(reorder.inputSchema)
        let reorderProperties = try promotedV319Object(reorderSchema["properties"])
        let identifiers = try promotedV319Object(reorderProperties["promoted_purchase_ids"])
        #expect(identifiers["type"] == .string("array"))
        #expect(identifiers["minItems"] == .int(1))
        #expect(identifiers["maxItems"] == .int(200))
        #expect(identifiers["uniqueItems"] == .bool(true))
        let canonicalIDPattern = #"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#
        let identifierItems = try promotedV319Object(identifiers["items"])
        #expect(identifierItems["minLength"] == .int(1))
        #expect(identifierItems["pattern"] == .string(canonicalIDPattern))
        #expect(try promotedV319StringSet(reorderSchema["required"]) == [
            "app_id", "promoted_purchase_ids"
        ])

        let list = try #require(tools.first { $0.name == "promoted_list" })
        let listSchema = try promotedV319Object(list.inputSchema)
        let listProperties = try promotedV319Object(listSchema["properties"])
        let limit = try promotedV319Object(listProperties["limit"])
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
        #expect(limit["default"] == .int(25))
        let nextURL = try promotedV319Object(listProperties["next_url"])
        #expect(nextURL["minLength"] == .int(1))
        #expect(nextURL["format"] == .string("uri-reference"))
        #expect(nextURL["pattern"] == .string(#"^(?!.*\s).+$"#))

        let activeIdentifierFields: [(String, [String])] = [
            ("promoted_list", ["app_id"]),
            ("promoted_get", ["promoted_purchase_id"]),
            ("promoted_create", ["app_id", "iap_id", "subscription_id"]),
            ("promoted_update", ["promoted_purchase_id"]),
            ("promoted_delete", ["promoted_purchase_id", "confirm_promoted_purchase_id"]),
            ("promoted_reorder", ["app_id"])
        ]
        for (toolName, fieldNames) in activeIdentifierFields {
            let tool = try #require(tools.first { $0.name == toolName })
            let schema = try promotedV319Object(tool.inputSchema)
            let properties = try promotedV319Object(schema["properties"])
            for fieldName in fieldNames {
                let identifier = try promotedV319Object(properties[fieldName])
                #expect(identifier["minLength"] == .int(1))
                #expect(identifier["pattern"] == .string(canonicalIDPattern))
            }
        }

        let delete = try #require(tools.first { $0.name == "promoted_delete" })
        let deleteSchema = try promotedV319Object(delete.inputSchema)
        #expect(try promotedV319StringSet(deleteSchema["required"]) == [
            "promoted_purchase_id", "confirm_promoted_purchase_id"
        ])

        for name in [
            "promoted_upload_image",
            "promoted_get_image",
            "promoted_delete_image",
            "promoted_get_image_for_purchase"
        ] {
            let tool = try #require(tools.first { $0.name == name })
            #expect(tool.description?.contains("absent from pinned executable OpenAPI 4.4.1") == true)
        }
    }

    @Test("reorder exhausts membership pages and verifies exact postflight order")
    func reorderUsesCompletePreflightAndPostflight() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: "preflight-2",
                    total: 2
                )
            ),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-2"],
                    cursor: "preflight-2",
                    nextCursor: nil,
                    total: 2
                )
            ),
            .init(statusCode: 204, body: ""),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-2"],
                    cursor: nil,
                    nextCursor: "postflight-2",
                    total: 2
                )
            ),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: "postflight-2",
                    nextCursor: nil,
                    total: 2
                )
            )
        ])
        let worker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(transport),
            uploadService: UploadService()
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-2"),
                    .string("promoted-1")
                ])
            ]
        ))

        #expect(result.isError != true)
        let root = try promotedV319Object(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["statusCode"] == .int(204))
        #expect(root["mutationAttempted"] == .bool(true))
        #expect(root["changed"] == .bool(true))
        #expect(root["order"] == .array([
            .string("promoted-2"),
            .string("promoted-1")
        ]))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 5)
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET", "GET"])
        #expect(requests[2].url?.path == "/v1/apps/app-1/relationships/promotedPurchases")
        let body = try promotedV319JSONBody(requests[2])
        let linkages = try promotedV319JSONArray(body["data"])
        #expect(linkages.map { ($0 as? [String: Any])?["id"] as? String } == [
            "promoted-2", "promoted-1"
        ])
        #expect(linkages.allSatisfy { ($0 as? [String: Any])?["type"] as? String == "promotedPurchases" })
    }

    @Test("reorder short-circuits an already current order without PATCH")
    func reorderNoOpDoesNotMutate() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1", "promoted-2"],
                    cursor: nil,
                    nextCursor: nil
                )
            )
        ])
        let worker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(transport),
            uploadService: UploadService()
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-1"),
                    .string("promoted-2")
                ])
            ]
        ))

        #expect(result.isError != true)
        let root = try promotedV319Object(result.structuredContent)
        #expect(root["operationCommitState"] == .string("not_attempted"))
        #expect(root["operationCommitted"] == .bool(false))
        #expect(root["mutationAttempted"] == .bool(false))
        #expect(root["changed"] == .bool(false))
        #expect(root["retrySafe"] == .bool(true))
        #expect(root["statusCode"] == nil)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("reorder rejects unstable totals and incomplete terminal pagination before PATCH")
    func reorderValidatesStableCumulativeTotal() async throws {
        let unstableTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: "page-2",
                    total: 2
                )
            ),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-2"],
                    cursor: "page-2",
                    nextCursor: nil,
                    total: 3
                )
            )
        ])
        let unstableWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(unstableTransport),
            uploadService: UploadService()
        )
        let unstable = try await unstableWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-2"),
                    .string("promoted-1")
                ])
            ]
        ))
        #expect(unstable.isError == true)
        #expect(await unstableTransport.requestCount() == 2)
        #expect((await unstableTransport.recordedRequests()).allSatisfy { $0.httpMethod == "GET" })

        let incompleteTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: nil,
                    total: 2
                )
            )
        ])
        let incompleteWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(incompleteTransport),
            uploadService: UploadService()
        )
        let incomplete = try await incompleteWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-1"),
                    .string("promoted-2")
                ])
            ]
        ))
        #expect(incomplete.isError == true)
        #expect(await incompleteTransport.requestCount() == 1)
        #expect((await incompleteTransport.recordedRequests()).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("reorder linkage pages enforce scoped advancing next links and exact paging metadata")
    func reorderValidatesRelationshipPageContracts() async throws {
        let relationshipPath = "/v1/apps/app-1/relationships/promotedPurchases"
        let overLimitIDs = (0...200).map { "promoted-\($0)" }
        let invalidBodies = [
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: "next",
                nextURLOverride: "https://evil.example.test\(relationshipPath)?limit=200&cursor=next"
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: "next",
                nextURLOverride: "https://api.example.test/v1/apps/app-2/relationships/promotedPurchases?limit=200&cursor=next"
            ),
            promotedV319LinkagePage(
                ids: overLimitIDs,
                cursor: nil,
                nextCursor: nil,
                includeMeta: false
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: nil,
                pagingLimit: 199
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: nil,
                total: 0
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: "next",
                includeNextCursorMetadata: false
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: "next",
                metadataNextCursor: "other"
            ),
            promotedV319LinkagePage(
                ids: ["promoted-1"],
                cursor: nil,
                nextCursor: nil,
                metadataNextCursor: "orphan"
            )
        ]

        for body in invalidBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = PromotedPurchasesWorker(
                httpClient: try await promotedV319Client(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "promoted_reorder",
                arguments: [
                    "app_id": .string("app-1"),
                    "promoted_purchase_ids": .array([.string("promoted-1")])
                ]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
            #expect((await transport.recordedRequests()).allSatisfy { $0.httpMethod == "GET" })
        }

        let repeatedCursorTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: "page-2",
                    total: 2
                )
            ),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-2"],
                    cursor: "page-2",
                    nextCursor: "page-2",
                    total: 2
                )
            )
        ])
        let repeatedCursorWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(repeatedCursorTransport),
            uploadService: UploadService()
        )
        let repeatedCursor = try await repeatedCursorWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-1"),
                    .string("promoted-2")
                ])
            ]
        ))
        #expect(repeatedCursor.isError == true)
        #expect(await repeatedCursorTransport.requestCount() == 2)
        #expect((await repeatedCursorTransport.recordedRequests()).allSatisfy {
            $0.httpMethod == "GET"
        })
    }

    @Test("reorder rejects duplicate or incomplete membership before PATCH")
    func reorderRejectsUnsafeMembership() async throws {
        let duplicateTransport = TestHTTPTransport(responses: [])
        let duplicateWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(duplicateTransport),
            uploadService: UploadService()
        )
        let duplicate = try await duplicateWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-1"),
                    .string("promoted-1")
                ])
            ]
        ))
        #expect(duplicate.isError == true)
        #expect(await duplicateTransport.requestCount() == 0)

        let incompleteTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1", "promoted-2"],
                    cursor: nil,
                    nextCursor: nil
                )
            )
        ])
        let incompleteWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(incompleteTransport),
            uploadService: UploadService()
        )
        let incomplete = try await incompleteWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([.string("promoted-1")])
            ]
        ))
        #expect(incomplete.isError == true)
        #expect(await incompleteTransport.requestCount() == 1)
        #expect((await incompleteTransport.recordedRequests()).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("reorder accepts only 204 and fails closed when postflight order differs")
    func reorderRequiresExactStatusAndOrder() async throws {
        let wrongStatusTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1", "promoted-2"],
                    cursor: nil,
                    nextCursor: nil
                )
            ),
            .init(statusCode: 200, body: "")
        ])
        let wrongStatusWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(wrongStatusTransport),
            uploadService: UploadService()
        )
        let wrongStatus = try await wrongStatusWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-2"),
                    .string("promoted-1")
                ])
            ]
        ))
        #expect(wrongStatus.isError == true)
        let wrongStatusRoot = try promotedV319Object(wrongStatus.structuredContent)
        #expect(wrongStatusRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(wrongStatusRoot["inspectionRequired"] == .bool(true))
        #expect(await wrongStatusTransport.requestCount() == 2)

        let mismatchTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1", "promoted-2"],
                    cursor: nil,
                    nextCursor: nil
                )
            ),
            .init(statusCode: 204, body: ""),
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1", "promoted-2"],
                    cursor: nil,
                    nextCursor: nil
                )
            )
        ])
        let mismatchWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(mismatchTransport),
            uploadService: UploadService()
        )
        let mismatch = try await mismatchWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([
                    .string("promoted-2"),
                    .string("promoted-1")
                ])
            ]
        ))
        #expect(mismatch.isError == true)
        let mismatchRoot = try promotedV319Object(mismatch.structuredContent)
        #expect(mismatchRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(await mismatchTransport.requestCount() == 3)
    }

    @Test("create and update require exact success status and canonical response identity")
    func existingMutationsFailClosedOnAcceptedResponseDrift() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1"}}"#
            )
        ])
        let createWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(createTransport),
            uploadService: UploadService()
        )
        let create = try await createWorker.handleTool(CallTool.Parameters(
            name: "promoted_create",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .bool(true),
                "iap_id": .string("iap-1")
            ]
        ))
        #expect(create.isError == true)
        let createRoot = try promotedV319Object(create.structuredContent)
        #expect(createRoot["operationCommitState"] == .string("committed_unverified"))
        let createDetails = try promotedV319Object(createRoot["details"])
        let createRecovery = try promotedV319Object(createDetails["recovery"])
        #expect(try promotedV319Object(createRecovery["list_candidates"])["tool"] == .string("promoted_list"))
        let candidateScope = try promotedV319Object(createRecovery["candidate_scope"])
        #expect(candidateScope["request_field"] == .string("app_id"))
        #expect(candidateScope["list_argument"] == .string("app_id"))
        #expect(candidateScope["value"] == .string("app-1"))
        let matchRequested = try promotedV319Object(createRecovery["match_requested"])
        #expect(matchRequested["request_values"] == .object([
            "visible": .bool(true),
            "iap_id": .string("iap-1")
        ]))
        let mappings = try promotedV319ValueArray(matchRequested["field_mappings"])
        #expect(mappings.contains(.object([
            "request_field": .string("visible"),
            "request_value": .bool(true),
            "output_field": .string("visibleForAllUsers")
        ])))
        #expect(mappings.contains(.object([
            "request_field": .string("iap_id"),
            "request_value": .string("iap-1"),
            "output_field": .string("inAppPurchaseId")
        ])))

        let updateTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"other-promoted"},"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1"}}"#
            )
        ])
        let updateWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(updateTransport),
            uploadService: UploadService()
        )
        let update = try await updateWorker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "enabled": .bool(false)
            ]
        ))
        #expect(update.isError == true)
        let updateRoot = try promotedV319Object(update.structuredContent)
        #expect(updateRoot["operationCommitState"] == .string("committed_unverified"))
        let updateDetails = try promotedV319Object(updateRoot["details"])
        let updateRecovery = try promotedV319Object(updateDetails["recovery"])
        #expect(try promotedV319Object(updateRecovery["inspect_target"])["tool"] == .string("promoted_get"))
    }

    @Test("reads require canonical document links and exact included lineage")
    func readsRejectMalformedDocumentContracts() async throws {
        let detailBodies = [
            #"{"data":{"type":"promotedPurchases","id":"promoted-1"}}"#,
            #"{"data":{"type":"promotedPurchases","id":"promoted-1"},"links":{"self":"https://api.example.test/v1/promotedPurchases/other?include=inAppPurchaseV2,subscription"}}"#,
            #"{"data":{"type":"promotedPurchases","id":"promoted-1","attributes":{"visibleForAllUsers":null}},"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#,
            #"{"data":{"type":"promotedPurchases","id":"promoted-1"},"included":[{"type":"inAppPurchases","id":"iap-1"}],"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#,
            #"{"data":{"type":"promotedPurchases","id":"promoted-1","relationships":{"inAppPurchaseV2":{"data":{"type":"inAppPurchases","id":"iap-1"}}}},"included":[{"type":"inAppPurchases","id":"iap-2"}],"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#
        ]
        for body in detailBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = PromotedPurchasesWorker(
                httpClient: try await promotedV319Client(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "promoted_get",
                arguments: ["promoted_purchase_id": .string("promoted-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }

        for body in [
            #"{"data":[]}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/promotedPurchases?limit=24"}}"#
        ] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = PromotedPurchasesWorker(
                httpClient: try await promotedV319Client(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "promoted_list",
                arguments: ["app_id": .string("app-1"), "limit": .int(25)]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("document, collection, and linkage self reject hostile origins")
    func requiredSelfLinksRejectHostileOrigin() async throws {
        let detailTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1"},"links":{"self":"https://evil.example.test/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#
            )
        ])
        let detailWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(detailTransport),
            uploadService: UploadService()
        )
        let detail = try await detailWorker.handleTool(CallTool.Parameters(
            name: "promoted_get",
            arguments: ["promoted_purchase_id": .string("promoted-1")]
        ))
        #expect(detail.isError == true)
        #expect(await detailTransport.requestCount() == 1)

        let listTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"https://evil.example.test/v1/apps/app-1/promotedPurchases?limit=25"}}"#
            )
        ])
        let listWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(listTransport),
            uploadService: UploadService()
        )
        let list = try await listWorker.handleTool(CallTool.Parameters(
            name: "promoted_list",
            arguments: ["app_id": .string("app-1"), "limit": .int(25)]
        ))
        #expect(list.isError == true)
        #expect(await listTransport.requestCount() == 1)

        let linkageTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: nil,
                    host: "evil.example.test"
                )
            )
        ])
        let linkageWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(linkageTransport),
            uploadService: UploadService()
        )
        let linkage = try await linkageWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([.string("promoted-1")])
            ]
        ))
        #expect(linkage.isError == true)
        #expect(await linkageTransport.requestCount() == 1)
        #expect((await linkageTransport.recordedRequests()).allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("document, collection, and linkage self accept root-relative references")
    func requiredSelfLinksAcceptRootRelativeOrigin() async throws {
        let detailTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1"},"links":{"self":"/v1/promotedPurchases/promoted-1?include=inAppPurchaseV2,subscription"}}"#
            )
        ])
        let detailWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(detailTransport),
            uploadService: UploadService()
        )
        let detail = try await detailWorker.handleTool(CallTool.Parameters(
            name: "promoted_get",
            arguments: ["promoted_purchase_id": .string("promoted-1")]
        ))
        #expect(detail.isError != true)

        let listTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/apps/app-1/promotedPurchases?limit=25"}}"#
            )
        ])
        let listWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(listTransport),
            uploadService: UploadService()
        )
        let list = try await listWorker.handleTool(CallTool.Parameters(
            name: "promoted_list",
            arguments: ["app_id": .string("app-1"), "limit": .int(25)]
        ))
        #expect(list.isError != true)

        let linkageTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319LinkagePage(
                    ids: ["promoted-1"],
                    cursor: nil,
                    nextCursor: nil,
                    host: nil
                )
            )
        ])
        let linkageWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(linkageTransport),
            uploadService: UploadService()
        )
        let linkage = try await linkageWorker.handleTool(CallTool.Parameters(
            name: "promoted_reorder",
            arguments: [
                "app_id": .string("app-1"),
                "promoted_purchase_ids": .array([.string("promoted-1")])
            ]
        ))
        #expect(linkage.isError != true)
        #expect(await linkageTransport.requestCount() == 1)
    }

    @Test("list response next links stay scoped and advance the cursor")
    func listValidatesResponseNextScope() async throws {
        let collectionPath = "/v1/apps/app-1/promotedPurchases"
        let validNext = "https://api.example.test\(collectionPath)?limit=25&cursor=next"
        let invalidCases: [([String: Value], String)] = [
            (
                ["app_id": .string("app-1"), "limit": .int(25)],
                promotedV319ListPage(
                    nextURL: "https://evil.example.test\(collectionPath)?limit=25&cursor=next"
                )
            ),
            (
                ["app_id": .string("app-1"), "limit": .int(25)],
                promotedV319ListPage(
                    nextURL: "https://api.example.test/v1/apps/app-2/promotedPurchases?limit=25&cursor=next"
                )
            ),
            (
                [
                    "app_id": .string("app-1"),
                    "limit": .int(25),
                    "next_url": .string(
                        "https://api.example.test\(collectionPath)?limit=25&cursor=current"
                    )
                ],
                promotedV319ListPage(
                    cursor: "current",
                    nextURL: "https://api.example.test\(collectionPath)?limit=25&cursor=current"
                )
            )
        ]

        for (arguments, body) in invalidCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = PromotedPurchasesWorker(
                httpClient: try await promotedV319Client(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "promoted_list",
                arguments: arguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }

        let validTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: promotedV319ListPage(
                    nextURL: validNext,
                    meta: #"{"paging":{"total":1,"limit":25,"nextCursor":"next"}}"#
                )
            )
        ])
        let validWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(validTransport),
            uploadService: UploadService()
        )
        let valid = try await validWorker.handleTool(CallTool.Parameters(
            name: "promoted_list",
            arguments: ["app_id": .string("app-1"), "limit": .int(25)]
        ))
        #expect(valid.isError != true)
        #expect(try promotedV319Object(valid.structuredContent)["next_url"] == .string(validNext))
    }

    @Test("list response enforces requested limit and paging metadata consistency")
    func listValidatesResponsePagingMetadata() async throws {
        let collectionPath = "/v1/apps/app-1/promotedPurchases"
        let validNext = "https://api.example.test\(collectionPath)?limit=25&cursor=next"
        let invalidCases: [(Int, String)] = [
            (
                1,
                promotedV319ListPage(ids: ["promoted-1", "promoted-2"], limit: 1)
            ),
            (25, promotedV319ListPage(meta: #"{}"#)),
            (
                25,
                promotedV319ListPage(meta: #"{"paging":{"total":0,"limit":24}}"#)
            ),
            (
                25,
                promotedV319ListPage(
                    ids: ["promoted-1"],
                    meta: #"{"paging":{"total":0,"limit":25}}"#
                )
            ),
            (
                25,
                promotedV319ListPage(
                    meta: #"{"paging":{"total":0,"limit":25,"nextCursor":"orphan"}}"#
                )
            ),
            (
                25,
                promotedV319ListPage(
                    nextURL: validNext,
                    meta: #"{"paging":{"total":1,"limit":25}}"#
                )
            ),
            (
                25,
                promotedV319ListPage(
                    nextURL: validNext,
                    meta: #"{"paging":{"total":1,"limit":25,"nextCursor":"other"}}"#
                )
            )
        ]

        for (limit, body) in invalidCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = PromotedPurchasesWorker(
                httpClient: try await promotedV319Client(transport),
                uploadService: UploadService()
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "promoted_list",
                arguments: ["app_id": .string("app-1"), "limit": .int(limit)]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("writes reject missing primary linkage and present-null response Booleans")
    func writesRejectMalformedAcceptedDocuments() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1"},"included":[{"type":"inAppPurchases","id":"iap-1"}],"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1"}}"#
            )
        ])
        let createWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(createTransport),
            uploadService: UploadService()
        )
        let create = try await createWorker.handleTool(CallTool.Parameters(
            name: "promoted_create",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .bool(true),
                "iap_id": .string("iap-1")
            ]
        ))
        #expect(create.isError == true)
        #expect(try promotedV319Object(create.structuredContent)["operationCommitState"] == .string("committed_unverified"))

        let updateTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"promotedPurchases","id":"promoted-1","attributes":{"enabled":null}},"links":{"self":"https://api.example.test/v1/promotedPurchases/promoted-1"}}"#
            )
        ])
        let updateWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(updateTransport),
            uploadService: UploadService()
        )
        let update = try await updateWorker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "enabled": .null
            ]
        ))
        #expect(update.isError == true)
        #expect(try promotedV319Object(update.structuredContent)["operationCommitState"] == .string("committed_unverified"))
    }

    @Test("mutation transport ambiguity and definitive rejection remain distinct")
    func mutationFailuresHaveStructuredRecovery() async throws {
        let unknownTransport = TestHTTPTransport(responses: [])
        let unknownWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(unknownTransport),
            uploadService: UploadService()
        )
        let unknown = try await unknownWorker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "visible": .bool(false)
            ]
        ))
        #expect(unknown.isError == true)
        let unknownRoot = try promotedV319Object(unknown.structuredContent)
        #expect(unknownRoot["operationCommitState"] == .string("unknown"))
        #expect(unknownRoot["outcomeUnknown"] == .bool(true))

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 422,
                body: #"{"errors":[{"status":"422","detail":"rejected"}]}"#
            )
        ])
        let rejectedWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(rejectedTransport),
            uploadService: UploadService()
        )
        let rejected = try await rejectedWorker.handleTool(CallTool.Parameters(
            name: "promoted_update",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "visible": .bool(false)
            ]
        ))
        #expect(rejected.isError == true)
        let rejectedRoot = try promotedV319Object(rejected.structuredContent)
        #expect(rejectedRoot["operationCommitState"] == .string("rejected"))
        let rejectedDetails = try promotedV319Object(rejectedRoot["details"])
        #expect(rejectedDetails["recovery"] == nil)
    }

    @Test("delete requires exact confirmation and distinguishes 204 from ambiguity")
    func deleteUsesConfirmationAndExactReceipt() async throws {
        let mismatchTransport = TestHTTPTransport(responses: [])
        let mismatchWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(mismatchTransport),
            uploadService: UploadService()
        )
        let mismatch = try await mismatchWorker.handleTool(CallTool.Parameters(
            name: "promoted_delete",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "confirm_promoted_purchase_id": .string("promoted-2")
            ]
        ))
        #expect(mismatch.isError == true)
        #expect(await mismatchTransport.requestCount() == 0)

        let successTransport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: "")
        ])
        let successWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(successTransport),
            uploadService: UploadService()
        )
        let success = try await successWorker.handleTool(CallTool.Parameters(
            name: "promoted_delete",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "confirm_promoted_purchase_id": .string("promoted-1")
            ]
        ))
        #expect(success.isError != true)
        let successRoot = try promotedV319Object(success.structuredContent)
        #expect(successRoot["deletionState"] == .string("confirmed"))
        #expect(successRoot["statusCode"] == .int(204))

        let unverifiedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let unverifiedWorker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(unverifiedTransport),
            uploadService: UploadService()
        )
        let unverified = try await unverifiedWorker.handleTool(CallTool.Parameters(
            name: "promoted_delete",
            arguments: [
                "promoted_purchase_id": .string("promoted-1"),
                "confirm_promoted_purchase_id": .string("promoted-1")
            ]
        ))
        #expect(unverified.isError == true)
        let unverifiedRoot = try promotedV319Object(unverified.structuredContent)
        #expect(unverifiedRoot["deletionState"] == .string("committed_unverified"))
        #expect(unverifiedRoot["inspectionRequired"] == .bool(true))
    }

    @Test("strict active arguments and schema bounds fail before network")
    func strictMutationArgumentsFailPreNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = PromotedPurchasesWorker(
            httpClient: try await promotedV319Client(transport),
            uploadService: UploadService()
        )
        let calls: [CallTool.Parameters] = [
            .init(
                name: "promoted_create",
                arguments: [
                    "app_id": .string("bad/id"),
                    "visible": .bool(true),
                    "iap_id": .string("iap-1")
                ]
            ),
            .init(
                name: "promoted_update",
                arguments: [
                    "promoted_purchase_id": .string("promoted-1"),
                    "enabled": .bool(true),
                    "unknown": .bool(true)
                ]
            ),
            .init(
                name: "promoted_delete",
                arguments: [
                    "promoted_purchase_id": .string("bad%2Fid"),
                    "confirm_promoted_purchase_id": .string("bad%2Fid")
                ]
            ),
            .init(
                name: "promoted_reorder",
                arguments: [
                    "app_id": .string("app-1"),
                    "promoted_purchase_ids": .string("promoted-1,promoted-2")
                ]
            ),
            .init(
                name: "promoted_reorder",
                arguments: [
                    "app_id": .string("app-1"),
                    "promoted_purchase_ids": .array([])
                ]
            ),
            .init(
                name: "promoted_reorder",
                arguments: [
                    "app_id": .string("app-1"),
                    "promoted_purchase_ids": .array((0...200).map {
                        .string("promoted-\($0)")
                    })
                ]
            ),
            .init(
                name: "promoted_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "next_url": .string(
                        "https://api.example.test/v1/apps/app-1/promotedPurchases?limit=25&cursor=bad value"
                    )
                ]
            )
        ]
        for call in calls {
            #expect(try await worker.handleTool(call).isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("operation manifest maps reorder and exact mutation statuses")
    func manifestMapsPinnedOperations() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let reorder = try #require(manifest.mapping(for: "promoted_reorder"))
        #expect(reorder.kind == .compound)
        #expect(Set(reorder.operations.map(\.operationID)) == [
            "apps_promotedPurchases_getToManyRelationship",
            "apps_promotedPurchases_replaceToManyRelationship"
        ])
        #expect(reorder.response.sources.contains {
            $0.operationID == "apps_promotedPurchases_replaceToManyRelationship"
                && $0.statusCode == "204"
        })

        let create = try #require(manifest.mapping(for: "promoted_create"))
        #expect(create.response.sources.map(\.statusCode) == ["201"])
        let update = try #require(manifest.mapping(for: "promoted_update"))
        #expect(update.response.sources.map(\.statusCode) == ["200"])
        let delete = try #require(manifest.mapping(for: "promoted_delete"))
        #expect(delete.response.sources.map(\.statusCode) == ["204"])
        #expect(delete.fields.contains { $0.toolField == "confirm_promoted_purchase_id" })
    }
}

private func promotedV319Client(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func promotedV319ListPage(
    ids: [String] = [],
    limit: Int = 25,
    cursor: String? = nil,
    nextURL: String? = nil,
    meta: String? = nil
) -> String {
    let path = "/v1/apps/app-1/promotedPurchases"
    var selfURL = "https://api.example.test\(path)?limit=\(limit)"
    if let cursor {
        selfURL += "&cursor=\(cursor)"
    }
    let data = ids.map {
        #"{"type":"promotedPurchases","id":"\#($0)"}"#
    }.joined(separator: ",")
    let nextJSON = nextURL.map { #", "next": "\#($0)""# } ?? ""
    let metaJSON = meta.map { #", "meta": \#($0)"# } ?? ""
    return #"{"data":[\#(data)],"links":{"self":"\#(selfURL)"\#(nextJSON)}\#(metaJSON)}"#
}

private func promotedV319LinkagePage(
    ids: [String],
    cursor: String?,
    nextCursor: String?,
    total: Int? = nil,
    host: String? = "api.example.test",
    nextURLOverride: String? = nil,
    pagingLimit: Int = 200,
    includeMeta: Bool = true,
    includeNextCursorMetadata: Bool = true,
    metadataNextCursor: String? = nil
) -> String {
    let path = "/v1/apps/app-1/relationships/promotedPurchases"
    let origin = host.map { "https://\($0)" } ?? ""
    var selfURL = "\(origin)\(path)?limit=200"
    if let cursor {
        selfURL += "&cursor=\(cursor)"
    }
    let nextURL = nextURLOverride ?? nextCursor.map {
        "\(origin)\(path)?limit=200&cursor=\($0)"
    }
    let nextJSON: String
    if let nextURL {
        nextJSON = #", "next": "\#(nextURL)""#
    } else {
        nextJSON = ""
    }
    let data = ids.map {
        #"{"type":"promotedPurchases","id":"\#($0)"}"#
    }.joined(separator: ",")
    let resolvedMetadataCursor = metadataNextCursor ?? nextCursor
    let cursorJSON: String
    if includeNextCursorMetadata, let resolvedMetadataCursor {
        cursorJSON = #", "nextCursor": "\#(resolvedMetadataCursor)""#
    } else {
        cursorJSON = ""
    }
    let metaJSON: String
    if includeMeta {
        metaJSON = #", "meta": {"paging":{"total":\#(total ?? ids.count),"limit":\#(pagingLimit)\#(cursorJSON)}}"#
    } else {
        metaJSON = ""
    }
    return #"{"data":[\#(data)],"links":{"self":"\#(selfURL)"\#(nextJSON)}\#(metaJSON)}"#
}

private func promotedV319Object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object Value")
        throw PromotedV319TestError.invalidValue
    }
    return object
}

private func promotedV319StringSet(_ value: Value?) throws -> Set<String> {
    guard case .array(let values) = value else {
        Issue.record("Expected array Value")
        throw PromotedV319TestError.invalidValue
    }
    return Set(try values.map {
        guard let string = $0.stringValue else {
            throw PromotedV319TestError.invalidValue
        }
        return string
    })
}

private func promotedV319ValueArray(_ value: Value?) throws -> [Value] {
    guard case .array(let values) = value else {
        Issue.record("Expected array Value")
        throw PromotedV319TestError.invalidValue
    }
    return values
}

private func promotedV319JSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        Issue.record("Expected JSON request body")
        throw PromotedV319TestError.invalidValue
    }
    return object
}

private func promotedV319JSONArray(_ value: Any?) throws -> [Any] {
    guard let array = value as? [Any] else {
        Issue.record("Expected JSON array")
        throw PromotedV319TestError.invalidValue
    }
    return array
}

private enum PromotedV319TestError: Error {
    case invalidValue
}
