import Testing
@testable import asc_mcp

@Suite("Build Uploads Manifest Contract Tests")
struct BuildUploadsManifestContractTests {
    @Test("manifest maps ten tools to eight Apple operations and keeps only linkage waivers")
    func lineageAndCoverage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "build_uploads" }
        )

        let expected: [String: Set<String>] = [
            "build_uploads_list": ["apps_buildUploads_getToManyRelated"],
            "build_uploads_get": ["buildUploads_getInstance"],
            "build_uploads_create": [
                "apps_buildUploads_getToManyRelated",
                "buildUploads_createInstance"
            ],
            "build_uploads_delete": ["buildUploads_deleteInstance"],
            "build_uploads_list_files": ["buildUploads_buildUploadFiles_getToManyRelated"],
            "build_uploads_get_file": ["buildUploadFiles_getInstance"],
            "build_uploads_reserve_file": [
                "buildUploads_buildUploadFiles_getToManyRelated",
                "buildUploadFiles_createInstance"
            ],
            "build_uploads_commit_file": [
                "buildUploadFiles_updateInstance",
                "buildUploadFiles_getInstance"
            ],
            "build_uploads_upload_file": [
                "buildUploads_getInstance",
                "buildUploads_buildUploadFiles_getToManyRelated",
                "buildUploadFiles_createInstance",
                "buildUploadFiles_getInstance",
                "buildUploadFiles_updateInstance"
            ],
            "build_uploads_upload": [
                "apps_buildUploads_getToManyRelated",
                "buildUploads_createInstance",
                "buildUploads_buildUploadFiles_getToManyRelated",
                "buildUploadFiles_createInstance",
                "buildUploadFiles_updateInstance",
                "buildUploadFiles_getInstance",
                "buildUploads_getInstance",
                "buildUploads_deleteInstance"
            ]
        ]

        #expect(worker.tools.count == 10)
        #expect(Set(worker.tools.map(\.tool)) == Set(expected.keys))
        for (tool, operations) in expected {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(Set(mapping.operations.map(\.operationID)) == operations)
            #expect(mapping.implementationState == .asBuilt)
        }

        let uniqueBuildUploadOperations = Set(worker.tools.flatMap(\.operations).map(\.operationID))
        #expect(uniqueBuildUploadOperations.count == 8)
        #expect(Set(manifest.tools.flatMap(\.operations).map(\.operationID)).count == 441)
        #expect(manifest.index.waivers.count == 459)
        #expect(manifest.index.specPin.operationCount == 1_263)
        #expect(441 + 459 + 363 == manifest.index.specPin.operationCount)

        let buildUploadWaivers = Set(
            manifest.index.waivers.compactMap(\.operationID).filter {
                $0.contains("buildUpload")
            }
        )
        #expect(buildUploadWaivers == [
            "apps_buildUploads_getToManyRelationship",
            "buildUploads_buildUploadFiles_getToManyRelationship"
        ])
        #expect(manifest.index.waivers.allSatisfy { waiver in
            waiver.operationID.map { !uniqueBuildUploadOperations.contains($0) } ?? true
        })

        let pin = try #require(manifest.index.optionalInputCoveragePin)
        #expect(pin.total == 2_548)
        #expect(pin.bound == 993)
        #expect(pin.internalControl == 40)
        #expect(pin.intentionallyOmitted == 1_515)
        #expect(pin.unclassified == 0)
        #expect(pin.identitySHA256 == "00b48805d61ba3849f940f2e7c020817882a0e942b8eef0bea14e81089d13323")
    }

    @Test("operation methods paths statuses and effects are exact")
    func exactOperationsAndStatuses() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "build_uploads" }
        )
        let expected: [String: (method: String, path: String, status: String)] = [
            "apps_buildUploads_getToManyRelated": ("get", "/v1/apps/{id}/buildUploads", "200"),
            "buildUploads_getInstance": ("get", "/v1/buildUploads/{id}", "200"),
            "buildUploads_createInstance": ("post", "/v1/buildUploads", "201"),
            "buildUploads_deleteInstance": ("delete", "/v1/buildUploads/{id}", "204"),
            "buildUploads_buildUploadFiles_getToManyRelated": ("get", "/v1/buildUploads/{id}/buildUploadFiles", "200"),
            "buildUploadFiles_getInstance": ("get", "/v1/buildUploadFiles/{id}", "200"),
            "buildUploadFiles_createInstance": ("post", "/v1/buildUploadFiles", "201"),
            "buildUploadFiles_updateInstance": ("patch", "/v1/buildUploadFiles/{id}", "200")
        ]

        for mapping in worker.tools {
            for operation in mapping.operations {
                let contract = try #require(expected[operation.operationID])
                #expect(operation.method == contract.method)
                #expect(operation.path == contract.path)
                #expect(mapping.response.sources.contains {
                    $0.operationID == operation.operationID && $0.statusCode == contract.status
                })
            }
        }

        let effects = Dictionary(uniqueKeysWithValues: worker.tools.map { ($0.tool, $0.effect) })
        for tool in [
            "build_uploads_list",
            "build_uploads_get",
            "build_uploads_list_files",
            "build_uploads_get_file"
        ] {
            #expect(effects[tool] == .read)
        }
        for tool in [
            "build_uploads_create",
            "build_uploads_reserve_file",
            "build_uploads_commit_file",
            "build_uploads_upload_file",
            "build_uploads_upload"
        ] {
            #expect(effects[tool] == .write)
        }
        #expect(effects["build_uploads_delete"] == .destructive)
        #expect(Set(worker.tools.filter { $0.kind == .compound }.map(\.tool)) == [
            "build_uploads_create",
            "build_uploads_reserve_file",
            "build_uploads_commit_file",
            "build_uploads_upload_file",
            "build_uploads_upload"
        ])
        #expect(worker.tools.flatMap(\.operations).allSatisfy {
            $0.operationID != "buildUploadFiles_deleteInstance"
        })
    }

    @Test("recovery transfer and sensitive-output guardrails stay explicit")
    func recoveryAndSecurityGuardrails() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let worker = try #require(
            manifest.workers.first { $0.workerKey == "build_uploads" }
        )
        let delete = try #require(manifest.mapping(for: "build_uploads_delete"))
        #expect(delete.fields.contains {
            $0.toolField == "confirm_build_upload_id" &&
                $0.sourceKind == .local &&
                $0.localRole?.contains("before any network request") == true
        })
        #expect(Set(delete.response.fields.map(\.outputField)).isSuperset(of: [
            "buildUploadId", "operationCommitState", "inspectionRequired", "inspection", "retrySafe"
        ]))

        for tool in ["build_uploads_create", "build_uploads_reserve_file"] {
            let mapping = try #require(manifest.mapping(for: tool))
            #expect(mapping.note?.contains("20 strict pages") == true)
            #expect(mapping.note?.contains("call stops") == true)
            #expect(mapping.note?.contains("safe to retry") == true)
            #expect(Set(mapping.response.fields.map(\.outputField)).isSuperset(of: [
                "candidateId",
                "candidateAttributionConfirmed",
                "workflowState",
                "createdByInvocation",
                "reconciledAfterCreate",
                "automaticDeletionAllowed",
                "operationCommitState",
                "inspectionRequired",
                "inspection",
                "retrySafe"
            ]))
            #expect(mapping.note?.contains("success false") == true)
            #expect(mapping.note?.contains("fresh membership") == true)
        }

        let commit = try #require(manifest.mapping(for: "build_uploads_commit_file"))
        let commitStateRole = try #require(
            commit.response.fields.first { $0.outputField == "operationCommitState" }?.localRole
        )
        #expect(commitStateRole.contains("committed only for an exact PATCH 200"))
        #expect(Set(commit.response.fields.map(\.outputField)).isSuperset(of: [
            "fileId", "inspectionRequired", "inspection"
        ]))
        #expect(commit.note?.contains("even if that GET fails") == true)

        let fullUpload = try #require(manifest.mapping(for: "build_uploads_upload"))
        let workflowStateRole = try #require(
            fullUpload.response.fields.first { $0.outputField == "workflowState" }?.localRole
        )
        #expect(workflowStateRole.contains("parent_unresolved"))

        for tool in ["build_uploads_upload_file", "build_uploads_upload"] {
            let mapping = try #require(manifest.mapping(for: tool))
            let fields = Set(mapping.response.fields.map(\.outputField))
            #expect(fields.isSuperset(of: [
                "workflowState",
                "checksumEvidence",
                "candidateAttributionConfirmed",
                "operationCommitState",
                "continuationRequired",
                "buildUploadId",
                "fileId",
                "parentDeleted",
                "continuation",
                "retrySafe"
            ]))
            #expect(mapping.note?.contains("MD5") == true)
            #expect(mapping.note?.contains("explicit PUT") == true)
            #expect(mapping.note?.contains("redirect") == true)
            #expect(mapping.note?.contains("checksum_inspection_required") == true)
            #expect(mapping.note?.contains("committed_unverified") == true)

            let workflowRole = try #require(
                mapping.response.fields.first { $0.outputField == "workflowState" }?.localRole
            )
            #expect(workflowRole.contains("checksum_inspection_required"))
            #expect(workflowRole.contains("UPLOAD_COMPLETE or COMPLETE"))

            let checksumEvidenceRole = try #require(
                mapping.response.fields.first { $0.outputField == "checksumEvidence" }?.localRole
            )
            #expect(checksumEvidenceRole.contains("snapshotChecksum"))
            #expect(checksumEvidenceRole.contains("verified false"))
            #expect(checksumEvidenceRole.contains("transfer and PATCH are not attempted"))
            #expect(checksumEvidenceRole.contains("retained for inspection"))

            let retryRole = try #require(
                mapping.fields.first { $0.toolField == "max_transfer_attempts" }?.localRole
            )
            #expect(retryRole.contains("explicitly specifies PUT"))
            #expect(retryRole.contains("one attempt"))
            #expect(retryRole.contains("JWT"))

            let continuationRole = try #require(
                mapping.response.fields.first { $0.outputField == "continuation" }?.localRole
            )
            #expect(continuationRole.contains("expected_md5"))
        }

        let uploadFile = try #require(manifest.mapping(for: "build_uploads_upload_file"))
        let expectedMD5 = try #require(
            uploadFile.fields.first { $0.toolField == "expected_md5" }
        )
        let expectedMD5Role = try #require(expectedMD5.localRole)
        #expect(expectedMD5.sourceKind == .local)
        #expect(expectedMD5Role.contains("required whenever file_id"))
        #expect(expectedMD5Role.contains("recovered-parent continuation"))
        #expect(expectedMD5Role.contains("fresh mode-0600 immutable snapshot"))
        #expect(expectedMD5Role.contains("before any Apple API request or presigned transfer"))

        let recoveryConditions = worker.tools
            .filter { $0.kind == .compound }
            .flatMap(\.operations)
            .compactMap(\.condition)
        #expect(recoveryConditions.filter { $0.contains("at most 20 pages") }.count == 5)

        let sensitiveControls = worker.tools.flatMap(\.fields).filter {
            $0.toolField == "include_sensitive_details"
        }
        #expect(sensitiveControls.count == 5)
        #expect(sensitiveControls.allSatisfy {
            $0.localRole?.contains("path") == true &&
                $0.localRole?.contains("redact") == true
        })
    }
}
