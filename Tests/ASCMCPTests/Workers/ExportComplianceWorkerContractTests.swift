import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Export Compliance Worker Contract Tests")
struct ExportComplianceWorkerContractTests {
    @Test("list uses app related endpoint, fixed fields, strict limit, total, and next URL")
    func listContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[{"type":"appEncryptionDeclarations","id":"declaration-1","attributes":{"appDescription":"Encrypted chat","appEncryptionDeclarationState":"APPROVED","codeValue":"CCATS-1"}}],"links":{"self":"https://api.example.test/v1/apps/app%2Fone/appEncryptionDeclarations","next":"https://api.example.test/v1/apps/app%2Fone/appEncryptionDeclarations?fields%5BappEncryptionDeclarations%5D=appDescription%2CcreatedDate%2Cexempt%2CcontainsProprietaryCryptography%2CcontainsThirdPartyCryptography%2CavailableOnFrenchStore%2CappEncryptionDeclarationState%2CcodeValue%2CappEncryptionDeclarationDocument&limit=37&cursor=next-page"},"meta":{"paging":{"total":4,"limit":37}}}"#
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_list_declarations",
            arguments: ["app_id": .string("app-one"), "limit": .int(37)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(try exportComplianceEncodedPath(request) == "/v1/apps/app-one/appEncryptionDeclarations")
        let query = try exportComplianceQuery(request)
        #expect(query["limit"] == "37")
        #expect(query["fields[appEncryptionDeclarations]"] == exportComplianceTestDeclarationFields)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["count"] == .int(1))
        #expect(payload["total"] == .int(4))
        #expect(payload["next_url"] != nil)
    }

    @Test("pagination rejects changed scope and unknown query before network")
    func strictPaginationContract() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let nextURL = exportComplianceNextURL(
            appID: "app-1",
            limit: 25,
            additions: ["cursor": "next", "unexpected": "value"]
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_list_declarations",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
        #expect(exportComplianceText(result).contains("outside the allowed set"))
    }

    @Test("continuation preserves a validated nondefault limit when limit is omitted")
    func nondefaultLimitContinuation() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[],"meta":{"paging":{"total":4,"limit":37}}}"#)
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let nextURL = exportComplianceNextURL(
            appID: "app-1",
            limit: 37,
            additions: ["cursor": "next-page"]
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_list_declarations",
            arguments: [
                "app_id": .string("app-1"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(try exportComplianceQuery(request)["limit"] == "37")

        let mismatchTransport = TestHTTPTransport(responses: [])
        let mismatchWorker = try await exportComplianceWorker(apiTransport: mismatchTransport)
        let mismatch = try await mismatchWorker.handleTool(.init(
            name: "export_compliance_list_declarations",
            arguments: [
                "app_id": .string("app-1"),
                "limit": .int(25),
                "next_url": .string(nextURL)
            ]
        ))
        #expect(mismatch.isError == true)
        #expect(await mismatchTransport.requestCount() == 0)
    }

    @Test("declaration create sends exact required questionnaire body")
    func createDeclarationContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_create_declaration",
            arguments: [
                "app_id": .string("app-1"),
                "app_description": .string("Encrypted collaboration"),
                "contains_proprietary_cryptography": .bool(true),
                "contains_third_party_cryptography": .bool(false),
                "available_on_french_store": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appEncryptionDeclarations")
        let data = try exportComplianceBodyData(request)
        #expect(data["type"] as? String == "appEncryptionDeclarations")
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes.count == 4)
        #expect(attributes["appDescription"] as? String == "Encrypted collaboration")
        #expect(attributes["containsProprietaryCryptography"] as? Bool == true)
        #expect(attributes["containsThirdPartyCryptography"] as? Bool == false)
        #expect(attributes["availableOnFrenchStore"] as? Bool == true)
        let relationships = try exportComplianceDictionary(data["relationships"])
        let app = try exportComplianceDictionary(relationships["app"])
        let linkage = try exportComplianceDictionary(app["data"])
        #expect(linkage as NSDictionary == ["type": "apps", "id": "app-1"] as NSDictionary)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["creationState"] == .string("confirmed"))
        #expect(payload["commitConfirmed"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("declaration create rejects nullable or nonboolean questionnaire answers")
    func createDeclarationStrictTypes() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        for invalid: Value in [.null, .string("true"), .int(1)] {
            let result = try await worker.handleTool(.init(
                name: "export_compliance_create_declaration",
                arguments: [
                    "app_id": .string("app-1"),
                    "app_description": .string("Encryption"),
                    "contains_proprietary_cryptography": .bool(false),
                    "contains_third_party_cryptography": .bool(false),
                    "available_on_french_store": invalid
                ]
            ))
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("declaration create distinguishes committed, unknown, and rejected outcomes")
    func createDeclarationMutationOutcomes() async throws {
        let malformedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{}"#)
        ])
        let malformedWorker = try await exportComplianceWorker(apiTransport: malformedTransport)
        let malformed = try await malformedWorker.handleTool(.init(
            name: "export_compliance_create_declaration",
            arguments: exportComplianceDeclarationCreateArguments()
        ))
        let malformedDetails = try exportComplianceErrorDetails(malformed)
        #expect(malformed.isError == true)
        #expect(malformedDetails["creationState"] == .string("committed_unverified"))
        #expect(malformedDetails["commitConfirmed"] == .bool(true))
        #expect(malformedDetails["retrySafe"] == .bool(false))
        let malformedInspection = try exportComplianceValueObject(malformedDetails["inspection"])
        #expect(malformedInspection["tool"] == .string("export_compliance_list_declarations"))

        for invalidID in ["", "   ", " declaration-1 "] {
            let identityTransport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 201,
                    body: exportComplianceDeclarationResponse(id: invalidID, state: "CREATED")
                )
            ])
            let identityWorker = try await exportComplianceWorker(apiTransport: identityTransport)
            let identity = try await identityWorker.handleTool(.init(
                name: "export_compliance_create_declaration",
                arguments: exportComplianceDeclarationCreateArguments()
            ))
            let identityDetails = try exportComplianceErrorDetails(identity)
            #expect(identityDetails["creationState"] == .string("committed_unverified"))
            #expect(identityDetails["commitConfirmed"] == .bool(true))
            #expect(identityDetails["retrySafe"] == .bool(false))
        }

        let unknownTransport = ExportComplianceScriptTransport(steps: [.networkFailure])
        let unknownWorker = try await exportComplianceWorker(apiTransport: unknownTransport)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "export_compliance_create_declaration",
            arguments: exportComplianceDeclarationCreateArguments()
        ))
        let unknownDetails = try exportComplianceErrorDetails(unknown)
        #expect(unknownDetails["creationState"] == .string("commit_unknown"))
        #expect(unknownDetails["commitConfirmed"] == .bool(false))
        #expect(unknownDetails["retrySafe"] == .bool(false))
        #expect(unknownDetails["inspection"] != nil)

        for statusCode in [408, 500] {
            let statusTransport = TestHTTPTransport(responses: [
                .init(statusCode: statusCode, body: exportComplianceAPIError(statusCode))
            ])
            let statusWorker = try await exportComplianceWorker(apiTransport: statusTransport)
            let statusResult = try await statusWorker.handleTool(.init(
                name: "export_compliance_create_declaration",
                arguments: exportComplianceDeclarationCreateArguments()
            ))
            let statusDetails = try exportComplianceErrorDetails(statusResult)
            #expect(statusDetails["creationState"] == .string("commit_unknown"))
            #expect(statusDetails["commitConfirmed"] == .bool(false))
            #expect(statusDetails["retrySafe"] == .bool(false))
        }

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 422, body: exportComplianceAPIError(422))
        ])
        let rejectedWorker = try await exportComplianceWorker(apiTransport: rejectedTransport)
        let rejected = try await rejectedWorker.handleTool(.init(
            name: "export_compliance_create_declaration",
            arguments: exportComplianceDeclarationCreateArguments()
        ))
        let rejectedDetails = try exportComplianceErrorDetails(rejected)
        #expect(rejectedDetails["creationState"] == .string("rejected"))
        #expect(rejectedDetails["commitConfirmed"] == .bool(false))
        #expect(rejectedDetails["retrySafe"] == .bool(true))
        #expect(rejectedDetails["inspection"] == nil)
    }

    @Test("document create preflights, reserves, transfers, commits, and polls one snapshot")
    func createDocumentContract() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl-1", state: "CREATED")),
            .init(statusCode: 404, body: exportComplianceAPIError(404)),
            .init(
                statusCode: 201,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            ),
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "UPLOAD_COMPLETE",
                    checksum: true
                )
            ),
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "COMPLETE",
                    checksum: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: transport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: [
                "declaration_id": .string("decl-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "PATCH", "GET"])
        #expect(await uploadTransport.requestCount() == 1)
        #expect(try exportComplianceEncodedPath(requests[0]) == "/v1/appEncryptionDeclarations/decl-1")
        #expect(try exportComplianceEncodedPath(requests[1]) == "/v1/appEncryptionDeclarations/decl-1/appEncryptionDeclarationDocument")
        #expect(requests[2].url?.path == "/v1/appEncryptionDeclarationDocuments")
        let data = try exportComplianceBodyData(requests[2])
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes["fileSize"] as? Int == 5)
        #expect(attributes["fileName"] as? String == fileURL.lastPathComponent)
        let commit = try exportComplianceBodyData(requests[3])
        let commitAttributes = try exportComplianceDictionary(commit["attributes"])
        #expect(commitAttributes["sourceFileChecksum"] as? String == exportComplianceHelloMD5)
        #expect(commitAttributes["uploaded"] as? Bool == true)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        exportComplianceExpectNoSecrets(result)
    }

    @Test("document create uploads the immutable snapshot when the source mutates with the same name and size")
    func createDocumentSameNameSameSizeMutation() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = ExportComplianceMutatingTransport(
            sourceURL: fileURL,
            replacement: Data("world".utf8),
            responses: [
                .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl-1", state: "CREATED")),
                .init(statusCode: 404, body: exportComplianceAPIError(404)),
                .init(
                    statusCode: 201,
                    body: exportComplianceDocumentResponse(
                        id: "document-1",
                        fileName: fileURL.lastPathComponent,
                        state: "AWAITING_UPLOAD",
                        uploadOperations: true,
                        includeSecrets: true
                    )
                ),
                .init(
                    statusCode: 200,
                    body: exportComplianceDocumentResponse(
                        id: "document-1",
                        fileName: fileURL.lastPathComponent,
                        state: "COMPLETE",
                        checksum: true
                    )
                )
            ]
        )
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: transport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: [
                "declaration_id": .string("decl-1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let uploaded = try #require(await uploadTransport.recordedRequests().first?.httpBody)
        #expect(uploaded == Data("hello".utf8))
        #expect(try Data(contentsOf: fileURL) == Data("world".utf8))
    }

    @Test("document create blocks duplicate reservation before POST")
    func createDocumentDuplicatePreflight() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl-1", state: "CREATED")),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: fileURL.lastPathComponent, state: "AWAITING_UPLOAD"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: ["declaration_id": .string("decl-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError == true)
        #expect(await transport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])
        #expect(exportComplianceText(result).contains("already has a document reservation"))
    }

    @Test("document reservation uncertainty never invites a duplicate create")
    func createDocumentMutationOutcomes() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let arguments: [String: Value] = [
            "declaration_id": .string("declaration-1"),
            "file_path": .string(fileURL.path)
        ]

        let malformedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
            .init(statusCode: 404, body: exportComplianceAPIError(404)),
            .init(statusCode: 201, body: #"{}"#)
        ])
        let malformedWorker = try await exportComplianceWorker(apiTransport: malformedTransport)
        let malformed = try await malformedWorker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: arguments
        ))
        let malformedPayload = try exportComplianceObject(malformed.structuredContent)
        #expect(malformedPayload["reservationState"] == .string("unknown"))
        #expect(malformedPayload["retrySafe"] == .bool(false))
        #expect(malformedPayload["inspection"] != nil)
        #expect(malformedPayload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))

        for invalidID in ["", "   ", " document-1 "] {
            let identityTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
                .init(statusCode: 404, body: exportComplianceAPIError(404)),
                .init(
                    statusCode: 201,
                    body: exportComplianceDocumentResponse(
                        id: invalidID,
                        fileName: fileURL.lastPathComponent,
                        state: "AWAITING_UPLOAD"
                    )
                )
            ])
            let identityWorker = try await exportComplianceWorker(apiTransport: identityTransport)
            let identity = try await identityWorker.handleTool(.init(
                name: "export_compliance_create_document",
                arguments: arguments
            ))
            let identityPayload = try exportComplianceObject(identity.structuredContent)
            #expect(identityPayload["reservationState"] == .string("unknown"))
            #expect(identityPayload["retrySafe"] == .bool(false))
            #expect(identityPayload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))
        }

        let unknownTransport = ExportComplianceScriptTransport(steps: [
            .response(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
            .response(statusCode: 404, body: exportComplianceAPIError(404)),
            .networkFailure
        ])
        let unknownWorker = try await exportComplianceWorker(apiTransport: unknownTransport)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: arguments
        ))
        let unknownPayload = try exportComplianceObject(unknown.structuredContent)
        #expect(unknownPayload["reservationState"] == .string("unknown"))
        #expect(unknownPayload["retrySafe"] == .bool(false))
        #expect(unknownPayload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))
        let unknownInspection = try exportComplianceValueObject(unknownPayload["inspection"])
        #expect(unknownInspection["tool"] == .string("export_compliance_inspect_document"))

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
            .init(statusCode: 404, body: exportComplianceAPIError(404)),
            .init(statusCode: 422, body: exportComplianceAPIError(422))
        ])
        let rejectedWorker = try await exportComplianceWorker(apiTransport: rejectedTransport)
        let rejected = try await rejectedWorker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: arguments
        ))
        let rejectedPayload = try exportComplianceObject(rejected.structuredContent)
        #expect(rejectedPayload["reservationState"] == .string("rejected"))
        #expect(rejectedPayload["reservationCreated"] == .bool(false))
        #expect(rejectedPayload["retrySafe"] == .bool(true))
        #expect(rejectedPayload["inspection"] == nil)
        #expect(rejectedPayload["sourceFileChecksumReceipt"] == nil)
    }

    @Test("document create fails closed before signed upload for missing or future reservation state")
    func createDocumentUnknownReservationState() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        for state in [nil, "FUTURE_STATE"] as [String?] {
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
                .init(statusCode: 404, body: exportComplianceAPIError(404)),
                .init(
                    statusCode: 201,
                    body: exportComplianceDocumentResponse(
                        id: "document-1",
                        fileName: fileURL.lastPathComponent,
                        state: state,
                        uploadOperations: true,
                        includeSecrets: true
                    )
                )
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await exportComplianceWorker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(.init(
                name: "export_compliance_create_document",
                arguments: [
                    "declaration_id": .string("declaration-1"),
                    "file_path": .string(fileURL.path)
                ]
            ))

            #expect(result.isError == true)
            #expect(await uploadTransport.requestCount() == 0)
            let payload = try exportComplianceObject(result.structuredContent)
            #expect(payload["retrySafe"] == .bool(false))
            #expect(payload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))
            #expect(payload["nextAction"] == nil)
        }
    }

    @Test("document create rejects conflicting reservation checksum bindings before transfer")
    func createDocumentChecksumBindingConflict() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        for state in [nil, "AWAITING_UPLOAD", "UPLOAD_COMPLETE", "FAILED", "FUTURE_STATE"] as [String?] {
            for storedChecksum in ["7d793037a0760186574b0282f2f435e7", "INVALID"] {
                let apiTransport = TestHTTPTransport(responses: [
                    .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
                    .init(statusCode: 404, body: exportComplianceAPIError(404)),
                    .init(
                        statusCode: 201,
                        body: exportComplianceDocumentResponse(
                            id: "document-1",
                            fileName: fileURL.lastPathComponent,
                            state: state,
                            uploadOperations: true,
                            includeSecrets: true,
                            sourceFileChecksum: storedChecksum
                        )
                    )
                ])
                let uploadTransport = TestHTTPTransport(responses: [])
                let worker = try await exportComplianceWorker(
                    apiTransport: apiTransport,
                    uploadTransport: uploadTransport
                )
                let result = try await worker.handleTool(.init(
                    name: "export_compliance_create_document",
                    arguments: [
                        "declaration_id": .string("declaration-1"),
                        "file_path": .string(fileURL.path)
                    ]
                ))

                #expect(result.isError == true)
                #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET", "POST"])
                #expect(await uploadTransport.requestCount() == 0)
                let payload = try exportComplianceObject(result.structuredContent)
                #expect(payload["retrySafe"] == .bool(false))
                #expect(payload["checksumBindingConflict"] == .bool(true))
                #expect(payload["sourceFileChecksumReceipt"] == nil)
                #expect(payload["nextAction"] == nil)
                #expect(payload["inspection"] != nil)
                exportComplianceExpectNoSecrets(result)
            }
        }
    }

    @Test("document read redacts download and upload secrets")
    func getDocumentRedaction() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: "export.pdf",
                    state: "COMPLETE",
                    uploadOperations: true,
                    includeSecrets: true,
                    includeDeliverySecrets: true
                )
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_get_document",
            arguments: ["document_id": .string("document-1")]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let query = try exportComplianceQuery(request)
        #expect(query["fields[appEncryptionDeclarationDocuments]"] == exportComplianceTestDocumentReadFields)
        let payload = try exportComplianceObject(result.structuredContent)
        let document = try exportComplianceValueObject(payload["document"])
        #expect(document["downloadAvailable"] == .bool(true))
        #expect(document["downloadURLRedacted"] == .bool(true))
        exportComplianceExpectNoSecrets(result)
    }

    @Test("document projection omits availability claims for fields absent from Apple's response")
    func getDocumentProjectionOmission() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: "export.pdf",
                    state: "COMPLETE"
                )
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_get_document",
            arguments: ["document_id": .string("document-1")]
        ))

        let payload = try exportComplianceObject(result.structuredContent)
        let document = try exportComplianceValueObject(payload["document"])
        for field in [
            "downloadAvailable",
            "downloadURLRedacted",
            "assetTokenPresent",
            "uploadOperationsAvailable",
            "uploadOperationCount",
            "uploadMetadataRedacted"
        ] {
            #expect(document[field] == nil)
        }
    }

    @Test("document update preserves explicit null and rejects empty patches")
    func updateDocumentTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "doc-1", fileName: "export.pdf", state: "AWAITING_UPLOAD"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: [
                "document_id": .string("doc-1"),
                "source_file_checksum": .null,
                "uploaded": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(try exportComplianceEncodedPath(request) == "/v1/appEncryptionDeclarationDocuments/doc-1")
        let data = try exportComplianceBodyData(request)
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes.keys.sorted() == ["sourceFileChecksum", "uploaded"])
        #expect(attributes["sourceFileChecksum"] is NSNull)
        #expect(attributes["uploaded"] is NSNull)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["updateState"] == .string("confirmed"))
        #expect(payload["commitConfirmed"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))

        let emptyTransport = TestHTTPTransport(responses: [])
        let emptyWorker = try await exportComplianceWorker(apiTransport: emptyTransport)
        let empty = try await emptyWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: ["document_id": .string("document-1")]
        ))
        #expect(empty.isError == true)
        #expect(await emptyTransport.requestCount() == 0)

        let whitespaceTransport = TestHTTPTransport(responses: [])
        let whitespaceWorker = try await exportComplianceWorker(apiTransport: whitespaceTransport)
        let whitespaceID = try await whitespaceWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: [
                "document_id": .string(" document-1 "),
                "uploaded": .bool(true)
            ]
        ))
        #expect(whitespaceID.isError == true)
        #expect(await whitespaceTransport.requestCount() == 0)
    }

    @Test("nullable document update schema states wire behavior without reversal promises")
    func updateDocumentNullableSchemaWording() async throws {
        let worker = try await exportComplianceWorker(apiTransport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let tool = try #require(tools.first {
            $0.name == "export_compliance_update_document"
        })
        let schema = try exportComplianceValueObject(tool.inputSchema)
        let properties = try exportComplianceValueObject(schema["properties"])
        for field in ["source_file_checksum", "uploaded"] {
            let fieldSchema = try exportComplianceValueObject(properties[field])
            let description = try #require(fieldSchema["description"]?.stringValue)
            #expect(description.contains("JSON null"))
            #expect(!description.lowercased().contains("clear"))
            #expect(!description.lowercased().contains("revers"))
        }
    }

    @Test("document update distinguishes committed, unknown, and rejected outcomes")
    func updateDocumentMutationOutcomes() async throws {
        let arguments: [String: Value] = [
            "document_id": .string("document-1"),
            "uploaded": .bool(true)
        ]

        let malformedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{}"#)
        ])
        let malformedWorker = try await exportComplianceWorker(apiTransport: malformedTransport)
        let malformed = try await malformedWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: arguments
        ))
        let malformedDetails = try exportComplianceErrorDetails(malformed)
        #expect(malformedDetails["updateState"] == .string("committed_unverified"))
        #expect(malformedDetails["commitConfirmed"] == .bool(true))
        #expect(malformedDetails["retrySafe"] == .bool(false))
        let malformedInspection = try exportComplianceValueObject(malformedDetails["inspection"])
        #expect(malformedInspection["tool"] == .string("export_compliance_get_document"))

        let unknownTransport = ExportComplianceScriptTransport(steps: [.networkFailure])
        let unknownWorker = try await exportComplianceWorker(apiTransport: unknownTransport)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: arguments
        ))
        let unknownDetails = try exportComplianceErrorDetails(unknown)
        #expect(unknownDetails["updateState"] == .string("commit_unknown"))
        #expect(unknownDetails["commitConfirmed"] == .bool(false))
        #expect(unknownDetails["retrySafe"] == .bool(false))
        #expect(unknownDetails["inspection"] != nil)

        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 422, body: exportComplianceAPIError(422))
        ])
        let rejectedWorker = try await exportComplianceWorker(apiTransport: rejectedTransport)
        let rejected = try await rejectedWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: arguments
        ))
        let rejectedDetails = try exportComplianceErrorDetails(rejected)
        #expect(rejectedDetails["updateState"] == .string("rejected"))
        #expect(rejectedDetails["commitConfirmed"] == .bool(false))
        #expect(rejectedDetails["retrySafe"] == .bool(true))
        #expect(rejectedDetails["inspection"] == nil)
    }

    @Test("document upload transfers exact snapshot, commits checksum, and reaches COMPLETE")
    func uploadDocumentComplete() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            ),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: fileURL.lastPathComponent, state: "COMPLETE", checksum: true))
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "PATCH"])
        #expect(await uploadTransport.requestCount() == 1)
        let patchRequest = try #require(await apiTransport.recordedRequests().last)
        let data = try exportComplianceBodyData(patchRequest)
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes["sourceFileChecksum"] as? String == "5d41402abc4b2a76b9719d911017c592")
        #expect(attributes["uploaded"] as? Bool == true)
        exportComplianceExpectNoSecrets(result)
    }

    @Test("document upload requires an exact lowercase MD5 receipt before network")
    func uploadDocumentChecksumValidation() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let schemaWorker = try await exportComplianceWorker(
            apiTransport: TestHTTPTransport(responses: [])
        )
        let schemaTools = await schemaWorker.getTools()
        let uploadTool = try #require(schemaTools.first {
            $0.name == "export_compliance_upload_document"
        })
        let schema = try exportComplianceValueObject(uploadTool.inputSchema)
        guard case .array(let required)? = schema["required"] else {
            Issue.record("Expected upload required-fields array")
            throw ExportComplianceTestError.expectedObject
        }
        #expect(required.compactMap(\.stringValue).contains("source_file_checksum"))
        let properties = try exportComplianceValueObject(schema["properties"])
        let checksumSchema = try exportComplianceValueObject(properties["source_file_checksum"])
        #expect(checksumSchema["pattern"] == .string("^[0-9a-f]{32}$"))

        for checksum in [nil, exportComplianceHelloMD5.uppercased(), "abc"] as [String?] {
            let apiTransport = TestHTTPTransport(responses: [])
            let worker = try await exportComplianceWorker(apiTransport: apiTransport)
            var arguments: [String: Value] = [
                "document_id": .string("document-1"),
                "file_path": .string(fileURL.path)
            ]
            if let checksum {
                arguments["source_file_checksum"] = .string(checksum)
            }
            let result = try await worker.handleTool(.init(
                name: "export_compliance_upload_document",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await apiTransport.requestCount() == 0)
        }
    }

    @Test("document upload rejects same-name same-size bytes that do not match the receipt")
    func uploadDocumentChecksumMismatch() async throws {
        let fileURL = try exportComplianceFile(Data("world".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["checksumBindingConflict"] == .bool(true))
        #expect(payload["sourceFileChecksumReceipt"] == nil)
        #expect(payload["nextAction"] == nil)
        #expect(payload["inspection"] != nil)
    }

    @Test("document upload requires the checksum already stored by Apple")
    func uploadDocumentStoredChecksumMismatch() async throws {
        let fileURL = try exportComplianceFile(Data("world".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true,
                    checksum: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(
                fileURL,
                checksum: "7d793037a0760186574b0282f2f435e7"
            )
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["checksumBindingConflict"] == .bool(true))
        #expect(payload["sourceFileChecksumReceipt"] == nil)
        #expect(payload["nextAction"] == nil)
        #expect(payload["inspection"] != nil)
    }

    @Test("document upload can correct a caller receipt from a matching Apple binding")
    func uploadDocumentStoredChecksumCorrectsCallerReceipt() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true,
                    checksum: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(
                fileURL,
                checksum: "7d793037a0760186574b0282f2f435e7"
            )
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["checksumBindingConflict"] == nil)
        #expect(payload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))
        let nextAction = try exportComplianceValueObject(payload["nextAction"])
        let arguments = try exportComplianceValueObject(nextAction["arguments"])
        #expect(arguments["source_file_checksum"] == .string(exportComplianceHelloMD5))
    }

    @Test("document upload fails closed for an invalid checksum stored by Apple")
    func uploadDocumentInvalidStoredChecksum() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true,
                    sourceFileChecksum: "INVALID"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        let details = try exportComplianceErrorDetails(result)
        #expect(details["retrySafe"] == .bool(false))
        #expect(details["checksumBindingConflict"] == .bool(true))
        #expect(details["sourceFileChecksumReceipt"] == nil)
        #expect(details["nextAction"] == nil)
        #expect(details["inspection"] != nil)
        #expect(payload["details"] != nil)
    }

    @Test("missing upload operations retain reservation without DELETE")
    func uploadDocumentRetainsWithoutDelete() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: fileURL.lastPathComponent, state: "AWAITING_UPLOAD"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: apiTransport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try exportComplianceValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("unavailable"))
        #expect(cleanup["tool"] == nil)
        #expect(payload["sourceFileChecksumReceipt"] == .string(exportComplianceHelloMD5))
        #expect(payload["nextAction"] != nil)
    }

    @Test("document upload rejects a snapshot that does not match the reservation")
    func uploadDocumentSnapshotMismatch() async throws {
        let fileURL = try exportComplianceFile(Data("changed bytes".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: "reserved.pdf",
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        let cleanup = try exportComplianceValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("unavailable"))
        #expect(payload["retrySafe"] == .bool(false))
        exportComplianceExpectNoSecrets(result)
    }

    @Test("UPLOAD_COMPLETE reservation is retained as committed processing")
    func uploadDocumentAlreadyCommitted() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "UPLOAD_COMPLETE",
                    includeSecrets: true
                )
            ),
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "COMPLETE",
                    checksum: true
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["alreadyCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(true))
        exportComplianceExpectNoSecrets(result)
    }

    @Test("UPLOAD_COMPLETE polling fails closed when Apple returns an unknown state")
    func uploadDocumentCommittedPollUnknownState() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "UPLOAD_COMPLETE"
                )
            ),
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "FUTURE_STATE"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let details = try exportComplianceErrorDetails(result)
        #expect(details["retrySafe"] == .bool(false))
        #expect(details["inspection"] != nil)
    }

    @Test("document upload fails closed for missing or future states without signed transfer")
    func uploadDocumentUnknownState() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        for state in [nil, "FUTURE_STATE"] as [String?] {
            let apiTransport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: exportComplianceDocumentResponse(
                        id: "document-1",
                        fileName: fileURL.lastPathComponent,
                        state: state,
                        uploadOperations: true,
                        includeSecrets: true
                    )
                )
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await exportComplianceWorker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(.init(
                name: "export_compliance_upload_document",
                arguments: exportComplianceUploadArguments(fileURL)
            ))

            #expect(result.isError == true)
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
            #expect(await uploadTransport.requestCount() == 0)
            let payload = try exportComplianceObject(result.structuredContent)
            let details = try exportComplianceValueObject(payload["details"])
            #expect(details["retrySafe"] == .bool(false))
            #expect(details["inspection"] != nil)
        }
    }

    @Test("ambiguous document commit reconciles with GET and does not leak secrets")
    func uploadDocumentAmbiguousCommit() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ExportComplianceScriptTransport(steps: [
            .response(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            ),
            .networkFailure,
            .response(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: fileURL.lastPathComponent, state: "COMPLETE", checksum: true))
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "PATCH", "GET"])
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["reconciledAfterCommit"] == .bool(true))
        exportComplianceExpectNoSecrets(result)
    }

    @Test("post-commit FAILED guidance uses App Store Connect or Apple Support without deletion advice")
    func uploadDocumentPostCommitFailedGuidance() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            ),
            .init(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "FAILED"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "PATCH"])
        try exportComplianceExpectSupportOnlyRetentionGuidance(result)
    }

    @Test("unresolved document commit guidance uses App Store Connect or Apple Support without deletion advice")
    func uploadDocumentCommitUnresolvedGuidance() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ExportComplianceScriptTransport(steps: [
            .response(
                statusCode: 200,
                body: exportComplianceDocumentResponse(
                    id: "document-1",
                    fileName: fileURL.lastPathComponent,
                    state: "AWAITING_UPLOAD",
                    uploadOperations: true,
                    includeSecrets: true
                )
            ),
            .networkFailure,
            .networkFailure
        ])
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "PATCH", "GET"])
        try exportComplianceExpectSupportOnlyRetentionGuidance(result)
    }

    @Test("terminal FAILED document never retries transfer")
    func uploadDocumentFailedState() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: fileURL.lastPathComponent, state: "FAILED"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: exportComplianceUploadArguments(fileURL)
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        #expect(exportComplianceText(result).contains("no document delete operation"))
    }

    @Test("inspect and build relationship translate 404 only after confirming each parent")
    func absenceSemantics() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "CREATED")),
            .init(statusCode: 404, body: exportComplianceAPIError(404)),
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 404, body: exportComplianceAPIError(404))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let document = try await worker.handleTool(.init(
            name: "export_compliance_inspect_document",
            arguments: ["declaration_id": .string("declaration-1")]
        ))
        let build = try await worker.handleTool(.init(
            name: "export_compliance_get_build_declaration",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(try exportComplianceObject(document.structuredContent)["documentPresent"] == .bool(false))
        #expect(try exportComplianceObject(build.structuredContent)["declarationAttached"] == .bool(false))
        #expect(await transport.recordedRequests().map(\.httpMethod) == ["GET", "GET", "GET", "GET"])
    }

    @Test("invalid declaration and build parents are errors rather than absent relationships")
    func invalidParentSemantics() async throws {
        let declarationTransport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: exportComplianceAPIError(404))
        ])
        let declarationWorker = try await exportComplianceWorker(apiTransport: declarationTransport)
        let document = try await declarationWorker.handleTool(.init(
            name: "export_compliance_inspect_document",
            arguments: ["declaration_id": .string("missing-declaration")]
        ))
        #expect(document.isError == true)
        #expect(await declarationTransport.requestCount() == 1)

        let buildTransport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: exportComplianceAPIError(404))
        ])
        let buildWorker = try await exportComplianceWorker(apiTransport: buildTransport)
        let declaration = try await buildWorker.handleTool(.init(
            name: "export_compliance_get_build_declaration",
            arguments: ["build_id": .string("missing-build")]
        ))
        #expect(declaration.isError == true)
        #expect(await buildTransport.requestCount() == 1)
    }

    @Test("attachment preflights approval and document, patches exact linkage, then verifies")
    func attachBuildDeclarationContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl-1", state: "APPROVED")),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE")),
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true, id: "build-1")),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl-1", state: "APPROVED"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_attach_build_declaration",
            arguments: ["build_id": .string("build-1"), "declaration_id": .string("decl-1")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        #expect(try exportComplianceEncodedPath(requests[2]) == "/v1/builds/build-1")
        let body = try exportComplianceJSONObject(requests[2])
        #expect(body as NSDictionary == [
            "data": [
                "type": "builds",
                "id": "build-1",
                "relationships": [
                    "appEncryptionDeclaration": [
                        "data": ["type": "appEncryptionDeclarations", "id": "decl-1"]
                    ]
                ]
            ]
        ] as NSDictionary)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["attachmentVerified"] == .bool(true))
    }

    @Test("attachment manifest uses Apple's nondeprecated build update replacement")
    func attachBuildDeclarationManifestReplacement() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mapping = try #require(manifest.mapping(for: "export_compliance_attach_build_declaration"))
        let operationIDs = Set(mapping.operations.map(\.operationID))

        #expect(operationIDs.contains("builds_updateInstance"))
        #expect(!operationIDs.contains("builds_appEncryptionDeclaration_updateToOneRelationship"))
        #expect(mapping.note?.contains("https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-builds-_id_") == true)
        #expect(mapping.note?.contains("https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-builds-_id_-relationships-appencryptiondeclaration") == true)
        let directPatchWaiver = try #require(manifest.index.waivers.first {
            $0.operationID == "builds_appEncryptionDeclaration_updateToOneRelationship"
        })
        #expect(directPatchWaiver.reason.contains("Pinned Apple OpenAPI 4.4.1 omits a deprecated flag"))
        #expect(directPatchWaiver.reason.contains("current Apple DocC marks"))
        #expect(directPatchWaiver.reason.contains("builds_updateInstance"))
        let declarationBuildsWaiver = try #require(manifest.index.waivers.first {
            $0.operationID == "appEncryptionDeclarations_builds_createToManyRelationship"
        })
        #expect(declarationBuildsWaiver.reason.contains("OpenAPI 4.4.1 marks"))
        #expect(declarationBuildsWaiver.reason.contains("deprecated"))
        #expect(declarationBuildsWaiver.reason.contains("builds_updateInstance"))
    }

    @Test("document and relationship manifests describe compound safety prerequisites")
    func compoundSafetyManifestContract() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()

        let create = try #require(manifest.mapping(for: "export_compliance_create_document"))
        #expect(create.kind.rawValue == "compound")
        let createOperations = Set(create.operations.map(\.operationID))
        #expect(createOperations.contains("appEncryptionDeclarationDocuments_createInstance"))
        #expect(createOperations.contains("appEncryptionDeclarationDocuments_updateInstance"))
        #expect(createOperations.contains("appEncryptionDeclarationDocuments_getInstance"))

        let inspect = try #require(manifest.mapping(for: "export_compliance_inspect_document"))
        #expect(inspect.kind.rawValue == "compound")
        #expect(inspect.operations.first?.operationID == "appEncryptionDeclarations_getInstance")

        let build = try #require(manifest.mapping(for: "export_compliance_get_build_declaration"))
        #expect(build.kind.rawValue == "compound")
        #expect(build.operations.first?.operationID == "builds_getInstance")

        let upload = try #require(manifest.mapping(for: "export_compliance_upload_document"))
        let checksum = try #require(upload.fields.first {
            $0.toolField == "source_file_checksum"
        })
        #expect(checksum.operationID == "appEncryptionDeclarationDocuments_updateInstance")
        #expect(checksum.jsonPointer == "/data/attributes/sourceFileChecksum")
    }

    @Test("ambiguous build update reconciles the intended declaration")
    func attachBuildDeclarationAmbiguousUpdate() async throws {
        let transport = ExportComplianceScriptTransport(steps: [
            .response(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED")),
            .response(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE")),
            .networkFailure,
            .response(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_attach_build_declaration",
            arguments: ["build_id": .string("build-1"), "declaration_id": .string("declaration-1")]
        ))

        #expect(result.isError != true)
        #expect(await transport.recordedRequests().map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["attachmentVerified"] == .bool(true))
        #expect(payload["reconciledAfterUpdate"] == .bool(true))
    }

    @Test("attachment does not mutate before APPROVED and COMPLETE preflight")
    func attachBuildDeclarationPreflight() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "IN_REVIEW"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_attach_build_declaration",
            arguments: ["build_id": .string("build-1"), "declaration_id": .string("declaration-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(exportComplianceText(result).contains("APPROVED"))
    }

    @Test("successful attachment with failed verification is never partial success")
    func attachBuildDeclarationUnverified() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED")),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE")),
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 500, body: exportComplianceAPIError(500))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_attach_build_declaration",
            arguments: ["build_id": .string("build-1"), "declaration_id": .string("declaration-1")]
        ))

        #expect(result.isError == true)
        let payload = try exportComplianceObject(result.structuredContent)
        let details = try exportComplianceValueObject(payload["details"])
        #expect(details["attachmentState"] == .string("unverified"))
        #expect(details["retrySafe"] == .bool(false))
    }

    @Test("false non-exempt answer is READY without declaration lookup")
    func readinessExemptBuild() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: false))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["scope"] == .string("EXPORT_COMPLIANCE_ONLY"))
        #expect(payload["status"] == .string("READY"))
        #expect(payload["exportComplianceReady"] == .bool(true))
        #expect(payload["releaseReady"] == nil)
        #expect(payload["appStoreSubmissionStatus"] == .string("NOT_DETERMINED"))
    }

    @Test("build processing and expiration are informational for export compliance")
    func readinessIgnoresNonExportBuildState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: exportComplianceBuildResponse(
                    usesNonExemptEncryption: false,
                    processingState: "FAILED",
                    expired: true
                )
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["status"] == .string("READY"))
        #expect(payload["exportComplianceReady"] == .bool(true))
        #expect(payload["appStoreSubmissionStatus"] == .string("NOT_DETERMINED"))
    }

    @Test("true non-exempt answer with no declaration is BLOCKED")
    func readinessMissingDeclaration() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 404, body: exportComplianceAPIError(404))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["status"] == .string("BLOCKED"))
        #expect(payload["exportComplianceReady"] == .bool(false))
        #expect(payload["declarationAttached"] == .bool(false))
    }

    @Test("approved declaration with COMPLETE document satisfies non-exempt gate")
    func readinessApprovedComplete() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["status"] == .string("READY"))
        #expect(payload["exportComplianceReady"] == .bool(true))
        #expect(payload["declarationAttached"] == .bool(true))
        #expect(payload["documentPresent"] == .bool(true))
    }

    @Test("pending, failed, missing, and future document states never pass", arguments: [
        ("AWAITING_UPLOAD", "BLOCKED"),
        ("UPLOAD_COMPLETE", "PENDING"),
        ("FAILED", "BLOCKED"),
        ("FUTURE_STATE", "BLOCKED")
    ])
    func readinessDocumentStates(_ state: String, _ expected: String) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: state))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["status"] == .string(expected))
        #expect(payload["exportComplianceReady"] == .bool(false))
    }

    @Test("readiness emits state-specific executable document actions")
    func readinessDocumentActions() async throws {
        let awaitingTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "AWAITING_UPLOAD"))
        ])
        let awaitingWorker = try await exportComplianceWorker(apiTransport: awaitingTransport)
        let awaitingResult = try await awaitingWorker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        let awaitingAction = try exportComplianceFirstAction(awaitingResult)
        #expect(awaitingAction["tool"] == .string("export_compliance_upload_document"))
        let awaitingArguments = try exportComplianceValueObject(awaitingAction["arguments"])
        #expect(awaitingArguments["file_path"] != nil)
        #expect(awaitingArguments["source_file_checksum"] != nil)

        let committedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "UPLOAD_COMPLETE"))
        ])
        let committedWorker = try await exportComplianceWorker(apiTransport: committedTransport)
        let committedResult = try await committedWorker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        let committedAction = try exportComplianceFirstAction(committedResult)
        #expect(committedAction["tool"] == .string("export_compliance_inspect_document"))
    }

    @Test("missing document suggests creation only in mutable declaration states")
    func readinessMissingDocumentActions() async throws {
        for (state, expectedTool) in [("CREATED", "export_compliance_create_document"), ("APPROVED", nil)] as [(String, String?)] {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
                .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: state, exempt: false)),
                .init(statusCode: 404, body: exportComplianceAPIError(404))
            ])
            let worker = try await exportComplianceWorker(apiTransport: transport)
            let result = try await worker.handleTool(.init(
                name: "export_compliance_check_release_readiness",
                arguments: ["build_id": .string("build-1")]
            ))
            let action = try exportComplianceFirstAction(result)
            #expect(action["tool"]?.stringValue == expectedTool)
        }
    }

    @Test("missing document delivery state fails closed")
    func readinessNilDocumentState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: nil))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["status"] == .string("BLOCKED"))
        #expect(payload["exportComplianceReady"] == .bool(false))
    }

    @Test("nullable encryption answer and future declaration state remain BLOCKED")
    func readinessUnknownStates() async throws {
        let nilTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: nil))
        ])
        let nilWorker = try await exportComplianceWorker(apiTransport: nilTransport)
        let nilResult = try await nilWorker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        let nilPayload = try exportComplianceObject(nilResult.structuredContent)
        #expect(nilPayload["status"] == .string("BLOCKED"))
        let encryptionAction = try exportComplianceFirstAction(nilResult)
        #expect(encryptionAction["tool"] == .string("builds_update_encryption"))
        let encryptionArguments = try exportComplianceValueObject(encryptionAction["arguments"])
        #expect(encryptionArguments["uses_non_exempt_encryption"] == .string("<true-or-false>"))

        let futureTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "FUTURE_STATE", exempt: false)),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE"))
        ])
        let futureWorker = try await exportComplianceWorker(apiTransport: futureTransport)
        let futureResult = try await futureWorker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        #expect(try exportComplianceObject(futureResult.structuredContent)["status"] == .string("BLOCKED"))

        let nilExemptTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true)),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "declaration-1", state: "APPROVED")),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE"))
        ])
        let nilExemptWorker = try await exportComplianceWorker(apiTransport: nilExemptTransport)
        let nilExemptResult = try await nilExemptWorker.handleTool(.init(
            name: "export_compliance_check_release_readiness",
            arguments: ["build_id": .string("build-1")]
        ))
        #expect(try exportComplianceObject(nilExemptResult.structuredContent)["status"] == .string("BLOCKED"))
    }

    @Test("legacy build readiness no longer treats true encryption answer as declaration proof")
    func legacyReadinessIsConservative() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true))
        ])
        let worker = BuildProcessingWorker(httpClient: try await exportComplianceClient(transport))
        let result = try await worker.handleTool(.init(
            name: "builds_check_readiness",
            arguments: ["build_id": .string("build-1")]
        ))

        let payload = try exportComplianceObject(result.structuredContent)
        let readiness = try exportComplianceValueObject(payload["readiness"])
        #expect(readiness["encryptionDeclarationRecorded"] == .bool(false))
        #expect(readiness["buildPrerequisitesSatisfied"] == .bool(false))
        #expect(exportComplianceText(result).contains("export_compliance_check_release_readiness"))
    }
}

private let exportComplianceTestDeclarationFields = "appDescription,createdDate,exempt,containsProprietaryCryptography,containsThirdPartyCryptography,availableOnFrenchStore,appEncryptionDeclarationState,codeValue,appEncryptionDeclarationDocument"
private let exportComplianceTestDocumentReadFields = "fileSize,fileName,downloadUrl,sourceFileChecksum,assetDeliveryState"
private let exportComplianceHelloMD5 = "5d41402abc4b2a76b9719d911017c592"

private func exportComplianceWorker(
    apiTransport: any HTTPTransport,
    uploadTransport: any HTTPTransport = TestHTTPTransport(responses: [])
) async throws -> ExportComplianceWorker {
    ExportComplianceWorker(
        httpClient: try await exportComplianceClient(apiTransport),
        uploadService: UploadService(transport: uploadTransport, batchSize: 1),
        deliveryPollAttempts: 2,
        deliveryPollIntervalNanoseconds: 0
    )
}

private func exportComplianceClient(_ transport: any HTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func exportComplianceDeclarationResponse(
    id: String,
    state: String,
    exempt: Bool? = nil
) -> String {
    let exemptValue = exempt.map { String($0) } ?? "null"
    return #"{"data":{"type":"appEncryptionDeclarations","id":"\#(id)","attributes":{"appDescription":"Encrypted app","createdDate":"2026-07-20T00:00:00Z","exempt":\#(exemptValue),"containsProprietaryCryptography":true,"containsThirdPartyCryptography":false,"availableOnFrenchStore":true,"appEncryptionDeclarationState":"\#(state)","codeValue":"CCATS-1"}}}"#
}

private func exportComplianceDocumentResponse(
    id: String,
    fileName: String,
    state: String?,
    uploadOperations: Bool = false,
    includeSecrets: Bool = false,
    includeDeliverySecrets: Bool = false,
    checksum: Bool = false,
    sourceFileChecksum: String? = nil
) -> String {
    let stateValue = state.map { #""\#($0)""# } ?? "null"
    let operations = uploadOperations
        ? #","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk?signed=signed-secret","length":5,"offset":0,"requestHeaders":[{"name":"X-Amz-Security-Token","value":"header-secret"}]}]"#
        : ""
    let secrets = includeSecrets
        ? #","assetToken":"asset-secret","downloadUrl":"https://download.example.test/file?signed=download-secret""#
        : ""
    let effectiveChecksum = sourceFileChecksum ?? (checksum ? exportComplianceHelloMD5 : nil)
    let checksumValue = effectiveChecksum.map {
        #","sourceFileChecksum":"\#($0)""#
    } ?? ""
    let errors = includeDeliverySecrets
        ? #"[{"code":"UPLOAD_FAILED","description":"Retry https://upload.example.test/chunk?signed=signed-secret with token=header-secret"}]"#
        : "[]"
    return #"{"data":{"type":"appEncryptionDeclarationDocuments","id":"\#(id)","attributes":{"fileSize":5,"fileName":"\#(fileName)","assetDeliveryState":{"state":\#(stateValue),"errors":\#(errors),"warnings":[]}\#(operations)\#(secrets)\#(checksumValue)}}}"#
}

private func exportComplianceBuildResponse(
    usesNonExemptEncryption: Bool?,
    id: String = "build-1",
    processingState: String = "VALID",
    expired: Bool = false
) -> String {
    let encryption = usesNonExemptEncryption.map { String($0) } ?? "null"
    return #"{"data":{"type":"builds","id":"\#(id)","attributes":{"version":"42","processingState":"\#(processingState)","expired":\#(expired),"usesNonExemptEncryption":\#(encryption)},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
}

private func exportComplianceAPIError(_ status: Int) -> String {
    #"{"errors":[{"status":"\#(status)","code":"NOT_FOUND","title":"Not found","detail":"Resource not found"}]}"#
}

private func exportComplianceFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-mcp-export-compliance-\(UUID().uuidString).pdf")
    try data.write(to: url)
    return url
}

private func exportComplianceUploadArguments(
    _ fileURL: URL,
    checksum: String = exportComplianceHelloMD5
) -> [String: Value] {
    [
        "document_id": .string("document-1"),
        "file_path": .string(fileURL.path),
        "source_file_checksum": .string(checksum)
    ]
}

private func exportComplianceNextURL(
    appID: String,
    limit: Int,
    additions: [String: String]
) -> String {
    var components = URLComponents(string: "https://api.example.test")!
    components.percentEncodedPath = "/v1/apps/\(appID)/appEncryptionDeclarations"
    var parameters = [
        "fields[appEncryptionDeclarations]": exportComplianceTestDeclarationFields,
        "limit": String(limit)
    ]
    parameters.merge(additions) { _, new in new }
    components.queryItems = parameters.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    return components.url!.absoluteString
}

private func exportComplianceQuery(_ request: URLRequest) throws -> [String: String] {
    let components = try #require(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func exportComplianceEncodedPath(_ request: URLRequest) throws -> String {
    try #require(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)).percentEncodedPath
}

private func exportComplianceJSONObject(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func exportComplianceBodyData(_ request: URLRequest) throws -> [String: Any] {
    let object = try exportComplianceJSONObject(request)
    return try exportComplianceDictionary(object["data"])
}

private func exportComplianceDictionary(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func exportComplianceObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw ExportComplianceTestError.expectedObject
    }
    return object
}

private func exportComplianceValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected nested structured object")
        throw ExportComplianceTestError.expectedObject
    }
    return object
}

private func exportComplianceErrorDetails(_ result: CallTool.Result) throws -> [String: Value] {
    let payload = try exportComplianceObject(result.structuredContent)
    return try exportComplianceValueObject(payload["details"])
}

private func exportComplianceFirstAction(_ result: CallTool.Result) throws -> [String: Value] {
    let payload = try exportComplianceObject(result.structuredContent)
    guard case .array(let actions)? = payload["actions"],
          let first = actions.first else {
        Issue.record("Expected at least one readiness action")
        throw ExportComplianceTestError.expectedObject
    }
    return try exportComplianceValueObject(first)
}

private func exportComplianceDeclarationCreateArguments() -> [String: Value] {
    [
        "app_id": .string("app-1"),
        "app_description": .string("Encrypted collaboration"),
        "contains_proprietary_cryptography": .bool(true),
        "contains_third_party_cryptography": .bool(false),
        "available_on_french_store": .bool(true)
    ]
}

private func exportComplianceExpectSupportOnlyRetentionGuidance(
    _ result: CallTool.Result
) throws {
    let payload = try exportComplianceObject(result.structuredContent)
    let cleanup = try exportComplianceValueObject(payload["cleanup"])
    let reason = cleanup["reason"]?.stringValue ?? ""
    let guidance = "\(exportComplianceText(result))\n\(reason)"
    #expect(guidance.contains("App Store Connect") || guidance.contains("Apple Support"))
    #expect(!guidance.lowercased().contains("delet"))
    #expect(cleanup["tool"] == nil)
}

private func exportComplianceText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content { return text }
        return nil
    }.joined(separator: "\n")
}

private func exportComplianceExpectNoSecrets(_ result: CallTool.Result) {
    let text = exportComplianceText(result)
    #expect(!text.contains("signed-secret"))
    #expect(!text.contains("header-secret"))
    #expect(!text.contains("asset-secret"))
    #expect(!text.contains("download-secret"))
    #expect(!text.contains("X-Amz-Security-Token"))
}

private enum ExportComplianceTestError: Error {
    case expectedObject
}

private actor ExportComplianceScriptTransport: HTTPTransport {
    enum Step: Sendable {
        case response(statusCode: Int, body: String)
        case networkFailure
    }

    private var steps: [Step]
    private var requests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else {
            throw ASCError.network("No scripted response queued")
        }
        switch steps.removeFirst() {
        case .response(let statusCode, let body):
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.example.test")!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: [:]
                )!
            )
        case .networkFailure:
            throw URLError(.networkConnectionLost)
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor ExportComplianceMutatingTransport: HTTPTransport {
    private let sourceURL: URL
    private let replacement: Data
    private var responses: [TestHTTPTransport.Response]
    private var requests: [URLRequest] = []

    init(
        sourceURL: URL,
        replacement: Data,
        responses: [TestHTTPTransport.Response]
    ) {
        self.sourceURL = sourceURL
        self.replacement = replacement
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw ASCError.network("No mutating response queued")
        }
        let response = responses.removeFirst()
        if request.httpMethod == "POST",
           request.url?.path == "/v1/appEncryptionDeclarationDocuments" {
            try replacement.write(to: sourceURL)
        }
        return (
            response.data,
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.example.test")!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
        )
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
