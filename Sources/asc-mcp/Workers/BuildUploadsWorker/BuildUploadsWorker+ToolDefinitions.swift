import Foundation
import MCP

extension BuildUploadsWorker {
    func listBuildUploadsTool() -> Tool {
        Tool(
            name: "build_uploads_list",
            description: "List build uploads for one app with Apple 4.4.1 filters, sparse fields, includes, and strict continuation validation. Transfer credentials are omitted unless include_sensitive_details is true.",
            inputSchema: objectSchema(
                properties: [
                    "app_id": identifierSchema("App Store Connect app ID"),
                    "short_version_strings": stringArraySchema("Exact CFBundleShortVersionString filters"),
                    "build_versions": stringArraySchema("Exact CFBundleVersion filters"),
                    "platforms": enumArraySchema("Platform filters", values: Self.platformValues),
                    "states": stringArraySchema("Build upload state filters"),
                    "sort": enumArraySchema(
                        "Sort expressions",
                        values: ["cfBundleVersion", "-cfBundleVersion", "uploadedDate", "-uploadedDate"]
                    ),
                    "fields_build_uploads": enumArraySchema(
                        "Sparse BuildUpload fields",
                        values: Self.buildUploadFieldValues
                    ),
                    "fields_builds": enumArraySchema("Sparse Build fields", values: Self.buildFieldValues),
                    "fields_build_upload_files": enumArraySchema(
                        "Sparse BuildUploadFile fields",
                        values: Self.buildUploadFileFieldValues
                    ),
                    "include": enumArraySchema(
                        "Relationships to include",
                        values: Self.buildUploadIncludeValues
                    ),
                    "include_sensitive_details": booleanSchema(
                        "Return path-scoped asset tokens and presigned transfer operations",
                        defaultValue: false
                    ),
                    "limit": limitSchema(),
                    "next_url": nextURLSchema()
                ],
                required: ["app_id"]
            )
        )
    }

    func getBuildUploadTool() -> Tool {
        Tool(
            name: "build_uploads_get",
            description: "Get one build upload with processing diagnostics, relationships, and optional included resources. Transfer credentials are omitted by default.",
            inputSchema: objectSchema(
                properties: [
                    "build_upload_id": identifierSchema("Build upload ID"),
                    "fields_build_uploads": enumArraySchema(
                        "Sparse BuildUpload fields",
                        values: Self.buildUploadFieldValues
                    ),
                    "fields_builds": enumArraySchema("Sparse Build fields", values: Self.buildFieldValues),
                    "fields_build_upload_files": enumArraySchema(
                        "Sparse BuildUploadFile fields",
                        values: Self.buildUploadFileFieldValues
                    ),
                    "include": enumArraySchema(
                        "Relationships to include",
                        values: Self.buildUploadIncludeValues
                    ),
                    "include_sensitive_details": booleanSchema(
                        "Return path-scoped asset tokens and presigned transfer operations",
                        defaultValue: false
                    )
                ],
                required: ["build_upload_id"]
            )
        )
    }

    func createBuildUploadTool() -> Tool {
        Tool(
            name: "build_uploads_create",
            description: "Create a build upload parent. Ambiguous POST outcomes are never replayed; exact preflight and postflight fingerprints are used only to identify a unique newly observed resource for recovery.",
            inputSchema: objectSchema(
                properties: [
                    "app_id": identifierSchema("Owning App ID"),
                    "short_version": nonemptyStringSchema("CFBundleShortVersionString"),
                    "build_version": nonemptyStringSchema("CFBundleVersion"),
                    "platform": enumSchema("Build platform", values: Self.platformValues)
                ],
                required: ["app_id", "short_version", "build_version", "platform"]
            )
        )
    }

    func deleteBuildUploadTool() -> Tool {
        Tool(
            name: "build_uploads_delete",
            description: "Delete a build upload parent and its file reservations after exact ID confirmation. Apple exposes no BuildUploadFile DELETE endpoint.",
            inputSchema: objectSchema(
                properties: [
                    "build_upload_id": identifierSchema("Build upload ID"),
                    "confirm_build_upload_id": identifierSchema(
                        "Exact build_upload_id confirmation for this destructive operation"
                    )
                ],
                required: ["build_upload_id", "confirm_build_upload_id"]
            )
        )
    }

    func listBuildUploadFilesTool() -> Tool {
        Tool(
            name: "build_uploads_list_files",
            description: "List files reserved under one build upload with strict continuation validation. Transfer credentials are omitted by default.",
            inputSchema: objectSchema(
                properties: [
                    "build_upload_id": identifierSchema("Parent build upload ID"),
                    "fields_build_upload_files": enumArraySchema(
                        "Sparse BuildUploadFile fields",
                        values: Self.buildUploadFileFieldValues
                    ),
                    "include_sensitive_details": booleanSchema(
                        "Return path-scoped asset tokens and presigned transfer operations",
                        defaultValue: false
                    ),
                    "limit": limitSchema(),
                    "next_url": nextURLSchema()
                ],
                required: ["build_upload_id"]
            )
        )
    }

    func getBuildUploadFileTool() -> Tool {
        Tool(
            name: "build_uploads_get_file",
            description: "Get one build upload file and its delivery state. Transfer credentials are omitted by default.",
            inputSchema: objectSchema(
                properties: [
                    "file_id": identifierSchema("Build upload file ID"),
                    "fields_build_upload_files": enumArraySchema(
                        "Sparse BuildUploadFile fields",
                        values: Self.buildUploadFileFieldValues
                    ),
                    "include_sensitive_details": booleanSchema(
                        "Return path-scoped asset tokens and presigned transfer operations",
                        defaultValue: false
                    )
                ],
                required: ["file_id"]
            )
        )
    }

    func reserveBuildUploadFileTool() -> Tool {
        Tool(
            name: "build_uploads_reserve_file",
            description: "Reserve one exact file under an existing build upload. Ambiguous POST outcomes are never replayed or cleaned up automatically.",
            inputSchema: objectSchema(
                properties: [
                    "build_upload_id": identifierSchema("Parent build upload ID"),
                    "asset_type": enumSchema("Build upload asset type", values: Self.assetTypeValues),
                    "file_name": fileNameSchema("File name recorded by Apple"),
                    "file_size": integerSchema(
                        "File size in bytes",
                        minimum: 1,
                        maximum: Self.maximumFileSize
                    ),
                    "uti": enumSchema("Build upload file UTI", values: Self.utiValues),
                    "include_sensitive_details": booleanSchema(
                        "Return path-scoped asset tokens and presigned transfer operations",
                        defaultValue: false
                    )
                ],
                required: ["build_upload_id", "asset_type", "file_name", "file_size", "uti"]
            )
        )
    }

    func commitBuildUploadFileTool() -> Tool {
        var schema = objectSchemaDictionary(
            properties: [
                "file_id": identifierSchema("Build upload file ID"),
                "source_file_checksums": nullableChecksumsSchema(),
                "uploaded": nullableBooleanSchema("Apple uploaded attribute")
            ],
            required: ["file_id"]
        )
        schema["anyOf"] = .array([
            .object(["required": .array([.string("source_file_checksums")])]),
            .object(["required": .array([.string("uploaded")])])
        ])
        return Tool(
            name: "build_uploads_commit_file",
            description: "Commit one build upload file with sourceFileChecksums and/or uploaded. Omission and explicit null remain distinct; an ambiguous PATCH is inspected but never replayed or inferred from state alone.",
            inputSchema: .object(schema)
        )
    }

    func uploadBuildFileTool() -> Tool {
        var schema = objectSchemaDictionary(
            properties: [
                "build_upload_id": identifierSchema("Existing build upload ID"),
                "file_id": identifierSchema("Existing BuildUploadFile ID to resume"),
                "file_path": absolutePathSchema("Absolute path to the upload file"),
                "expected_md5": .object([
                    "type": .string("string"),
                    "pattern": .string(#"^[A-Fa-f0-9]{32}$"#),
                    "description": .string("Expected MD5 of the immutable snapshot; required when resuming an existing file reservation")
                ]),
                "asset_type": enumSchema("Required for a new reservation", values: Self.assetTypeValues),
                "uti": enumSchema("Required for a new reservation", values: Self.utiValues),
                "max_transfer_attempts": integerSchema(
                    "Maximum attempts for each retry-safe presigned part",
                    minimum: 1,
                    maximum: 5,
                    defaultValue: 3
                )
            ],
            required: ["build_upload_id", "file_path"]
        )
        schema["oneOf"] = .array([
            .object(["required": .array([.string("file_id"), .string("expected_md5")])]),
            .object([
                "required": .array([.string("asset_type"), .string("uti")]),
                "not": .object(["required": .array([.string("file_id")])])
            ])
        ])
        return Tool(
            name: "build_uploads_upload_file",
            description: "Reserve and transfer a new file, or resume an existing file after validating parent membership and the immutable snapshot fingerprint. Existing parents are never deleted automatically.",
            inputSchema: .object(schema)
        )
    }

    func uploadBuildTool() -> Tool {
        Tool(
            name: "build_uploads_upload",
            description: "Upload a build from an immutable snapshot through parent creation, file reservation, presigned transfer, commit, and processing reconciliation. Automatic cleanup is limited to a parent conclusively created by this invocation before commit starts.",
            inputSchema: objectSchema(
                properties: [
                    "app_id": identifierSchema("Owning App ID"),
                    "file_path": absolutePathSchema("Absolute path to an IPA, PKG, ZIP, or property-list file"),
                    "short_version": nonemptyStringSchema("CFBundleShortVersionString"),
                    "build_version": nonemptyStringSchema("CFBundleVersion"),
                    "platform": enumSchema("Build platform", values: Self.platformValues),
                    "asset_type": enumSchema(
                        "Build upload asset type",
                        values: Self.assetTypeValues,
                        defaultValue: "ASSET"
                    ),
                    "uti": enumSchema("Build upload file UTI", values: Self.utiValues),
                    "max_transfer_attempts": integerSchema(
                        "Maximum attempts for each retry-safe presigned part",
                        minimum: 1,
                        maximum: 5,
                        defaultValue: 3
                    )
                ],
                required: ["app_id", "file_path", "short_version", "build_version", "platform", "uti"]
            )
        )
    }

    private func objectSchema(properties: [String: Value], required: [String]) -> Value {
        .object(objectSchemaDictionary(properties: properties, required: required))
    }

    private func objectSchemaDictionary(
        properties: [String: Value],
        required: [String]
    ) -> [String: Value] {
        var schema: [String: Value] = [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return schema
    }

    private func identifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#),
            "description": .string("\(description); canonical App Store Connect resource ID")
        ])
    }

    private func nonemptyStringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1),
            "pattern": .string(#"^\S(?:.*\S)?$"#)
        ])
    }

    private func absolutePathSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(2),
            "pattern": .string(#"^/"#)
        ])
    }

    private func fileNameSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1),
            "pattern": .string(#"^(?!\.{1,2}$)(?!\s)(?!.*\s$)[^/\\\u0000-\u001F\u007F]+$"#)
        ])
    }

    private func stringArraySchema(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object([
                "type": .string("string"),
                "minLength": .int(1),
                "pattern": .string(#"^(?!\s)(?!.*\s$)[^,\u0000-\u001F\u007F]+$"#)
            ]),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ])
    }

    private func enumArraySchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object([
                "type": .string("string"),
                "enum": .array(values.map(Value.string))
            ]),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ])
    }

    private func enumSchema(
        _ description: String,
        values: [String],
        defaultValue: String? = nil
    ) -> Value {
        var schema: [String: Value] = [
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string))
        ]
        if let defaultValue {
            schema["default"] = .string(defaultValue)
        }
        return .object(schema)
    }

    private func booleanSchema(_ description: String, defaultValue: Bool? = nil) -> Value {
        var schema: [String: Value] = [
            "type": .string("boolean"),
            "description": .string(description)
        ]
        if let defaultValue {
            schema["default"] = .bool(defaultValue)
        }
        return .object(schema)
    }

    private func nullableBooleanSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
            "description": .string(description)
        ])
    }

    private func integerSchema(
        _ description: String,
        minimum: Int,
        maximum: Int,
        defaultValue: Int? = nil
    ) -> Value {
        var schema: [String: Value] = [
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(minimum),
            "maximum": .int(maximum)
        ]
        if let defaultValue {
            schema["default"] = .int(defaultValue)
        }
        return .object(schema)
    }

    private func nullableChecksumsSchema() -> Value {
        .object([
            "type": .array([.string("object"), .string("null")]),
            "description": .string("Apple Checksums object, or explicit null"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "file": checksumSchema(algorithms: ["MD5", "SHA_256"]),
                "composite": checksumSchema(algorithms: ["MD5"])
            ])
        ])
    }

    private func checksumSchema(algorithms: [String]) -> Value {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "hash": nonemptyStringSchema("Checksum hash"),
                "algorithm": enumSchema("Checksum algorithm", values: algorithms)
            ])
        ])
    }

    private func limitSchema() -> Value {
        integerSchema("Maximum resources per page", minimum: 1, maximum: 200, defaultValue: 25)
    }

    private func nextURLSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "description": .string("Exact next_url returned by this tool. Repeat the same parent ID and every originating filter, field, include, sensitive-details flag, and effective or default limit; the path, exact query, and non-empty cursor are validated")
        ])
    }

    static let platformValues = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
    static let maximumFileSize = 9_007_199_254_740_991
    static let assetTypeValues = ["ASSET", "ASSET_DESCRIPTION", "ASSET_SPI"]
    static let utiValues = [
        "com.apple.binary-property-list",
        "com.apple.ipa",
        "com.apple.pkg",
        "com.apple.xml-property-list",
        "com.pkware.zip-archive"
    ]
    static let buildUploadFieldValues = [
        "cfBundleShortVersionString", "cfBundleVersion", "createdDate", "state", "platform",
        "uploadedDate", "build", "assetFile", "assetDescriptionFile", "assetSpiFile", "buildUploadFiles"
    ]
    static let buildUploadFileFieldValues = [
        "assetDeliveryState", "assetToken", "assetType", "fileName", "fileSize",
        "sourceFileChecksums", "uploadOperations", "uti"
    ]
    static let sensitiveBuildUploadFileFieldValues: Set<String> = ["assetToken", "uploadOperations"]
    static let buildUploadIncludeValues = ["build", "assetFile", "assetDescriptionFile", "assetSpiFile"]
    static let buildUploadStateValues = ["AWAITING_UPLOAD", "PROCESSING", "FAILED", "COMPLETE"]
    static let buildUploadFileStateValues = ["AWAITING_UPLOAD", "UPLOAD_COMPLETE", "COMPLETE", "FAILED"]
    static let buildUploadIncludedTypes: Set<String> = ["buildUploadFiles", "builds"]
    static let buildFieldValues = [
        "version", "uploadedDate", "expirationDate", "expired", "minOsVersion",
        "lsMinimumSystemVersion", "computedMinMacOsVersion", "computedMinVisionOsVersion",
        "iconAssetToken", "processingState", "buildAudienceType", "usesNonExemptEncryption",
        "preReleaseVersion", "individualTesters", "betaGroups", "betaBuildLocalizations",
        "appEncryptionDeclaration", "betaAppReviewSubmission", "app", "buildBetaDetail",
        "appStoreVersion", "icons", "buildBundles", "buildUpload", "perfPowerMetrics",
        "diagnosticSignatures"
    ]
}
