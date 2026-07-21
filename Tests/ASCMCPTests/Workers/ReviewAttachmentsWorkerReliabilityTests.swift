import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Review Attachments Worker Reliability Tests")
struct ReviewAttachmentsWorkerReliabilityTests {
    @Test("schemas publish generic files and bounded list limits")
    func schemasPublishCurrentContracts() async throws {
        let worker = try await reviewAttachmentsWorker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let upload = try reviewAttachmentsProperties(try #require(tools.first { $0.name == "review_attachments_upload" }))
        let list = try reviewAttachmentsProperties(try #require(tools.first { $0.name == "review_attachments_list" }))

        #expect(upload["file_path"]?.objectValue?["description"]?.stringValue == "Absolute path to the attachment file on disk")
        #expect(list["limit"]?.objectValue?["minimum"]?.intValue == 1)
        #expect(list["limit"]?.objectValue?["maximum"]?.intValue == 200)
        #expect(list["limit"]?.objectValue?["default"]?.intValue == 25)
        #expect(list["next_url"]?.objectValue?["description"]?.stringValue?.contains("pass the same limit again") == true)
    }

    @Test("get projects current attachment fields and review detail linkage")
    func getProjectsCurrentAttachment() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsSingleResponse())
        ])
        let worker = try await reviewAttachmentsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_get",
            arguments: ["attachment_id": .string("attachment-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/appStoreReviewAttachments/attachment-1")
        let query = reviewAttachmentsQuery(request)
        #expect(query["fields[appStoreReviewAttachments]"] == reviewAttachmentsReadFields)
        #expect(query["include"] == nil)
        let root = try reviewAttachmentsObject(result.structuredContent)
        let attachment = try reviewAttachmentsObject(root["attachment"])
        #expect(attachment["appStoreReviewDetailId"] == .string("review-detail-1"))
        #expect(attachment["fileName"] == .string("review-notes.pdf"))
    }

    @Test("list uses default projection and publishes paging total")
    func listUsesDefaultAndPublishesTotal() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsCollectionResponse())
        ])
        let worker = try await reviewAttachmentsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_list",
            arguments: ["review_detail_id": .string("review-detail-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = reviewAttachmentsQuery(request)
        #expect(query["fields[appStoreReviewAttachments]"] == reviewAttachmentsReadFields)
        #expect(query["limit"] == "25")
        #expect(query["include"] == nil)
        let root = try reviewAttachmentsObject(result.structuredContent)
        #expect(root["count"] == .int(1))
        #expect(root["total"] == .int(41))
        let attachments = try reviewAttachmentsArray(root["attachments"])
        let attachment = try reviewAttachmentsObject(attachments.first)
        #expect(attachment["appStoreReviewDetailId"] == .string("review-detail-1"))
    }

    @Test("list rejects oversized limits before network access")
    func listRejectsOversizedLimit() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await reviewAttachmentsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_list",
            arguments: [
                "review_detail_id": .string("review-detail-1"),
                "limit": .int(500)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("list accepts a continuation preserving projection and effective limit")
    func listAcceptsStableContinuation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsEmptyCollectionResponse())
        ])
        let worker = try await reviewAttachmentsWorker(transport)
        let nextURL = reviewAttachmentsNextURL(fields: reviewAttachmentsReadFields, limit: 73)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_list",
            arguments: [
                "review_detail_id": .string("review-detail-1"),
                "limit": .int(73),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = reviewAttachmentsQuery(request)
        #expect(query["fields[appStoreReviewAttachments]"] == reviewAttachmentsReadFields)
        #expect(query["limit"] == "73")
        #expect(query["cursor"] == "next")
    }

    @Test("list rejects a custom-limit continuation unless the same limit is repeated")
    func listRejectsCustomLimitWithoutMatchingArgument() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await reviewAttachmentsWorker(transport)
        let nextURL = reviewAttachmentsNextURL(fields: reviewAttachmentsReadFields, limit: 73)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_list",
            arguments: [
                "review_detail_id": .string("review-detail-1"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("list rejects continuation projection or page-size drift")
    func listRejectsContinuationDrift() async throws {
        let cases = [
            reviewAttachmentsNextURL(fields: "fileName,uploadOperations", limit: 200),
            reviewAttachmentsNextURL(fields: reviewAttachmentsReadFields, limit: 199)
        ]

        for nextURL in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await reviewAttachmentsWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "review_attachments_list",
                arguments: [
                    "review_detail_id": .string("review-detail-1"),
                    "limit": .int(200),
                    "next_url": .string(nextURL)
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("delete returns confirmation after Apple's empty success")
    func deleteReturnsConfirmation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: "")
        ])
        let worker = try await reviewAttachmentsWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "review_attachments_delete",
            arguments: [
                "attachment_id": .string("attachment-1"),
                "confirm_attachment_id": .string("attachment-1")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/appStoreReviewAttachments/attachment-1")
        let root = try reviewAttachmentsObject(result.structuredContent)
        #expect(root["success"] == .bool(true))
    }

    @Test("current response models decode relationship linkage and paging")
    func currentResponseModelsDecode() throws {
        let single = try JSONDecoder().decode(
            ASCReviewAttachmentResponse.self,
            from: Data(reviewAttachmentsSingleResponse().utf8)
        )
        let collection = try JSONDecoder().decode(
            ASCReviewAttachmentsResponse.self,
            from: Data(reviewAttachmentsCollectionResponse().utf8)
        )

        #expect(single.data.relationships?.appStoreReviewDetail?.data?.id == "review-detail-1")
        #expect(single.data.attributes?.uploadOperations == nil)
        #expect(collection.data.first?.relationships?.appStoreReviewDetail?.data?.id == "review-detail-1")
        #expect(collection.meta?.paging?.total == 41)
    }

    @Test("manifest records three include omissions and fixed safe projections")
    func manifestRecordsReadInvocations() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let readInvocations = [
            try #require(manifest.mapping(for: "review_attachments_get")?.operations.first),
            try #require(manifest.mapping(for: "review_attachments_list")?.operations.first)
        ]

        var reasons: Set<String> = []
        for invocation in readInvocations {
            let include = try #require(invocation.optionalParameterClassifications?.first {
                $0.location == "query" && $0.appleName == "include"
            })
            #expect(include.disposition == .intentionallyOmitted)
            reasons.insert(include.reason)
            let fields = try #require(invocation.inputs?.first {
                $0.sourceKind == .fixed
                    && $0.location == "query"
                    && $0.appleName == "fields[appStoreReviewAttachments]"
            }?.fixedValue)
            #expect(fields == .array(reviewAttachmentsReadFields.split(separator: ",").map {
                .string(String($0))
            }))
        }

        let reconciliation = try #require(manifest.mapping(for: "review_attachments_upload")?.operations.first {
            $0.operationID == "appStoreReviewAttachments_getInstance"
        })
        let reconciliationInclude = try #require(reconciliation.optionalParameterClassifications?.first {
            $0.location == "query" && $0.appleName == "include"
        })
        #expect(reconciliationInclude.disposition == .intentionallyOmitted)
        #expect(reconciliation.inputs?.contains {
            $0.location == "query" && $0.appleName == "fields[appStoreReviewAttachments]"
        } != true)
        reasons.insert(reconciliationInclude.reason)
        #expect(reasons.count == 3)

        let relationshipWaiver = try #require(manifest.index.waivers.first {
            $0.operationID == "appStoreReviewDetails_appStoreReviewAttachments_getToManyRelationship"
        })
        #expect(relationshipWaiver.reason.contains("linkage-only"))
        #expect(relationshipWaiver.reason.contains("not yet exposed") == false)
    }
}

private let reviewAttachmentsReadFields = "fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail"

private func reviewAttachmentsWorker(_ transport: TestHTTPTransport) async throws -> ReviewAttachmentsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ReviewAttachmentsWorker(
        httpClient: client,
        uploadService: UploadService(transport: TestHTTPTransport(responses: []))
    )
}

private func reviewAttachmentsProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw ReviewAttachmentsReliabilityTestError.expectedObject
    }
    return properties
}

private func reviewAttachmentsQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func reviewAttachmentsObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw ReviewAttachmentsReliabilityTestError.expectedObject
    }
    return object
}

private func reviewAttachmentsArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw ReviewAttachmentsReliabilityTestError.expectedArray
    }
    return array
}

private func reviewAttachmentsNextURL(fields: String, limit: Int) -> String {
    var components = URLComponents(string: "https://api.example.test/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments")!
    components.queryItems = [
        URLQueryItem(name: "cursor", value: "next"),
        URLQueryItem(name: "fields[appStoreReviewAttachments]", value: fields),
        URLQueryItem(name: "limit", value: String(limit))
    ]
    return components.url!.absoluteString
}

private func reviewAttachmentsSingleResponse() -> String {
    """
    {
      "data": {
        "type": "appStoreReviewAttachments",
        "id": "attachment-1",
        "attributes": {
          "fileSize": 512,
          "fileName": "review-notes.pdf",
          "sourceFileChecksum": "checksum",
          "assetDeliveryState": {"state": "COMPLETE"}
        },
        "relationships": {
          "appStoreReviewDetail": {
            "data": {"type": "appStoreReviewDetails", "id": "review-detail-1"}
          }
        }
      },
      "links": {
        "self": "https://api.example.test/v1/appStoreReviewAttachments/attachment-1?fields%5BappStoreReviewAttachments%5D=fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail"
      }
    }
    """
}

private func reviewAttachmentsCollectionResponse() -> String {
    """
    {
      "data": [
        {
          "type": "appStoreReviewAttachments",
          "id": "attachment-1",
          "attributes": {
            "fileSize": 512,
            "fileName": "review-notes.pdf",
            "sourceFileChecksum": "checksum",
            "assetDeliveryState": {"state": "COMPLETE"}
          },
          "relationships": {
            "appStoreReviewDetail": {
              "data": {"type": "appStoreReviewDetails", "id": "review-detail-1"}
            }
          }
        }
      ],
      "links": {
        "self": "https://api.example.test/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments?fields%5BappStoreReviewAttachments%5D=fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail&limit=25"
      },
      "meta": {"paging": {"total": 41, "limit": 25}}
    }
    """
}

private func reviewAttachmentsEmptyCollectionResponse() -> String {
    """
    {
      "data": [],
      "links": {
        "self": "https://api.example.test/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments?cursor=next&fields%5BappStoreReviewAttachments%5D=fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail&limit=73"
      },
      "meta": {"paging": {"total": 0, "limit": 73}}
    }
    """
}

private enum ReviewAttachmentsReliabilityTestError: Error {
    case expectedObject
    case expectedArray
}
