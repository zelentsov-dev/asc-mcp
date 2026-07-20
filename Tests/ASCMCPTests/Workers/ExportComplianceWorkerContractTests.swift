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
            arguments: ["app_id": .string("app/one"), "limit": .int(37)]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(try exportComplianceEncodedPath(request) == "/v1/apps/app%2Fone/appEncryptionDeclarations")
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

    @Test("document create preflights state and absence, then reserves exact snapshot metadata")
    func createDocumentContract() async throws {
        let fileURL = try exportComplianceFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl/1", state: "CREATED")),
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
            )
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_create_document",
            arguments: [
                "declaration_id": .string("decl/1"),
                "file_path": .string(fileURL.path)
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST"])
        #expect(try exportComplianceEncodedPath(requests[0]) == "/v1/appEncryptionDeclarations/decl%2F1")
        #expect(try exportComplianceEncodedPath(requests[1]) == "/v1/appEncryptionDeclarations/decl%2F1/appEncryptionDeclarationDocument")
        #expect(requests[2].url?.path == "/v1/appEncryptionDeclarationDocuments")
        let data = try exportComplianceBodyData(requests[2])
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes["fileSize"] as? Int == 5)
        #expect(attributes["fileName"] as? String == fileURL.lastPathComponent)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["reservationCreated"] == .bool(true))
        #expect(payload["uploadCommitted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        exportComplianceExpectNoSecrets(result)
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

    @Test("document update preserves explicit null and rejects empty patches")
    func updateDocumentTriState() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "doc/1", fileName: "export.pdf", state: "AWAITING_UPLOAD"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: [
                "document_id": .string("doc/1"),
                "source_file_checksum": .null,
                "uploaded": .null
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(try exportComplianceEncodedPath(request) == "/v1/appEncryptionDeclarationDocuments/doc%2F1")
        let data = try exportComplianceBodyData(request)
        let attributes = try exportComplianceDictionary(data["attributes"])
        #expect(attributes.keys.sorted() == ["sourceFileChecksum", "uploaded"])
        #expect(attributes["sourceFileChecksum"] is NSNull)
        #expect(attributes["uploaded"] is NSNull)

        let emptyTransport = TestHTTPTransport(responses: [])
        let emptyWorker = try await exportComplianceWorker(apiTransport: emptyTransport)
        let empty = try await emptyWorker.handleTool(.init(
            name: "export_compliance_update_document",
            arguments: ["document_id": .string("document-1")]
        ))
        #expect(empty.isError == true)
        #expect(await emptyTransport.requestCount() == 0)
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
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
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
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try exportComplianceValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("unavailable"))
        #expect(cleanup["tool"] == nil)
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
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
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
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await exportComplianceWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )
        let result = try await worker.handleTool(.init(
            name: "export_compliance_upload_document",
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["uploadCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(false))
        #expect(payload["deliveryPending"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        exportComplianceExpectNoSecrets(result)
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
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET", "PATCH", "GET"])
        let payload = try exportComplianceObject(result.structuredContent)
        #expect(payload["reconciledAfterCommit"] == .bool(true))
        exportComplianceExpectNoSecrets(result)
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
            arguments: ["document_id": .string("document-1"), "file_path": .string(fileURL.path)]
        ))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
        #expect(exportComplianceText(result).contains("no document delete operation"))
    }

    @Test("inspect and build relationship translate 404 into explicit absence")
    func absenceSemantics() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 404, body: exportComplianceAPIError(404)),
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
    }

    @Test("attachment preflights approval and document, patches exact linkage, then verifies")
    func attachBuildDeclarationContract() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl/1", state: "APPROVED")),
            .init(statusCode: 200, body: exportComplianceDocumentResponse(id: "document-1", fileName: "export.pdf", state: "COMPLETE")),
            .init(statusCode: 200, body: exportComplianceBuildResponse(usesNonExemptEncryption: true, id: "build/1")),
            .init(statusCode: 200, body: exportComplianceDeclarationResponse(id: "decl/1", state: "APPROVED"))
        ])
        let worker = try await exportComplianceWorker(apiTransport: transport)
        let result = try await worker.handleTool(.init(
            name: "export_compliance_attach_build_declaration",
            arguments: ["build_id": .string("build/1"), "declaration_id": .string("decl/1")]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        #expect(try exportComplianceEncodedPath(requests[2]) == "/v1/builds/build%2F1")
        let body = try exportComplianceJSONObject(requests[2])
        #expect(body as NSDictionary == [
            "data": [
                "type": "builds",
                "id": "build/1",
                "relationships": [
                    "appEncryptionDeclaration": [
                        "data": ["type": "appEncryptionDeclarations", "id": "decl/1"]
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
        #expect(manifest.index.waivers.contains {
            $0.operationID == "builds_appEncryptionDeclaration_updateToOneRelationship"
        })
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
        #expect(payload["releaseReady"] == .bool(true))
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
        #expect(payload["releaseReady"] == .bool(false))
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
        #expect(payload["releaseReady"] == .bool(true))
        #expect(payload["declarationAttached"] == .bool(true))
        #expect(payload["documentPresent"] == .bool(true))
    }

    @Test("pending, failed, missing, and future document states never pass", arguments: [
        ("AWAITING_UPLOAD", "PENDING"),
        ("UPLOAD_COMPLETE", "PENDING"),
        ("FAILED", "BLOCKED"),
        ("FUTURE_STATE", "PENDING")
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
        #expect(payload["releaseReady"] == .bool(false))
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
        #expect(try exportComplianceObject(nilResult.structuredContent)["status"] == .string("BLOCKED"))

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
    state: String,
    uploadOperations: Bool = false,
    includeSecrets: Bool = false,
    includeDeliverySecrets: Bool = false,
    checksum: Bool = false
) -> String {
    let operations = uploadOperations
        ? #","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk?signed=signed-secret","length":5,"offset":0,"requestHeaders":[{"name":"X-Amz-Security-Token","value":"header-secret"}]}]"#
        : ""
    let secrets = includeSecrets
        ? #","assetToken":"asset-secret","downloadUrl":"https://download.example.test/file?signed=download-secret""#
        : ""
    let checksumValue = checksum
        ? #","sourceFileChecksum":"5d41402abc4b2a76b9719d911017c592""#
        : ""
    let errors = includeDeliverySecrets
        ? #"[{"code":"UPLOAD_FAILED","description":"Retry https://upload.example.test/chunk?signed=signed-secret with token=header-secret"}]"#
        : "[]"
    return #"{"data":{"type":"appEncryptionDeclarationDocuments","id":"\#(id)","attributes":{"fileSize":5,"fileName":"\#(fileName)","assetDeliveryState":{"state":"\#(state)","errors":\#(errors),"warnings":[]}\#(operations)\#(secrets)\#(checksumValue)}}}"#
}

private func exportComplianceBuildResponse(
    usesNonExemptEncryption: Bool?,
    id: String = "build-1"
) -> String {
    let encryption = usesNonExemptEncryption.map { String($0) } ?? "null"
    return #"{"data":{"type":"builds","id":"\#(id)","attributes":{"version":"42","processingState":"VALID","expired":false,"usesNonExemptEncryption":\#(encryption)},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
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
