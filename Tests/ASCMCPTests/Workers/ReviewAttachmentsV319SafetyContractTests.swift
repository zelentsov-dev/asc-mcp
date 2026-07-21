import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Review Attachments v3.19 Safety Contract Tests")
struct ReviewAttachmentsV319SafetyContractTests {
    @Test("schemas reject unknown fields and require exact delete confirmation")
    func schemasAreStrict() async throws {
        let worker = try await reviewAttachmentsV319Worker(
            apiTransport: TestHTTPTransport(responses: []),
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let tools = await worker.getTools()

        for tool in tools {
            let schema = try reviewAttachmentsV319Object(tool.inputSchema)
            #expect(schema["additionalProperties"] == .bool(false))
        }

        let deletion = try #require(tools.first { $0.name == "review_attachments_delete" })
        let schema = try reviewAttachmentsV319Object(deletion.inputSchema)
        let required = try reviewAttachmentsV319Array(schema["required"])
        #expect(Set(required.compactMap(\.stringValue)) == [
            "attachment_id",
            "confirm_attachment_id"
        ])

        let listing = try #require(tools.first { $0.name == "review_attachments_list" })
        let listSchema = try reviewAttachmentsV319Object(listing.inputSchema)
        let listProperties = try reviewAttachmentsV319Object(listSchema["properties"])
        let nextURL = try reviewAttachmentsV319Object(listProperties["next_url"])
        #expect(nextURL["format"] == .string("uri-reference"))
        #expect(nextURL["minLength"] == .int(1))
        #expect(nextURL["pattern"] == .string(#"^\S(?:.*\S)?$"#))
    }

    @Test("invalid destructive arguments fail before any request")
    func invalidDeleteArgumentsAreRequestFree() async throws {
        let cases: [[String: Value]] = [
            ["attachment_id": .string("attachment-1")],
            [
                "attachment_id": .string("attachment-1"),
                "confirm_attachment_id": .string("attachment-2")
            ],
            [
                "attachment_id": .string("attachment/1"),
                "confirm_attachment_id": .string("attachment/1")
            ],
            [
                "attachment_id": .string("attachment-1"),
                "confirm_attachment_id": .string("attachment-1"),
                "force": .bool(true)
            ]
        ]

        for arguments in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: transport,
                uploadTransport: TestHTTPTransport(responses: [])
            )
            let result = try await worker.handleTool(.init(
                name: "review_attachments_delete",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("unknown fields, wrong types, and unsafe paths fail without requests")
    func invalidArgumentsAreRequestFreeAcrossTools() async throws {
        let cases: [CallTool.Parameters] = [
            .init(name: "review_attachments_upload", arguments: [
                "review_detail_id": .string("review-detail-1"),
                "file_path": .string("/tmp/review-attachment.bin"),
                "unexpected": .bool(true)
            ]),
            .init(name: "review_attachments_get", arguments: [
                "attachment_id": .string("attachment-1"),
                "unexpected": .bool(true)
            ]),
            .init(name: "review_attachments_list", arguments: [
                "review_detail_id": .string("review-detail-1"),
                "unexpected": .bool(true)
            ]),
            .init(name: "review_attachments_upload", arguments: [
                "review_detail_id": .int(1),
                "file_path": .string("/tmp/review-attachment.bin")
            ]),
            .init(name: "review_attachments_upload", arguments: [
                "review_detail_id": .string("review-detail-1"),
                "file_path": .int(1)
            ]),
            .init(name: "review_attachments_get", arguments: [
                "attachment_id": .int(1)
            ]),
            .init(name: "review_attachments_get", arguments: [
                "attachment_id": .string("attachment/1")
            ]),
            .init(name: "review_attachments_list", arguments: [
                "review_detail_id": .int(1)
            ]),
            .init(name: "review_attachments_list", arguments: [
                "review_detail_id": .string("review-detail-1"),
                "limit": .string("25")
            ]),
            .init(name: "review_attachments_list", arguments: [
                "review_detail_id": .string("review-detail-1"),
                "next_url": .int(1)
            ]),
            .init(name: "review_attachments_list", arguments: [
                "review_detail_id": .string("../review-detail-1")
            ]),
            .init(name: "review_attachments_delete", arguments: [
                "attachment_id": .int(1),
                "confirm_attachment_id": .int(1)
            ])
        ]

        for parameters in cases {
            let transport = TestHTTPTransport(responses: [])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: transport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(parameters)
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("delete requires exact HTTP 204 and preserves uncertain-state inspection")
    func deleteRequiresExactStatus() async throws {
        let successTransport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: "")
        ])
        let successWorker = try await reviewAttachmentsV319Worker(
            apiTransport: successTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let success = try await successWorker.handleTool(
            reviewAttachmentsV319DeleteParameters()
        )
        #expect(success.isError != true)
        #expect(await successTransport.recordedRequests().map(\.httpMethod) == ["DELETE"])

        let unexpectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "{}")
        ])
        let unexpectedWorker = try await reviewAttachmentsV319Worker(
            apiTransport: unexpectedTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let unexpected = try await unexpectedWorker.handleTool(
            reviewAttachmentsV319DeleteParameters()
        )
        let payload = try reviewAttachmentsV319Object(unexpected.structuredContent)
        let inspection = try reviewAttachmentsV319Object(payload["inspection"])
        let arguments = try reviewAttachmentsV319Object(inspection["arguments"])

        #expect(unexpected.isError == true)
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(arguments["attachment_id"] == .string("attachment-1"))
    }

    @Test("reservation and commit require exact Apple success statuses")
    func uploadRequiresExactStatuses() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let reserveTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true
            ))
        ])
        let reserveUpload = TestHTTPTransport(responses: [])
        let reserveWorker = try await reviewAttachmentsV319Worker(
            apiTransport: reserveTransport,
            uploadTransport: reserveUpload
        )
        let reserveResult = try await reserveWorker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )
        let reservePayload = try reviewAttachmentsV319Object(reserveResult.structuredContent)

        #expect(reserveResult.isError == true)
        #expect(reservePayload["statusCode"] == .int(200))
        #expect(reservePayload["operationCommitState"] == .string("committed_unverified"))
        #expect(reservePayload["retrySafe"] == .bool(false))
        #expect(await reserveTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        #expect(await reserveUpload.requestCount() == 0)

        let commitTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileName: fileURL.lastPathComponent
            )),
            .init(statusCode: 201, body: reviewAttachmentsV319Response(state: "COMPLETE"))
        ])
        let commitWorker = try await reviewAttachmentsV319Worker(
            apiTransport: commitTransport,
            uploadTransport: TestHTTPTransport(responses: [
                .init(statusCode: 200, body: "")
            ])
        )
        let commitResult = try await commitWorker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )
        let commitPayload = try reviewAttachmentsV319Object(commitResult.structuredContent)

        #expect(commitResult.isError == true)
        #expect(commitPayload["statusCode"] == .int(201))
        #expect(commitPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(commitPayload["attachmentId"] == .string("attachment-1"))
        #expect(await commitTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH"])
    }

    @Test("immutable snapshot binds reservation transfer and commit bytes")
    func immutableSnapshotIsAuthoritative() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentsV319MutatingTransport(
            fileURL: fileURL,
            responses: [
                .init(statusCode: 201, body: reviewAttachmentsV319Response(
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true,
                    fileName: fileURL.lastPathComponent
                )),
                .init(statusCode: 200, body: reviewAttachmentsV319Response(state: "COMPLETE"))
            ]
        )
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await reviewAttachmentsV319Worker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )

        #expect(result.isError != true)
        let uploadRequest = try #require(await uploadTransport.recordedRequests().first)
        #expect(uploadRequest.httpBody == Data("hello".utf8))
        let requests = await apiTransport.recordedRequests()
        let reserveBody = try reviewAttachmentsV319JSONBody(requests[0])
        let reserveData = try reviewAttachmentsV319AnyObject(reserveBody["data"])
        let reserveAttributes = try reviewAttachmentsV319AnyObject(reserveData["attributes"])
        let commitBody = try reviewAttachmentsV319JSONBody(requests[1])
        let commitData = try reviewAttachmentsV319AnyObject(commitBody["data"])
        let commitAttributes = try reviewAttachmentsV319AnyObject(commitData["attributes"])
        #expect(reserveAttributes["fileSize"] as? Int == 5)
        #expect(commitAttributes["sourceFileChecksum"] as? String == "5d41402abc4b2a76b9719d911017c592")
    }

    @Test("noncanonical reservation identity and conflicting lineage never start transfer")
    func invalidReservationIdentityIsNotAttributed() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let cases = [
            reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                id: "attachment%2F1",
                includeUploadOperation: true
            ),
            reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                reviewDetailID: "review-detail-2",
                includeUploadOperation: true
            )
        ]

        for body in cases {
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: body)
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(
                reviewAttachmentsV319UploadParameters(fileURL)
            )
            let payload = try reviewAttachmentsV319Object(result.structuredContent)

            #expect(result.isError == true)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["reservationIdKnown"] == .bool(false))
            #expect(payload["retrySafe"] == .bool(false))
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("ambiguous reservation requires manual resolution without claiming a unique fingerprint")
    func ambiguousReservationHasSafeRecovery() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentsV319FailureTransport(
            message: "https://upload.example.test/chunk?token=signed-secret"
        )
        let worker = try await reviewAttachmentsV319Worker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )
        let payload = try reviewAttachmentsV319Object(result.structuredContent)
        let hints = try reviewAttachmentsV319Object(payload["reservationHints"])
        let inspection = try reviewAttachmentsV319Object(payload["inspection"])
        let resolution = try reviewAttachmentsV319Object(payload["manualResolution"])
        let verify = try reviewAttachmentsV319Object(resolution["verify"])
        let cleanup = try reviewAttachmentsV319Object(resolution["cleanup"])
        let rendered = result.content.compactMap { content -> String? in
            guard case .text(let text, _, _) = content else { return nil }
            return text
        }.joined(separator: "\n")

        #expect(result.isError == true)
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["reservationFingerprint"] == nil)
        #expect(payload["sourceFileChecksumReceipt"] == nil)
        #expect(payload["manualResolutionRequired"] == .bool(true))
        #expect(hints["fileName"] == .string(fileURL.lastPathComponent))
        #expect(hints["fileSize"] == .int(5))
        #expect(hints["matchStrength"] == .string("non_unique"))
        #expect(hints["checksumAvailableBeforeCommit"] == .bool(false))
        #expect(inspection["continue_with_next_url"] == .bool(true))
        #expect(inspection["candidate_match"] == nil)
        #expect(verify["tool"] == .string("review_attachments_get"))
        #expect(verify["id_argument"] == .string("attachment_id"))
        #expect(cleanup["tool"] == .string("review_attachments_delete"))
        #expect(cleanup["confirmation_argument"] == .string("confirm_attachment_id"))
        #expect(rendered.contains("signed-secret") == false)
        #expect(rendered.contains("upload.example.test") == false)
    }

    @Test("reservation metadata must echo the immutable snapshot before transfer")
    func reservationSnapshotMismatchRollsBackWithoutTransfer() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let mismatches = [
            reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileName: "different.bin"
            ),
            reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileName: fileURL.lastPathComponent,
                fileSize: 6
            )
        ]

        for body in mismatches {
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: body),
                .init(statusCode: 204, body: "")
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )

            let result = try await worker.handleTool(
                reviewAttachmentsV319UploadParameters(fileURL)
            )
            let payload = try reviewAttachmentsV319Object(result.structuredContent)

            #expect(result.isError == true)
            #expect(payload["reservationDeleted"] == .bool(true))
            #expect(payload["retrySafe"] == .bool(true))
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("a semantic commit conflict cannot be laundered by later reconciliation")
    func semanticCommitConflictRemainsUnresolved() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileName: fileURL.lastPathComponent
            )),
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "PROCESSING",
                reviewDetailID: "review-detail-2"
            )),
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "PROCESSING",
                includeRelationship: false
            ))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await reviewAttachmentsV319Worker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )
        let payload = try reviewAttachmentsV319Object(result.structuredContent)

        #expect(result.isError == true)
        #expect(payload["success"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["uploadCommitted"] != .bool(true))
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(await uploadTransport.requestCount() == 1)
    }

    @Test("a conflicting commit resource ID cannot be laundered by reconciliation")
    func commitIdentityConflictRemainsUnresolved() async throws {
        let fileURL = try reviewAttachmentsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentsV319Response(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                fileName: fileURL.lastPathComponent
            )),
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "PROCESSING",
                id: "attachment-2"
            )),
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "PROCESSING",
                includeRelationship: false
            ))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await reviewAttachmentsV319Worker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(
            reviewAttachmentsV319UploadParameters(fileURL)
        )
        let payload = try reviewAttachmentsV319Object(result.structuredContent)

        #expect(result.isError == true)
        #expect(payload["success"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["uploadCommitted"] != .bool(true))
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
    }

    @Test("single and collection documents require links bound to the requested scope")
    func responseDocumentLinksAreRequiredAndScoped() async throws {
        let getBodies = [
            reviewAttachmentsV319Response(
                state: "COMPLETE",
                includeLinks: false,
                includeReadQuery: true
            ),
            reviewAttachmentsV319Response(
                state: "COMPLETE",
                selfID: "attachment-2",
                includeReadQuery: true
            ),
            reviewAttachmentsV319Response(
                state: "COMPLETE",
                selfBaseURL: "https://hostile.example.test",
                includeReadQuery: true
            )
        ]
        for body in getBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: transport,
                uploadTransport: TestHTTPTransport(responses: [])
            )
            let result = try await worker.handleTool(.init(
                name: "review_attachments_get",
                arguments: ["attachment_id": .string("attachment-1")]
            ))
            #expect(result.isError == true)
        }

        let listBodies = [
            reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                includeLinks: false
            ),
            reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                selfReviewDetailID: "review-detail-2"
            ),
            reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                selfLimit: 50
            ),
            reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                selfBaseURL: "https://hostile.example.test"
            ),
            reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                nextBaseURL: "https://hostile.example.test"
            )
        ]
        for body in listBodies {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: body)
            ])
            let worker = try await reviewAttachmentsV319Worker(
                apiTransport: transport,
                uploadTransport: TestHTTPTransport(responses: [])
            )
            let result = try await worker.handleTool(.init(
                name: "review_attachments_list",
                arguments: ["review_detail_id": .string("review-detail-1")]
            ))
            #expect(result.isError == true)
        }

        let rootRelativeGetTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "COMPLETE",
                selfBaseURL: "",
                includeReadQuery: true
            ))
        ])
        let rootRelativeGetWorker = try await reviewAttachmentsV319Worker(
            apiTransport: rootRelativeGetTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let rootRelativeGet = try await rootRelativeGetWorker.handleTool(.init(
            name: "review_attachments_get",
            arguments: ["attachment_id": .string("attachment-1")]
        ))
        #expect(rootRelativeGet.isError != true)

        let rootRelativeListTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-1",
                selfBaseURL: "",
                nextBaseURL: ""
            ))
        ])
        let rootRelativeListWorker = try await reviewAttachmentsV319Worker(
            apiTransport: rootRelativeListTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let rootRelativeList = try await rootRelativeListWorker.handleTool(.init(
            name: "review_attachments_list",
            arguments: ["review_detail_id": .string("review-detail-1")]
        ))
        #expect(rootRelativeList.isError != true)
        let rootRelativeListPayload = try reviewAttachmentsV319Object(
            rootRelativeList.structuredContent
        )
        #expect(rootRelativeListPayload["next_url"]?.stringValue?.hasPrefix("/v1/") == true)
    }

    @Test("read projections reject mismatched resource identity and parent lineage")
    func readResponsesAreBoundToRequestedResources() async throws {
        let getTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsV319Response(
                state: "COMPLETE",
                id: "attachment-2",
                includeReadQuery: true
            ))
        ])
        let getWorker = try await reviewAttachmentsV319Worker(
            apiTransport: getTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let getResult = try await getWorker.handleTool(.init(
            name: "review_attachments_get",
            arguments: ["attachment_id": .string("attachment-1")]
        ))
        #expect(getResult.isError == true)

        let listTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: reviewAttachmentsV319CollectionResponse(
                reviewDetailID: "review-detail-2"
            ))
        ])
        let listWorker = try await reviewAttachmentsV319Worker(
            apiTransport: listTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let listResult = try await listWorker.handleTool(.init(
            name: "review_attachments_list",
            arguments: ["review_detail_id": .string("review-detail-1")]
        ))
        #expect(listResult.isError == true)
    }

    @Test("manifest binds confirmation and exact upload receipts")
    func manifestRecordsV319SafetyContract() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let deletion = try #require(manifest.mapping(for: "review_attachments_delete"))
        let confirmation = try #require(deletion.fields.first {
            $0.toolField == "confirm_attachment_id"
        })
        #expect(confirmation.sourceKind == .local)
        #expect(confirmation.localRole?.contains("exact canonical match") == true)

        let upload = try #require(manifest.mapping(for: "review_attachments_upload"))
        let reserve = try #require(upload.operations.first {
            $0.operationID == "appStoreReviewAttachments_createInstance"
        })
        let commit = try #require(upload.operations.first {
            $0.operationID == "appStoreReviewAttachments_updateInstance"
        })
        #expect(reserve.condition?.contains("exactly HTTP 201") == true)
        #expect(commit.condition?.contains("exactly HTTP 200") == true)
        #expect(upload.response.fields.contains {
            $0.outputField == "reservationHints"
        })
        #expect(upload.response.fields.contains {
            $0.outputField == "manualResolutionRequired"
        })
        #expect(upload.response.fields.contains {
            $0.outputField == "manualResolution"
        })
        #expect(upload.response.fields.contains {
            $0.outputField == "sourceFileChecksumReceipt"
        })
    }
}

private func reviewAttachmentsV319Worker(
    apiTransport: any HTTPTransport,
    uploadTransport: any HTTPTransport
) async throws -> ReviewAttachmentsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 1
    )
    return ReviewAttachmentsWorker(
        httpClient: client,
        uploadService: UploadService(transport: uploadTransport, batchSize: 1),
        deliveryPollAttempts: 1,
        deliveryPollIntervalNanoseconds: 0
    )
}

private func reviewAttachmentsV319UploadParameters(_ fileURL: URL) -> CallTool.Parameters {
    .init(
        name: "review_attachments_upload",
        arguments: [
            "review_detail_id": .string("review-detail-1"),
            "file_path": .string(fileURL.path)
        ]
    )
}

private func reviewAttachmentsV319DeleteParameters() -> CallTool.Parameters {
    .init(
        name: "review_attachments_delete",
        arguments: [
            "attachment_id": .string("attachment-1"),
            "confirm_attachment_id": .string("attachment-1")
        ]
    )
}

private func reviewAttachmentsV319File(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-mcp-review-attachments-v319-\(UUID().uuidString).bin")
    try data.write(to: url)
    return url
}

private func reviewAttachmentsV319Response(
    state: String,
    id: String = "attachment-1",
    reviewDetailID: String = "review-detail-1",
    includeUploadOperation: Bool = false,
    fileName: String = "attachment.bin",
    fileSize: Int = 5,
    includeRelationship: Bool = true,
    includeLinks: Bool = true,
    selfID: String? = nil,
    selfBaseURL: String = "https://api.example.test",
    includeReadQuery: Bool = false
) -> String {
    let uploadOperations = includeUploadOperation
        ? #", "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk?token=signed-secret","length":5,"offset":0,"requestHeaders":[]}]"#
        : ""
    let relationship = includeRelationship
        ? #", "relationships":{"appStoreReviewDetail":{"data":{"type":"appStoreReviewDetails","id":"\#(reviewDetailID)"}}}"#
        : ""
    let query = includeReadQuery ? "?\(reviewAttachmentsV319ReadQuery)" : ""
    let links = includeLinks
        ? #", "links":{"self":"\#(selfBaseURL)/v1/appStoreReviewAttachments/\#(selfID ?? id)\#(query)"}"#
        : ""
    return #"{"data":{"type":"appStoreReviewAttachments","id":"\#(id)","attributes":{"fileSize":\#(fileSize),"fileName":"\#(fileName)","sourceFileChecksum":"5d41402abc4b2a76b9719d911017c592","assetDeliveryState":{"state":"\#(state)"}\#(uploadOperations)}\#(relationship)}\#(links)}"#
}

private func reviewAttachmentsV319CollectionResponse(
    reviewDetailID: String,
    includeLinks: Bool = true,
    selfReviewDetailID: String = "review-detail-1",
    selfBaseURL: String = "https://api.example.test",
    nextBaseURL: String? = nil,
    selfLimit: Int = 25
) -> String {
    let next = nextBaseURL.map {
        #", "next":"\#($0)/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments?fields%5BappStoreReviewAttachments%5D=\#(reviewAttachmentsV319EncodedReadFields)&limit=25&cursor=next""#
    } ?? ""
    let links = includeLinks
        ? #", "links":{"self":"\#(selfBaseURL)/v1/appStoreReviewDetails/\#(selfReviewDetailID)/appStoreReviewAttachments?fields%5BappStoreReviewAttachments%5D=\#(reviewAttachmentsV319EncodedReadFields)&limit=\#(selfLimit)"\#(next)}"#
        : ""
    let nextCursor = nextBaseURL == nil ? "" : #", "nextCursor":"next""#
    return #"{"data":[{"type":"appStoreReviewAttachments","id":"attachment-1","attributes":{"fileSize":5,"fileName":"attachment.bin","sourceFileChecksum":"5d41402abc4b2a76b9719d911017c592","assetDeliveryState":{"state":"COMPLETE"}},"relationships":{"appStoreReviewDetail":{"data":{"type":"appStoreReviewDetails","id":"\#(reviewDetailID)"}}}}]\#(links),"meta":{"paging":{"total":1,"limit":25\#(nextCursor)}}}"#
}

private let reviewAttachmentsV319EncodedReadFields =
    "fileSize%2CfileName%2CsourceFileChecksum%2CassetDeliveryState%2CappStoreReviewDetail"
private let reviewAttachmentsV319ReadQuery =
    "fields%5BappStoreReviewAttachments%5D=\(reviewAttachmentsV319EncodedReadFields)"

private func reviewAttachmentsV319Object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw ReviewAttachmentsV319TestError.expectedObject
    }
    return object
}

private func reviewAttachmentsV319Array(_ value: Value?) throws -> [Value] {
    guard case .array(let values) = value else {
        throw ReviewAttachmentsV319TestError.expectedArray
    }
    return values
}

private func reviewAttachmentsV319AnyObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw ReviewAttachmentsV319TestError.expectedObject
    }
    return object
}

private func reviewAttachmentsV319JSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let data = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ReviewAttachmentsV319TestError.expectedObject
    }
    return object
}

private actor ReviewAttachmentsV319MutatingTransport: HTTPTransport {
    private let fileURL: URL
    private var responses: [TestHTTPTransport.Response]
    private var requests: [URLRequest] = []

    init(fileURL: URL, responses: [TestHTTPTransport.Response]) {
        self.fileURL = fileURL
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw ASCError.network("No mock response queued")
        }
        if request.httpMethod == "POST" {
            try Data("changed after snapshot".utf8).write(to: fileURL)
        }
        let response = responses.removeFirst()
        return (
            response.data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
        )
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor ReviewAttachmentsV319FailureTransport: HTTPTransport {
    let message: String
    private var requests: [URLRequest] = []

    init(message: String) {
        self.message = message
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        throw ASCError.network(message)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request)
    }
}

private enum ReviewAttachmentsV319TestError: Error {
    case expectedObject
    case expectedArray
}
