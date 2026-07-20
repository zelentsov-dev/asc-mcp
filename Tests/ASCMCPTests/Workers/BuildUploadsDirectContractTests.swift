import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Build Uploads Direct Contract Tests")
struct BuildUploadsDirectContractTests {
    @Test("worker exposes ten bounded tools and conditional schemas")
    func toolSchemas() async throws {
        let worker = BuildUploadsWorker(
            httpClient: try await TestFactory.makeHTTPClient(),
            uploadService: UploadService()
        )
        let tools = await worker.getTools()

        #expect(tools.count == 10)
        #expect(Set(tools.map(\.name)) == [
            "build_uploads_list",
            "build_uploads_get",
            "build_uploads_create",
            "build_uploads_delete",
            "build_uploads_list_files",
            "build_uploads_get_file",
            "build_uploads_reserve_file",
            "build_uploads_commit_file",
            "build_uploads_upload_file",
            "build_uploads_upload"
        ])
        for tool in tools {
            let schema = try directObject(tool.inputSchema)
            #expect(schema["additionalProperties"] == .bool(false))
        }

        let commit = try directObject(try #require(
            tools.first { $0.name == "build_uploads_commit_file" }
        ).inputSchema)
        #expect(commit["anyOf"]?.arrayValue?.count == 2)

        let uploadFile = try directObject(try #require(
            tools.first { $0.name == "build_uploads_upload_file" }
        ).inputSchema)
        #expect(uploadFile["oneOf"]?.arrayValue?.count == 2)
        let uploadBranches = try #require(uploadFile["oneOf"]?.arrayValue)
        let uploadBranchRequirements = try uploadBranches.map {
            try directStringSet(try directObject($0)["required"])
        }
        #expect(uploadBranchRequirements.contains(Set(["file_id", "expected_md5"])))
        let uploadProperties = try directObject(uploadFile["properties"])
        #expect(
            uploadProperties["expected_md5"]?.objectValue?["pattern"] ==
                .string(#"^[A-Fa-f0-9]{32}$"#)
        )

        let delete = try directObject(try #require(
            tools.first { $0.name == "build_uploads_delete" }
        ).inputSchema)
        #expect(try directStringSet(delete["required"]) == [
            "build_upload_id", "confirm_build_upload_id"
        ])

        let list = try directObject(try #require(
            tools.first { $0.name == "build_uploads_list" }
        ).inputSchema)
        let listProperties = try directObject(list["properties"])
        let states = try directObject(listProperties["states"])
        let stateItems = try directObject(states["items"])
        #expect(
            stateItems["pattern"] ==
                .string(#"^(?!\s)(?!.*\s$)[^,\u0000-\u001F\u007F]+$"#)
        )
    }

    @Test("direct mutations emit exact Apple resource bodies and statuses")
    func directMutationBodies() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploads),
            .init(statusCode: 201, body: directBuildUploadDocument(id: "upload-1")),
            .init(statusCode: 200, body: directBuildUploadsList(ids: ["upload-1"])),
            .init(statusCode: 200, body: directEmptyBuildUploadFiles),
            .init(statusCode: 201, body: directBuildUploadFileDocument(id: "file-1")),
            .init(statusCode: 200, body: directBuildUploadFilesList(ids: ["file-1"])),
            .init(statusCode: 200, body: directBuildUploadFileDocument(id: "file-1", state: "UPLOAD_COMPLETE"))
        ])
        let worker = try await makeDirectBuildUploadsWorker(transport: transport)

        let create = try await worker.handleTool(.init(
            name: "build_uploads_create",
            arguments: [
                "app_id": .string("app-1"),
                "short_version": .string("2.4.0"),
                "build_version": .string("240"),
                "platform": .string("IOS")
            ]
        ))
        #expect(create.isError != true)

        let reserve = try await worker.handleTool(.init(
            name: "build_uploads_reserve_file",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "asset_type": .string("ASSET"),
                "file_name": .string("Example.ipa"),
                "file_size": .int(3),
                "uti": .string("com.apple.ipa")
            ]
        ))
        #expect(reserve.isError != true)

        let commit = try await worker.handleTool(.init(
            name: "build_uploads_commit_file",
            arguments: [
                "file_id": .string("file-1"),
                "source_file_checksums": .null,
                "uploaded": .null
            ]
        ))
        #expect(commit.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET", "PATCH"
        ])

        let createData = try directRequestData(requests[1])
        #expect(createData["type"] as? String == "buildUploads")
        let createAttributes = try directJSONObject(createData["attributes"])
        #expect(createAttributes["cfBundleShortVersionString"] as? String == "2.4.0")
        #expect(createAttributes["cfBundleVersion"] as? String == "240")
        #expect(createAttributes["platform"] as? String == "IOS")
        let createRelationships = try directJSONObject(createData["relationships"])
        let app = try directJSONObject(createRelationships["app"])
        let appData = try directJSONObject(app["data"])
        #expect(appData["type"] as? String == "apps")
        #expect(appData["id"] as? String == "app-1")

        let reserveData = try directRequestData(requests[4])
        #expect(reserveData["type"] as? String == "buildUploadFiles")
        let reserveAttributes = try directJSONObject(reserveData["attributes"])
        #expect(reserveAttributes["assetType"] as? String == "ASSET")
        #expect(reserveAttributes["fileName"] as? String == "Example.ipa")
        #expect(reserveAttributes["fileSize"] as? Int == 3)
        #expect(reserveAttributes["uti"] as? String == "com.apple.ipa")
        let reserveRelationships = try directJSONObject(reserveData["relationships"])
        let parent = try directJSONObject(reserveRelationships["buildUpload"])
        let parentData = try directJSONObject(parent["data"])
        #expect(parentData["type"] as? String == "buildUploads")
        #expect(parentData["id"] as? String == "upload-1")

        let commitData = try directRequestData(requests[6])
        #expect(commitData["type"] as? String == "buildUploadFiles")
        #expect(commitData["id"] as? String == "file-1")
        let commitAttributes = try directJSONObject(commitData["attributes"])
        #expect(Set(commitAttributes.keys) == ["sourceFileChecksums", "uploaded"])
        #expect(commitAttributes["sourceFileChecksums"] is NSNull)
        #expect(commitAttributes["uploaded"] is NSNull)
    }

    @Test("unexpected successful mutation statuses remain unverified and are never replayed")
    func unexpectedMutationStatuses() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploads),
            .init(statusCode: 200, body: directBuildUploadDocument(id: "upload-unverified")),
            .init(statusCode: 200, body: directEmptyBuildUploads)
        ])
        let createWorker = try await makeDirectBuildUploadsWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "build_uploads_create",
            arguments: [
                "app_id": .string("app-1"),
                "short_version": .string("2.4.0"),
                "build_version": .string("240"),
                "platform": .string("IOS")
            ]
        ))
        let createPayload = try directResultObject(create)
        #expect(create.isError == true)
        #expect(createPayload["operationCommitState"] == .string("committed_unverified"))
        #expect((await createTransport.recordedRequests()).filter { $0.httpMethod == "POST" }.count == 1)

        let reserveTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploadFiles),
            .init(statusCode: 202, body: directBuildUploadFileDocument(id: "file-unverified")),
            .init(statusCode: 200, body: directEmptyBuildUploadFiles)
        ])
        let reserveWorker = try await makeDirectBuildUploadsWorker(transport: reserveTransport)
        let reserve = try await reserveWorker.handleTool(.init(
            name: "build_uploads_reserve_file",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "asset_type": .string("ASSET"),
                "file_name": .string("Example.ipa"),
                "file_size": .int(3),
                "uti": .string("com.apple.ipa")
            ]
        ))
        let reservePayload = try directResultObject(reserve)
        #expect(reserve.isError == true)
        #expect(reservePayload["operationCommitState"] == .string("committed_unverified"))
        #expect((await reserveTransport.recordedRequests()).filter { $0.httpMethod == "POST" }.count == 1)

        let patchTransport = TestHTTPTransport(responses: [
            .init(statusCode: 202, body: directBuildUploadFileDocument(id: "file-1")),
            .init(statusCode: 200, body: directBuildUploadFileDocument(id: "file-1", state: "COMPLETE"))
        ])
        let patchWorker = try await makeDirectBuildUploadsWorker(transport: patchTransport)
        let patch = try await patchWorker.handleTool(.init(
            name: "build_uploads_commit_file",
            arguments: ["file_id": .string("file-1"), "uploaded": .bool(true)]
        ))
        let patchPayload = try directResultObject(patch)
        #expect(patch.isError == true)
        #expect(patchPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(patchPayload["commitState"] == .string("committed_unverified"))
        #expect((await patchTransport.recordedRequests()).map(\.httpMethod) == ["PATCH", "GET"])
    }

    @Test("unique ambiguous create and reservation candidates fail closed")
    func ambiguousCandidatesRequireInspection() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploads),
            .init(statusCode: 200, body: directBuildUploadDocument(id: "upload-candidate")),
            .init(statusCode: 200, body: directBuildUploadsList(ids: ["upload-candidate"]))
        ])
        let createWorker = try await makeDirectBuildUploadsWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "build_uploads_create",
            arguments: [
                "app_id": .string("app-1"),
                "short_version": .string("2.4.0"),
                "build_version": .string("240"),
                "platform": .string("IOS")
            ]
        ))
        let createPayload = try directResultObject(create)
        let createCandidate = try directObject(createPayload["buildUpload"])
        let createInspection = try directObject(createPayload["inspection"])
        let createInspectionArguments = try directObject(createInspection["arguments"])

        #expect(create.isError == true)
        #expect(createPayload["success"] == .bool(false))
        #expect(createPayload["candidateAttributionConfirmed"] == .bool(false))
        #expect(createPayload["inspectionRequired"] == .bool(true))
        #expect(createPayload["createdByInvocation"] == .bool(false))
        #expect(createPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(createPayload["retrySafe"] == .bool(false))
        #expect(createCandidate["id"] == .string("upload-candidate"))
        #expect(createInspection["tool"] == .string("build_uploads_get"))
        #expect(createInspectionArguments["build_upload_id"] == .string("upload-candidate"))
        #expect((await createTransport.recordedRequests()).map(\.httpMethod) == ["GET", "POST", "GET"])

        let reserveTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploadFiles),
            .init(statusCode: 408, body: "{}"),
            .init(
                statusCode: 200,
                body: directBuildUploadFilesList(
                    ids: ["file-candidate"],
                    includeCredentials: true
                )
            )
        ])
        let reserveWorker = try await makeDirectBuildUploadsWorker(transport: reserveTransport)
        let reserve = try await reserveWorker.handleTool(.init(
            name: "build_uploads_reserve_file",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "asset_type": .string("ASSET"),
                "file_name": .string("Example.ipa"),
                "file_size": .int(3),
                "uti": .string("com.apple.ipa"),
                "include_sensitive_details": .bool(true)
            ]
        ))
        let reservePayload = try directResultObject(reserve)
        let reserveCandidate = try directObject(reservePayload["buildUploadFile"])
        let reserveInspection = try directObject(reservePayload["inspection"])
        let reserveInspectionArguments = try directObject(reserveInspection["arguments"])

        #expect(reserve.isError == true)
        #expect(reservePayload["success"] == .bool(false))
        #expect(reservePayload["candidateAttributionConfirmed"] == .bool(false))
        #expect(reservePayload["inspectionRequired"] == .bool(true))
        #expect(reservePayload["createdByInvocation"] == .bool(false))
        #expect(reservePayload["operationCommitState"] == .string("unknown"))
        #expect(reservePayload["outcomeUnknown"] == .bool(true))
        #expect(reservePayload["operationCommitted"] == nil)
        #expect(reservePayload["retrySafe"] == .bool(false))
        #expect(reserveCandidate["id"] == .string("file-candidate"))
        #expect(reserveInspection["tool"] == .string("build_uploads_get_file"))
        #expect(reserveInspectionArguments["file_id"] == .string("file-candidate"))
        #expect(!directContains(.object(reservePayload), "asset-token-secret"))
        #expect(!directContains(.object(reservePayload), "upload-secret"))
        #expect(!directContains(.object(reservePayload), "header-secret"))
        #expect((await reserveTransport.recordedRequests()).map(\.httpMethod) == ["GET", "POST", "GET"])
    }

    @Test("ambiguous commit preserves executable inspection when follow-up read fails")
    func ambiguousCommitPreservesFileInspection() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 500, body: "{}"),
            .init(statusCode: 500, body: "{}")
        ])
        let worker = try await makeDirectBuildUploadsWorker(transport: transport)

        let result = try await worker.handleTool(.init(
            name: "build_uploads_commit_file",
            arguments: ["file_id": .string("file-known"), "uploaded": .bool(true)]
        ))
        let payload = try directResultObject(result)
        let inspection = try directObject(payload["inspection"])
        let arguments = try directObject(inspection["arguments"])

        #expect(result.isError == true)
        #expect(payload["fileId"] == .string("file-known"))
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(inspection["tool"] == .string("build_uploads_get_file"))
        #expect(arguments["file_id"] == .string("file-known"))
        #expect((await transport.recordedRequests()).map(\.httpMethod) == ["PATCH", "GET"])
    }

    @Test("confirmed creates require fresh membership in the requested collection")
    func confirmedCreatesRequireScopedMembership() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directBuildUploadsList(ids: ["upload-stale"])),
            .init(statusCode: 201, body: directBuildUploadDocument(id: "upload-stale")),
            .init(statusCode: 200, body: directBuildUploadsList(ids: ["upload-stale"]))
        ])
        let createWorker = try await makeDirectBuildUploadsWorker(transport: createTransport)
        let create = try await createWorker.handleTool(.init(
            name: "build_uploads_create",
            arguments: [
                "app_id": .string("app-1"),
                "short_version": .string("2.4.0"),
                "build_version": .string("240"),
                "platform": .string("IOS")
            ]
        ))
        let createPayload = try directResultObject(create)

        #expect(create.isError == true)
        #expect(createPayload["success"] == .bool(false))
        #expect(createPayload["candidateIds"] == .array([]))
        #expect(createPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(createPayload["inspectionRequired"] == .bool(true))
        #expect(createPayload["retrySafe"] == .bool(false))
        #expect(createPayload["buildUpload"] == nil)
        #expect((await createTransport.recordedRequests()).map(\.httpMethod) == ["GET", "POST", "GET"])

        let reserveTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directEmptyBuildUploadFiles),
            .init(statusCode: 201, body: directBuildUploadFileDocument(id: "file-wrong-parent")),
            .init(statusCode: 200, body: directEmptyBuildUploadFiles)
        ])
        let reserveWorker = try await makeDirectBuildUploadsWorker(transport: reserveTransport)
        let reserve = try await reserveWorker.handleTool(.init(
            name: "build_uploads_reserve_file",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "asset_type": .string("ASSET"),
                "file_name": .string("Example.ipa"),
                "file_size": .int(3),
                "uti": .string("com.apple.ipa")
            ]
        ))
        let reservePayload = try directResultObject(reserve)

        #expect(reserve.isError == true)
        #expect(reservePayload["success"] == .bool(false))
        #expect(reservePayload["candidateIds"] == .array([]))
        #expect(reservePayload["operationCommitState"] == .string("committed_unverified"))
        #expect(reservePayload["inspectionRequired"] == .bool(true))
        #expect(reservePayload["retrySafe"] == .bool(false))
        #expect(reservePayload["buildUploadFile"] == nil)
        #expect((await reserveTransport.recordedRequests()).map(\.httpMethod) == ["GET", "POST", "GET"])
    }

    @Test("delete requires exact confirmation and preserves 204 semantics")
    func deleteConfirmation() async throws {
        let blockedTransport = TestHTTPTransport(responses: [])
        let blockedWorker = try await makeDirectBuildUploadsWorker(transport: blockedTransport)

        let missing = try await blockedWorker.handleTool(.init(
            name: "build_uploads_delete",
            arguments: ["build_upload_id": .string("upload-1")]
        ))
        let mismatch = try await blockedWorker.handleTool(.init(
            name: "build_uploads_delete",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "confirm_build_upload_id": .string("upload-2")
            ]
        ))
        #expect(missing.isError == true)
        #expect(mismatch.isError == true)
        #expect(await blockedTransport.requestCount() == 0)

        let successTransport = TestHTTPTransport(responses: [.init(statusCode: 204, body: "")])
        let successWorker = try await makeDirectBuildUploadsWorker(transport: successTransport)
        let success = try await successWorker.handleTool(.init(
            name: "build_uploads_delete",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "confirm_build_upload_id": .string("upload-1")
            ]
        ))
        #expect(success.isError != true)
        #expect((await successTransport.recordedRequests()).map(\.httpMethod) == ["DELETE"])

        let unexpectedTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "{}")])
        let unexpectedWorker = try await makeDirectBuildUploadsWorker(transport: unexpectedTransport)
        let unexpected = try await unexpectedWorker.handleTool(.init(
            name: "build_uploads_delete",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "confirm_build_upload_id": .string("upload-1")
            ]
        ))
        let unexpectedPayload = try directResultObject(unexpected)
        let unexpectedInspection = try directObject(unexpectedPayload["inspection"])
        let unexpectedArguments = try directObject(unexpectedInspection["arguments"])
        #expect(unexpected.isError == true)
        #expect(unexpectedPayload["buildUploadId"] == .string("upload-1"))
        #expect(unexpectedPayload["operationCommitState"] == .string("committed_unverified"))
        #expect(unexpectedPayload["inspectionRequired"] == .bool(true))
        #expect(unexpectedPayload["retrySafe"] == .bool(false))
        #expect(unexpectedInspection["tool"] == .string("build_uploads_get"))
        #expect(unexpectedArguments["build_upload_id"] == .string("upload-1"))

        let unknownTransport = TestHTTPTransport(responses: [
            .init(statusCode: 500, body: "{}")
        ])
        let unknownWorker = try await makeDirectBuildUploadsWorker(transport: unknownTransport)
        let unknown = try await unknownWorker.handleTool(.init(
            name: "build_uploads_delete",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "confirm_build_upload_id": .string("upload-1")
            ]
        ))
        let unknownPayload = try directResultObject(unknown)
        let unknownInspection = try directObject(unknownPayload["inspection"])
        let unknownArguments = try directObject(unknownInspection["arguments"])
        #expect(unknown.isError == true)
        #expect(unknownPayload["buildUploadId"] == .string("upload-1"))
        #expect(unknownPayload["operationCommitState"] == .string("unknown"))
        #expect(unknownPayload["outcomeUnknown"] == .bool(true))
        #expect(unknownPayload["inspectionRequired"] == .bool(true))
        #expect(unknownPayload["retrySafe"] == .bool(false))
        #expect(unknownInspection["tool"] == .string("build_uploads_get"))
        #expect(unknownArguments["build_upload_id"] == .string("upload-1"))
        #expect((await unknownTransport.recordedRequests()).map(\.httpMethod) == ["DELETE"])
    }

    @Test("pagination is bound to the exact collection query and a nonempty cursor")
    func strictPagination() async throws {
        let requiredQuery = [
            "fields[buildUploads]": BuildUploadsWorker.buildUploadFieldValues.joined(separator: ","),
            "fields[buildUploadFiles]": safeBuildUploadFileFields,
            "limit": "25"
        ]
        let invalidURLs = [
            directURL(
                path: "/v1/apps/app-2/buildUploads",
                query: requiredQuery.merging(["cursor": "next"]) { _, new in new }
            ),
            directURL(
                path: "/v1/apps/app-1/buildUploads",
                query: requiredQuery.merging(["cursor": "next", "include": "build"]) { _, new in new }
            ),
            directURL(path: "/v1/apps/app-1/buildUploads", query: requiredQuery)
        ]

        for nextURL in invalidURLs {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeDirectBuildUploadsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "build_uploads_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "next_url": .string(nextURL)
                ]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("required links identity and canonical IDs are validated")
    func responseIdentityAndCanonicalIDs() async throws {
        let invalidIDTransport = TestHTTPTransport(responses: [])
        let invalidIDWorker = try await makeDirectBuildUploadsWorker(transport: invalidIDTransport)
        let invalidID = try await invalidIDWorker.handleTool(.init(
            name: "build_uploads_get",
            arguments: ["build_upload_id": .string(" upload-1 ")]
        ))
        #expect(invalidID.isError == true)
        #expect(await invalidIDTransport.requestCount() == 0)

        let missingLinksTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directBuildUploadDataOnly(id: "upload-1"))
        ])
        let missingLinksWorker = try await makeDirectBuildUploadsWorker(transport: missingLinksTransport)
        let missingLinks = try await missingLinksWorker.handleTool(.init(
            name: "build_uploads_get",
            arguments: ["build_upload_id": .string("upload-1")]
        ))
        #expect(missingLinks.isError == true)

        let wrongIdentityTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directBuildUploadDocument(id: "upload-2"))
        ])
        let wrongIdentityWorker = try await makeDirectBuildUploadsWorker(transport: wrongIdentityTransport)
        let wrongIdentity = try await wrongIdentityWorker.handleTool(.init(
            name: "build_uploads_get",
            arguments: ["build_upload_id": .string("upload-1")]
        ))
        #expect(wrongIdentity.isError == true)
    }

    @Test("present paging metadata requires Apple paging and limit members")
    func incompletePagingMetadata() async throws {
        let malformedDocuments = [
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"},"meta":{}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"},"meta":{"paging":{}}}"#
        ]

        for document in malformedDocuments {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: document)
            ])
            let worker = try await makeDirectBuildUploadsWorker(transport: transport)
            let result = try await worker.handleTool(.init(
                name: "build_uploads_list",
                arguments: ["app_id": .string("app-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("transfer credentials require the exact explicit output paths")
    func sensitiveOutputPaths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: directBuildUploadFileDocument(
                id: "file-1",
                includeCredentials: true
            )),
            .init(statusCode: 200, body: directBuildUploadFileDocument(
                id: "file-1",
                includeCredentials: true
            ))
        ])
        let worker = try await makeDirectBuildUploadsWorker(transport: transport)

        let redacted = try await worker.handleTool(.init(
            name: "build_uploads_get_file",
            arguments: ["file_id": .string("file-1")]
        ))
        let redactedPayload = try directResultObject(redacted)
        #expect(!directContains(.object(redactedPayload), "asset-token-secret"))
        #expect(!directContains(.object(redactedPayload), "upload-secret"))

        let revealed = try await worker.handleTool(.init(
            name: "build_uploads_get_file",
            arguments: [
                "file_id": .string("file-1"),
                "include_sensitive_details": .bool(true)
            ]
        ))
        let revealedPayload = try directResultObject(revealed)
        #expect(directContains(.object(revealedPayload), "asset-token-secret"))
        #expect(directContains(.object(revealedPayload), "upload-secret"))
        #expect(directContains(.object(revealedPayload), "header-secret"))
    }

    @Test("unknown and conditionally invalid arguments fail before network")
    func runtimeArgumentValidation() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeDirectBuildUploadsWorker(transport: transport)

        let unknown = try await worker.handleTool(.init(
            name: "build_uploads_get",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "unexpected": .bool(true)
            ]
        ))
        let emptyCommit = try await worker.handleTool(.init(
            name: "build_uploads_commit_file",
            arguments: ["file_id": .string("file-1")]
        ))
        let invalidList = try await worker.handleTool(.init(
            name: "build_uploads_list",
            arguments: [
                "app_id": .string("app-1"),
                "platforms": .string("IOS")
            ]
        ))
        let missingFileSize = try await worker.handleTool(.init(
            name: "build_uploads_reserve_file",
            arguments: [
                "build_upload_id": .string("upload-1"),
                "asset_type": .string("ASSET"),
                "file_name": .string("Example.ipa"),
                "uti": .string("com.apple.ipa")
            ]
        ))
        #expect(unknown.isError == true)
        #expect(emptyCommit.isError == true)
        #expect(invalidList.isError == true)
        #expect(missingFileSize.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("sensitive sparse fields require explicit opt in before network")
    func sensitiveFieldSelectionRequiresOptIn() async throws {
        let cases: [(String, [String: Value])] = [
            (
                "build_uploads_list",
                [
                    "app_id": .string("app-1"),
                    "fields_build_upload_files": .array([.string("assetToken")])
                ]
            ),
            (
                "build_uploads_get",
                [
                    "build_upload_id": .string("upload-1"),
                    "fields_build_upload_files": .array([.string("uploadOperations")])
                ]
            ),
            (
                "build_uploads_list_files",
                [
                    "build_upload_id": .string("upload-1"),
                    "fields_build_upload_files": .array([.string("assetToken")])
                ]
            ),
            (
                "build_uploads_get_file",
                [
                    "file_id": .string("file-1"),
                    "fields_build_upload_files": .array([.string("uploadOperations")])
                ]
            )
        ]

        for (name, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await makeDirectBuildUploadsWorker(transport: transport)
            let result = try await worker.handleTool(.init(name: name, arguments: arguments))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("cancellation after preflight never starts create or reservation POST")
    func cancellationAfterPreflight() async throws {
        let createTransport = DirectCancelAfterResponseTransport(body: directEmptyBuildUploads)
        let createWorker = try await makeDirectBuildUploadsWorker(transport: createTransport)
        let createTask = Task {
            try await createWorker.handleTool(.init(
                name: "build_uploads_create",
                arguments: [
                    "app_id": .string("app-1"),
                    "short_version": .string("2.4.0"),
                    "build_version": .string("240"),
                    "platform": .string("IOS")
                ]
            ))
        }
        let create = try await createTask.value
        let createPayload = try directResultObject(create)
        #expect(create.isError == true)
        #expect(createPayload["operationCommitState"] == .string("not_attempted"))
        #expect((await createTransport.recordedMethods()) == ["GET"])

        let reserveTransport = DirectCancelAfterResponseTransport(body: directEmptyBuildUploadFiles)
        let reserveWorker = try await makeDirectBuildUploadsWorker(transport: reserveTransport)
        let reserveTask = Task {
            try await reserveWorker.handleTool(.init(
                name: "build_uploads_reserve_file",
                arguments: [
                    "build_upload_id": .string("upload-1"),
                    "asset_type": .string("ASSET"),
                    "file_name": .string("Example.ipa"),
                    "file_size": .int(3),
                    "uti": .string("com.apple.ipa")
                ]
            ))
        }
        let reserve = try await reserveTask.value
        let reservePayload = try directResultObject(reserve)
        #expect(reserve.isError == true)
        #expect(reservePayload["operationCommitState"] == .string("not_attempted"))
        #expect((await reserveTransport.recordedMethods()) == ["GET"])
    }

    @Test("pre-cancelled commit and delete remain not attempted")
    func preCancelledMutations() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeDirectBuildUploadsWorker(transport: transport)

        let commitTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.handleTool(.init(
                name: "build_uploads_commit_file",
                arguments: ["file_id": .string("file-1"), "uploaded": .bool(true)]
            ))
        }
        let commit = try await commitTask.value
        let commitPayload = try directResultObject(commit)
        #expect(commit.isError == true)
        #expect(commitPayload["operationCommitState"] == .string("not_attempted"))

        let deleteTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.handleTool(.init(
                name: "build_uploads_delete",
                arguments: [
                    "build_upload_id": .string("upload-1"),
                    "confirm_build_upload_id": .string("upload-1")
                ]
            ))
        }
        let delete = try await deleteTask.value
        let deletePayload = try directResultObject(delete)
        #expect(delete.isError == true)
        #expect(deletePayload["operationCommitState"] == .string("not_attempted"))
        #expect(await transport.requestCount() == 0)
    }
}

private let directEmptyBuildUploads =
    #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"}}"#

private let directEmptyBuildUploadFiles =
    #"{"data":[],"links":{"self":"https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles"}}"#

private func directBuildUploadsList(ids: [String]) -> String {
    let resources = ids.map { directBuildUploadResource(id: $0) }.joined(separator: ",")
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"}}"#
}

private func directBuildUploadDataOnly(id: String) -> String {
    #"{"data":\#(directBuildUploadResource(id: id))}"#
}

private func directBuildUploadDocument(id: String) -> String {
    #"{"data":\#(directBuildUploadResource(id: id)),"links":{"self":"https://api.example.test/v1/buildUploads/\#(id)"}}"#
}

private func directBuildUploadResource(id: String) -> String {
    #"{"type":"buildUploads","id":"\#(id)","attributes":{"cfBundleShortVersionString":"2.4.0","cfBundleVersion":"240","platform":"IOS","state":{"state":"AWAITING_UPLOAD","errors":[],"warnings":[],"infos":[]}}}"#
}

private func directBuildUploadFileDocument(
    id: String,
    state: String = "AWAITING_UPLOAD",
    includeCredentials: Bool = false
) -> String {
    #"{"data":\#(directBuildUploadFileResource(id: id, state: state, includeCredentials: includeCredentials)),"links":{"self":"https://api.example.test/v1/buildUploadFiles/\#(id)"}}"#
}

private func directBuildUploadFilesList(
    ids: [String],
    parentID: String = "upload-1",
    includeCredentials: Bool = false
) -> String {
    let resources = ids.map {
        directBuildUploadFileResource(id: $0, includeCredentials: includeCredentials)
    }.joined(separator: ",")
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/buildUploads/\#(parentID)/buildUploadFiles"}}"#
}

private func directBuildUploadFileResource(
    id: String,
    state: String = "AWAITING_UPLOAD",
    includeCredentials: Bool = false
) -> String {
    let credentials = includeCredentials
        ? #", "assetToken":"asset-token-secret","uploadOperations":[{"method":"PUT","url":"https://upload.example.test/upload-secret","length":3,"offset":0,"requestHeaders":[{"name":"X-Upload-Secret","value":"header-secret"}]}]"#
        : ""
    return #"{"type":"buildUploadFiles","id":"\#(id)","attributes":{"assetDeliveryState":{"state":"\#(state)","errors":[],"warnings":[]},"assetType":"ASSET","fileName":"Example.ipa","fileSize":3,"uti":"com.apple.ipa"\#(credentials)}}"#
}

private func makeDirectBuildUploadsWorker(
    transport: any HTTPTransport
) async throws -> BuildUploadsWorker {
    let jwtService = try TestFactory.makeJWTService()
    let client = await HTTPClient(
        jwtService: jwtService,
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return BuildUploadsWorker(
        httpClient: client,
        uploadService: UploadService(),
        pollAttempts: 1,
        pollIntervalNanoseconds: 0,
        maxTransferAttempts: 1,
        transferRetryDelayNanoseconds: 0
    )
}

private func directURL(path: String, query: [String: String]) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.example.test"
    components.path = path
    components.queryItems = query.keys.sorted().map {
        URLQueryItem(name: $0, value: query[$0])
    }
    return components.url!.absoluteString
}

private func directRequestData(_ request: URLRequest) throws -> [String: Any] {
    let body = try directJSONObject(try #require(request.httpBody))
    return try directJSONObject(body["data"])
}

private func directJSONObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BuildUploadsDirectTestError.expectedObject
    }
    return object
}

private func directJSONObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw BuildUploadsDirectTestError.expectedObject
    }
    return object
}

private func directResultObject(_ result: CallTool.Result) throws -> [String: Value] {
    try directObject(result.structuredContent)
}

private func directObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        throw BuildUploadsDirectTestError.expectedObject
    }
    return object
}

private func directStringSet(_ value: Value?) throws -> Set<String> {
    guard case .array(let values)? = value else {
        throw BuildUploadsDirectTestError.expectedArray
    }
    return Set(values.compactMap(\.stringValue))
}

private func directContains(_ value: Value?, _ needle: String) -> Bool {
    guard let value else { return false }
    switch value {
    case .string(let string):
        return string.contains(needle)
    case .array(let values):
        return values.contains { directContains($0, needle) }
    case .object(let object):
        return object.contains { key, child in
            key.contains(needle) || directContains(child, needle)
        }
    default:
        return false
    }
}

private enum BuildUploadsDirectTestError: Error {
    case expectedObject
    case expectedArray
}

private actor DirectCancelAfterResponseTransport: HTTPTransport {
    private let body: String
    private var methods: [String] = []

    init(body: String) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        methods.append(request.httpMethod ?? "")
        withUnsafeCurrentTask { $0?.cancel() }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("DirectCancelAfterResponseTransport does not upload files")
    }

    func recordedMethods() -> [String] {
        methods
    }
}
