import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Custom Product Pages v3.19 Contract Tests")
struct CustomPagesV319ContractTests {
    @Test("worker exposes the exact 17-tool Apple 4.4.1 surface with closed schemas")
    func toolSurface() async throws {
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(.init(responses: [])))
        let tools = await worker.getTools()
        let expected: Set<String> = [
            "custom_pages_list",
            "custom_pages_get",
            "custom_pages_create",
            "custom_pages_update",
            "custom_pages_delete",
            "custom_pages_list_versions",
            "custom_pages_get_version",
            "custom_pages_create_version",
            "custom_pages_update_version",
            "custom_pages_list_localizations",
            "custom_pages_get_localization",
            "custom_pages_create_localization",
            "custom_pages_update_localization",
            "custom_pages_delete_localization",
            "custom_pages_list_search_keywords",
            "custom_pages_add_search_keywords",
            "custom_pages_remove_search_keywords"
        ]
        #expect(tools.count == expected.count)
        #expect(Set(tools.map(\.name)) == expected)
        for tool in tools {
            let schema = try cppV319Object(tool.inputSchema)
            #expect(schema["additionalProperties"] == .bool(false))
        }

        let pageDelete = try #require(tools.first { $0.name == "custom_pages_delete" })
        #expect(try cppV319Required(pageDelete) == Set(["page_id", "confirm_page_id"]))
        let pageDeleteSchema = try cppV319Object(pageDelete.inputSchema)
        let pageDeleteProperties = try cppV319Object(pageDeleteSchema["properties"])
        #expect(try cppV319Object(pageDeleteProperties["page_id"])["pattern"] ==
            .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))
        let localizationDelete = try #require(tools.first { $0.name == "custom_pages_delete_localization" })
        #expect(try cppV319Required(localizationDelete) == Set(["localization_id", "confirm_localization_id"]))
        let updateVersion = try #require(tools.first { $0.name == "custom_pages_update_version" })
        #expect(try cppV319Required(updateVersion) == Set(["version_id", "deep_link"]))
        let updatePage = try #require(tools.first { $0.name == "custom_pages_update" })
        let updatePageSchema = try cppV319Object(updatePage.inputSchema)
        #expect(updatePageSchema["minProperties"] == .int(2))
        #expect(updatePageSchema["anyOf"]?.arrayValue?.count == 2)
        let publishedUpdatePageSchema = try cppV319Object(ToolMetadataPolicy.apply(to: updatePage).inputSchema)
        #expect(publishedUpdatePageSchema["minProperties"] == .int(2))
        #expect(publishedUpdatePageSchema["anyOf"] == nil)
        let updateLocalization = try #require(tools.first { $0.name == "custom_pages_update_localization" })
        #expect(try cppV319Required(updateLocalization) == Set(["localization_id", "promotional_text"]))
        let removeKeywords = try #require(tools.first { $0.name == "custom_pages_remove_search_keywords" })
        #expect(try cppV319Required(removeKeywords) == Set([
            "localization_id",
            "keyword_ids",
            "confirm_localization_id"
        ]))
        let addKeywords = try #require(tools.first { $0.name == "custom_pages_add_search_keywords" })
        let additionMetadata = ToolMetadataPolicy.apply(to: addKeywords)
        #expect(additionMetadata.annotations.readOnlyHint == false)
        #expect(additionMetadata.annotations.idempotentHint == false)
        let removalMetadata = ToolMetadataPolicy.apply(to: removeKeywords)
        #expect(removalMetadata.annotations.readOnlyHint == false)
        #expect(removalMetadata.annotations.destructiveHint == true)
        #expect(removalMetadata.annotations.idempotentHint == false)

        let list = try #require(tools.first { $0.name == "custom_pages_list" })
        let listSchema = try cppV319Object(list.inputSchema)
        let listProperties = try cppV319Object(listSchema["properties"])
        #expect(try cppV319Object(listProperties["next_url"])["pattern"] ==
            .string(#"^(?!.*[\s\u0000-\u001F\u007F]).+$"#))
    }

    @Test("manifest maps the complete 17-tool surface and destructive confirmations")
    func manifest() throws {
        let expected: [String: (String, String)] = [
            "custom_pages_create": ("appCustomProductPages_createInstance", "201"),
            "custom_pages_create_localization": ("appCustomProductPageLocalizations_createInstance", "201"),
            "custom_pages_create_version": ("appCustomProductPageVersions_createInstance", "201"),
            "custom_pages_delete": ("appCustomProductPages_deleteInstance", "204"),
            "custom_pages_get": ("appCustomProductPages_getInstance", "200"),
            "custom_pages_list": ("apps_appCustomProductPages_getToManyRelated", "200"),
            "custom_pages_list_localizations": ("appCustomProductPageVersions_appCustomProductPageLocalizations_getToManyRelated", "200"),
            "custom_pages_list_versions": ("appCustomProductPages_appCustomProductPageVersions_getToManyRelated", "200"),
            "custom_pages_update": ("appCustomProductPages_updateInstance", "200"),
            "custom_pages_update_localization": ("appCustomProductPageLocalizations_updateInstance", "200"),
            "custom_pages_get_version": ("appCustomProductPageVersions_getInstance", "200"),
            "custom_pages_update_version": ("appCustomProductPageVersions_updateInstance", "200"),
            "custom_pages_get_localization": ("appCustomProductPageLocalizations_getInstance", "200"),
            "custom_pages_delete_localization": ("appCustomProductPageLocalizations_deleteInstance", "204"),
            "custom_pages_list_search_keywords": ("appCustomProductPageLocalizations_searchKeywords_getToManyRelated", "200"),
            "custom_pages_add_search_keywords": ("appCustomProductPageLocalizations_searchKeywords_createToManyRelationship", "204"),
            "custom_pages_remove_search_keywords": ("appCustomProductPageLocalizations_searchKeywords_deleteToManyRelationship", "204")
        ]
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let allMappings = manifest.tools.filter { $0.tool.hasPrefix("custom_pages_") }
        #expect(allMappings.count == 17)
        #expect(Set(allMappings.map(\.tool)).count == 17)
        #expect(Set(allMappings.map(\.tool)) == Set(expected.keys))
        #expect(allMappings.allSatisfy { !$0.response.fields.isEmpty })
        let mappings = manifest.tools.filter { expected[$0.tool] != nil }
        #expect(mappings.count == expected.count)
        for mapping in mappings {
            let contract = try #require(expected[mapping.tool])
            #expect(mapping.operations.count == 1)
            #expect(mapping.operations.first?.operationID == contract.0)
            #expect(mapping.response.sources.count == 1)
            #expect(mapping.response.sources.first?.statusCode == contract.1)
            #expect(!mapping.response.fields.isEmpty)
        }
        let pageDelete = try #require(manifest.tools.first { $0.tool == "custom_pages_delete" })
        #expect(pageDelete.fields.contains { $0.toolField == "confirm_page_id" && $0.sourceKind == .local })
        let localizationDelete = try #require(manifest.tools.first { $0.tool == "custom_pages_delete_localization" })
        #expect(localizationDelete.fields.contains {
            $0.toolField == "confirm_localization_id" && $0.sourceKind == .local
        })
        let removeKeywords = try #require(manifest.tools.first {
            $0.tool == "custom_pages_remove_search_keywords"
        })
        #expect(removeKeywords.effect == .destructive)
        #expect(removeKeywords.fields.contains {
            $0.toolField == "confirm_localization_id" && $0.sourceKind == .local
        })
        #expect(removeKeywords.response.fields.contains { $0.outputField == "confirmationMatched" })
    }

    @Test("nullable page version and localization updates preserve null and reject no-op input")
    func nullableUpdates() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPages","id":"page-1","attributes":{"name":null,"visible":null}},"links":{"self":"/v1/appCustomProductPages/page-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-1","attributes":{"deepLink":null}},"links":{"self":"/v1/appCustomProductPageVersions/version-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPageLocalizations","id":"localization-1","attributes":{"promotionalText":null}},"links":{"self":"/v1/appCustomProductPageLocalizations/localization-1"}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let page = try await worker.handleTool(.init(
            name: "custom_pages_update",
            arguments: ["page_id": .string("page-1"), "name": .null, "visible": .null]
        ))
        let version = try await worker.handleTool(.init(
            name: "custom_pages_update_version",
            arguments: ["version_id": .string("version-1"), "deep_link": .null]
        ))
        let localization = try await worker.handleTool(.init(
            name: "custom_pages_update_localization",
            arguments: ["localization_id": .string("localization-1"), "promotional_text": .null]
        ))
        #expect(page.isError != true)
        #expect(version.isError != true)
        #expect(localization.isError != true)
        #expect(try cppV319Object(page.structuredContent)["changed"] == .null)
        #expect(try cppV319Object(version.structuredContent)["changed"] == .null)
        #expect(try cppV319Object(localization.structuredContent)["changed"] == .null)
        let requests = await transport.recordedRequests()
        #expect(try cppV319Attributes(requests[0])["name"] is NSNull)
        #expect(try cppV319Attributes(requests[0])["visible"] is NSNull)
        #expect(try cppV319Attributes(requests[1])["deepLink"] is NSNull)
        #expect(try cppV319Attributes(requests[2])["promotionalText"] is NSNull)

        let invalidTransport = TestHTTPTransport(responses: [])
        let invalidWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(invalidTransport))
        let noOp = try await invalidWorker.handleTool(.init(
            name: "custom_pages_update",
            arguments: ["page_id": .string("page-1")]
        ))
        let missingDeepLink = try await invalidWorker.handleTool(.init(
            name: "custom_pages_update_version",
            arguments: ["version_id": .string("version-1")]
        ))
        let wrongType = try await invalidWorker.handleTool(.init(
            name: "custom_pages_update_localization",
            arguments: ["localization_id": .string("localization-1"), "promotional_text": .int(4)]
        ))
        let unknown = try await invalidWorker.handleTool(.init(
            name: "custom_pages_get_version",
            arguments: ["version_id": .string("version-1"), "unknown": .bool(true)]
        ))
        #expect(noOp.isError == true)
        #expect(missingDeepLink.isError == true)
        #expect(wrongType.isError == true)
        #expect(unknown.isError == true)
        #expect(await invalidTransport.requestCount() == 0)
    }

    @Test("create forwards both independent Apple template relationships")
    func createWithBothTemplates() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"appCustomProductPages","id":"page-1","attributes":{"name":"Campaign"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}},"links":{"self":"/v1/appCustomProductPages/page-1"}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "custom_pages_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Campaign"),
                "locale": .string("en-US"),
                "template_version_id": .string("version-template-1"),
                "template_page_id": .string("page-template-1")
            ]
        ))
        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let data = try #require(cppV319Body(request)["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let versionTemplate = try #require(
            relationships["appStoreVersionTemplate"] as? [String: Any]
        )
        let versionIdentifier = try #require(versionTemplate["data"] as? [String: Any])
        #expect(versionIdentifier["type"] as? String == "appStoreVersions")
        #expect(versionIdentifier["id"] as? String == "version-template-1")
        let pageTemplate = try #require(
            relationships["customProductPageTemplate"] as? [String: Any]
        )
        let pageIdentifier = try #require(pageTemplate["data"] as? [String: Any])
        #expect(pageIdentifier["type"] as? String == "appCustomProductPages")
        #expect(pageIdentifier["id"] as? String == "page-template-1")
        #expect(await transport.requestCount() == 1)
    }

    @Test("get operations enforce canonical response identity")
    func getIdentity() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-1","attributes":{"state":"APPROVED","deepLink":"ascmcp://campaign"}},"links":{"self":"/v1/appCustomProductPageVersions/version-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPageLocalizations","id":"localization-other","attributes":{"locale":"en-US"}},"links":{"self":"/v1/appCustomProductPageLocalizations/localization-other"}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let version = try await worker.handleTool(.init(
            name: "custom_pages_get_version",
            arguments: ["version_id": .string("version-1")]
        ))
        let wrongLocalization = try await worker.handleTool(.init(
            name: "custom_pages_get_localization",
            arguments: ["localization_id": .string("localization-1")]
        ))
        #expect(version.isError != true)
        #expect(wrongLocalization.isError == true)

        let invalidTransport = TestHTTPTransport(responses: [])
        let invalidWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(invalidTransport))
        for identifier in ["", ".", "..", "bad/id", "bad%2Fid", " spaced "] {
            let result = try await invalidWorker.handleTool(.init(
                name: "custom_pages_get_version",
                arguments: ["version_id": .string(identifier)]
            ))
            #expect(result.isError == true)
        }
        #expect(await invalidTransport.requestCount() == 0)
    }

    @Test("single and collection responses require document links and validate returned lineage")
    func requiredLinksAndLineage() async throws {
        let missingLinksTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appCustomProductPages","id":"page-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appCustomProductPageLocalizations","id":"localization-1"}}"#),
            .init(statusCode: 200, body: #"{"data":[]}"#),
            .init(statusCode: 200, body: #"{"data":[]}"#),
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let missingLinksWorker = CustomProductPagesWorker(
            httpClient: try await cppV319Client(missingLinksTransport)
        )
        let missingLinksCalls: [(String, [String: Value])] = [
            ("custom_pages_get", ["page_id": .string("page-1")]),
            ("custom_pages_get_version", ["version_id": .string("version-1")]),
            ("custom_pages_get_localization", ["localization_id": .string("localization-1")]),
            ("custom_pages_list", ["app_id": .string("app-1")]),
            ("custom_pages_list_versions", ["page_id": .string("page-1")]),
            ("custom_pages_list_localizations", ["version_id": .string("version-1")])
        ]
        for (name, arguments) in missingLinksCalls {
            let result = try await missingLinksWorker.handleTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true)
        }
        #expect(await missingLinksTransport.requestCount() == missingLinksCalls.count)

        let lineageTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"appCustomProductPages","id":"page-1","relationships":{"app":{"data":{"type":"apps","id":"app-2"}}}}],"links":{"self":"/v1/apps/app-1/appCustomProductPages"},"meta":{"paging":{"limit":25,"total":1}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"appCustomProductPageVersions","id":"version-1","relationships":{"appCustomProductPage":{"data":{"type":"appCustomProductPages","id":"page-2"}}}}],"links":{"self":"/v1/appCustomProductPages/page-1/appCustomProductPageVersions"},"meta":{"paging":{"limit":25,"total":1}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"appCustomProductPageLocalizations","id":"localization-1","relationships":{"appCustomProductPageVersion":{"data":{"type":"appCustomProductPageVersions","id":"version-2"}}}}],"links":{"self":"/v1/appCustomProductPageVersions/version-1/appCustomProductPageLocalizations"},"meta":{"paging":{"limit":25,"total":1}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-1","relationships":{"appCustomProductPage":{"data":{"type":"apps","id":"page-1"}}}},"links":{"self":"/v1/appCustomProductPageVersions/version-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPages","id":"page-1","links":{"self":"/v1/appCustomProductPages/page-2"}},"links":{"self":"/v1/appCustomProductPages/page-1"}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":{"type":"appCustomProductPages","id":"page-1"},"links":{"self":"https://foreign.example/v1/appCustomProductPages/page-1"}}"#
            )
        ])
        let lineageWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(lineageTransport))
        let lineageCalls: [(String, [String: Value])] = [
            ("custom_pages_list", ["app_id": .string("app-1")]),
            ("custom_pages_list_versions", ["page_id": .string("page-1")]),
            ("custom_pages_list_localizations", ["version_id": .string("version-1")]),
            ("custom_pages_get_version", ["version_id": .string("version-1")]),
            ("custom_pages_get", ["page_id": .string("page-1")]),
            ("custom_pages_get", ["page_id": .string("page-1")])
        ]
        for (name, arguments) in lineageCalls {
            let result = try await lineageWorker.handleTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true)
        }
        #expect(await lineageTransport.requestCount() == lineageCalls.count)
    }

    @Test("returned continuation links preserve the exact originating collection scope")
    func returnedContinuationScope() async throws {
        let path = "/v1/apps/app-1/appCustomProductPages"
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: """
                {"data":[],"links":{"self":"\(path)","next":"\(path)?filter%5Bvisible%5D=false&limit=25&cursor=next"},"meta":{"paging":{"limit":25,"total":1,"nextCursor":"next"}}}
                """
            ),
            .init(
                statusCode: 200,
                body: """
                {"data":[],"links":{"self":"\(path)","next":"/v1/apps/app-2/appCustomProductPages?filter%5Bvisible%5D=true&limit=25&cursor=next"},"meta":{"paging":{"limit":25,"total":1,"nextCursor":"next"}}}
                """
            ),
            .init(
                statusCode: 200,
                body: """
                {"data":[],"links":{"self":"\(path)","next":"\(path)?filter%5Bvisible%5D=true&limit=25&cursor=next"},"meta":{"paging":{"limit":25,"total":1,"nextCursor":"different"}}}
                """
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        for _ in 0..<3 {
            let result = try await worker.handleTool(.init(
                name: "custom_pages_list",
                arguments: ["app_id": .string("app-1"), "visible": .bool(true)]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 3)
    }

    @Test("write recovery preserves action and requested nullable template identities")
    func writeRecoveryRequestedValues() async throws {
        let templateVersionID = "template-version-id-0123456789"
        let templatePageID = "template-page-id-0123456789"
        let transport = TestHTTPTransport(responses: [])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "custom_pages_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Campaign"),
                "locale": .string("en-US"),
                "promotional_text": .null,
                "template_version_id": .string(templateVersionID),
                "template_page_id": .string(templatePageID)
            ]
        ))
        let root = try cppV319Object(result.structuredContent)
        let requested = try cppV319Object(root["requested"])
        #expect(result.isError == true)
        #expect(root["action"] == .string("create_page"))
        #expect(try cppV319Object(root["recovery"])["action"] == .string("inspect_before_retry"))
        #expect(try cppV319Object(requested["name"])["value"] == .string("Campaign"))
        #expect(try cppV319Object(requested["locale"])["value"] == .string("en-US"))
        let promotionalText = try cppV319Object(requested["promotionalText"])
        #expect(promotionalText["state"] == .string("null"))
        #expect(promotionalText["value"] == .null)
        let templateVersion = try cppV319Object(requested["templateVersionId"])
        #expect(templateVersion["state"] == .string("value"))
        #expect(templateVersion["value"] == .string(templateVersionID))
        let templatePage = try cppV319Object(requested["templatePageId"])
        #expect(templatePage["state"] == .string("value"))
        #expect(templatePage["value"] == .string(templatePageID))
    }

    @Test("deterministic create rejection preserves corrective recovery action")
    func deterministicCreateRejectionRecoveryAction() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 422,
                body: #"{"errors":[{"status":"422","code":"ENTITY_ERROR","title":"Rejected"}]}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "custom_pages_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Campaign"),
                "locale": .string("en-US")
            ]
        ))
        let root = try cppV319Object(result.structuredContent)
        let recovery = try cppV319Object(root["recovery"])
        #expect(result.isError == true)
        #expect(root["operationCommitState"] == .string("rejected"))
        #expect(root["retrySafe"] == .bool(true))
        #expect(recovery["action"] == .string("correct_request_before_retry"))
    }

    @Test("remove keyword failure preserves operation and inspection action")
    func removeKeywordRecoveryConstants() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let result = try await worker.handleTool(.init(
            name: "custom_pages_remove_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "keyword_ids": .array([.string("keyword-1")]),
                "confirm_localization_id": .string("localization-1")
            ]
        ))
        let root = try cppV319Object(result.structuredContent)
        let recovery = try cppV319Object(root["recovery"])
        #expect(result.isError == true)
        #expect(root["operation"] == .string("remove_search_keywords"))
        #expect(root["action"] == .string("remove_search_keywords"))
        #expect(recovery["action"] == .string("inspect_before_retry"))
    }

    @Test("search keyword list maps filters and locks pagination scope")
    func searchKeywordList() async throws {
        let path = "/v1/appCustomProductPageLocalizations/localization-1/searchKeywords"
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: """
                {"data":[{"type":"appKeywords","id":"keyword-1"}],"links":{"self":"\(path)","next":"\(path)?filter%5Bplatform%5D=IOS&filter%5Blocale%5D=en-US&limit=37&cursor=next"},"meta":{"paging":{"limit":37,"total":2,"nextCursor":"next"}}}
                """
            ),
            .init(
                statusCode: 200,
                body: """
                {"data":[{"type":"appKeywords","id":"keyword-2"}],"links":{"self":"\(path)?filter%5Bplatform%5D=IOS&filter%5Blocale%5D=en-US&limit=37&cursor=next"},"meta":{"paging":{"limit":37,"total":2}}}
                """
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let first = try await worker.handleTool(.init(
            name: "custom_pages_list_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "platform": .string("IOS"),
                "locale": .array([.string("en-US")]),
                "limit": .int(37)
            ]
        ))
        let firstRoot = try cppV319Object(first.structuredContent)
        let nextURL = try #require(firstRoot["next_url"]?.stringValue)
        let second = try await worker.handleTool(.init(
            name: "custom_pages_list_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "platform": .string("IOS"),
                "locale": .string("en-US"),
                "limit": .int(37),
                "next_url": .string(nextURL)
            ]
        ))
        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(cppV319Query(requests[0])["filter[platform]"] == "IOS")
        #expect(cppV319Query(requests[0])["filter[locale]"] == "en-US")
        #expect(cppV319Query(requests[0])["limit"] == "37")
        #expect(cppV319Query(requests[1])["cursor"] == "next")

        let invalid = try await worker.handleTool(.init(
            name: "custom_pages_list_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "platform": .string("MAC_OS"),
                "locale": .string("en-US"),
                "limit": .int(37),
                "next_url": .string(nextURL)
            ]
        ))
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 2)
    }

    @Test("keyword relationship writes use exact linkage bodies and reject unsafe IDs")
    func keywordMutations() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: ""),
            .init(statusCode: 204, body: "")
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppV319Client(transport))
        let arguments: [String: Value] = [
            "localization_id": .string("localization-1"),
            "keyword_ids": .array([.string("keyword-1"), .string("keyword-2")])
        ]
        let added = try await worker.handleTool(.init(name: "custom_pages_add_search_keywords", arguments: arguments))
        var removeArguments = arguments
        removeArguments["confirm_localization_id"] = .string("localization-1")
        let removed = try await worker.handleTool(.init(
            name: "custom_pages_remove_search_keywords",
            arguments: removeArguments
        ))
        #expect(added.isError != true)
        #expect(removed.isError != true)
        #expect(try cppV319Object(added.structuredContent)["changed"] == .null)
        let removedRoot = try cppV319Object(removed.structuredContent)
        #expect(removedRoot["changed"] == .null)
        #expect(removedRoot["confirmationMatched"] == .bool(true))
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
        for request in requests {
            let data = try #require(cppV319Body(request)["data"] as? [[String: Any]])
            #expect(data.map { $0["type"] as? String } == ["appKeywords", "appKeywords"])
            #expect(data.map { $0["id"] as? String } == ["keyword-1", "keyword-2"])
        }

        let invalidTransport = TestHTTPTransport(responses: [])
        let invalidWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(invalidTransport))
        for keywordIDs in [
            Value.array([]),
            .array([.string("keyword-1"), .string("keyword-1")]),
            .array([.string("bad/id")]),
            .array([.int(1)])
        ] {
            let result = try await invalidWorker.handleTool(.init(
                name: "custom_pages_add_search_keywords",
                arguments: ["localization_id": .string("localization-1"), "keyword_ids": keywordIDs]
            ))
            #expect(result.isError == true)
        }
        let missingConfirmation = try await invalidWorker.handleTool(.init(
            name: "custom_pages_remove_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "keyword_ids": .array([.string("keyword-1")])
            ]
        ))
        let mismatchedConfirmation = try await invalidWorker.handleTool(.init(
            name: "custom_pages_remove_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "keyword_ids": .array([.string("keyword-1")]),
                "confirm_localization_id": .string("localization-2")
            ]
        ))
        #expect(missingConfirmation.isError == true)
        #expect(mismatchedConfirmation.isError == true)
        #expect(await invalidTransport.requestCount() == 0)
    }

    @Test("destructive confirmations and exact status recovery fail closed")
    func destructiveRecovery() async throws {
        let mismatchTransport = TestHTTPTransport(responses: [])
        let mismatchWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(mismatchTransport))
        let mismatch = try await mismatchWorker.handleTool(.init(
            name: "custom_pages_delete",
            arguments: ["page_id": .string("page-1"), "confirm_page_id": .string("page-2")]
        ))
        #expect(mismatch.isError == true)
        #expect(await mismatchTransport.requestCount() == 0)

        let acceptedTransport = TestHTTPTransport(responses: [.init(statusCode: 202, body: "")])
        let acceptedWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(acceptedTransport))
        let accepted = try await acceptedWorker.handleTool(.init(
            name: "custom_pages_delete",
            arguments: ["page_id": .string("page-1"), "confirm_page_id": .string("page-1")]
        ))
        let acceptedRoot = try cppV319Object(accepted.structuredContent)
        #expect(accepted.isError == true)
        #expect(acceptedRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(acceptedRoot["operationCommitted"] == .bool(true))

        let unknownTransport = TestHTTPTransport(responses: [])
        let unknownWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(unknownTransport))
        let unknown = try await unknownWorker.handleTool(.init(
            name: "custom_pages_remove_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "keyword_ids": .array([.string("keyword-1")]),
                "confirm_localization_id": .string("localization-1")
            ]
        ))
        let unknownRoot = try cppV319Object(unknown.structuredContent)
        #expect(unknown.isError == true)
        #expect(unknownRoot["operationCommitState"] == .string("unknown"))
        #expect(unknownRoot["operationCommitted"] == .null)
        #expect(unknownRoot["retrySafe"] == .bool(false))

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 422, body: #"{"errors":[{"status":"422","code":"ENTITY_ERROR","title":"Rejected"}]}"#)
        ])
        let rejectedWorker = CustomProductPagesWorker(httpClient: try await cppV319Client(rejectedTransport))
        let rejected = try await rejectedWorker.handleTool(.init(
            name: "custom_pages_add_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "keyword_ids": .array([.string("keyword-1")])
            ]
        ))
        let rejectedRoot = try cppV319Object(rejected.structuredContent)
        #expect(rejected.isError == true)
        #expect(rejectedRoot["operationCommitState"] == .string("rejected"))
        #expect(rejectedRoot["operationCommitted"] == .bool(false))
        #expect(rejectedRoot["retrySafe"] == .bool(true))
    }
}

private func cppV319Client(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func cppV319Object(_ value: Value?) throws -> [String: Value] {
    try #require(value?.objectValue)
}

private func cppV319Required(_ tool: Tool) throws -> Set<String> {
    let schema = try cppV319Object(tool.inputSchema)
    let values = try #require(schema["required"]?.arrayValue)
    return Set(try values.map { try #require($0.stringValue) })
}

private func cppV319Body(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func cppV319Attributes(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(try cppV319Body(request)["data"] as? [String: Any])
    return try #require(data["attributes"] as? [String: Any])
}

private func cppV319Query(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).compactMap { item in
        guard let value = item.value else { return nil }
        return (item.name, value)
    })
}
