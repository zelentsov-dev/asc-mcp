import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Beta App Worker Contract Tests")
struct BetaAppWorkerContractTests {
    @Test("all beta app tools use current Apple endpoints and JSON API write types")
    func allToolsUseCurrentEndpointsAndWriteTypes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppLocalizationPage()),
            .init(statusCode: 201, body: betaAppLocalizationResponse(id: "loc-created")),
            .init(statusCode: 200, body: betaAppLocalizationResponse(id: "loc-1")),
            .init(statusCode: 200, body: betaAppLocalizationResponse(id: "loc-1")),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 201, body: betaAppSubmissionResponse(id: "submission-created")),
            .init(statusCode: 200, body: betaAppSubmissionPage()),
            .init(statusCode: 200, body: betaAppSubmissionResponse(id: "submission-1", buildID: "build-1")),
            .init(statusCode: 200, body: betaAppReviewDetailResponse()),
            .init(statusCode: 200, body: betaAppReviewDetailResponse())
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let calls: [CallTool.Parameters] = [
            .init(name: "beta_app_list_localizations", arguments: ["app_id": .string("app-1")]),
            .init(name: "beta_app_create_localization", arguments: [
                "app_id": .string("app-1"),
                "locale": .string("en-US"),
                "feedback_email": .string("feedback@example.com"),
                "marketing_url": .string("https://example.com"),
                "privacy_policy_url": .string("https://example.com/privacy"),
                "tv_os_privacy_policy": .string("Privacy policy"),
                "description": .string("Try the beta")
            ]),
            .init(name: "beta_app_get_localization", arguments: ["localization_id": .string("loc-1")]),
            .init(name: "beta_app_update_localization", arguments: [
                "localization_id": .string("loc-1"),
                "description": .string("Updated beta")
            ]),
            .init(name: "beta_app_delete_localization", arguments: ["localization_id": .string("loc-1")]),
            .init(name: "beta_app_submit_for_review", arguments: ["build_id": .string("build-1")]),
            .init(name: "beta_app_list_submissions", arguments: ["build_id": .string("build-1")]),
            .init(name: "beta_app_get_submission", arguments: ["submission_id": .string("submission-1")]),
            .init(name: "beta_app_get_review_details", arguments: ["app_id": .string("app-1")]),
            .init(name: "beta_app_update_review_details", arguments: [
                "review_detail_id": .string("detail-1"),
                "notes": .string("Reviewer note")
            ])
        ]

        var results: [CallTool.Result] = []
        for call in calls {
            results.append(try await worker.handleTool(call))
        }
        #expect(results.allSatisfy { $0.isError != true })

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "PATCH", "DELETE", "POST", "GET", "GET", "GET", "PATCH"])
        #expect(requests.compactMap { $0.url?.path } == [
            "/v1/apps/app-1/betaAppLocalizations",
            "/v1/betaAppLocalizations",
            "/v1/betaAppLocalizations/loc-1",
            "/v1/betaAppLocalizations/loc-1",
            "/v1/betaAppLocalizations/loc-1",
            "/v1/betaAppReviewSubmissions",
            "/v1/betaAppReviewSubmissions",
            "/v1/betaAppReviewSubmissions/submission-1",
            "/v1/apps/app-1/betaAppReviewDetail",
            "/v1/betaAppReviewDetails/detail-1"
        ])

        let createLocalization = try betaAppContractRequestData(requests[1])
        #expect(createLocalization["type"] as? String == "betaAppLocalizations")
        let createLocalizationRelationships = try betaAppContractDictionary(createLocalization["relationships"])
        let appRelationship = try betaAppContractDictionary(createLocalizationRelationships["app"])
        let appLinkage = try betaAppContractDictionary(appRelationship["data"])
        #expect(appLinkage["type"] as? String == "apps")
        #expect(appLinkage["id"] as? String == "app-1")
        let createLocalizationAttributes = try betaAppContractDictionary(createLocalization["attributes"])
        #expect(Set(createLocalizationAttributes.keys) == [
            "locale", "feedbackEmail", "marketingUrl", "privacyPolicyUrl", "tvOsPrivacyPolicy", "description"
        ])
        #expect(createLocalizationAttributes["feedbackEmail"] as? String == "feedback@example.com")
        #expect(createLocalizationAttributes["marketingUrl"] as? String == "https://example.com")
        #expect(createLocalizationAttributes["privacyPolicyUrl"] as? String == "https://example.com/privacy")
        #expect(createLocalizationAttributes["tvOsPrivacyPolicy"] as? String == "Privacy policy")
        #expect(createLocalizationAttributes["description"] as? String == "Try the beta")

        let updateLocalization = try betaAppContractRequestData(requests[3])
        #expect(updateLocalization["type"] as? String == "betaAppLocalizations")
        #expect(updateLocalization["id"] as? String == "loc-1")

        let createSubmission = try betaAppContractRequestData(requests[5])
        #expect(createSubmission["type"] as? String == "betaAppReviewSubmissions")
        let createSubmissionRelationships = try betaAppContractDictionary(createSubmission["relationships"])
        let buildRelationship = try betaAppContractDictionary(createSubmissionRelationships["build"])
        let buildLinkage = try betaAppContractDictionary(buildRelationship["data"])
        #expect(buildLinkage["type"] as? String == "builds")
        #expect(buildLinkage["id"] as? String == "build-1")

        let updateReviewDetail = try betaAppContractRequestData(requests[9])
        #expect(updateReviewDetail["type"] as? String == "betaAppReviewDetails")
        #expect(updateReviewDetail["id"] as? String == "detail-1")

        let submitRoot = try betaAppContractObject(results[5].structuredContent)
        let submitted = try betaAppContractObject(submitRoot["submission"])
        #expect(submitted["relationshipBuildId"] == .null)
        #expect(submitted["buildId"] == .string("build-1"))
        #expect(submitted["buildIdSource"] == .string("request"))
        #expect(submitted["relationshipFallbackBuildId"] == nil)
        let localizationRoot = try betaAppContractObject(results[1].structuredContent)
        let localization = try betaAppContractObject(localizationRoot["localization"])
        #expect(localization["selfURL"] == .string("https://api.example.test/v1/betaAppLocalizations/loc-created"))
        let reviewRoot = try betaAppContractObject(results[8].structuredContent)
        let reviewDetail = try betaAppContractObject(reviewRoot["review_detail"])
        #expect(reviewDetail["selfURL"] == .string("https://api.example.test/v1/betaAppReviewDetails/detail-1"))
    }

    @Test("all review detail fields preserve value null and omission")
    func allReviewDetailFieldsPreserveTriState() async throws {
        let fields: [(tool: String, apple: String, value: Value)] = [
            ("contact_first_name", "contactFirstName", .string("Alex")),
            ("contact_last_name", "contactLastName", .string("Tester")),
            ("contact_phone", "contactPhone", .string("+1 555 0100")),
            ("contact_email", "contactEmail", .string("review@example.com")),
            ("demo_account_name", "demoAccountName", .string("demo")),
            ("demo_account_password", "demoAccountPassword", .string("secret")),
            ("demo_account_required", "demoAccountRequired", .bool(true)),
            ("notes", "notes", .string("Reviewer note"))
        ]
        let transport = TestHTTPTransport(responses: Array(
            repeating: .init(statusCode: 200, body: betaAppReviewDetailResponse()),
            count: fields.count * 2
        ))
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        for field in fields {
            let valueResult = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_review_details",
                arguments: [
                    "review_detail_id": .string("detail-1"),
                    field.tool: field.value
                ]
            ))
            #expect(valueResult.isError != true)

            let nullResult = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_review_details",
                arguments: [
                    "review_detail_id": .string("detail-1"),
                    field.tool: .null
                ]
            ))
            #expect(nullResult.isError != true)
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == fields.count * 2)
        for (index, field) in fields.enumerated() {
            let valueAttributes = try betaAppContractRequestAttributes(requests[index * 2])
            #expect(Set(valueAttributes.keys) == [field.apple])
            if case .string(let expected) = field.value {
                #expect(valueAttributes[field.apple] as? String == expected)
            } else if case .bool(let expected) = field.value {
                #expect(valueAttributes[field.apple] as? Bool == expected)
            }

            let nullAttributes = try betaAppContractRequestAttributes(requests[index * 2 + 1])
            #expect(Set(nullAttributes.keys) == [field.apple])
            #expect(nullAttributes[field.apple] is NSNull)
        }
    }

    @Test("review detail update rejects empty and malformed patches")
    func reviewDetailUpdateRejectsEmptyAndMalformedPatches() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_review_details",
            arguments: ["review_detail_id": .string("detail-1")]
        ))
        #expect(empty.isError == true)

        let malformed: [(String, Value)] = [
            ("contact_first_name", .int(1)),
            ("contact_last_name", .bool(true)),
            ("contact_phone", .array([])),
            ("contact_email", .object([:])),
            ("demo_account_name", .int(1)),
            ("demo_account_password", .bool(false)),
            ("demo_account_required", .string("true")),
            ("notes", .int(1))
        ]
        for (field, value) in malformed {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_review_details",
                arguments: [
                    "review_detail_id": .string("detail-1"),
                    field: value
                ]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("review detail output redacts present passwords without inventing absent passwords")
    func reviewDetailPasswordProjectionIsConditional() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppReviewDetailResponse(password: "secret")),
            .init(statusCode: 200, body: betaAppReviewDetailResponse(password: nil))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let present = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_review_details",
            arguments: ["app_id": .string("app-1")]
        ))
        let absent = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_review_details",
            arguments: ["app_id": .string("app-1")]
        ))

        let presentRoot = try betaAppContractObject(present.structuredContent)
        let presentDetail = try betaAppContractObject(presentRoot["review_detail"])
        #expect(presentDetail["demoAccountPassword"] == .string("[REDACTED]"))
        let absentRoot = try betaAppContractObject(absent.structuredContent)
        let absentDetail = try betaAppContractObject(absentRoot["review_detail"])
        #expect(absentDetail["demoAccountPassword"] == nil)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            #expect(betaAppContractQuery(request)["fields[betaAppReviewDetails]"] == "contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountName,demoAccountPassword,demoAccountRequired,notes")
        }
    }

    @Test("all localization update fields preserve value null and omission")
    func allLocalizationUpdateFieldsPreserveTriState() async throws {
        let fields: [(tool: String, apple: String, value: String)] = [
            ("feedback_email", "feedbackEmail", "feedback@example.com"),
            ("marketing_url", "marketingUrl", "https://example.com"),
            ("privacy_policy_url", "privacyPolicyUrl", "https://example.com/privacy"),
            ("tv_os_privacy_policy", "tvOsPrivacyPolicy", "Privacy policy"),
            ("description", "description", "Try the beta")
        ]
        let transport = TestHTTPTransport(responses: Array(
            repeating: .init(statusCode: 200, body: betaAppLocalizationResponse(id: "loc-1")),
            count: fields.count * 2
        ))
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        for field in fields {
            let concrete = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_localization",
                arguments: [
                    "localization_id": .string("loc-1"),
                    field.tool: .string(field.value)
                ]
            ))
            let explicitNull = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_localization",
                arguments: [
                    "localization_id": .string("loc-1"),
                    field.tool: .null
                ]
            ))
            #expect(concrete.isError != true)
            #expect(explicitNull.isError != true)
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == fields.count * 2)
        for (index, field) in fields.enumerated() {
            let concreteAttributes = try betaAppContractRequestAttributes(requests[index * 2])
            #expect(Set(concreteAttributes.keys) == [field.apple])
            #expect(concreteAttributes[field.apple] as? String == field.value)

            let nullAttributes = try betaAppContractRequestAttributes(requests[index * 2 + 1])
            #expect(Set(nullAttributes.keys) == [field.apple])
            #expect(nullAttributes[field.apple] is NSNull)
        }
    }

    @Test("localization update rejects malformed and empty writes")
    func localizationUpdateRejectsInvalidWrites() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let fields = ["feedback_email", "marketing_url", "privacy_policy_url", "tv_os_privacy_policy", "description"]
        for field in fields {
            let malformed = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_update_localization",
                arguments: [
                    "localization_id": .string("loc-1"),
                    field: .int(1)
                ]
            ))
            #expect(malformed.isError == true)
        }
        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_update_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))

        #expect(empty.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("all localization create fields preserve value null and omission")
    func allLocalizationCreateFieldsPreserveTriState() async throws {
        let fields: [(tool: String, apple: String, value: String)] = [
            ("feedback_email", "feedbackEmail", "feedback@example.com"),
            ("marketing_url", "marketingUrl", "https://example.com"),
            ("privacy_policy_url", "privacyPolicyUrl", "https://example.com/privacy"),
            ("tv_os_privacy_policy", "tvOsPrivacyPolicy", "Privacy policy"),
            ("description", "description", "Try the beta")
        ]
        let transport = TestHTTPTransport(responses: Array(
            repeating: .init(statusCode: 201, body: betaAppLocalizationResponse(id: "loc-created")),
            count: fields.count * 2 + 1
        ))
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        for field in fields {
            let concrete = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_create_localization",
                arguments: [
                    "app_id": .string("app-1"),
                    "locale": .string("en-US"),
                    field.tool: .string(field.value)
                ]
            ))
            let explicitNull = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_create_localization",
                arguments: [
                    "app_id": .string("app-1"),
                    "locale": .string("en-US"),
                    field.tool: .null
                ]
            ))
            #expect(concrete.isError != true)
            #expect(explicitNull.isError != true)
        }
        let omitted = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_create_localization",
            arguments: [
                "app_id": .string("app-1"),
                "locale": .string("en-US")
            ]
        ))
        #expect(omitted.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests.count == fields.count * 2 + 1)
        for (index, field) in fields.enumerated() {
            let concreteAttributes = try betaAppContractRequestAttributes(requests[index * 2])
            #expect(Set(concreteAttributes.keys) == ["locale", field.apple])
            #expect(concreteAttributes[field.apple] as? String == field.value)

            let nullAttributes = try betaAppContractRequestAttributes(requests[index * 2 + 1])
            #expect(Set(nullAttributes.keys) == ["locale", field.apple])
            #expect(nullAttributes[field.apple] is NSNull)
        }
        if let omittedRequest = requests.last {
            let omittedAttributes = try betaAppContractRequestAttributes(omittedRequest)
            #expect(Set(omittedAttributes.keys) == ["locale"])
        } else {
            Issue.record("Expected an omission-only localization request")
        }
    }

    @Test("localization create rejects malformed optional values")
    func localizationCreateRejectsInvalidOptionalValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let fields = ["feedback_email", "marketing_url", "privacy_policy_url", "tv_os_privacy_policy", "description"]
        let invalidValues: [Value] = [.bool(true), .int(1)]
        for field in fields {
            for value in invalidValues {
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: "beta_app_create_localization",
                    arguments: [
                        "app_id": .string("app-1"),
                        "locale": .string("en-US"),
                        field: value
                    ]
                ))
                #expect(result.isError == true)
            }
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization get requires only its resource ID")
    func localizationGetRequiresOnlyResourceID() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"betaAppLocalizations","id":"loc-1","attributes":{"locale":"en-US"}}}"#)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_localization",
            arguments: ["localization_id": .string("loc-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/betaAppLocalizations/loc-1")
        #expect(betaAppContractQuery(request)["fields[betaAppLocalizations]"] == "feedbackEmail,marketingUrl,privacyPolicyUrl,tvOsPrivacyPolicy,description,locale")
    }

    @Test("submission list encodes Apple array filters and preserves build linkage")
    func submissionListEncodesArrayFiltersAndPreservesBuildLinkage() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [
                {
                  "type": "betaAppReviewSubmissions",
                  "id": "submission-1",
                  "attributes": {"betaReviewState": "IN_REVIEW"},
                  "relationships": {
                    "build": {
                      "data": {"type": "builds", "id": "build-1"},
                      "links": {"related": "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions/submission-1/build"}
                    }
                  },
                  "links": {"self": "https://api.example.test/v1/betaAppReviewSubmissions/submission-1"}
                }
              ],
              "included": [
                {
                  "type": "builds",
                  "id": "build-1",
                  "attributes": {"version": "42", "uploadedDate": "2026-07-20T01:02:03Z", "processingState": "VALID"},
                  "links": {"self": "https://api.example.test/v1/builds/build-1"}
                }
              ],
              "meta": {"paging": {"total": 3, "limit": 25}}
            }
            """)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "review_state": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = betaAppContractQuery(request)
        #expect(query["filter[build]"] == "build-1,build-2")
        #expect(query["filter[betaReviewState]"] == "WAITING_FOR_REVIEW,IN_REVIEW")
        #expect(query["include"] == "build")
        #expect(query["fields[betaAppReviewSubmissions]"] == "betaReviewState,submittedDate,build")
        #expect(query["fields[builds]"] == "version,uploadedDate,processingState")
        #expect(query["limit"] == "25")
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["total"] == .int(3))
        let submissions = try betaAppContractArray(root["submissions"])
        let submission = try betaAppContractObject(submissions.first)
        #expect(submission["buildId"] == .string("build-1"))
        #expect(submission["relationshipBuildId"] == .string("build-1"))
        #expect(submission["buildIdSource"] == .string("relationship"))
        #expect(submission["relationshipFallbackBuildId"] == nil)
        #expect(submission["betaReviewState"] == .string("IN_REVIEW"))
        #expect(submission["buildRelatedURL"] == .string("https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions/submission-1/build"))
        #expect(submission["selfURL"] == .string("https://api.example.test/v1/betaAppReviewSubmissions/submission-1"))
        let includedBuilds = try betaAppContractArray(root["includedBuilds"])
        let includedBuild = try betaAppContractObject(includedBuilds.first)
        #expect(includedBuild["id"] == .string("build-1"))
        #expect(includedBuild["version"] == .string("42"))
        #expect(includedBuild["processingState"] == .string("VALID"))
        #expect(includedBuild["selfURL"] == .string("https://api.example.test/v1/builds/build-1"))
    }

    @Test("submission create rejects response linkage to a different build")
    func submissionCreateRejectsUnexpectedBuildLinkage() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: betaAppSubmissionResponse(
                id: "submission-created",
                buildID: "build-2"
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_submit_for_review",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission create reports committed state for contradictory included Build")
    func submissionCreateReportsCommittedForeignIncludedBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: betaAppSubmissionResponse(
                id: "submission-created",
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_submit_for_review",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError == true)
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["submissionId"] == .string("submission-created"))
        #expect(root["requestedBuildId"] == .string("build-1"))
        let inspection = try betaAppContractObject(root["inspection"])
        #expect(inspection["tool"] == .string("beta_app_list_submissions"))
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission create rejects contradictory included Build even with primary linkage")
    func submissionCreateRejectsPrimaryIncludedDisagreement() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: betaAppSubmissionResponse(
                id: "submission-created",
                buildID: "build-1",
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_submit_for_review",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError == true)
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission filters accept scalars and use a single filter as deterministic lineage")
    func submissionFiltersAcceptScalars() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(includeRelationship: false))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .string("build-1"),
                "review_state": .string("APPROVED")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = betaAppContractQuery(request)
        #expect(query["filter[build]"] == "build-1")
        #expect(query["filter[betaReviewState]"] == "APPROVED")
        let root = try betaAppContractObject(result.structuredContent)
        let submission = try betaAppContractObject(try betaAppContractArray(root["submissions"]).first)
        #expect(submission["relationshipBuildId"] == .null)
        #expect(submission["buildId"] == .string("build-1"))
        #expect(submission["buildIdSource"] == .string("filter"))
        #expect(submission["relationshipFallbackBuildId"] == nil)
    }

    @Test("single included build is a deterministic get fallback")
    func getSubmissionUsesSingleIncludedBuildFallback() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionResponse(
                id: "submission-1",
                includedBuilds: [betaAppIncludedBuild(id: "build-1", version: "42")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_submission",
            arguments: ["submission_id": .string("submission-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = betaAppContractQuery(request)
        #expect(query["include"] == "build")
        #expect(query["fields[betaAppReviewSubmissions]"] == "betaReviewState,submittedDate,build")
        #expect(query["fields[builds]"] == "version,uploadedDate,processingState")
        let root = try betaAppContractObject(result.structuredContent)
        let submission = try betaAppContractObject(root["submission"])
        #expect(submission["relationshipBuildId"] == .null)
        #expect(submission["buildId"] == .string("build-1"))
        #expect(submission["buildIdSource"] == .string("included"))
        #expect(submission["relationshipFallbackBuildId"] == nil)
        let includedBuild = try betaAppContractObject(try betaAppContractArray(root["includedBuilds"]).first)
        #expect(includedBuild["version"] == .string("42"))
    }

    @Test("submission get rejects a mismatched response identity")
    func getSubmissionRejectsMismatchedIdentity() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionResponse(id: "submission-2"))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_submission",
            arguments: ["submission_id": .string("submission-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission get rejects primary and included Build disagreement")
    func getSubmissionRejectsPrimaryIncludedDisagreement() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionResponse(
                id: "submission-1",
                buildID: "build-1",
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_submission",
            arguments: ["submission_id": .string("submission-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission get rejects invalid included Build evidence")
    func getSubmissionRejectsInvalidIncludedBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionResponse(
                id: "submission-1",
                includedBuilds: [betaAppIncludedBuild(id: "build-1", type: "apps")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_submission",
            arguments: ["submission_id": .string("submission-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("single included build is a deterministic one-item list fallback")
    func submissionListUsesSingleIncludedBuildFallback() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includeRelationship: false,
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError != true)
        let root = try betaAppContractObject(result.structuredContent)
        let submission = try betaAppContractObject(try betaAppContractArray(root["submissions"]).first)
        #expect(submission["relationshipBuildId"] == .null)
        #expect(submission["buildId"] == .string("build-2"))
        #expect(submission["buildIdSource"] == .string("included"))
        #expect(submission["relationshipFallbackBuildId"] == nil)
    }

    @Test("submission list rejects foreign included Build before filter fallback")
    func submissionListRejectsForeignIncludedBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includeRelationship: false,
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission list rejects invalid and duplicate included Build evidence")
    func submissionListRejectsMalformedIncludedBuilds() async throws {
        let includedCases = [
            [betaAppIncludedBuild(id: "", type: "builds")],
            [betaAppIncludedBuild(id: "build-1", type: "apps")],
            [betaAppIncludedBuild(id: "build-1"), betaAppIncludedBuild(id: "build-1")]
        ]

        for includedBuilds in includedCases {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: betaAppSubmissionPage(
                    includeRelationship: false,
                    includedBuilds: includedBuilds
                ))
            ])
            let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_list_submissions",
                arguments: ["build_id": .string("build-1")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("submission list rejects primary and included Build disagreement")
    func submissionListRejectsPrimaryIncludedDisagreement() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includedBuilds: [betaAppIncludedBuild(id: "build-2")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission list rejects foreign included Build with a multi-build filter")
    func submissionListRejectsForeignIncludedBuildWithMultipleFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includeRelationship: false,
                includedBuilds: [betaAppIncludedBuild(id: "build-3")]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("ambiguous included builds are rejected for a one-item response")
    func submissionListRejectsAmbiguousIncludedBuilds() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includeRelationship: false,
                includedBuilds: [
                    betaAppIncludedBuild(id: "build-1"),
                    betaAppIncludedBuild(id: "build-2")
                ]
            ))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 1)
    }

    @Test("submission list resolves absent linkage through the relationship endpoint")
    func submissionListUsesRelationshipEndpointWhenEvidenceIsAbsent() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(includeRelationship: false)),
            .init(statusCode: 200, body: betaAppBuildLinkageResponse(id: "build-2"))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError != true)
        let root = try betaAppContractObject(result.structuredContent)
        let submission = try betaAppContractObject(try betaAppContractArray(root["submissions"]).first)
        #expect(submission["relationshipFallbackBuildId"] == .string("build-2"))
        #expect(submission["buildId"] == .string("build-2"))
        #expect(submission["buildIdSource"] == .string("relationshipEndpoint"))
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/v1/betaAppReviewSubmissions/submission-1/relationships/build")
    }

    @Test("submission get resolves missing include linkage through the relationship endpoint")
    func getSubmissionUsesRelationshipEndpointFallback() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionResponse(id: "submission-1")),
            .init(statusCode: 200, body: betaAppBuildLinkageResponse(id: "build-1"))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_get_submission",
            arguments: ["submission_id": .string("submission-1")]
        ))

        #expect(result.isError != true)
        let root = try betaAppContractObject(result.structuredContent)
        let submission = try betaAppContractObject(root["submission"])
        #expect(submission["buildId"] == .string("build-1"))
        #expect(submission["buildIdSource"] == .string("relationshipEndpoint"))
        #expect(submission["relationshipFallbackBuildId"] == .string("build-1"))
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.url?.path) == [
            "/v1/betaAppReviewSubmissions/submission-1",
            "/v1/betaAppReviewSubmissions/submission-1/relationships/build"
        ])
    }

    @Test("relationship fallback rejects a build outside the requested filter")
    func relationshipFallbackRejectsUnexpectedBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage(
                includeRelationship: false
            )),
            .init(statusCode: 200, body: betaAppBuildLinkageResponse(id: "build-3"))
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .string("build-2")])]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 2)
    }

    @Test("submission list rejects unsupported filter values before network")
    func submissionListRejectsUnsupportedFilterValues() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .string("build-1"),
                "review_state": .array([.string("APPROVED"), .string("UNKNOWN")])
            ]
        ))
        let malformedBuild = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: ["build_id": .array([.string("build-1"), .int(2)])]
        ))
        let malformedLimit = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .string("build-1"),
                "limit": .string("25")
            ]
        ))

        let invalidLists: [(String, Value)] = [
            ("build_id", .string("")),
            ("build_id", .string(" build-1")),
            ("build_id", .string("build-1,build-2")),
            ("build_id", .array([])),
            ("build_id", .array([.string("build-1"), .string("build-1")])),
            ("review_state", .string("")),
            ("review_state", .string("APPROVED,REJECTED")),
            ("review_state", .array([])),
            ("review_state", .array([.string("APPROVED"), .string("APPROVED")]))
        ]
        for (field, value) in invalidLists {
            var arguments: [String: Value] = ["build_id": .string("build-1")]
            arguments[field] = value
            let invalid = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_list_submissions",
                arguments: arguments
            ))
            #expect(invalid.isError == true)
        }

        #expect(result.isError == true)
        #expect(malformedBuild.isError == true)
        #expect(malformedLimit.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("write tools reject malformed required strings before network")
    func writeToolsRejectMalformedRequiredStrings() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))
        let calls: [CallTool.Parameters] = [
            .init(name: "beta_app_create_localization", arguments: [
                "app_id": .int(1),
                "locale": .string("en-US")
            ]),
            .init(name: "beta_app_create_localization", arguments: [
                "app_id": .string("app-1"),
                "locale": .string(" ")
            ]),
            .init(name: "beta_app_update_localization", arguments: [
                "localization_id": .null,
                "description": .string("Updated")
            ]),
            .init(name: "beta_app_delete_localization", arguments: ["localization_id": .string("")]),
            .init(name: "beta_app_submit_for_review", arguments: ["build_id": .bool(true)]),
            .init(name: "beta_app_update_review_details", arguments: [
                "review_detail_id": .string(" detail-1"),
                "notes": .string("Reviewer note")
            ])
        ]

        for call in calls {
            let result = try await worker.handleTool(call)
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("read tools reject malformed required strings before network")
    func readToolsRejectMalformedRequiredStrings() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))
        let tools = [
            (name: "beta_app_list_localizations", field: "app_id"),
            (name: "beta_app_get_localization", field: "localization_id"),
            (name: "beta_app_get_submission", field: "submission_id"),
            (name: "beta_app_get_review_details", field: "app_id")
        ]
        let invalidValues: [Value] = [.null, .int(1), .string(""), .string(" id"), .string("id ")]

        for tool in tools {
            for invalidValue in invalidValues {
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: tool.name,
                    arguments: [tool.field: invalidValue]
                ))
                #expect(result.isError == true)
            }
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("localization list preserves paging total and sparse resources")
    func localizationListPreservesPagingTotalAndSparseResources() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{"type": "betaAppLocalizations", "id": "loc-1"}],
              "meta": {"paging": {"total": 4, "limit": 25}}
            }
            """)
        ])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_localizations",
            arguments: ["app_id": .string("app-1")]
        ))

        #expect(result.isError != true)
        let root = try betaAppContractObject(result.structuredContent)
        #expect(root["total"] == .int(4))
        let localization = try betaAppContractObject(try betaAppContractArray(root["localizations"]).first)
        #expect(localization["id"] == .string("loc-1"))
        #expect(localization["locale"] == .null)
        let request = try #require(await transport.recordedRequests().first)
        let query = betaAppContractQuery(request)
        #expect(query["fields[betaAppLocalizations]"] == "feedbackEmail,marketingUrl,privacyPolicyUrl,tvOsPrivacyPolicy,description,locale")
        #expect(query["limit"] == "25")
    }

    @Test("localization list rejects a malformed limit before network")
    func localizationListRejectsMalformedLimit() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_app_list_localizations",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .string("25")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("localization continuation preserves sparse fields and effective limit")
    func localizationContinuationPreservesScope() async throws {
        let path = "/v1/apps/app-1/betaAppLocalizations"
        let explicitParameters = [
            "cursor": "next",
            "fields[betaAppLocalizations]": "feedbackEmail,marketingUrl,privacyPolicyUrl,tvOsPrivacyPolicy,description,locale",
            "limit": "200"
        ]
        let acceptedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppLocalizationPage())
        ])
        let acceptedWorker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(acceptedTransport))
        let accepted = try await acceptedWorker.handleTool(CallTool.Parameters(
            name: "beta_app_list_localizations",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(500),
                "next_url": .string(betaAppContractPaginationURL(path: path, parameters: explicitParameters))
            ]
        ))
        #expect(accepted.isError != true)
        #expect(await acceptedTransport.requestCount() == 1)
        #expect(betaAppContractQuery(try #require(await acceptedTransport.recordedRequests().first)) == explicitParameters)

        var defaultParameters = explicitParameters
        defaultParameters["limit"] = "25"
        let defaultTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppLocalizationPage())
        ])
        let defaultWorker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(defaultTransport))
        let defaultResult = try await defaultWorker.handleTool(CallTool.Parameters(
            name: "beta_app_list_localizations",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(betaAppContractPaginationURL(path: path, parameters: defaultParameters))
            ]
        ))
        #expect(defaultResult.isError != true)
        #expect(await defaultTransport.requestCount() == 1)
        #expect(betaAppContractQuery(try #require(await defaultTransport.recordedRequests().first)) == defaultParameters)

        var invalidURLs: [String] = []
        var missingFields = explicitParameters
        missingFields.removeValue(forKey: "fields[betaAppLocalizations]")
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: missingFields))
        var changedFields = explicitParameters
        changedFields["fields[betaAppLocalizations]"] = "locale"
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: changedFields))
        var missingLimit = explicitParameters
        missingLimit.removeValue(forKey: "limit")
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: missingLimit))
        var changedLimit = explicitParameters
        changedLimit["limit"] = "25"
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: changedLimit))
        var missingCursor = explicitParameters
        missingCursor.removeValue(forKey: "cursor")
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: missingCursor))
        var emptyCursor = explicitParameters
        emptyCursor["cursor"] = ""
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: emptyCursor))
        var blankCursor = explicitParameters
        blankCursor["cursor"] = "   "
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: blankCursor))
        var injectedQuery = explicitParameters
        injectedQuery["filter[locale]"] = "en-US"
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: injectedQuery))
        invalidURLs.append(betaAppContractPaginationURL(
            path: path,
            parameters: explicitParameters,
            additionalParameters: [("cursor", "second")]
        ))
        invalidURLs.append(betaAppContractPaginationURL(
            path: path,
            parameters: explicitParameters,
            additionalParameters: [("limit", "200")]
        ))
        invalidURLs.append(betaAppContractPaginationURL(
            path: "/v1/apps/app-2/betaAppLocalizations",
            parameters: explicitParameters
        ))

        for invalidURL in invalidURLs {
            let transport = TestHTTPTransport(responses: [])
            let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_list_localizations",
                arguments: [
                    "app_id": .string("app-1"),
                    "limit": .int(500),
                    "next_url": .string(invalidURL)
                ]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("submission continuation preserves filters include sparse fields and effective limit")
    func submissionContinuationPreservesScope() async throws {
        let path = "/v1/betaAppReviewSubmissions"
        let explicitParameters = [
            "cursor": "next",
            "filter[build]": "build-1,build-2",
            "filter[betaReviewState]": "WAITING_FOR_REVIEW,IN_REVIEW",
            "fields[betaAppReviewSubmissions]": "betaReviewState,submittedDate,build",
            "fields[builds]": "version,uploadedDate,processingState",
            "include": "build",
            "limit": "200"
        ]
        let arguments: [String: Value] = [
            "build_id": .array([.string("build-1"), .string("build-2")]),
            "review_state": .array([.string("WAITING_FOR_REVIEW"), .string("IN_REVIEW")]),
            "limit": .int(500)
        ]
        let acceptedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage())
        ])
        let acceptedWorker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(acceptedTransport))
        var acceptedArguments = arguments
        acceptedArguments["next_url"] = .string(betaAppContractPaginationURL(path: path, parameters: explicitParameters))
        let accepted = try await acceptedWorker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: acceptedArguments
        ))
        #expect(accepted.isError != true)
        #expect(await acceptedTransport.requestCount() == 1)
        #expect(betaAppContractQuery(try #require(await acceptedTransport.recordedRequests().first)) == explicitParameters)

        var defaultParameters = explicitParameters
        defaultParameters["limit"] = "25"
        let defaultTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: betaAppSubmissionPage())
        ])
        let defaultWorker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(defaultTransport))
        var defaultArguments = arguments
        defaultArguments.removeValue(forKey: "limit")
        defaultArguments["next_url"] = .string(betaAppContractPaginationURL(path: path, parameters: defaultParameters))
        let defaultResult = try await defaultWorker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: defaultArguments
        ))
        #expect(defaultResult.isError != true)
        #expect(await defaultTransport.requestCount() == 1)
        #expect(betaAppContractQuery(try #require(await defaultTransport.recordedRequests().first)) == defaultParameters)

        var invalidURLs: [String] = []
        let mutations: [(String, String?)] = [
            ("filter[build]", nil),
            ("filter[build]", "build-1"),
            ("filter[betaReviewState]", nil),
            ("filter[betaReviewState]", "APPROVED"),
            ("fields[betaAppReviewSubmissions]", nil),
            ("fields[betaAppReviewSubmissions]", "build"),
            ("fields[builds]", nil),
            ("fields[builds]", "version"),
            ("include", nil),
            ("include", "app"),
            ("limit", nil),
            ("limit", "25")
        ]
        for (field, replacement) in mutations {
            var invalid = explicitParameters
            invalid[field] = replacement
            invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: invalid))
        }
        var missingCursor = explicitParameters
        missingCursor.removeValue(forKey: "cursor")
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: missingCursor))
        var emptyCursor = explicitParameters
        emptyCursor["cursor"] = ""
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: emptyCursor))
        var blankCursor = explicitParameters
        blankCursor["cursor"] = "   "
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: blankCursor))
        var injectedQuery = explicitParameters
        injectedQuery["sort"] = "-submittedDate"
        invalidURLs.append(betaAppContractPaginationURL(path: path, parameters: injectedQuery))
        invalidURLs.append(betaAppContractPaginationURL(
            path: path,
            parameters: explicitParameters,
            additionalParameters: [("cursor", "second")]
        ))
        invalidURLs.append(betaAppContractPaginationURL(
            path: path,
            parameters: explicitParameters,
            additionalParameters: [("filter[build]", "build-1,build-2")]
        ))
        invalidURLs.append(betaAppContractPaginationURL(
            path: "/v1/apps/app-1/betaAppReviewSubmissions",
            parameters: explicitParameters
        ))

        for invalidURL in invalidURLs {
            let transport = TestHTTPTransport(responses: [])
            let worker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(transport))
            var invalidArguments = arguments
            invalidArguments["next_url"] = .string(invalidURL)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "beta_app_list_submissions",
                arguments: invalidArguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        var documentedInjection = explicitParameters
        documentedInjection.removeValue(forKey: "filter[betaReviewState]")
        documentedInjection["filter[betaReviewState]"] = "APPROVED"
        let injectionTransport = TestHTTPTransport(responses: [])
        let injectionWorker = BetaAppWorker(httpClient: try await makeBetaAppContractClient(injectionTransport))
        let injectionResult = try await injectionWorker.handleTool(CallTool.Parameters(
            name: "beta_app_list_submissions",
            arguments: [
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "limit": .int(500),
                "next_url": .string(betaAppContractPaginationURL(path: path, parameters: documentedInjection))
            ]
        ))
        #expect(injectionResult.isError == true)
        #expect(await injectionTransport.requestCount() == 0)
    }

    @Test("beta app schemas expose nullable updates arrays and bounds")
    func betaAppSchemasExposeContracts() async throws {
        let worker = BetaAppWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()
        let updateReview = try #require(tools.first { $0.name == "beta_app_update_review_details" })
        let createLocalization = try #require(tools.first { $0.name == "beta_app_create_localization" })
        let updateLocalization = try #require(tools.first { $0.name == "beta_app_update_localization" })
        let listLocalizations = try #require(tools.first { $0.name == "beta_app_list_localizations" })
        let getLocalization = try #require(tools.first { $0.name == "beta_app_get_localization" })
        let listSubmissions = try #require(tools.first { $0.name == "beta_app_list_submissions" })
        let getSubmission = try #require(tools.first { $0.name == "beta_app_get_submission" })
        let getReview = try #require(tools.first { $0.name == "beta_app_get_review_details" })

        let reviewProperties = try betaAppContractProperties(updateReview)
        let nullableStringFields = [
            "contact_first_name", "contact_last_name", "contact_phone", "contact_email",
            "demo_account_name", "demo_account_password", "notes"
        ]
        for field in nullableStringFields {
            #expect(try betaAppContractArray(try betaAppContractObject(reviewProperties[field])["type"]) == [.string("string"), .string("null")])
        }
        #expect(try betaAppContractArray(try betaAppContractObject(reviewProperties["demo_account_required"])["type"]) == [.string("boolean"), .string("null")])
        #expect(try betaAppContractObject(updateReview.inputSchema)["minProperties"] == .int(2))
        #expect(try betaAppContractObject(updateLocalization.inputSchema)["minProperties"] == .int(2))
        let localizationFields = [
            "feedback_email", "marketing_url", "privacy_policy_url", "tv_os_privacy_policy", "description"
        ]
        for tool in [createLocalization, updateLocalization] {
            let properties = try betaAppContractProperties(tool)
            for field in localizationFields {
                #expect(try betaAppContractArray(try betaAppContractObject(properties[field])["type"]) == [.string("string"), .string("null")])
            }
        }
        let submissionProperties = try betaAppContractProperties(listSubmissions)
        #expect(try betaAppContractObject(submissionProperties["build_id"])["oneOf"] != nil)
        let limit = try betaAppContractObject(submissionProperties["limit"])
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(200))
        #expect(limit["default"] == .int(25))
        let localizationLimit = try betaAppContractObject(try betaAppContractProperties(listLocalizations)["limit"])
        #expect(localizationLimit["minimum"] == .int(1))
        #expect(localizationLimit["maximum"] == .int(200))
        #expect(localizationLimit["default"] == .int(25))
        for (tool, field) in [
            (listLocalizations, "app_id"),
            (getLocalization, "localization_id"),
            (getSubmission, "submission_id"),
            (getReview, "app_id")
        ] {
            #expect(try betaAppContractObject(try betaAppContractProperties(tool)[field])["minLength"] == .int(1))
        }
    }

    @Test("beta app manifest pins include decisions fallback lineage and coverage")
    func betaAppManifestPinsExactContracts() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let getLocalization = try #require(manifest.mapping(for: "beta_app_get_localization"))
        let getSubmission = try #require(manifest.mapping(for: "beta_app_get_submission"))
        let listSubmissions = try #require(manifest.mapping(for: "beta_app_list_submissions"))

        let localizationOperation = try #require(getLocalization.operations.first)
        let localizationInclude = try #require(localizationOperation.optionalParameterClassifications?.first {
            $0.location == "query" && $0.appleName == "include"
        })
        #expect(localizationInclude.disposition == .intentionallyOmitted)
        #expect(localizationInclude.reviewAtSpec == "4.4.1")

        for mapping in [getSubmission, listSubmissions] {
            #expect(mapping.kind == .compound)
            #expect(mapping.status == .partial)
            let primary = try #require(mapping.operations.first { $0.role == .primary })
            let include = try #require(primary.inputs?.first {
                $0.location == "query" && $0.appleName == "include"
            })
            #expect(include.sourceKind == .fixed)
            #expect(include.fixedValue == .array([.string("build")]))
            let fallback = try #require(mapping.operations.first {
                $0.operationID == "betaAppReviewSubmissions_build_getToOneRelationship"
            })
            #expect(fallback.role == .conditional)
            #expect(fallback.path == "/v1/betaAppReviewSubmissions/{id}/relationships/build")

            let outputFields = Set(mapping.response.fields.map(\.outputField))
            #expect(outputFields.contains { $0.hasSuffix("buildId") })
            #expect(outputFields.contains { $0.hasSuffix("buildIdSource") })
            #expect(outputFields.contains { $0.hasSuffix("relationshipFallbackBuildId") })
            #expect(outputFields.contains { $0.hasSuffix("betaReviewState") })
            #expect(outputFields.contains("includedBuilds[].processingState"))
        }

        #expect(!manifest.index.waivers.contains {
            $0.operationID == "betaAppReviewSubmissions_build_getToOneRelationship"
        })
        #expect(manifest.index.specPin.version == "4.4.1")
        #expect(manifest.index.specPin.sha256 == "ed0202ef37155b9334772482d2ea0be688c3046b284c895bcbea5455fbe54fd8")
    }
}

private func makeBetaAppContractClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func betaAppContractQuery(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func betaAppContractRequestAttributes(_ request: URLRequest) throws -> [String: Any] {
    let data = try betaAppContractRequestData(request)
    return try #require(data["attributes"] as? [String: Any])
}

private func betaAppContractRequestData(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try betaAppContractDictionary(json["data"])
}

private func betaAppContractDictionary(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func betaAppContractPaginationURL(
    path: String,
    parameters: [String: String],
    additionalParameters: [(String, String)] = []
) -> String {
    var components = URLComponents(string: "https://api.example.test\(path)")!
    components.queryItems = parameters.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    } + additionalParameters.map { URLQueryItem(name: $0.0, value: $0.1) }
    return components.url!.absoluteString
}

private func betaAppLocalizationPage() -> String {
    #"{"data":[{"type":"betaAppLocalizations","id":"loc-1","attributes":{"locale":"en-US"},"links":{"self":"https://api.example.test/v1/betaAppLocalizations/loc-1"}}],"meta":{"paging":{"total":1,"limit":25}}}"#
}

private func betaAppLocalizationResponse(id: String) -> String {
    #"{"data":{"type":"betaAppLocalizations","id":"\#(id)","attributes":{"locale":"en-US"},"links":{"self":"https://api.example.test/v1/betaAppLocalizations/\#(id)"}}}"#
}

private func betaAppIncludedBuild(
    id: String,
    version: String? = nil,
    type: String = "builds"
) -> String {
    let attributes = version.map { #", "attributes":{"version":"\#($0)","processingState":"VALID"}"# } ?? ""
    return #"{"type":"\#(type)","id":"\#(id)"\#(attributes)}"#
}

private func betaAppBuildLinkageResponse(id: String) -> String {
    #"{"data":{"type":"builds","id":"\#(id)"},"links":{"self":"https://api.example.test/v1/betaAppReviewSubmissions/submission-1/relationships/build"}}"#
}

private func betaAppSubmissionResponse(
    id: String,
    buildID: String? = nil,
    includedBuilds: [String] = []
) -> String {
    let relationships = buildID.map {
        #", "relationships":{"build":{"data":{"type":"builds","id":"\#($0)"}}}"#
    } ?? ""
    let included = includedBuilds.isEmpty ? "" : #", "included":[\#(includedBuilds.joined(separator: ","))]"#
    return #"{"data":{"type":"betaAppReviewSubmissions","id":"\#(id)","attributes":{"betaReviewState":"WAITING_FOR_REVIEW"}\#(relationships)}\#(included)}"#
}

private func betaAppSubmissionPage(
    includeRelationship: Bool = true,
    includedBuilds: [String] = []
) -> String {
    let relationships = includeRelationship
        ? #", "relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}"#
        : ""
    let included = includedBuilds.isEmpty ? "" : #", "included":[\#(includedBuilds.joined(separator: ","))]"#
    return #"{"data":[{"type":"betaAppReviewSubmissions","id":"submission-1","attributes":{"betaReviewState":"APPROVED"}\#(relationships)}]\#(included),"meta":{"paging":{"total":1,"limit":25}}}"#
}

private func betaAppReviewDetailResponse(password: String? = nil) -> String {
    let passwordAttribute = password.map { #", "demoAccountPassword":"\#($0)""# } ?? ""
    return #"{"data":{"type":"betaAppReviewDetails","id":"detail-1","attributes":{"contactFirstName":"Alex"\#(passwordAttribute)},"links":{"self":"https://api.example.test/v1/betaAppReviewDetails/detail-1"}}}"#
}

private func betaAppContractProperties(_ tool: Tool) throws -> [String: Value] {
    let schema = try betaAppContractObject(tool.inputSchema)
    return try betaAppContractObject(schema["properties"])
}

private func betaAppContractObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw BetaAppContractTestError.expectedObject
    }
    return object
}

private func betaAppContractArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected array, got \(String(describing: value))")
        throw BetaAppContractTestError.expectedArray
    }
    return array
}

private enum BetaAppContractTestError: Error {
    case expectedObject
    case expectedArray
}
