import MCP

// MARK: - Tool Definitions

extension ExportComplianceWorker {
    func listDeclarationsTool() -> Tool {
        Tool(
            name: "export_compliance_list_declarations",
            description: "List export-compliance declarations for one app with strict pagination and approval state metadata",
            inputSchema: exportComplianceSchema(
                properties: [
                    "app_id": exportComplianceID("App ID"),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Results per page (default 25, maximum 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Unmodified next_url returned by this tool")
                    ])
                ],
                required: ["app_id"]
            )
        )
    }

    func getDeclarationTool() -> Tool {
        Tool(
            name: "export_compliance_get_declaration",
            description: "Get one export-compliance declaration without deprecated document URL fields",
            inputSchema: exportComplianceSchema(
                properties: ["declaration_id": exportComplianceID("Declaration ID")],
                required: ["declaration_id"]
            )
        )
    }

    func createDeclarationTool() -> Tool {
        Tool(
            name: "export_compliance_create_declaration",
            description: "Create an export-compliance declaration questionnaire for an app",
            inputSchema: exportComplianceSchema(
                properties: [
                    "app_id": exportComplianceID("App ID"),
                    "app_description": .object([
                        "type": .string("string"),
                        "minLength": .int(1),
                        "description": .string("Plain-language description of the app and its encryption use")
                    ]),
                    "contains_proprietary_cryptography": exportComplianceBoolean(
                        "Whether the app contains proprietary cryptography"
                    ),
                    "contains_third_party_cryptography": exportComplianceBoolean(
                        "Whether the app contains third-party cryptography"
                    ),
                    "available_on_french_store": exportComplianceBoolean(
                        "Whether the app will be available on the French App Store"
                    )
                ],
                required: [
                    "app_id",
                    "app_description",
                    "contains_proprietary_cryptography",
                    "contains_third_party_cryptography",
                    "available_on_french_store"
                ]
            )
        )
    }

    func createDocumentTool() -> Tool {
        Tool(
            name: "export_compliance_create_document",
            description: "Reserve an encryption-declaration document upload from a local file; signed upload secrets are never returned",
            inputSchema: exportComplianceSchema(
                properties: [
                    "declaration_id": exportComplianceID("Declaration ID"),
                    "file_path": exportComplianceFilePath()
                ],
                required: ["declaration_id", "file_path"]
            )
        )
    }

    func getDocumentTool() -> Tool {
        Tool(
            name: "export_compliance_get_document",
            description: "Get safe document delivery and download-availability metadata without signed URLs, tokens, or upload headers",
            inputSchema: exportComplianceSchema(
                properties: ["document_id": exportComplianceID("Document ID")],
                required: ["document_id"]
            )
        )
    }

    func updateDocumentTool() -> Tool {
        Tool(
            name: "export_compliance_update_document",
            description: "Apply a low-level nullable checksum or uploaded-state patch to a reserved encryption document",
            inputSchema: exportComplianceSchema(
                properties: [
                    "document_id": exportComplianceID("Document ID"),
                    "source_file_checksum": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "minLength": .int(1),
                        "description": .string("MD5 checksum, or null to clear it")
                    ]),
                    "uploaded": .object([
                        "type": .array([.string("boolean"), .string("null")]),
                        "description": .string("Upload completion flag, or null to clear it")
                    ])
                ],
                required: ["document_id"]
            )
        )
    }

    func uploadDocumentTool() -> Tool {
        Tool(
            name: "export_compliance_upload_document",
            description: "Transfer, commit, and poll an existing document reservation using a stable local file snapshot",
            inputSchema: exportComplianceSchema(
                properties: [
                    "document_id": exportComplianceID("Reserved document ID"),
                    "file_path": exportComplianceFilePath()
                ],
                required: ["document_id", "file_path"]
            )
        )
    }

    func inspectDocumentTool() -> Tool {
        Tool(
            name: "export_compliance_inspect_document",
            description: "Inspect whether a declaration has a document and classify its delivery state",
            inputSchema: exportComplianceSchema(
                properties: ["declaration_id": exportComplianceID("Declaration ID")],
                required: ["declaration_id"]
            )
        )
    }

    func getBuildDeclarationTool() -> Tool {
        Tool(
            name: "export_compliance_get_build_declaration",
            description: "Get the export-compliance declaration currently attached to a build, or report that none is attached",
            inputSchema: exportComplianceSchema(
                properties: ["build_id": exportComplianceID("Build ID")],
                required: ["build_id"]
            )
        )
    }

    func attachBuildDeclarationTool() -> Tool {
        Tool(
            name: "export_compliance_attach_build_declaration",
            description: "Attach an approved declaration through the supported build update API and verify the resulting relationship",
            inputSchema: exportComplianceSchema(
                properties: [
                    "build_id": exportComplianceID("Build ID"),
                    "declaration_id": exportComplianceID("Approved declaration ID")
                ],
                required: ["build_id", "declaration_id"]
            )
        )
    }

    func checkReleaseReadinessTool() -> Tool {
        Tool(
            name: "export_compliance_check_release_readiness",
            description: "Evaluate the build's export-compliance release gate; other App Store release requirements remain not determined",
            inputSchema: exportComplianceSchema(
                properties: ["build_id": exportComplianceID("Build ID")],
                required: ["build_id"]
            )
        )
    }
}

private func exportComplianceSchema(properties: [String: Value], required: [String]) -> Value {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map(Value.string)),
        "additionalProperties": .bool(false)
    ])
}

private func exportComplianceID(_ description: String) -> Value {
    .object([
        "type": .string("string"),
        "minLength": .int(1),
        "description": .string(description)
    ])
}

private func exportComplianceBoolean(_ description: String) -> Value {
    .object([
        "type": .string("boolean"),
        "description": .string(description)
    ])
}

private func exportComplianceFilePath() -> Value {
    .object([
        "type": .string("string"),
        "minLength": .int(1),
        "pattern": .string("^/"),
        "description": .string("Absolute local path to the document file")
    ])
}
