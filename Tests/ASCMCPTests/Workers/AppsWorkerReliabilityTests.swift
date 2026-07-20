import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("AppsWorker Reliability Tests")
struct AppsWorkerReliabilityTests {
    @Test("apps list schema and runtime use the documented default")
    func appsListUsesDocumentedDefault() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appsCollectionPage(next: nil))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)
        let tool = try #require(await worker.getTools().first { $0.name == "apps_list" })
        let properties = try appsReliabilityProperties(tool)

        #expect(properties["limit"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(properties["limit"]?.objectValue?["maximum"]?.intValue == 200)
        #expect(properties["limit"]?.objectValue?["default"]?.intValue == 25)
        #expect(properties["sort"]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue) == [
            "name", "-name", "bundleId", "-bundleId", "sku", "-sku"
        ])

        let result = try await worker.handleTool(.init(name: "apps_list", arguments: [:]))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(appsReliabilityQueryValue(request, "limit") == "25")
    }

    @Test("apps list pagination preserves clamped limit sort and filters")
    func appsListPaginationPreservesControls() async throws {
        let nextURL = "https://api.example.test/v1/apps?cursor=next&limit=200&sort=-name&filter%5BbundleId%5D=com.example.app"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appsCollectionPage(next: nextURL)),
            .init(statusCode: 200, body: appsCollectionPage(next: nil))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)
        let arguments: [String: Value] = [
            "limit": .int(500),
            "sort": .string("-name"),
            "bundle_id": .string("com.example.app")
        ]

        let first = try await worker.handleTool(.init(name: "apps_list", arguments: arguments))
        var continuationArguments = arguments
        continuationArguments["next_url"] = .string(nextURL)
        let second = try await worker.handleTool(.init(name: "apps_list", arguments: continuationArguments))

        #expect(first.isError != true)
        #expect(second.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            #expect(appsReliabilityQueryValue(request, "limit") == "200")
            #expect(appsReliabilityQueryValue(request, "sort") == "-name")
            #expect(appsReliabilityQueryValue(request, "filter[bundleId]") == "com.example.app")
        }
    }

    @Test("apps list pagination rejects changed ordering or default page size")
    func appsListPaginationRejectsControlDrift() async throws {
        let cases: [([String: Value], String)] = [
            (
                ["limit": .int(500), "sort": .string("-name")],
                "https://api.example.test/v1/apps?cursor=next&limit=200"
            ),
            (
                [:],
                "https://api.example.test/v1/apps?cursor=next&limit=200"
            )
        ]

        for (arguments, nextURL) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeAppsReliabilityWorker(transport)
            var continuationArguments = arguments
            continuationArguments["next_url"] = .string(nextURL)

            let result = try await worker.handleTool(.init(name: "apps_list", arguments: continuationArguments))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("manifest records fixed query controls used by Apps flows")
    func manifestRecordsFixedQueries() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()

        #expect(try appsReliabilityFixedQueries(manifest, "apps_get_metadata", "appStoreVersions_getInstance")["fields[appStoreVersions]"] == .array([
            .string("app"), .string("platform"), .string("versionString"), .string("appVersionState"), .string("appStoreState")
        ]))
        let versionCollection = try appsReliabilityFixedQueries(manifest, "apps_get_metadata", "apps_appStoreVersions_getToManyRelated")
        #expect(versionCollection["fields[appStoreVersions]"] == .array([
            .string("platform"), .string("versionString"), .string("appVersionState"), .string("appStoreState"), .string("createdDate")
        ]))
        #expect(versionCollection["limit"] == .integer(200))

        let localizations = try appsReliabilityFixedQueries(manifest, "apps_get_metadata", "appStoreVersions_appStoreVersionLocalizations_getToManyRelated")
        #expect(localizations["fields[appStoreVersionLocalizations]"] == .array([
            .string("description"), .string("locale"), .string("keywords"), .string("marketingUrl"),
            .string("promotionalText"), .string("supportUrl"), .string("whatsNew"), .string("appStoreVersion")
        ]))
        #expect(localizations["limit"] == .integer(200))

        let previews = try appsReliabilityFixedQueries(manifest, "apps_get_metadata", "appStoreVersionLocalizations_appPreviewSets_getToManyRelated")
        #expect(previews["include"] == .array([.string("appPreviews")]))
        #expect(previews["limit"] == .integer(200))
        #expect(previews["limit[appPreviews]"] == .integer(50))

        let screenshots = try appsReliabilityFixedQueries(manifest, "apps_get_metadata", "appStoreVersionLocalizations_appScreenshotSets_getToManyRelated")
        #expect(screenshots["include"] == .array([.string("appScreenshots")]))
        #expect(screenshots["limit"] == .integer(200))
        #expect(screenshots["limit[appScreenshots]"] == .integer(50))

        #expect(try appsReliabilityFixedQueries(manifest, "apps_list_versions", "apps_appStoreVersions_getToManyRelated") == versionCollection)
        #expect(try appsReliabilityFixedQueries(manifest, "apps_list_localizations", "appStoreVersions_getInstance")["fields[appStoreVersions]"] == .array([.string("app")]))
        #expect(try appsReliabilityFixedQueries(manifest, "apps_list_localizations", "appStoreVersions_appStoreVersionLocalizations_getToManyRelated")["fields[appStoreVersionLocalizations]"] == .array([
            .string("locale"), .string("description"), .string("whatsNew"), .string("keywords"),
            .string("promotionalText"), .string("supportUrl"), .string("marketingUrl"), .string("appStoreVersion")
        ]))
        #expect(try appsReliabilityFixedQueries(manifest, "apps_update_metadata", "appStoreVersions_getInstance")["fields[appStoreVersions]"] == .array([
            .string("app"), .string("platform"), .string("versionString"), .string("appVersionState"), .string("appStoreState")
        ]))
        #expect(try appsReliabilityFixedQueries(manifest, "apps_update_metadata", "appStoreVersions_appStoreVersionLocalizations_getToManyRelated")["fields[appStoreVersionLocalizations]"] == .array([
            .string("locale"), .string("appStoreVersion")
        ]))
    }

    @Test("app details preserve included resources and relationship cardinality")
    func appDetailsPreserveIncludedAndCardinality() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "apps",
                "id": "app-1",
                "attributes": { "name": "Example", "bundleId": "com.example.app", "sku": "EXAMPLE", "primaryLocale": "en-US" },
                "relationships": {
                  "appStoreVersions": { "data": [{ "type": "appStoreVersions", "id": "ver-1" }] },
                  "betaLicenseAgreement": { "data": { "type": "betaLicenseAgreements", "id": "license-1" } },
                  "appStoreIcon": { "data": null },
                  "webhooks": { "data": [{ "type": "webhooks", "id": "webhook-1" }] }
                }
              },
              "included": [{ "type": "appStoreVersions", "id": "ver-1", "attributes": { "appVersionState": "READY_FOR_REVIEW" } }],
              "links": { "self": "https://api.example.test/v1/apps/app-1" }
            }
            """)
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_details",
            arguments: ["app_id": .string("app-1"), "include": .string("appStoreVersions,betaLicenseAgreement")]
        ))

        #expect(result.isError != true)
        let payload = try appsReliabilityObject(result)
        let app = try #require(payload["app"] as? [String: Any])
        let relationships = try #require(app["relationships"] as? [String: Any])
        let versions = try #require(relationships["appStoreVersions"] as? [String: Any])
        let license = try #require(relationships["betaLicenseAgreement"] as? [String: Any])
        let icon = try #require(relationships["appStoreIcon"] as? [String: Any])
        let webhooks = try #require(relationships["webhooks"] as? [String: Any])
        #expect(versions["data"] is [[String: Any]])
        #expect(license["data"] is [String: Any])
        #expect(icon["data"] is NSNull)
        #expect(webhooks["data"] is [[String: Any]])
        #expect((payload["included"] as? [[String: Any]])?.first?["id"] as? String == "ver-1")
    }

    @Test("version and localization lists request current ownership fields")
    func listToolsUseCurrentFixedFields() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsPage(
                versions: [version(id: "ver-1", appVersionState: "READY_FOR_DISTRIBUTION", appStoreState: "READY_FOR_SALE", platform: "IOS")],
                next: nil
            )),
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1"))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let versionsResult = try await worker.handleTool(.init(
            name: "apps_list_versions",
            arguments: ["app_id": .string("app-1")]
        ))
        let localizationsResult = try await worker.handleTool(.init(
            name: "apps_list_localizations",
            arguments: ["app_id": .string("app-1"), "version_id": .string("ver-1")]
        ))

        #expect(versionsResult.isError != true)
        #expect(localizationsResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 3)
        #expect(appsReliabilityQueryValue(requests[0], "fields[appStoreVersions]") == "platform,versionString,appVersionState,appStoreState,createdDate")
        #expect(appsReliabilityQueryValue(requests[0], "limit") == "200")
        #expect(appsReliabilityQueryValue(requests[1], "fields[appStoreVersions]") == "app")
        #expect(appsReliabilityQueryValue(requests[2], "fields[appStoreVersionLocalizations]") == "locale,description,whatsNew,keywords,promotionalText,supportUrl,marketingUrl,appStoreVersion")
    }

    @Test("version list pagination rejects a changed fixed projection")
    func versionListPaginationRequiresFixedProjection() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_list_versions",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string("https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&limit=200")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("version list pagination rejects missing or changed fixed limit")
    func versionListPaginationRequiresFixedLimit() async throws {
        let projection = "platform%2CversionString%2CappVersionState%2CappStoreState%2CcreatedDate"
        let nextURLs = [
            "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&fields%5BappStoreVersions%5D=\(projection)",
            "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&fields%5BappStoreVersions%5D=\(projection)&limit=199"
        ]

        for nextURL in nextURLs {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeAppsReliabilityWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "apps_list_versions",
                arguments: [
                    "app_id": .string("app-1"),
                    "next_url": .string(nextURL)
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("localization pagination rejects a missing ownership projection")
    func localizationPaginationRequiresOwnershipProjection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1"))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_list_localizations",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "next_url": .string("https://api.example.test/v1/appStoreVersions/ver-1/appStoreVersionLocalizations?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("metadata selection follows all pages and prefers appVersionState")
    func metadataSelectionUsesCurrentStateAcrossPages() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsPage(
                versions: [version(id: "legacy", appVersionState: nil, appStoreState: "REJECTED", platform: "IOS")],
                next: "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=page-2&fields%5BappStoreVersions%5D=platform%2CversionString%2CappVersionState%2CappStoreState%2CcreatedDate&limit=200"
            )),
            .init(statusCode: 200, body: versionsPage(
                versions: [version(id: "current", appVersionState: "PREPARE_FOR_SUBMISSION", appStoreState: "READY_FOR_SALE", platform: "MAC_OS")],
                next: nil
            )),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "current"))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: ["app_id": .string("app-1"), "locale": .string("en-US")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 3)
        let query = URLComponents(url: try #require(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first(where: { $0.name == "limit" })?.value == "200")
        #expect(query.first(where: { $0.name == "fields[appStoreVersions]" })?.value?.contains("appVersionState") == true)
        #expect(appsReliabilityQueryValue(requests[2], "fields[appStoreVersionLocalizations]") == "description,locale,keywords,marketingUrl,promotionalText,supportUrl,whatsNew,appStoreVersion")
        #expect(appsReliabilityQueryValue(requests[2], "limit") == "200")
        let payload = try appsReliabilityObject(result)
        let selected = try #require(payload["version"] as? [String: Any])
        #expect(selected["id"] as? String == "current")
        #expect(selected["appVersionState"] as? String == "PREPARE_FOR_SUBMISSION")
        #expect(selected["appStoreState"] as? String == "READY_FOR_SALE")
    }

    @Test("metadata selection returns a canonical structured error when the app has no versions")
    func metadataSelectionWithoutVersionsReturnsCanonicalError() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsPage(versions: [], next: nil))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError == true)
        guard case .object(let payload)? = result.structuredContent,
              case .text(let humanText, _, _) = result.content.first,
              case .text(let mirror, _, _) = result.content.last else {
            Issue.record("Expected canonical structured metadata error")
            return
        }
        #expect(humanText == "Error: App app-1 has no versions")
        #expect(payload["success"] == .bool(false))
        #expect(payload["error"] == .string("App app-1 has no versions"))
        #expect(payload["details"] == .null)
        #expect(mirror == (try MCPValue.compactJSONString(from: .object(payload))))
    }

    @Test("metadata state-selection error preserves long App Store states")
    func metadataStateSelectionErrorPreservesLongStates() async throws {
        let requestedState = "WAITING_FOR_EXPORT_COMPLIANCE"
        let availableStates = ["PREPARE_FOR_SUBMISSION", "READY_FOR_DISTRIBUTION"]
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsPage(
                versions: availableStates.enumerated().map { index, state in
                    version(
                        id: "ver-\(index)",
                        appVersionState: state,
                        appStoreState: nil,
                        platform: "IOS"
                    )
                },
                next: nil
            ))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_state": .string(requestedState)
            ]
        ))

        #expect(result.isError == true)
        guard case .object(let payload)? = result.structuredContent,
              case .string(let error)? = payload["error"],
              case .text(let humanText, _, _) = result.content.first else {
            Issue.record("Expected canonical state-selection error")
            return
        }
        #expect(error.contains(requestedState))
        for state in availableStates {
            #expect(error.contains(state))
        }
        #expect(humanText == "Error: \(error)")
        #expect(!error.contains("[REDACTED]"))
    }

    @Test("metadata version pagination rejects missing or changed fixed limit")
    func metadataVersionPaginationRequiresFixedLimit() async throws {
        let projection = "platform%2CversionString%2CappVersionState%2CappStoreState%2CcreatedDate"
        let nextURLs = [
            "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&fields%5BappStoreVersions%5D=\(projection)",
            "https://api.example.test/v1/apps/app-1/appStoreVersions?cursor=next&fields%5BappStoreVersions%5D=\(projection)&limit=199"
        ]

        for nextURL in nextURLs {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: versionsPage(
                    versions: [version(id: "ver-1", appVersionState: "PREPARE_FOR_SUBMISSION", appStoreState: nil, platform: "IOS")],
                    next: nextURL
                ))
            ])
            let worker = try await makeAppsReliabilityWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "apps_get_metadata",
                arguments: ["app_id": .string("app-1"), "locale": .string("en-US")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("metadata selection recognizes the current published state")
    func metadataSelectionRecognizesReadyForDistribution() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionsPage(
                versions: [
                    version(id: "fallback", appVersionState: "WAITING_FOR_REVIEW", appStoreState: nil, platform: "IOS"),
                    version(id: "published", appVersionState: "READY_FOR_DISTRIBUTION", appStoreState: nil, platform: "IOS")
                ],
                next: nil
            )),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "published"))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: ["app_id": .string("app-1"), "locale": .string("en-US")]
        ))

        #expect(result.isError != true)
        let payload = try appsReliabilityObject(result)
        let selected = try #require(payload["version"] as? [String: Any])
        #expect(selected["id"] as? String == "published")
        #expect(selected["appVersionState"] as? String == "READY_FOR_DISTRIBUTION")
    }

    @Test("metadata update validates ownership and sends explicit null")
    func metadataUpdateValidatesOwnershipAndNull() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1")),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersionLocalizations","id":"loc-1","attributes":{"locale":"en-US","marketingUrl":null}}}"#)
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "marketing_url": .null
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().last)
        let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let data = try #require(object["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.count == 1)
        #expect(attributes["marketingUrl"] is NSNull)
        let requests = await transport.recordedRequests()
        #expect(appsReliabilityQueryValue(requests[0], "fields[appStoreVersions]") == "app,platform,versionString,appVersionState,appStoreState")
        #expect(appsReliabilityQueryValue(requests[1], "fields[appStoreVersionLocalizations]") == "locale,appStoreVersion")
    }

    @Test("metadata update rejects app ownership mismatch before localization lookup")
    func metadataUpdateRejectsOwnershipMismatch() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "other-app"))
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_update_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "keywords": .string("example")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("media reads propagate errors")
    func mediaErrorsAreNotSwallowed() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1")),
            .init(statusCode: 422, body: #"{"errors":[{"status":"422","detail":"preview lookup failed"}]}"#)
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "include_media": .bool(true)
            ]
        ))

        #expect(result.isError == true)
        #expect(appsReliabilityText(result).contains("preview lookup failed"))
    }

    @Test("media reads follow pages and use Apple dimensions")
    func mediaReadsFollowPagesAndUseDimensions() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
            .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1")),
            .init(statusCode: 200, body: """
            {
              "data": [{"type":"appPreviewSets","id":"preview-set-1","attributes":{"previewType":"IPHONE_67"},"relationships":{"appPreviews":{"data":[{"type":"appPreviews","id":"preview-1"}]}}}],
              "included": [{"type":"appPreviews","id":"preview-1","attributes":{"fileName":"preview.mov","videoUrl":"https://example.test/preview.mov","previewFrameImage":{"image":{"templateUrl":"https://example.test/{w}x{h}.{f}","width":886,"height":1920},"state":{"state":"COMPLETE"}}}}],
              "links": {"self":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets","next":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets?cursor=2&include=appPreviews&limit=200&limit%5BappPreviews%5D=50"}
            }
            """),
            .init(statusCode: 200, body: #"{"data":[{"type":"appPreviewSets","id":"preview-set-2","attributes":{"previewType":"IPAD_PRO_3GEN_129"}}],"links":{"self":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets?cursor=2"}}"#),
            .init(statusCode: 200, body: """
            {
              "data": [{"type":"appScreenshotSets","id":"screenshot-set-1","attributes":{"screenshotDisplayType":"APP_IPHONE_67"},"relationships":{"appScreenshots":{"data":[{"type":"appScreenshots","id":"shot-1"}]}}}],
              "included": [{"type":"appScreenshots","id":"shot-1","attributes":{"fileName":"screen.png","imageAsset":{"templateUrl":"https://example.test/{w}x{h}.{f}","width":1179,"height":2556}}}],
              "links": {"self":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets","next":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets?cursor=2&include=appScreenshots&limit=200&limit%5BappScreenshots%5D=50"}
            }
            """),
            .init(statusCode: 200, body: #"{"data":[{"type":"appScreenshotSets","id":"screenshot-set-2","attributes":{"screenshotDisplayType":"APP_IPAD_PRO_3GEN_129"}}],"links":{"self":"https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets?cursor=2"}}"#)
        ])
        let worker = try await makeAppsReliabilityWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_get_metadata",
            arguments: [
                "app_id": .string("app-1"),
                "version_id": .string("ver-1"),
                "locale": .string("en-US"),
                "include_media": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 6)
        let requests = await transport.recordedRequests()
        #expect(appsReliabilityQueryValue(requests[2], "include") == "appPreviews")
        #expect(appsReliabilityQueryValue(requests[2], "limit") == "200")
        #expect(appsReliabilityQueryValue(requests[2], "limit[appPreviews]") == "50")
        #expect(appsReliabilityQueryValue(requests[4], "include") == "appScreenshots")
        #expect(appsReliabilityQueryValue(requests[4], "limit") == "200")
        #expect(appsReliabilityQueryValue(requests[4], "limit[appScreenshots]") == "50")
        let payload = try appsReliabilityObject(result)
        let previewSets = try #require(payload["appPreviewSets"] as? [[String: Any]])
        let screenshotSets = try #require(payload["screenshotSets"] as? [[String: Any]])
        #expect(previewSets.count == 2)
        #expect(screenshotSets.count == 2)
        let previews = try #require(previewSets.first?["appPreviews"] as? [[String: Any]])
        let screenshots = try #require(screenshotSets.first?["screenshots"] as? [[String: Any]])
        #expect(previews.first?["width"] as? Int == 886)
        #expect(previews.first?["height"] as? Int == 1920)
        #expect(previews.first?["previewImageUrl"] as? String == "https://example.test/886x1920.png")
        #expect(screenshots.first?["width"] as? Int == 1179)
        #expect(screenshots.first?["height"] as? Int == 2556)
        #expect(screenshots.first?["url"] as? String == "https://example.test/1179x2556.png")
    }

    @Test("preview pagination rejects changed fixed include and limits")
    func previewPaginationRequiresFixedControls() async throws {
        let base = "https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets?cursor=2"
        let invalidNextURLs = [
            "\(base)&limit=200&limit%5BappPreviews%5D=50",
            "\(base)&include=appScreenshots&limit=200&limit%5BappPreviews%5D=50",
            "\(base)&include=appPreviews&limit%5BappPreviews%5D=50",
            "\(base)&include=appPreviews&limit=199&limit%5BappPreviews%5D=50",
            "\(base)&include=appPreviews&limit=200",
            "\(base)&include=appPreviews&limit=200&limit%5BappPreviews%5D=49"
        ]

        for nextURL in invalidNextURLs {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
                .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1")),
                .init(statusCode: 200, body: emptyCollectionPage(
                    selfURL: "https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets",
                    next: nextURL
                ))
            ])
            let worker = try await makeAppsReliabilityWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "apps_get_metadata",
                arguments: metadataMediaArguments()
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 3)
        }
    }

    @Test("screenshot pagination rejects changed fixed include and limits")
    func screenshotPaginationRequiresFixedControls() async throws {
        let base = "https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets?cursor=2"
        let invalidNextURLs = [
            "\(base)&limit=200&limit%5BappScreenshots%5D=50",
            "\(base)&include=appPreviews&limit=200&limit%5BappScreenshots%5D=50",
            "\(base)&include=appScreenshots&limit%5BappScreenshots%5D=50",
            "\(base)&include=appScreenshots&limit=199&limit%5BappScreenshots%5D=50",
            "\(base)&include=appScreenshots&limit=200",
            "\(base)&include=appScreenshots&limit=200&limit%5BappScreenshots%5D=49"
        ]

        for nextURL in invalidNextURLs {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: versionResponse(id: "ver-1", appId: "app-1")),
                .init(statusCode: 200, body: localizationPage(id: "loc-1", versionId: "ver-1")),
                .init(statusCode: 200, body: emptyCollectionPage(
                    selfURL: "https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appPreviewSets",
                    next: nil
                )),
                .init(statusCode: 200, body: emptyCollectionPage(
                    selfURL: "https://api.example.test/v1/appStoreVersionLocalizations/loc-1/appScreenshotSets",
                    next: nextURL
                ))
            ])
            let worker = try await makeAppsReliabilityWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "apps_get_metadata",
                arguments: metadataMediaArguments()
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 4)
        }
    }
}

private func makeAppsReliabilityWorker(_ transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func version(id: String, appVersionState: String?, appStoreState: String?, platform: String) -> String {
    let current = appVersionState.map { #", "appVersionState": "\#($0)""# } ?? ""
    let legacy = appStoreState.map { #", "appStoreState": "\#($0)""# } ?? ""
    return #"{"type":"appStoreVersions","id":"\#(id)","attributes":{"platform":"\#(platform)","versionString":"1.0"\#(current)\#(legacy)}}"#
}

private func versionsPage(versions: [String], next: String?) -> String {
    let nextField = next.map { #", "next": "\#($0)""# } ?? ""
    return #"{"data":[\#(versions.joined(separator: ","))],"links":{"self":"https://api.example.test/v1/apps/app-1/appStoreVersions"\#(nextField)}}"#
}

private func appsCollectionPage(next: String?) -> String {
    let nextField = next.map { #", "next": "\#($0)""# } ?? ""
    return #"{"data":[],"links":{"self":"https://api.example.test/v1/apps"\#(nextField)}}"#
}

private func versionResponse(id: String, appId: String) -> String {
    #"{"data":{"type":"appStoreVersions","id":"\#(id)","attributes":{"platform":"IOS","versionString":"1.0","appVersionState":"PREPARE_FOR_SUBMISSION"},"relationships":{"app":{"data":{"type":"apps","id":"\#(appId)"}}}}}"#
}

private func localizationPage(id: String, versionId: String) -> String {
    #"{"data":[{"type":"appStoreVersionLocalizations","id":"\#(id)","attributes":{"locale":"en-US"},"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"\#(versionId)"}}}}]}"#
}

private func emptyCollectionPage(selfURL: String, next: String?) -> String {
    let nextField = next.map { #", "next": "\#($0)""# } ?? ""
    return #"{"data":[],"links":{"self":"\#(selfURL)"\#(nextField)}}"#
}

private func metadataMediaArguments() -> [String: Value] {
    [
        "app_id": .string("app-1"),
        "version_id": .string("ver-1"),
        "locale": .string("en-US"),
        "include_media": .bool(true)
    ]
}

private func appsReliabilityText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content { return text }
        return nil
    }.joined(separator: "\n")
}

private func appsReliabilityObject(_ result: CallTool.Result) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(appsReliabilityText(result).utf8)) as? [String: Any])
}

private func appsReliabilityQueryValue(_ request: URLRequest, _ name: String) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

private func appsReliabilityProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AppsReliabilityTestError.expectedProperties
    }
    return properties
}

private func appsReliabilityFixedQueries(
    _ manifest: ASCOperationManifestBundle,
    _ tool: String,
    _ operationID: String
) throws -> [String: ASCJSONValue] {
    let mapping = try #require(manifest.mapping(for: tool))
    let operation = try #require(mapping.operations.first { $0.operationID == operationID })
    return Dictionary(uniqueKeysWithValues: (operation.inputs ?? []).compactMap { input in
        guard input.sourceKind == .fixed,
              input.location == "query",
              let appleName = input.appleName,
              let fixedValue = input.fixedValue else {
            return nil
        }
        return (appleName, fixedValue)
    })
}

private enum AppsReliabilityTestError: Error {
    case expectedProperties
}
