import Foundation
import MCP

private let exportComplianceDeclarationFields = "appDescription,createdDate,exempt,containsProprietaryCryptography,containsThirdPartyCryptography,availableOnFrenchStore,appEncryptionDeclarationState,codeValue,appEncryptionDeclarationDocument"
private let exportComplianceDocumentReadFields = "fileSize,fileName,downloadUrl,sourceFileChecksum,assetDeliveryState"
private let exportComplianceDocumentUploadFields = "fileSize,fileName,sourceFileChecksum,uploadOperations,assetDeliveryState"
private let exportComplianceBuildFields = "version,processingState,expired,usesNonExemptEncryption,app"
private let exportComplianceNoDeleteReason = "Apple exposes no delete operation for app encryption declaration documents; the reservation was retained for App Store Connect inspection or Apple Support."

// MARK: - Handlers

extension ExportComplianceWorker {
    func listDeclarations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let appID = try exportComplianceString(arguments, "app_id")
            let limit = try exportComplianceLimit(arguments["limit"])
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID))/appEncryptionDeclarations"
            let query = [
                "fields[appEncryptionDeclarations]": exportComplianceDeclarationFields,
                "limit": String(limit)
            ]

            let response: ASCExportComplianceDeclarationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(
                        path: path,
                        requiredParameters: query,
                        allowedParameters: [
                            "fields[appEncryptionDeclarations]",
                            "limit",
                            "cursor"
                        ],
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCExportComplianceDeclarationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCExportComplianceDeclarationsResponse.self
                )
            }

            let declarations = response.data.map(exportComplianceDeclarationDictionary)
            var result: [String: Any] = [
                "success": true,
                "declarations": declarations,
                "count": declarations.count
            ]
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let nextURL = response.links?.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return exportComplianceError("Failed to list export-compliance declarations", error)
        }
    }

    func getDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let declarationID = try exportComplianceString(arguments, "declaration_id")
            let declaration = try await fetchDeclaration(declarationID)
            return MCPResult.jsonObject([
                "success": true,
                "declaration": exportComplianceDeclarationDictionary(declaration)
            ])
        } catch {
            return exportComplianceError("Failed to get export-compliance declaration", error)
        }
    }

    func createDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let appID = try exportComplianceString(arguments, "app_id")
            let appDescription = try exportComplianceString(arguments, "app_description")
            let containsProprietaryCryptography = try exportComplianceBoolean(
                arguments,
                "contains_proprietary_cryptography"
            )
            let containsThirdPartyCryptography = try exportComplianceBoolean(
                arguments,
                "contains_third_party_cryptography"
            )
            let availableOnFrenchStore = try exportComplianceBoolean(
                arguments,
                "available_on_french_store"
            )
            let request = ExportComplianceCreateDeclarationRequest(
                data: .init(
                    attributes: .init(
                        appDescription: appDescription,
                        containsProprietaryCryptography: containsProprietaryCryptography,
                        containsThirdPartyCryptography: containsThirdPartyCryptography,
                        availableOnFrenchStore: availableOnFrenchStore
                    ),
                    relationships: .init(
                        app: .init(data: ASCResourceIdentifier(type: "apps", id: appID))
                    )
                )
            )
            let response: ASCExportComplianceDeclarationResponse = try await httpClient.post(
                "/v1/appEncryptionDeclarations",
                body: request,
                as: ASCExportComplianceDeclarationResponse.self
            )
            guard response.data.type == "appEncryptionDeclarations", !response.data.id.isEmpty else {
                throw ExportComplianceInputError("Apple returned an unexpected declaration resource")
            }
            return MCPResult.jsonObject([
                "success": true,
                "declaration": exportComplianceDeclarationDictionary(response.data)
            ])
        } catch {
            return exportComplianceError("Failed to create export-compliance declaration", error)
        }
    }

    func createDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let declarationID: String
        let filePath: String
        do {
            let arguments = try exportComplianceArguments(params)
            declarationID = try exportComplianceString(arguments, "declaration_id")
            filePath = try exportComplianceFilePath(arguments, "file_path")
        } catch {
            return exportComplianceError("Invalid document reservation input", error)
        }

        do {
            let declaration = try await fetchDeclaration(declarationID)
            guard ["CREATED", "REJECTED"].contains(
                declaration.attributes?.appEncryptionDeclarationState ?? ""
            ) else {
                return MCPResult.error(
                    "A document can only be reserved while the declaration is CREATED or REJECTED.",
                    details: .object([
                        "declaration_id": .string(declarationID),
                        "state": declaration.attributes?.appEncryptionDeclarationState.map(Value.string) ?? .null
                    ])
                )
            }
            if let existing = try await fetchDocumentForDeclaration(declarationID) {
                return MCPResult.error(
                    "The declaration already has a document reservation. Inspect or upload the existing resource instead of creating a duplicate.",
                    details: .object([
                        "document_id": .string(existing.id),
                        "retrySafe": .bool(false),
                        "inspectionTool": .string("export_compliance_get_document")
                    ])
                )
            }
        } catch {
            return exportComplianceError("Failed document reservation preflight", error)
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await uploadService.prepareSnapshot(filePath: filePath)
        } catch {
            return exportComplianceError("Failed to read encryption document", error)
        }
        defer { snapshot.discard() }

        let request = ExportComplianceCreateDocumentRequest(
            data: .init(
                attributes: .init(fileSize: snapshot.fileSize, fileName: snapshot.fileName),
                relationships: .init(
                    appEncryptionDeclaration: .init(
                        data: ASCResourceIdentifier(
                            type: "appEncryptionDeclarations",
                            id: declarationID
                        )
                    )
                )
            )
        )

        do {
            let response: ASCExportComplianceDocumentResponse = try await httpClient.post(
                "/v1/appEncryptionDeclarationDocuments",
                body: request,
                as: ASCExportComplianceDocumentResponse.self
            )
            guard response.data.type == "appEncryptionDeclarationDocuments", !response.data.id.isEmpty else {
                throw ExportComplianceInputError("Apple returned an unexpected document reservation")
            }
            return MCPResult.jsonObject([
                "success": true,
                "reservationCreated": true,
                "uploadCommitted": false,
                "retrySafe": false,
                "document": exportComplianceDocumentDictionary(response.data),
                "nextAction": [
                    "tool": "export_compliance_upload_document",
                    "arguments": ["document_id": response.data.id],
                    "instruction": "Reuse the same absolute file path to transfer this reservation."
                ]
            ])
        } catch {
            return MCPResult.error(
                "The document reservation request did not return a confirmed resource: \(error.localizedDescription)",
                details: .object([
                    "reservationState": .string("unknown"),
                    "reservationIdKnown": .bool(false),
                    "retrySafe": .bool(false),
                    "inspection": .object([
                        "tool": .string("export_compliance_inspect_document"),
                        "arguments": .object(["declaration_id": .string(declarationID)])
                    ])
                ])
            )
        }
    }

    func getDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let documentID = try exportComplianceString(arguments, "document_id")
            let document = try await fetchDocument(documentID, includeUploadOperations: false)
            return MCPResult.jsonObject([
                "success": true,
                "document": exportComplianceDocumentDictionary(document)
            ])
        } catch {
            return exportComplianceError("Failed to get encryption document", error)
        }
    }

    func updateDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let documentID = try exportComplianceString(arguments, "document_id")
            let checksum = try exportComplianceNullableString(arguments["source_file_checksum"], field: "source_file_checksum")
            let uploaded = try exportComplianceNullableBoolean(arguments["uploaded"], field: "uploaded")
            guard checksum != nil || uploaded != nil else {
                throw ExportComplianceInputError(
                    "At least one update field is required: source_file_checksum or uploaded"
                )
            }
            let request = ExportComplianceUpdateDocumentRequest(
                data: .init(
                    id: documentID,
                    attributes: .init(sourceFileChecksum: checksum, uploaded: uploaded)
                )
            )
            let response: ASCExportComplianceDocumentResponse = try await httpClient.patch(
                "/v1/appEncryptionDeclarationDocuments/\(try ASCPathSegment.encode(documentID))",
                body: request,
                as: ASCExportComplianceDocumentResponse.self
            )
            guard response.data.id == documentID,
                  response.data.type == "appEncryptionDeclarationDocuments" else {
                throw ExportComplianceInputError("Apple returned an unexpected document resource")
            }
            return MCPResult.jsonObject([
                "success": true,
                "document": exportComplianceDocumentDictionary(response.data)
            ])
        } catch {
            return exportComplianceError("Failed to update encryption document", error)
        }
    }

    func uploadDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let documentID: String
        let filePath: String
        do {
            let arguments = try exportComplianceArguments(params)
            documentID = try exportComplianceString(arguments, "document_id")
            filePath = try exportComplianceFilePath(arguments, "file_path")
        } catch {
            return exportComplianceError("Invalid encryption document upload input", error)
        }

        let reserved: ASCExportComplianceDocument
        do {
            reserved = try await fetchDocument(documentID, includeUploadOperations: true)
        } catch {
            return exportComplianceError("Failed to load the document reservation", error)
        }

        switch reserved.recoveryDeliveryStatus {
        case .complete:
            return MCPResult.jsonObject([
                "success": true,
                "alreadyComplete": true,
                "document": exportComplianceDocumentDictionary(reserved)
            ])
        case .failed:
            return MCPResult.error(
                "Apple reports terminal document delivery state 'FAILED'. Use App Store Connect or Apple Support because this API version exposes no document delete operation.",
                details: .object([
                    "document_id": .string(documentID),
                    "retrySafe": .bool(false),
                    "cleanupAvailable": .bool(false)
                ])
            )
        case .pending(let state) where state == "UPLOAD_COMPLETE":
            return MCPResult.jsonObject([
                "success": true,
                "uploadCommitted": true,
                "processingComplete": false,
                "deliveryPending": true,
                "retrySafe": false,
                "document": exportComplianceDocumentDictionary(reserved),
                "nextAction": [
                    "tool": "export_compliance_get_document",
                    "arguments": ["document_id": documentID]
                ]
            ])
        case .pending:
            break
        }

        let outcome: UploadTransactionOutcome<ASCExportComplianceDocument> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "encryption document",
            expectedType: "appEncryptionDeclarationDocuments",
            reservationEndpoint: "/v1/appEncryptionDeclarationDocuments",
            httpClient: httpClient,
            uploadService: uploadService,
            cleanupPolicy: .retain(exportComplianceNoDeleteReason),
            existingResource: reserved,
            validateSnapshot: { document, fileSize, fileName in
                guard document?.attributes?.fileSize == fileSize,
                      document?.attributes?.fileName == fileName else {
                    throw ExportComplianceInputError(
                        "file name and byte size must match the existing reservation"
                    )
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { _, _ in
                throw ExportComplianceInputError("An existing document reservation is required")
            },
            decodeResource: {
                try JSONDecoder().decode(ASCExportComplianceDocumentResponse.self, from: $0).data
            },
            makeCommitBody: { id, checksum in
                try JSONEncoder().encode(
                    ExportComplianceUpdateDocumentRequest(
                        data: .init(
                            id: id,
                            attributes: .init(
                                sourceFileChecksum: .string(checksum),
                                uploaded: .bool(true)
                            )
                        )
                    )
                )
            },
            resourceEndpoint: {
                "/v1/appEncryptionDeclarationDocuments/\(try ASCPathSegment.encode($0))"
            }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "encryption document",
                successKey: "document",
                idArgument: "document_id",
                getTool: "export_compliance_get_document",
                getIDArgument: "document_id",
                deleteTool: nil,
                inspectionTool: "export_compliance_get_document",
                inspectionArguments: ["document_id": documentID]
            ),
            format: exportComplianceDocumentDictionary
        )
    }

    func inspectDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let declarationID = try exportComplianceString(arguments, "declaration_id")
            guard let document = try await fetchDocumentForDeclaration(declarationID) else {
                return MCPResult.jsonObject([
                    "success": true,
                    "declarationId": declarationID,
                    "documentPresent": false,
                    "deliveryStatus": "MISSING",
                    "processingComplete": false
                ])
            }
            let classification = exportComplianceDocumentClassification(document)
            return MCPResult.jsonObject([
                "success": true,
                "declarationId": declarationID,
                "documentPresent": true,
                "deliveryStatus": classification.state,
                "processingComplete": classification.complete,
                "deliveryFailed": classification.failed,
                "document": exportComplianceDocumentDictionary(document)
            ])
        } catch {
            return exportComplianceError("Failed to inspect encryption document", error)
        }
    }

    func getBuildDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let buildID = try exportComplianceString(arguments, "build_id")
            guard let declaration = try await fetchBuildDeclaration(buildID) else {
                return MCPResult.jsonObject([
                    "success": true,
                    "buildId": buildID,
                    "declarationAttached": false
                ])
            }
            return MCPResult.jsonObject([
                "success": true,
                "buildId": buildID,
                "declarationAttached": true,
                "declaration": exportComplianceDeclarationDictionary(declaration)
            ])
        } catch {
            return exportComplianceError("Failed to get the build declaration", error)
        }
    }

    func attachBuildDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let buildID: String
        let declarationID: String
        do {
            let arguments = try exportComplianceArguments(params)
            buildID = try exportComplianceString(arguments, "build_id")
            declarationID = try exportComplianceString(arguments, "declaration_id")
        } catch {
            return exportComplianceError("Invalid build declaration attachment input", error)
        }

        do {
            let declaration = try await fetchDeclaration(declarationID)
            guard declaration.attributes?.appEncryptionDeclarationState == "APPROVED" else {
                return MCPResult.error(
                    "Only an APPROVED export-compliance declaration can be attached to a build.",
                    details: .object([
                        "declaration_id": .string(declarationID),
                        "state": declaration.attributes?.appEncryptionDeclarationState.map(Value.string) ?? .null,
                        "action": .string("Wait for Apple approval or resolve the declaration review issue before attaching.")
                    ])
                )
            }
            guard let document = try await fetchDocumentForDeclaration(declarationID),
                  document.attributes?.assetDeliveryState?.state == "COMPLETE" else {
                return MCPResult.error(
                    "The approved declaration must have a document in COMPLETE delivery state before attachment.",
                    details: .object([
                        "declaration_id": .string(declarationID),
                        "inspectionTool": .string("export_compliance_inspect_document")
                    ])
                )
            }
        } catch {
            return exportComplianceError("Failed to validate the declaration before attachment", error)
        }

        let request = ExportComplianceAttachDeclarationRequest(
            data: .init(
                id: buildID,
                relationships: .init(
                    appEncryptionDeclaration: .init(
                        data: ASCResourceIdentifier(
                            type: "appEncryptionDeclarations",
                            id: declarationID
                        )
                    )
                )
            )
        )

        do {
            _ = try await httpClient.patch(
                "/v1/builds/\(try ASCPathSegment.encode(buildID))",
                body: try JSONEncoder().encode(request)
            )
        } catch {
            do {
                if let attached = try await fetchBuildDeclaration(buildID),
                   attached.id == declarationID {
                    return MCPResult.jsonObject([
                        "success": true,
                        "attachmentVerified": true,
                        "reconciledAfterUpdate": true,
                        "buildId": buildID,
                        "declaration": exportComplianceDeclarationDictionary(attached)
                    ])
                }
            } catch {
                return exportComplianceUnverifiedAttachment(
                    buildID: buildID,
                    declarationID: declarationID,
                    reason: "The build update had no confirmed response, and relationship reconciliation failed: \(error.localizedDescription)"
                )
            }
            return exportComplianceUnverifiedAttachment(
                buildID: buildID,
                declarationID: declarationID,
                reason: "The build update had no confirmed response, and the intended declaration could not be verified."
            )
        }

        do {
            guard let attached = try await fetchBuildDeclaration(buildID),
                  attached.id == declarationID else {
                return exportComplianceUnverifiedAttachment(
                    buildID: buildID,
                    declarationID: declarationID,
                    reason: "The build relationship could not be verified after the update."
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "attachmentVerified": true,
                "buildId": buildID,
                "declaration": exportComplianceDeclarationDictionary(attached)
            ])
        } catch {
            return exportComplianceUnverifiedAttachment(
                buildID: buildID,
                declarationID: declarationID,
                reason: "The update succeeded, but relationship verification failed: \(error.localizedDescription)"
            )
        }
    }

    func checkReleaseReadiness(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let buildID = try exportComplianceString(arguments, "build_id")
            let buildResponse: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(try ASCPathSegment.encode(buildID))",
                parameters: ["fields[builds]": exportComplianceBuildFields],
                as: ASCBuildResponse.self
            )
            guard buildResponse.data.id == buildID, buildResponse.data.type == "builds" else {
                throw ExportComplianceInputError("Apple returned an unexpected build resource")
            }

            let build = buildResponse.data
            let appID = build.relationships?.app?.data?.id
            let processingState = build.attributes.processingState
            let expired = build.attributes.expired
            let usesNonExemptEncryption = build.attributes.usesNonExemptEncryption
            var checks: [[String: Any]] = []
            var actions: [[String: Any]] = []
            var blocked = false
            var pending = false
            var declaration: ASCExportComplianceDeclaration?
            var document: ASCExportComplianceDocument?

            switch processingState {
            case "VALID":
                checks.append(exportComplianceCheck("buildProcessing", "PASS", "Build processing is VALID."))
            case "PROCESSING":
                pending = true
                checks.append(exportComplianceCheck("buildProcessing", "PENDING", "Build processing is still running."))
            case "FAILED", "INVALID":
                blocked = true
                checks.append(exportComplianceCheck("buildProcessing", "FAIL", "Build processing failed."))
            default:
                blocked = true
                checks.append(exportComplianceCheck("buildProcessing", "UNKNOWN", "Build processing state is unavailable."))
            }

            if expired == false {
                checks.append(exportComplianceCheck("buildExpiration", "PASS", "Build is not expired."))
            } else if expired == true {
                blocked = true
                checks.append(exportComplianceCheck("buildExpiration", "FAIL", "Build is expired."))
            } else {
                blocked = true
                checks.append(exportComplianceCheck("buildExpiration", "UNKNOWN", "Build expiration state is unavailable."))
            }

            switch usesNonExemptEncryption {
            case false:
                checks.append(exportComplianceCheck(
                    "nonExemptEncryption",
                    "PASS",
                    "The build declares no non-exempt encryption; no declaration attachment is required."
                ))
            case nil:
                blocked = true
                checks.append(exportComplianceCheck(
                    "nonExemptEncryption",
                    "UNKNOWN",
                    "The build has no usesNonExemptEncryption answer."
                ))
                actions.append(exportComplianceAction(
                    tool: "builds_update_encryption",
                    arguments: ["build_id": buildID],
                    reason: "Set the build encryption answer before release."
                ))
            case true:
                checks.append(exportComplianceCheck(
                    "nonExemptEncryption",
                    "REQUIRED",
                    "The build requires an approved declaration and a completed document."
                ))
                declaration = try await fetchBuildDeclaration(buildID)
                guard let declaration else {
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "declarationAttachment",
                        "FAIL",
                        "No export-compliance declaration is attached to the build."
                    ))
                    if let appID {
                        actions.append(exportComplianceAction(
                            tool: "export_compliance_list_declarations",
                            arguments: ["app_id": appID],
                            reason: "Select or create an approved declaration, then attach it to the build."
                        ))
                    } else {
                        actions.append(exportComplianceAction(
                            tool: nil,
                            arguments: [:],
                            reason: "Select or create an approved declaration, then attach it to the build."
                        ))
                    }
                    return exportComplianceReadinessResult(
                        build: build,
                        appID: appID,
                        declaration: nil,
                        document: nil,
                        checks: checks,
                        actions: actions,
                        blocked: blocked,
                        pending: pending
                    )
                }

                checks.append(exportComplianceCheck(
                    "declarationAttachment",
                    "PASS",
                    "A declaration is attached to the build."
                ))
                switch declaration.attributes?.appEncryptionDeclarationState {
                case "APPROVED":
                    checks.append(exportComplianceCheck("declarationApproval", "PASS", "Declaration is APPROVED."))
                case "IN_REVIEW":
                    pending = true
                    checks.append(exportComplianceCheck("declarationApproval", "PENDING", "Declaration is IN_REVIEW."))
                case "CREATED":
                    blocked = true
                    checks.append(exportComplianceCheck("declarationApproval", "FAIL", "Declaration has not entered review."))
                case "REJECTED", "INVALID", "EXPIRED":
                    blocked = true
                    checks.append(exportComplianceCheck("declarationApproval", "FAIL", "Declaration is not usable for release."))
                default:
                    blocked = true
                    checks.append(exportComplianceCheck("declarationApproval", "UNKNOWN", "Declaration state is unavailable."))
                }

                switch declaration.attributes?.exempt {
                case false:
                    checks.append(exportComplianceCheck(
                        "declarationConsistency",
                        "PASS",
                        "The attached declaration is explicitly non-exempt."
                    ))
                case true:
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "declarationConsistency",
                        "FAIL",
                        "The build declares non-exempt encryption, but the attached declaration is marked exempt."
                    ))
                case nil:
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "declarationConsistency",
                        "UNKNOWN",
                        "The declaration exempt status is unavailable."
                    ))
                }

                document = try await fetchDocumentForDeclaration(declaration.id)
                guard let document else {
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "documentDelivery",
                        "FAIL",
                        "The attached declaration has no document."
                    ))
                    actions.append(exportComplianceAction(
                        tool: "export_compliance_create_document",
                        arguments: ["declaration_id": declaration.id],
                        reason: "Reserve and upload the required export-compliance document."
                    ))
                    return exportComplianceReadinessResult(
                        build: build,
                        appID: appID,
                        declaration: declaration,
                        document: nil,
                        checks: checks,
                        actions: actions,
                        blocked: blocked,
                        pending: pending
                    )
                }

                let documentState = exportComplianceDocumentClassification(document)
                if documentState.complete {
                    checks.append(exportComplianceCheck("documentDelivery", "PASS", "Document delivery is COMPLETE."))
                } else if documentState.failed {
                    blocked = true
                    checks.append(exportComplianceCheck("documentDelivery", "FAIL", "Document delivery FAILED."))
                    actions.append(exportComplianceAction(
                        tool: nil,
                        arguments: [:],
                        reason: "Resolve the failed document in App Store Connect or contact Apple Support; document deletion is unavailable in this API."
                    ))
                } else {
                    pending = true
                    checks.append(exportComplianceCheck(
                        "documentDelivery",
                        "PENDING",
                        "Document delivery is \(documentState.state)."
                    ))
                    actions.append(exportComplianceAction(
                        tool: "export_compliance_get_document",
                        arguments: ["document_id": document.id],
                        reason: "Inspect the existing document until delivery completes."
                    ))
                }
            }

            return exportComplianceReadinessResult(
                build: build,
                appID: appID,
                declaration: declaration,
                document: document,
                checks: checks,
                actions: actions,
                blocked: blocked,
                pending: pending
            )
        } catch {
            return exportComplianceError("Failed to evaluate export-compliance readiness", error)
        }
    }

    // MARK: - Requests

    private func fetchDeclaration(_ declarationID: String) async throws -> ASCExportComplianceDeclaration {
        let response: ASCExportComplianceDeclarationResponse = try await httpClient.get(
            "/v1/appEncryptionDeclarations/\(try ASCPathSegment.encode(declarationID))",
            parameters: ["fields[appEncryptionDeclarations]": exportComplianceDeclarationFields],
            as: ASCExportComplianceDeclarationResponse.self
        )
        guard response.data.id == declarationID,
              response.data.type == "appEncryptionDeclarations" else {
            throw ExportComplianceInputError("Apple returned an unexpected declaration resource")
        }
        return response.data
    }

    private func fetchDocument(
        _ documentID: String,
        includeUploadOperations: Bool
    ) async throws -> ASCExportComplianceDocument {
        let response: ASCExportComplianceDocumentResponse = try await httpClient.get(
            "/v1/appEncryptionDeclarationDocuments/\(try ASCPathSegment.encode(documentID))",
            parameters: [
                "fields[appEncryptionDeclarationDocuments]": includeUploadOperations
                    ? exportComplianceDocumentUploadFields
                    : exportComplianceDocumentReadFields
            ],
            as: ASCExportComplianceDocumentResponse.self
        )
        guard response.data.id == documentID,
              response.data.type == "appEncryptionDeclarationDocuments" else {
            throw ExportComplianceInputError("Apple returned an unexpected document resource")
        }
        return response.data
    }

    private func fetchDocumentForDeclaration(
        _ declarationID: String
    ) async throws -> ASCExportComplianceDocument? {
        do {
            let response: ASCExportComplianceDocumentResponse = try await httpClient.get(
                "/v1/appEncryptionDeclarations/\(try ASCPathSegment.encode(declarationID))/appEncryptionDeclarationDocument",
                parameters: ["fields[appEncryptionDeclarationDocuments]": exportComplianceDocumentReadFields],
                as: ASCExportComplianceDocumentResponse.self
            )
            guard response.data.type == "appEncryptionDeclarationDocuments", !response.data.id.isEmpty else {
                throw ExportComplianceInputError("Apple returned an unexpected document resource")
            }
            return response.data
        } catch let error as ASCError where exportComplianceHTTPStatus(error) == 404 {
            return nil
        }
    }

    private func fetchBuildDeclaration(
        _ buildID: String
    ) async throws -> ASCExportComplianceDeclaration? {
        do {
            let response: ASCExportComplianceDeclarationResponse = try await httpClient.get(
                "/v1/builds/\(try ASCPathSegment.encode(buildID))/appEncryptionDeclaration",
                parameters: ["fields[appEncryptionDeclarations]": exportComplianceDeclarationFields],
                as: ASCExportComplianceDeclarationResponse.self
            )
            guard response.data.type == "appEncryptionDeclarations", !response.data.id.isEmpty else {
                throw ExportComplianceInputError("Apple returned an unexpected declaration resource")
            }
            return response.data
        } catch let error as ASCError where exportComplianceHTTPStatus(error) == 404 {
            return nil
        }
    }
}

// MARK: - Formatting

private func exportComplianceDeclarationDictionary(
    _ declaration: ASCExportComplianceDeclaration
) -> [String: Any] {
    [
        "id": declaration.id,
        "type": declaration.type,
        "appDescription": declaration.attributes?.appDescription.jsonSafe,
        "createdDate": declaration.attributes?.createdDate.jsonSafe,
        "exempt": declaration.attributes?.exempt.jsonSafe,
        "containsProprietaryCryptography": declaration.attributes?.containsProprietaryCryptography.jsonSafe,
        "containsThirdPartyCryptography": declaration.attributes?.containsThirdPartyCryptography.jsonSafe,
        "availableOnFrenchStore": declaration.attributes?.availableOnFrenchStore.jsonSafe,
        "state": declaration.attributes?.appEncryptionDeclarationState.jsonSafe,
        "codeValue": declaration.attributes?.codeValue.jsonSafe,
        "documentId": declaration.relationships?.appEncryptionDeclarationDocument?.data?.id.jsonSafe
    ]
}

private func exportComplianceDocumentDictionary(
    _ document: ASCExportComplianceDocument
) -> [String: Any] {
    let attributes = document.attributes
    let state = attributes?.assetDeliveryState
    return [
        "id": document.id,
        "type": document.type,
        "fileSize": attributes?.fileSize.jsonSafe,
        "fileName": attributes?.fileName.jsonSafe,
        "sourceFileChecksum": attributes?.sourceFileChecksum.jsonSafe,
        "deliveryState": state?.state.jsonSafe,
        "deliveryErrors": exportComplianceAssetMessages(state?.errors),
        "deliveryWarnings": exportComplianceAssetMessages(state?.warnings),
        "downloadAvailable": attributes?.downloadUrl != nil,
        "downloadURLRedacted": attributes?.downloadUrl != nil,
        "assetTokenPresent": attributes?.assetToken != nil,
        "uploadOperationsAvailable": !(attributes?.uploadOperations?.isEmpty ?? true),
        "uploadOperationCount": attributes?.uploadOperations?.count ?? 0,
        "uploadMetadataRedacted": !(attributes?.uploadOperations?.isEmpty ?? true)
    ]
}

private func exportComplianceAssetMessages(
    _ messages: [ASCAssetDeliveryError]?
) -> [[String: Any]] {
    (messages ?? []).map { message in
        [
            "code": message.code.jsonSafe,
            "description": message.description.map(Redactor.redact).jsonSafe
        ]
    }
}

private func exportComplianceDocumentClassification(
    _ document: ASCExportComplianceDocument
) -> (state: String, complete: Bool, failed: Bool) {
    let state = document.attributes?.assetDeliveryState?.state ?? "UNKNOWN"
    return (state, state == "COMPLETE", state == "FAILED")
}

private func exportComplianceCheck(_ name: String, _ status: String, _ detail: String) -> [String: Any] {
    ["name": name, "status": status, "detail": detail]
}

private func exportComplianceAction(
    tool: String?,
    arguments: [String: String],
    reason: String
) -> [String: Any] {
    var result: [String: Any] = ["reason": reason, "arguments": arguments]
    if let tool {
        result["tool"] = tool
    }
    return result
}

private func exportComplianceReadinessResult(
    build: ASCBuild,
    appID: String?,
    declaration: ASCExportComplianceDeclaration?,
    document: ASCExportComplianceDocument?,
    checks: [[String: Any]],
    actions: [[String: Any]],
    blocked: Bool,
    pending: Bool
) -> CallTool.Result {
    let status = blocked ? "BLOCKED" : (pending ? "PENDING" : "READY")
    return MCPResult.jsonObject([
        "success": true,
        "scope": "EXPORT_COMPLIANCE_ONLY",
        "status": status,
        "releaseReady": status == "READY",
        "appStoreSubmissionStatus": "NOT_DETERMINED",
        "build": [
            "id": build.id,
            "version": build.attributes.version.jsonSafe,
            "appId": appID.jsonSafe,
            "processingState": build.attributes.processingState.jsonSafe,
            "expired": build.attributes.expired.jsonSafe,
            "usesNonExemptEncryption": build.attributes.usesNonExemptEncryption.jsonSafe
        ],
        "declarationAttached": declaration != nil,
        "declaration": declaration.map(exportComplianceDeclarationDictionary).jsonSafe,
        "documentPresent": document != nil,
        "document": document.map(exportComplianceDocumentDictionary).jsonSafe,
        "checks": checks,
        "actions": actions,
        "warnings": [
            "This gate covers export compliance only. Version metadata, review details, agreements, pricing, availability, and other release requirements are not evaluated."
        ]
    ])
}

private func exportComplianceUnverifiedAttachment(
    buildID: String,
    declarationID: String,
    reason: String
) -> CallTool.Result {
    let safeReason = Redactor.redact(reason)
    return MCPResult.error(
        safeReason,
        details: .object([
            "attachmentState": .string("unverified"),
            "retrySafe": .bool(false),
            "build_id": .string(buildID),
            "declaration_id": .string(declarationID),
            "inspection": .object([
                "tool": .string("export_compliance_get_build_declaration"),
                "arguments": .object(["build_id": .string(buildID)])
            ])
        ])
    )
}

// MARK: - Validation

private func exportComplianceArguments(_ params: CallTool.Parameters) throws -> [String: Value] {
    guard let arguments = params.arguments else {
        throw ExportComplianceInputError("Tool arguments are required")
    }
    return arguments
}

private func exportComplianceString(
    _ arguments: [String: Value],
    _ field: String
) throws -> String {
    guard let value = arguments[field],
          let string = value.stringValue,
          !string.isEmpty,
          string == string.trimmingCharacters(in: .whitespacesAndNewlines),
          !string.contains("\0") else {
        throw ExportComplianceInputError("Parameter '\(field)' must be a non-empty string without surrounding whitespace")
    }
    return string
}

private func exportComplianceBoolean(
    _ arguments: [String: Value],
    _ field: String
) throws -> Bool {
    guard let value = arguments[field]?.boolValue else {
        throw ExportComplianceInputError("Parameter '\(field)' must be a boolean")
    }
    return value
}

private func exportComplianceFilePath(
    _ arguments: [String: Value],
    _ field: String
) throws -> String {
    let path = try exportComplianceString(arguments, field)
    guard path.hasPrefix("/") else {
        throw ExportComplianceInputError("Parameter '\(field)' must be an absolute file path")
    }
    return path
}

private func exportComplianceLimit(_ value: Value?) throws -> Int {
    guard let value else { return 25 }
    guard let limit = value.intValue, (1...200).contains(limit) else {
        throw ExportComplianceInputError("Parameter 'limit' must be an integer from 1 through 200")
    }
    return limit
}

private func exportComplianceNullableString(
    _ value: Value?,
    field: String
) throws -> JSONValue? {
    guard let value else { return nil }
    if value.isNull { return .null }
    guard let string = value.stringValue,
          !string.isEmpty,
          string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw ExportComplianceInputError("Parameter '\(field)' must be a non-empty string or null")
    }
    return .string(string)
}

private func exportComplianceNullableBoolean(
    _ value: Value?,
    field: String
) throws -> JSONValue? {
    guard let value else { return nil }
    if value.isNull { return .null }
    guard let boolean = value.boolValue else {
        throw ExportComplianceInputError("Parameter '\(field)' must be a boolean or null")
    }
    return .bool(boolean)
}

private func exportComplianceHTTPStatus(_ error: ASCError) -> Int? {
    switch error {
    case .api(_, let statusCode), .apiResponse(_, let statusCode):
        return statusCode
    default:
        return nil
    }
}

private func exportComplianceError(_ context: String, _ error: Error) -> CallTool.Result {
    MCPResult.error("\(context): \(Redactor.redact(error.localizedDescription))")
}

private struct ExportComplianceInputError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
