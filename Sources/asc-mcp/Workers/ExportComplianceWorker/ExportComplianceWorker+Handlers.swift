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
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID))/appEncryptionDeclarations"
            let requestedLimit = try exportComplianceLimit(arguments["limit"])
            let nextURL = try paginationURL(from: arguments["next_url"])
            let limit: Int
            if let nextURL {
                limit = try exportComplianceContinuationLimit(nextURL)
                if arguments["limit"] != nil, requestedLimit != limit {
                    throw ExportComplianceInputError(
                        "Parameter 'limit' must match the validated continuation URL when both are provided"
                    )
                }
            } else {
                limit = requestedLimit
            }
            let query = [
                "fields[appEncryptionDeclarations]": exportComplianceDeclarationFields,
                "limit": String(limit)
            ]

            let response: ASCExportComplianceDeclarationsResponse
            if let nextURL {
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
        let appID: String
        let request: ExportComplianceCreateDeclarationRequest
        do {
            let arguments = try exportComplianceArguments(params)
            appID = try exportComplianceString(arguments, "app_id")
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
            request = ExportComplianceCreateDeclarationRequest(
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
        } catch {
            return exportComplianceError("Invalid export-compliance declaration input", error)
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return exportComplianceError("Failed to prepare export-compliance declaration", error)
        }

        do {
            let data = try await httpClient.post("/v1/appEncryptionDeclarations", body: body)
            let response: ASCExportComplianceDeclarationResponse
            do {
                response = try JSONDecoder().decode(ASCExportComplianceDeclarationResponse.self, from: data)
            } catch {
                return exportComplianceDeclarationCreationFailure(
                    appID: appID,
                    state: .committedUnverified,
                    reason: "Apple accepted the declaration create request but returned an unreadable response: \(error.localizedDescription)"
                )
            }
            guard response.data.type == "appEncryptionDeclarations",
                  exportComplianceHasUsableResourceID(response.data.id) else {
                return exportComplianceDeclarationCreationFailure(
                    appID: appID,
                    state: .committedUnverified,
                    reason: "Apple returned an unexpected declaration resource after accepting the create request."
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "creationState": "confirmed",
                "commitConfirmed": true,
                "retrySafe": false,
                "declaration": exportComplianceDeclarationDictionary(response.data)
            ])
        } catch {
            let state = exportComplianceMutationState(for: error)
            return exportComplianceDeclarationCreationFailure(
                appID: appID,
                state: state,
                reason: "The declaration create request did not return a confirmed resource: \(error.localizedDescription)"
            )
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

        let outcome = await performDocumentUpload(
            filePath: filePath,
            declarationID: declarationID,
            existingResource: nil,
            expectedChecksum: nil
        )
        return exportComplianceUploadResult(
            outcome,
            descriptor: exportComplianceUploadDescriptor(declarationID: declarationID),
            filePath: filePath,
            authoritativeChecksum: nil
        )
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
        let documentID: String
        let endpoint: String
        let request: ExportComplianceUpdateDocumentRequest
        do {
            let arguments = try exportComplianceArguments(params)
            documentID = try exportComplianceString(arguments, "document_id")
            endpoint = "/v1/appEncryptionDeclarationDocuments/\(try ASCPathSegment.encode(documentID))"
            let checksum = try exportComplianceNullableString(arguments["source_file_checksum"], field: "source_file_checksum")
            let uploaded = try exportComplianceNullableBoolean(arguments["uploaded"], field: "uploaded")
            guard checksum != nil || uploaded != nil else {
                throw ExportComplianceInputError(
                    "At least one update field is required: source_file_checksum or uploaded"
                )
            }
            request = ExportComplianceUpdateDocumentRequest(
                data: .init(
                    id: documentID,
                    attributes: .init(sourceFileChecksum: checksum, uploaded: uploaded)
                )
            )
        } catch {
            return exportComplianceError("Invalid encryption document update input", error)
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return exportComplianceError("Failed to prepare encryption document update", error)
        }

        do {
            let data = try await httpClient.patch(endpoint, body: body)
            let response: ASCExportComplianceDocumentResponse
            do {
                response = try JSONDecoder().decode(ASCExportComplianceDocumentResponse.self, from: data)
            } catch {
                return exportComplianceDocumentUpdateFailure(
                    documentID: documentID,
                    state: .committedUnverified,
                    reason: "Apple accepted the document update but returned an unreadable response: \(error.localizedDescription)"
                )
            }
            guard response.data.id == documentID,
                  response.data.type == "appEncryptionDeclarationDocuments" else {
                return exportComplianceDocumentUpdateFailure(
                    documentID: documentID,
                    state: .committedUnverified,
                    reason: "Apple returned an unexpected document resource after accepting the update request."
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "updateState": "confirmed",
                "commitConfirmed": true,
                "retrySafe": false,
                "document": exportComplianceDocumentDictionary(response.data)
            ])
        } catch {
            return exportComplianceDocumentUpdateFailure(
                documentID: documentID,
                state: exportComplianceMutationState(for: error),
                reason: "The document update did not return a confirmed resource: \(error.localizedDescription)"
            )
        }
    }

    func uploadDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let documentID: String
        let filePath: String
        let expectedChecksum: String
        do {
            let arguments = try exportComplianceArguments(params)
            documentID = try exportComplianceString(arguments, "document_id")
            filePath = try exportComplianceFilePath(arguments, "file_path")
            expectedChecksum = try exportComplianceMD5(arguments, "source_file_checksum")
        } catch {
            return exportComplianceError("Invalid encryption document upload input", error)
        }

        let reserved: ASCExportComplianceDocument
        do {
            reserved = try await fetchDocument(documentID, includeUploadOperations: true)
        } catch {
            return exportComplianceError("Failed to load the document reservation", error)
        }

        switch reserved.attributes?.assetDeliveryState?.state {
        case "COMPLETE":
            return MCPResult.jsonObject([
                "success": true,
                "alreadyComplete": true,
                "document": exportComplianceDocumentDictionary(reserved)
            ])
        case "FAILED":
            return MCPResult.error(
                "Apple reports terminal document delivery state 'FAILED'. Use App Store Connect or Apple Support because this API version exposes no document delete operation.",
                details: .object([
                    "document_id": .string(documentID),
                    "retrySafe": .bool(false),
                    "cleanupAvailable": .bool(false)
                ])
            )
        case "UPLOAD_COMPLETE":
            do {
                let current = try await pollCommittedDocument(reserved)
                switch current.attributes?.assetDeliveryState?.state {
                case "COMPLETE":
                    return MCPResult.jsonObject([
                        "success": true,
                        "alreadyCommitted": true,
                        "processingComplete": true,
                        "document": exportComplianceDocumentDictionary(current)
                    ])
                case "FAILED":
                    return MCPResult.error(
                        "Apple reports terminal document delivery state 'FAILED'. Use App Store Connect or Apple Support because this API version exposes no document delete operation.",
                        details: .object([
                            "document_id": .string(documentID),
                            "retrySafe": .bool(false),
                            "cleanupAvailable": .bool(false)
                        ])
                    )
                case "UPLOAD_COMPLETE":
                    return MCPResult.jsonObject([
                        "success": true,
                        "uploadCommitted": true,
                        "processingComplete": false,
                        "deliveryPending": true,
                        "retrySafe": false,
                        "document": exportComplianceDocumentDictionary(current),
                        "nextAction": [
                            "tool": "export_compliance_get_document",
                            "arguments": ["document_id": documentID]
                        ]
                    ])
                default:
                    return MCPResult.error(
                        "Document processing could not be confirmed because Apple returned an unknown delivery state.",
                        details: .object([
                            "document_id": .string(documentID),
                            "deliveryState": current.attributes?.assetDeliveryState?.state.map(Value.string) ?? .null,
                            "retrySafe": .bool(false),
                            "inspection": .object([
                                "tool": .string("export_compliance_get_document"),
                                "arguments": .object(["document_id": .string(documentID)])
                            ])
                        ])
                    )
                }
            } catch {
                return exportComplianceError("Failed to inspect the committed encryption document", error)
            }
        case "AWAITING_UPLOAD":
            break
        case let state:
            return MCPResult.error(
                "Document transfer is blocked because Apple returned an unknown delivery state.",
                details: .object([
                    "document_id": .string(documentID),
                    "deliveryState": state.map(Value.string) ?? .null,
                    "retrySafe": .bool(false),
                    "inspection": .object([
                        "tool": .string("export_compliance_get_document"),
                        "arguments": .object(["document_id": .string(documentID)])
                    ])
                ])
            )
        }

        if let storedChecksum = reserved.attributes?.sourceFileChecksum,
           !exportComplianceIsLowercaseMD5(storedChecksum) {
            return MCPResult.error(
                "Document transfer is blocked because Apple returned an invalid stored checksum binding.",
                details: .object([
                    "document_id": .string(documentID),
                    "retrySafe": .bool(false),
                    "inspection": .object([
                        "tool": .string("export_compliance_get_document"),
                        "arguments": .object(["document_id": .string(documentID)])
                    ])
                ])
            )
        }

        let outcome = await performDocumentUpload(
            filePath: filePath,
            declarationID: nil,
            existingResource: reserved,
            expectedChecksum: expectedChecksum
        )
        let storedChecksum = reserved.attributes?.sourceFileChecksum
        let authoritativeChecksum: String?
        if let storedChecksum {
            authoritativeChecksum = exportComplianceIsLowercaseMD5(storedChecksum)
                ? storedChecksum
                : nil
        } else {
            authoritativeChecksum = expectedChecksum
        }
        return exportComplianceUploadResult(
            outcome,
            descriptor: exportComplianceUploadDescriptor(documentID: documentID),
            filePath: filePath,
            authoritativeChecksum: authoritativeChecksum
        )
    }

    func inspectDocument(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try exportComplianceArguments(params)
            let declarationID = try exportComplianceString(arguments, "declaration_id")
            let declaration = try await fetchDeclaration(declarationID)
            guard let document = try await fetchDocumentForDeclaration(declarationID) else {
                return MCPResult.jsonObject([
                    "success": true,
                    "declarationId": declarationID,
                    "declarationState": declaration.attributes?.appEncryptionDeclarationState.jsonSafe,
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
            _ = try await fetchBuild(buildID)
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
            let build = try await fetchBuild(buildID)
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
                checks.append(exportComplianceCheck("buildProcessing", "INFO", "Build processing is VALID."))
            case "PROCESSING":
                checks.append(exportComplianceCheck("buildProcessing", "INFO", "Build processing is still running; this does not change export-compliance status."))
            case "FAILED", "INVALID":
                checks.append(exportComplianceCheck("buildProcessing", "INFO", "Build processing failed; this does not change export-compliance status."))
            default:
                checks.append(exportComplianceCheck("buildProcessing", "INFO", "Build processing state is unavailable; this does not change export-compliance status."))
            }

            if expired == false {
                checks.append(exportComplianceCheck("buildExpiration", "INFO", "Build is not expired."))
            } else if expired == true {
                checks.append(exportComplianceCheck("buildExpiration", "INFO", "Build is expired; this does not change export-compliance status."))
            } else {
                checks.append(exportComplianceCheck("buildExpiration", "INFO", "Build expiration state is unavailable; this does not change export-compliance status."))
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
                    arguments: [
                        "build_id": buildID,
                        "uses_non_exempt_encryption": "<true-or-false>"
                    ],
                    reason: "Choose the accurate encryption answer and set it before evaluating export compliance."
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
                    if ["CREATED", "REJECTED"].contains(
                        declaration.attributes?.appEncryptionDeclarationState ?? ""
                    ) {
                        actions.append(exportComplianceAction(
                            tool: "export_compliance_create_document",
                            arguments: [
                                "declaration_id": declaration.id,
                                "file_path": "<absolute-path-to-document>"
                            ],
                            reason: "Create, transfer, commit, and poll the required document from one immutable local snapshot."
                        ))
                    } else {
                        actions.append(exportComplianceAction(
                            tool: nil,
                            arguments: [:],
                            reason: "The declaration state does not allow document creation through this API. Resolve the missing document in App Store Connect or contact Apple Support."
                        ))
                    }
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

                let documentState = document.attributes?.assetDeliveryState?.state
                if documentState == "COMPLETE" {
                    checks.append(exportComplianceCheck("documentDelivery", "PASS", "Document delivery is COMPLETE."))
                } else if documentState == "FAILED" {
                    blocked = true
                    checks.append(exportComplianceCheck("documentDelivery", "FAIL", "Document delivery FAILED."))
                    actions.append(exportComplianceAction(
                        tool: nil,
                        arguments: [:],
                        reason: "Resolve the failed document in App Store Connect or contact Apple Support; document deletion is unavailable in this API."
                    ))
                } else if documentState == "AWAITING_UPLOAD" {
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "documentDelivery",
                        "FAIL",
                        "Document delivery is AWAITING_UPLOAD."
                    ))
                    actions.append(exportComplianceAction(
                        tool: "export_compliance_upload_document",
                        arguments: [
                            "document_id": document.id,
                            "file_path": "<absolute-path-to-the-exact-reserved-bytes>",
                            "source_file_checksum": "<lowercase-md5-checksum-receipt>"
                        ],
                        reason: "Resume only with the exact immutable bytes and lowercase MD5 receipt returned by the retained precommit recovery."
                    ))
                } else if documentState == "UPLOAD_COMPLETE" {
                    pending = true
                    checks.append(exportComplianceCheck(
                        "documentDelivery",
                        "PENDING",
                        "Document upload is committed and Apple is still processing it."
                    ))
                    actions.append(exportComplianceAction(
                        tool: "export_compliance_inspect_document",
                        arguments: ["declaration_id": declaration.id],
                        reason: "Poll the existing document until delivery becomes COMPLETE or FAILED."
                    ))
                } else {
                    blocked = true
                    checks.append(exportComplianceCheck(
                        "documentDelivery",
                        "UNKNOWN",
                        "Document delivery state is unavailable or unsupported."
                    ))
                    actions.append(exportComplianceAction(
                        tool: "export_compliance_inspect_document",
                        arguments: ["declaration_id": declaration.id],
                        reason: "Inspect the existing document and resolve an unknown state in App Store Connect or with Apple Support before release."
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

    private func performDocumentUpload(
        filePath: String,
        declarationID: String?,
        existingResource: ASCExportComplianceDocument?,
        expectedChecksum: String?
    ) async -> UploadTransactionOutcome<ASCExportComplianceDocument> {
        await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "encryption document",
            expectedType: "appEncryptionDeclarationDocuments",
            reservationEndpoint: "/v1/appEncryptionDeclarationDocuments",
            httpClient: httpClient,
            uploadService: uploadService,
            cleanupPolicy: .retain(exportComplianceNoDeleteReason),
            existingResource: existingResource,
            validateSnapshot: { document, snapshot in
                if let document {
                    guard document.attributes?.fileSize == snapshot.fileSize,
                          document.attributes?.fileName == snapshot.fileName else {
                        throw ExportComplianceInputError(
                            "file name and byte size must match the existing reservation"
                        )
                    }
                }
                if let expectedChecksum,
                   snapshot.md5Checksum != expectedChecksum {
                    throw ExportComplianceInputError(
                        "snapshot bytes must match source_file_checksum exactly"
                    )
                }
            },
            validateReservedResource: { document, snapshot in
                guard document.attributes?.fileSize == snapshot.fileSize,
                      document.attributes?.fileName == snapshot.fileName else {
                    throw ExportComplianceInputError(
                        "reservation file name and byte size must match the immutable snapshot"
                    )
                }
                if let storedChecksum = document.attributes?.sourceFileChecksum {
                    guard exportComplianceIsLowercaseMD5(storedChecksum),
                          storedChecksum == snapshot.md5Checksum,
                          expectedChecksum == nil || storedChecksum == expectedChecksum else {
                        throw ExportComplianceInputError(
                            "immutable snapshot and source_file_checksum must match the checksum already stored by Apple"
                        )
                    }
                }
                guard document.attributes?.assetDeliveryState?.state == "AWAITING_UPLOAD" else {
                    throw ExportComplianceInputError(
                        "delivery state must be exactly AWAITING_UPLOAD before signed transfer"
                    )
                }
            },
            reservationFailureDisposition: { error in
                switch exportComplianceMutationState(for: error) {
                case .rejected:
                    return .rejected
                case .committedUnverified, .commitUnknown:
                    return .unresolved
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                guard let declarationID else {
                    throw ExportComplianceInputError("An existing document reservation is required")
                }
                return try JSONEncoder().encode(
                    ExportComplianceCreateDocumentRequest(
                        data: .init(
                            attributes: .init(fileSize: fileSize, fileName: fileName),
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
                )
            },
            decodeResource: { data in
                let document = try JSONDecoder()
                    .decode(ASCExportComplianceDocumentResponse.self, from: data)
                    .data
                guard document.type == "appEncryptionDeclarationDocuments",
                      exportComplianceHasUsableResourceID(document.id) else {
                    throw ExportComplianceInputError("Apple returned an unexpected document resource")
                }
                return document
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
    }

    private func pollCommittedDocument(
        _ document: ASCExportComplianceDocument
    ) async throws -> ASCExportComplianceDocument {
        var current = document
        for attempt in 0..<deliveryPollAttempts {
            guard current.attributes?.assetDeliveryState?.state == "UPLOAD_COMPLETE" else {
                return current
            }
            current = try await fetchDocument(current.id, includeUploadOperations: false)
            if attempt + 1 < deliveryPollAttempts,
               current.attributes?.assetDeliveryState?.state == "UPLOAD_COMPLETE" {
                try await Task.sleep(nanoseconds: deliveryPollIntervalNanoseconds)
            }
        }
        return current
    }

    private func fetchBuild(_ buildID: String) async throws -> ASCBuild {
        let response: ASCBuildResponse = try await httpClient.get(
            "/v1/builds/\(try ASCPathSegment.encode(buildID))",
            parameters: ["fields[builds]": exportComplianceBuildFields],
            as: ASCBuildResponse.self
        )
        guard response.data.id == buildID, response.data.type == "builds" else {
            throw ExportComplianceInputError("Apple returned an unexpected build resource")
        }
        return response.data
    }

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
            guard response.data.type == "appEncryptionDeclarationDocuments",
                  exportComplianceHasUsableResourceID(response.data.id) else {
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
            guard response.data.type == "appEncryptionDeclarations",
                  exportComplianceHasUsableResourceID(response.data.id) else {
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
    var result: [String: Any] = [
        "id": document.id,
        "type": document.type,
        "fileSize": attributes?.fileSize.jsonSafe,
        "fileName": attributes?.fileName.jsonSafe,
        "sourceFileChecksum": attributes?.sourceFileChecksum.jsonSafe,
        "deliveryState": state?.state.jsonSafe
    ]
    if let errors = state?.errors {
        result["deliveryErrors"] = exportComplianceAssetMessages(errors)
    }
    if let warnings = state?.warnings {
        result["deliveryWarnings"] = exportComplianceAssetMessages(warnings)
    }
    if attributes?.downloadUrl != nil {
        result["downloadAvailable"] = true
        result["downloadURLRedacted"] = true
    }
    if attributes?.assetToken != nil {
        result["assetTokenPresent"] = true
    }
    if let uploadOperations = attributes?.uploadOperations {
        result["uploadOperationsAvailable"] = !uploadOperations.isEmpty
        result["uploadOperationCount"] = uploadOperations.count
        result["uploadMetadataRedacted"] = !uploadOperations.isEmpty
    }
    return result
}

private func exportComplianceAssetMessages(
    _ messages: [ASCAssetDeliveryError]?
) -> [[String: Any]] {
    (messages ?? []).map { message in
        [
            "code": message.code.jsonSafe,
            "description": message.description.map(exportComplianceSafeAssetDescription).jsonSafe
        ]
    }
}

private func exportComplianceSafeAssetDescription(_ description: String) -> String {
    Redactor.redact(description).replacingOccurrences(
        of: #"(?i)https?://[^\s\"'<>]+"#,
        with: "[REDACTED_URL]",
        options: .regularExpression
    )
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
        "exportComplianceReady": status == "READY",
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

private func exportComplianceUploadDescriptor(
    documentID: String? = nil,
    declarationID: String? = nil
) -> UploadRecoveryDescriptor {
    let inspectionTool: String
    let inspectionArguments: [String: String]
    if let documentID {
        inspectionTool = "export_compliance_get_document"
        inspectionArguments = ["document_id": documentID]
    } else {
        inspectionTool = "export_compliance_inspect_document"
        inspectionArguments = ["declaration_id": declarationID ?? ""]
    }
    return UploadRecoveryDescriptor(
        resourceName: "encryption document",
        successKey: "document",
        idArgument: "document_id",
        getTool: "export_compliance_get_document",
        getIDArgument: "document_id",
        deleteTool: nil,
        inspectionTool: inspectionTool,
        inspectionArguments: inspectionArguments,
        checksumReceiptKey: "sourceFileChecksumReceipt"
    )
}

private func exportComplianceUploadResult(
    _ outcome: UploadTransactionOutcome<ASCExportComplianceDocument>,
    descriptor: UploadRecoveryDescriptor,
    filePath: String,
    authoritativeChecksum: String?
) -> CallTool.Result {
    if case .processingPending(_, let document, _) = outcome,
       document.attributes?.assetDeliveryState?.state != "UPLOAD_COMPLETE" {
        let state = document.attributes?.assetDeliveryState?.state
        return MCPResult.jsonObject(
            [
                "success": false,
                "error": "Apple returned an unknown delivery state after the document commit.",
                "document_id": document.id,
                "document": exportComplianceDocumentDictionary(document),
                "deliveryState": state.jsonSafe,
                "retrySafe": false,
                "inspection": [
                    "tool": "export_compliance_get_document",
                    "arguments": ["document_id": document.id]
                ]
            ],
            text: "Error: Apple returned an unknown delivery state after the document commit. Inspect the retained document before any retry.",
            isError: true
        )
    }

    guard var payload = UploadTransactionRecovery.failurePayload(
        for: outcome,
        descriptor: descriptor,
        format: exportComplianceDocumentDictionary
    ) else {
        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: descriptor,
            format: exportComplianceDocumentDictionary
        )
    }

    let retainedDocument: ASCExportComplianceDocument?
    if case .preCommitFailure(_, let document, _, _) = outcome,
       document.attributes?.assetDeliveryState?.state == "AWAITING_UPLOAD" {
        retainedDocument = document
    } else {
        retainedDocument = nil
    }
    if let retainedDocument,
       payload["reservationDeleted"] as? Bool == false,
       let documentID = payload["document_id"] as? String {
        let snapshotChecksum = payload["sourceFileChecksumReceipt"] as? String
        let storedChecksum = retainedDocument.attributes?.sourceFileChecksum
        let checksumBindingConflict = storedChecksum.map {
            !exportComplianceIsLowercaseMD5($0) || $0 != snapshotChecksum
        } ?? false
        if checksumBindingConflict {
            payload.removeValue(forKey: "sourceFileChecksumReceipt")
            payload["checksumBindingConflict"] = true
            payload["inspection"] = [
                "tool": descriptor.inspectionTool,
                "arguments": descriptor.inspectionArguments
            ]
        }
        let checksum = checksumBindingConflict
            ? nil
            : (storedChecksum ?? authoritativeChecksum ?? snapshotChecksum)
        if let checksum {
            payload["sourceFileChecksumReceipt"] = checksum
            payload["nextAction"] = [
                "tool": "export_compliance_upload_document",
                "arguments": [
                    "document_id": documentID,
                    "file_path": filePath,
                    "source_file_checksum": checksum
                ],
                "instruction": "Resume only with local bytes whose lowercase MD5 exactly matches this receipt."
            ]
        }
    }

    let message = payload["error"] as? String ?? "Encryption document upload failed"
    return MCPResult.jsonObject(payload, text: "Error: \(message)", isError: true)
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

private enum ExportComplianceMutationState: String {
    case committedUnverified = "committed_unverified"
    case commitUnknown = "commit_unknown"
    case rejected

    var commitConfirmed: Bool {
        switch self {
        case .committedUnverified:
            return true
        case .commitUnknown, .rejected:
            return false
        }
    }

    var retrySafe: Bool {
        switch self {
        case .rejected:
            return true
        case .committedUnverified, .commitUnknown:
            return false
        }
    }

    var needsInspection: Bool {
        switch self {
        case .committedUnverified, .commitUnknown:
            return true
        case .rejected:
            return false
        }
    }
}

private func exportComplianceMutationState(for error: Error) -> ExportComplianceMutationState {
    guard let error = error as? ASCError else {
        return .commitUnknown
    }
    switch error {
    case .network(_):
        return .commitUnknown
    case .api(_, let statusCode), .apiResponse(_, let statusCode):
        return statusCode == 408 || (500...599).contains(statusCode)
            ? .commitUnknown
            : .rejected
    case .authentication(_), .configuration(_), .parsing(_):
        return .rejected
    }
}

private func exportComplianceDeclarationCreationFailure(
    appID: String,
    state: ExportComplianceMutationState,
    reason: String
) -> CallTool.Result {
    let safeReason = Redactor.redact(reason)
    var details: [String: Value] = [
        "creationState": .string(state.rawValue),
        "commitConfirmed": .bool(state.commitConfirmed),
        "declarationIdKnown": .bool(false),
        "retrySafe": .bool(state.retrySafe)
    ]
    if state.needsInspection {
        details["inspection"] = .object([
            "tool": .string("export_compliance_list_declarations"),
            "arguments": .object(["app_id": .string(appID)])
        ])
    }
    return MCPResult.error(
        safeReason,
        details: .object(details)
    )
}

private func exportComplianceDocumentUpdateFailure(
    documentID: String,
    state: ExportComplianceMutationState,
    reason: String
) -> CallTool.Result {
    let safeReason = Redactor.redact(reason)
    var details: [String: Value] = [
        "updateState": .string(state.rawValue),
        "commitConfirmed": .bool(state.commitConfirmed),
        "retrySafe": .bool(state.retrySafe)
    ]
    if state.needsInspection {
        details["inspection"] = .object([
            "tool": .string("export_compliance_get_document"),
            "arguments": .object(["document_id": .string(documentID)])
        ])
    }
    return MCPResult.error(
        safeReason,
        details: .object(details)
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

private func exportComplianceMD5(
    _ arguments: [String: Value],
    _ field: String
) throws -> String {
    let checksum = try exportComplianceString(arguments, field)
    guard exportComplianceIsLowercaseMD5(checksum) else {
        throw ExportComplianceInputError(
            "Parameter '\(field)' must be exactly 32 lowercase hexadecimal MD5 characters"
        )
    }
    return checksum
}

private func exportComplianceIsLowercaseMD5(_ checksum: String) -> Bool {
    checksum.range(
        of: #"^[0-9a-f]{32}$"#,
        options: .regularExpression
    ) != nil
}

private func exportComplianceLimit(_ value: Value?) throws -> Int {
    guard let value else { return 25 }
    guard let limit = value.intValue, (1...200).contains(limit) else {
        throw ExportComplianceInputError("Parameter 'limit' must be an integer from 1 through 200")
    }
    return limit
}

private func exportComplianceContinuationLimit(_ nextURL: String) throws -> Int {
    guard let components = URLComponents(string: nextURL) else {
        throw ExportComplianceInputError("Parameter 'next_url' must be a valid URL")
    }
    let values = (components.queryItems ?? []).filter { $0.name == "limit" }
    guard values.count == 1,
          let rawValue = values[0].value,
          let limit = Int(rawValue),
          (1...200).contains(limit) else {
        throw ExportComplianceInputError(
            "Parameter 'next_url' must contain exactly one limit from 1 through 200"
        )
    }
    return limit
}

private func exportComplianceHasUsableResourceID(_ id: String) -> Bool {
    guard !id.isEmpty,
          id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return false
    }
    return (try? ASCPathSegment.encode(id)) != nil
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
