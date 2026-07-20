import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("AppLifecycleWorker Apple Contract Tests")
struct AppLifecycleWorkerContractTests {
    @Test("age rating schema exposes the Apple 4.4.1 questionnaire fields")
    func ageRatingSchemaExposesCurrentFields() async throws {
        let worker = try await makeContractWorker(transport: TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first(where: { $0.name == "app_versions_update_age_rating" }))
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let appInfoID)? = properties["app_info_id"],
              case .object(let socialMedia)? = properties["social_media"],
              case .object(let socialMediaAgeRestricted)? = properties["social_media_age_restricted"],
              case .object(let alcohol)? = properties["alcohol_tobacco_or_drug_use"] else {
            Issue.record("Expected age rating schema properties")
            return
        }

        #expect(appInfoID["type"]?.stringValue == "string")
        #expect(schema["anyOf"]?.arrayValue?.count == 2)
        #expect(socialMedia["type"]?.arrayValue?.compactMap(\.stringValue) == ["boolean", "null"])
        #expect(socialMediaAgeRestricted["type"]?.arrayValue?.compactMap(\.stringValue) == ["boolean", "null"])
        let values = alcohol["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(values.contains("INFREQUENT"))
        #expect(values.contains("FREQUENT"))
        #expect(alcohol["enum"]?.arrayValue?.contains(where: { $0.isNull }) == true)
        #expect(tool.description?.contains("legacy compatibility") == true)
    }

    @Test("review detail schema exposes explicit null clearing")
    func reviewDetailSchemaExposesNullClearing() async throws {
        let worker = try await makeContractWorker(transport: TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first(where: { $0.name == "app_versions_set_review_details" }))
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let notes)? = properties["notes"],
              case .object(let demoRequired)? = properties["demo_account_required"] else {
            Issue.record("Expected nullable review detail schema properties")
            return
        }

        #expect(notes["type"]?.arrayValue?.compactMap(\.stringValue) == ["string", "null"])
        #expect(demoRequired["type"]?.arrayValue?.compactMap(\.stringValue) == ["boolean", "null"])
    }

    @Test("get version only sends supported includes and returns included resources")
    func getVersionUsesSupportedIncludes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "appStoreVersions",
                "id": "ver-1",
                "attributes": { "versionString": "4.0" }
              },
              "included": [
                {
                  "type": "builds",
                  "id": "build-1",
                  "attributes": { "version": "42" }
                }
              ]
            }
            """)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_get",
            arguments: ["version_id": .string("ver-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let include = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "include" })?
            .value
        #expect(include == "build,appStoreVersionPhasedRelease")
        #expect(include?.contains("ageRatingDeclaration") == false)
        #expect(include?.contains("appStoreReviewDetail") == false)
        let payload = try contractObject(result.structuredContent)
        let includedValue = try #require(payload["included"])
        guard case .array(let included) = includedValue else {
            Issue.record("Expected included resources")
            return
        }
        #expect(included.count == 1)
    }

    @Test("review details update resolves the related resource and omits unsupported attachment attributes")
    func reviewDetailsUpdateUsesRelatedResource() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreReviewDetails","id":"review-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreReviewDetails","id":"review-1","attributes":{"notes":"Updated"}}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-1"),
                "notes": .string("Updated")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "PATCH"])
        #expect(requests[0].url?.path == "/v1/appStoreVersions/ver-1/appStoreReviewDetail")
        #expect(requests[1].url?.path == "/v1/appStoreReviewDetails/review-1")
        let body = try #require(await transport.recordedBodyStrings().last)
        #expect(body.contains(#""notes":"Updated""#))
        #expect(!body.contains("attachmentAssetId"))
    }

    @Test("review detail update preserves omitted value and explicit null fields")
    func reviewDetailsUpdatePreservesTriStateAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreReviewDetails","id":"review-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreReviewDetails","id":"review-1"}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-1"),
                "contact_first_name": .null,
                "demo_account_required": .null,
                "notes": .string("Keep this note")
            ]
        ))

        #expect(result.isError != true)
        let body = try #require(await transport.recordedBodyStrings().last)
        let bodyObject = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let data = try #require(bodyObject["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.count == 3)
        #expect(attributes["contactFirstName"] is NSNull)
        #expect(attributes["demoAccountRequired"] is NSNull)
        #expect(attributes["notes"] as? String == "Keep this note")
        #expect(attributes["contactLastName"] == nil)
    }

    @Test("invalid review detail attribute types fail before network access")
    func invalidReviewDetailTypeFailsBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-1"),
                "contact_email": .bool(true)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("review details create follows a not found related-resource lookup")
    func reviewDetailsCreateAfterNotFound() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: #"{"errors":[{"status":"404","detail":"No review detail"}]}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appStoreVersions","id":"ver-2","attributes":{"versionString":"4.0"}}}"#),
            .init(statusCode: 201, body: #"{"data":{"type":"appStoreReviewDetails","id":"review-2","attributes":{"contactEmail":"review@example.com"}}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-2"),
                "contact_email": .string("review@example.com"),
                "notes": .null
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "GET", "POST"])
        #expect(requests[0].url?.path == "/v1/appStoreVersions/ver-2/appStoreReviewDetail")
        #expect(requests[1].url?.path == "/v1/appStoreVersions/ver-2")
        #expect(requests[2].url?.path == "/v1/appStoreReviewDetails")
        let body = try #require(await transport.recordedBodyStrings().last)
        let bodyObject = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let data = try #require(bodyObject["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let appStoreVersion = try #require(relationships["appStoreVersion"] as? [String: Any])
        let linkage = try #require(appStoreVersion["data"] as? [String: Any])
        #expect(attributes.count == 2)
        #expect(attributes["contactEmail"] as? String == "review@example.com")
        #expect(attributes["notes"] is NSNull)
        #expect(linkage["id"] as? String == "ver-2")
        #expect(linkage["type"] as? String == "appStoreVersions")
        #expect(!body.contains("attachmentAssetId"))
    }

    @Test("review details lookup errors other than not found never create a resource")
    func reviewDetailsLookupFailureDoesNotCreate() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 403, body: #"{"errors":[{"status":"403","detail":"Forbidden"}]}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-1"),
                "notes": .string("Do not create")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
        #expect(await transport.recordedRequests().first?.httpMethod == "GET")
    }

    @Test("review detail not found never creates for a missing parent version")
    func reviewDetailsNotFoundConfirmsParentVersion() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: #"{"errors":[{"status":"404","detail":"No review detail"}]}"#),
            .init(statusCode: 404, body: #"{"errors":[{"status":"404","detail":"No version"}]}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("missing-version"),
                "notes": .string("Do not create")
            ]
        ))

        #expect(result.isError == true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "GET"])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("legacy review attachment parameter fails before network mutation")
    func reviewAttachmentParameterFailsBeforeNetworkMutation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_set_review_details",
            arguments: [
                "version_id": .string("ver-1"),
                "attachment_file_id": .string("legacy-file")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("direct App Info age rating path preserves explicit null without version lookup")
    func ageRatingUsesDirectAppInfoAndTriStateAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-direct"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-direct"}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "app_info_id": .string("info-direct"),
                "social_media": .null,
                "advertising": .bool(true),
                "developer_age_rating_info_url": .string("https://example.com/age")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "PATCH"])
        #expect(requests.map { $0.url?.path ?? "" } == [
            "/v1/appInfos/info-direct/ageRatingDeclaration",
            "/v1/ageRatingDeclarations/age-direct"
        ])
        let body = try #require(await transport.recordedBodyStrings().last)
        let bodyObject = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        let data = try #require(bodyObject["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.count == 3)
        #expect(attributes["socialMedia"] is NSNull)
        #expect(attributes["advertising"] as? Bool == true)
        #expect(attributes["developerAgeRatingInfoUrl"] as? String == "https://example.com/age")
        #expect(attributes["userGeneratedContent"] == nil)
    }

    @Test("invalid age rating attribute types fail before network access")
    func invalidAgeRatingTypeFailsBeforeNetwork() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "app_info_id": .string("info-direct"),
                "social_media": .string("true")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("legacy version lookup rejects one incompatible App Info")
    func ageRatingRejectsSingleIncompatibleAppInfo() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionWithAppBody(state: "REPLACED_WITH_NEW_VERSION")),
            .init(statusCode: 200, body: """
            {
              "data": [
                { "type": "appInfos", "id": "info-current", "attributes": { "state": "ACCEPTED" } }
              ]
            }
            """)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "version_id": .string("ver-old"),
                "advertising": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("legacy invalid binary version requires an explicit App Info ID")
    func ageRatingRejectsInvalidBinaryVersionLookup() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionWithAppBody(state: "INVALID_BINARY"))
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "version_id": .string("ver-invalid"),
                "advertising": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/v1/appStoreVersions/ver-invalid")
        guard case .text(let message, _, _) = result.content.first else {
            Issue.record("Expected an explicit App Info error")
            return
        }
        #expect(message.contains("app_info_id"))
    }

    @Test("legacy pending version state maps only to pending App Info")
    func ageRatingMapsPendingVersionState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionWithAppBody(state: "PENDING_DEVELOPER_RELEASE")),
            .init(statusCode: 200, body: """
            {
              "data": [
                { "type": "appInfos", "id": "info-pending", "attributes": { "state": "PENDING_RELEASE" } }
              ]
            }
            """),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-pending"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-pending"}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "version_id": .string("ver-next"),
                "advertising": .bool(false)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.url?.path ?? "" } == [
            "/v1/appStoreVersions/ver-next",
            "/v1/apps/app-1/appInfos",
            "/v1/appInfos/info-pending/ageRatingDeclaration",
            "/v1/ageRatingDeclarations/age-pending"
        ])
    }

    @Test("age rating resolves editable App Info and patches the existing declaration")
    func ageRatingUsesEditableAppInfo() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionWithAppBody(state: "PREPARE_FOR_SUBMISSION")),
            .init(statusCode: 200, body: """
            {
              "data": [
                { "type": "appInfos", "id": "info-live", "attributes": { "state": "ACCEPTED" } },
                { "type": "appInfos", "id": "info-next", "attributes": { "state": "PREPARE_FOR_SUBMISSION" } }
              ],
              "links": { "self": "https://api.example.test/v1/apps/app-1/appInfos" }
            }
            """),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1","attributes":{"socialMedia":true,"socialMediaAgeRestricted":true,"alcoholTobaccoOrDrugUseOrReferences":"INFREQUENT"}}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "version_id": .string("ver-1"),
                "social_media": .bool(true),
                "social_media_age_restricted": .bool(true),
                "alcohol_tobacco_or_drug_use": .string("INFREQUENT")
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map { $0.httpMethod ?? "" } == ["GET", "GET", "GET", "PATCH"])
        #expect(requests.map { $0.url?.path ?? "" } == [
            "/v1/appStoreVersions/ver-1",
            "/v1/apps/app-1/appInfos",
            "/v1/appInfos/info-next/ageRatingDeclaration",
            "/v1/ageRatingDeclarations/age-1"
        ])
        let patchBody = try #require(await transport.recordedBodyStrings().last)
        #expect(patchBody.contains(#""id":"age-1""#))
        #expect(patchBody.contains(#""socialMedia":true"#))
        #expect(patchBody.contains(#""socialMediaAgeRestricted":true"#))
        #expect(patchBody.contains(#""alcoholTobaccoOrDrugUseOrReferences":"INFREQUENT""#))
        #expect(!patchBody.contains("appStoreVersion"))
        let payload = try contractObject(result.structuredContent)
        #expect(payload["app_info_id"] == .string("info-next"))
        #expect(payload["action"] == .string("updated"))
    }

    @Test("age rating stops before mutation when App Info selection is ambiguous")
    func ageRatingStopsOnAmbiguousAppInfo() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: versionWithAppBody(state: "ACCEPTED")),
            .init(statusCode: 200, body: """
            {
              "data": [
                { "type": "appInfos", "id": "info-accepted", "attributes": { "state": "ACCEPTED" } },
                { "type": "appInfos", "id": "info-accepted-2", "attributes": { "state": "ACCEPTED" } }
              ],
              "links": { "self": "https://api.example.test/v1/apps/app-1/appInfos" }
            }
            """)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "app_versions_update_age_rating",
            arguments: [
                "version_id": .string("ver-1"),
                "advertising": .bool(false)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("age rating declaration read uses the App Info relationship")
    func ageRatingDeclarationRead() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1","attributes":{"socialMedia":true,"ageRatingOverrideV2":"THIRTEEN_PLUS"}},"links":{"self":"https://api.example.test/v1/ageRatingDeclarations/age-1"}}"#)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_get_age_rating_declaration",
            arguments: ["app_info_id": .string("info-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/appInfos/info-1/ageRatingDeclaration")
        #expect(request.url?.query == nil)
        let payload = try contractObject(result.structuredContent)
        #expect(payload["app_info_id"] == .string("info-1"))
        #expect(payload["age_rating_declaration"]?.objectValue?["id"] == .string("age-1"))
    }

    @Test("territory age ratings return calculated ratings territories and paging metadata")
    func territoryAgeRatingsRead() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {"type":"territoryAgeRatings","id":"rating-VNM","attributes":{"appStoreAgeRating":"ZERO_ZERO"},"relationships":{"territory":{"data":{"type":"territories","id":"VNM"}}}},
                {"type":"territoryAgeRatings","id":"rating-KOR","attributes":{"appStoreAgeRating":"FIFTEEN_PLUS"},"relationships":{"territory":{"data":{"type":"territories","id":"KOR"}}}}
              ],
              "included": [
                {"type":"territories","id":"VNM","attributes":{"currency":"VND"}},
                {"type":"territories","id":"KOR","attributes":{"currency":"KRW"}}
              ],
              "links": {"self":"https://api.example.test/v1/appInfos/info-1/territoryAgeRatings","next":"https://api.example.test/v1/appInfos/info-1/territoryAgeRatings?cursor=next"},
              "meta": {"paging":{"total":175,"limit":2,"nextCursor":"next"}}
            }
            """)
        ])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_list_territory_age_ratings",
            arguments: ["app_info_id": .string("info-1"), "limit": .int(2)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/appInfos/info-1/territoryAgeRatings")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["fields[territoryAgeRatings]"] == "appStoreAgeRating,territory")
        #expect(query["fields[territories]"] == "currency")
        #expect(query["include"] == "territory")
        #expect(query["limit"] == "2")
        let payload = try contractObject(result.structuredContent)
        #expect(payload["count"] == .int(2))
        #expect(payload["total"] == .int(175))
        #expect(payload["territory_age_ratings"]?.arrayValue?.count == 2)
        #expect(
            payload["territory_age_ratings"]?.arrayValue?.first?.objectValue?["attributes"]?
                .objectValue?["appStoreAgeRating"] == .string("ZERO_ZERO")
        )
        #expect(payload["included_territories"]?.arrayValue?.count == 2)
        #expect(payload["meta"]?.objectValue?["paging"]?.objectValue?["nextCursor"] == .string("next"))
    }

    @Test("age rating developer information URL rejects non-absolute values")
    func ageRatingRejectsRelativeDeveloperURL() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeContractWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "app_versions_update_age_rating",
            arguments: [
                "app_info_id": .string("info-1"),
                "developer_age_rating_info_url": .string("/age-rating")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }
}

private func makeContractWorker(transport: TestHTTPTransport) async throws -> AppLifecycleWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppLifecycleWorker(httpClient: client)
}

private func versionWithAppBody(state: String) -> String {
    """
    {
      "data": {
        "type": "appStoreVersions",
        "id": "ver-1",
        "attributes": { "appVersionState": "\(state)" },
        "relationships": {
          "app": { "data": { "type": "apps", "id": "app-1" } }
        }
      }
    }
    """
}

private func contractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw AppLifecycleContractTestFailure.expectedObject
    }
    return object
}

private enum AppLifecycleContractTestFailure: Error {
    case expectedObject
}
