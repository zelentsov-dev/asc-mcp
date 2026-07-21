import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Screenshots v3.19 Contract Tests")
struct ScreenshotsV319ContractTests {
    @Test("schemas expose strict batch reorder get and cascade confirmation contracts")
    func schemas() async throws {
        let worker = try await screenshotsV319Worker(responses: [])
        let tools = await worker.getTools()
        let names = Set(tools.map(\.name))
        let canonicalIDPattern = #"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#
        let absolutePathPattern = #"^/(?:.*\S)?$"#

        #expect(tools.count == 19)
        #expect(names.contains("screenshots_get_set"))
        #expect(names.contains("screenshots_get_preview_set"))
        #expect(names.contains("screenshots_reorder_previews"))

        let batch = try screenshotsV319ToolSchema("screenshots_upload_batch", in: tools)
        let batchPaths = try screenshotsV319Property("file_paths", in: batch)
        #expect(batch["additionalProperties"] == .bool(false))
        #expect(batchPaths["minItems"] == .int(1))
        #expect(batchPaths["maxItems"] == .int(ScreenshotsWorker.maximumBatchUploadCount))
        #expect(batchPaths["uniqueItems"] == .bool(true))
        let batchItem = try screenshotsV319Object(batchPaths["items"])
        #expect(batchItem["minLength"] == .int(1))
        #expect(batchItem["pattern"] == .string(absolutePathPattern))

        for toolName in ["screenshots_upload", "screenshots_upload_preview"] {
            let schema = try screenshotsV319ToolSchema(toolName, in: tools)
            #expect(schema["additionalProperties"] == .bool(false))
            let filePath = try screenshotsV319Property("file_path", in: schema)
            #expect(filePath["minLength"] == .int(1))
            #expect(filePath["pattern"] == .string(absolutePathPattern))
        }

        for (toolName, fieldName) in [
            ("screenshots_reorder", "screenshot_ids"),
            ("screenshots_reorder_previews", "preview_ids")
        ] {
            let schema = try screenshotsV319ToolSchema(toolName, in: tools)
            let ids = try screenshotsV319Property(fieldName, in: schema)
            #expect(ids["type"] == .string("array"))
            #expect(ids["minItems"] == .int(1))
            #expect(ids["maxItems"] == .int(ScreenshotsWorker.maximumReorderCount))
            #expect(ids["uniqueItems"] == .bool(true))
            #expect(try screenshotsV319Object(ids["items"])["pattern"] == .string(canonicalIDPattern))
        }

        for toolName in ["screenshots_delete_set", "screenshots_delete_preview_set"] {
            let schema = try screenshotsV319ToolSchema(toolName, in: tools)
            let required = try screenshotsV319Array(schema["required"])
            #expect(required.contains(.string("set_id")))
            #expect(required.contains(.string("confirm_set_id")))
        }

        for toolName in ["screenshots_list_sets", "screenshots_list_preview_sets"] {
            let schema = try screenshotsV319ToolSchema(toolName, in: tools)
            let properties = try screenshotsV319Object(schema["properties"])
            #expect(schema["additionalProperties"] == .bool(false))
            #expect(try screenshotsV319Array(schema["oneOf"]).count == 4)
            #expect(properties["app_store_version_localization_id"] != nil)
            #expect(properties["custom_product_page_localization_id"] != nil)
            #expect(properties["treatment_localization_id"] != nil)
            #expect(properties["app_store_version_localization_ids"] != nil)
            #expect(try screenshotsV319Object(properties["app_store_version_localization_id"])["pattern"] == .string(canonicalIDPattern))
            let nextURL = try screenshotsV319Object(properties["next_url"])
            #expect(nextURL["minLength"] == .int(1))
            #expect(nextURL["format"] == .string("uri-reference"))
            #expect(nextURL["pattern"] == .string(#"^\S(?:.*\S)?$"#))
        }

        let getScreenshot = try screenshotsV319ToolSchema("screenshots_get", in: tools)
        #expect(try screenshotsV319Property("screenshot_id", in: getScreenshot)["pattern"] == .string(canonicalIDPattern))
        let deletePreview = try screenshotsV319ToolSchema("screenshots_delete_preview", in: tools)
        #expect(try screenshotsV319Property("confirm_preview_id", in: deletePreview)["pattern"] == .string(canonicalIDPattern))

        let uploadPreview = try screenshotsV319ToolSchema("screenshots_upload_preview", in: tools)
        for field in ["mime_type", "preview_frame_time_code"] {
            let nullable = try screenshotsV319Property(field, in: uploadPreview)
            #expect(nullable["minLength"] == .int(1))
            #expect(nullable["pattern"] == .string(#"^\S(?:.*\S)?$"#))
        }
    }

    @Test("manifest publishes an exact non-empty response keyset for all 19 tools")
    func manifestResponseKeysets() throws {
        let expected: [String: Set<String>] = [
            "screenshots_create_preview_set": ["success", "operation", "operationCommitted", "operationCommitState", "createdByInvocation", "candidateAttributionConfirmed", "retrySafe", "statusCode", "parent", "preview_set", "mutationAttempted", "write_outcome", "error", "mediaType", "existingCandidates", "setId", "responseSetId", "observedCandidates", "inspectionError", "outcomeUnknown", "inspectionRequired", "inspection"],
            "screenshots_create_set": ["success", "operation", "operationCommitted", "operationCommitState", "createdByInvocation", "candidateAttributionConfirmed", "retrySafe", "statusCode", "parent", "screenshot_set", "mutationAttempted", "write_outcome", "error", "mediaType", "existingCandidates", "setId", "responseSetId", "observedCandidates", "inspectionError", "outcomeUnknown", "inspectionRequired", "inspection"],
            "screenshots_delete": ["success", "operationCommitState", "operationCommitted", "retrySafe", "statusCode", "message", "operation", "write_outcome", "mutationAttempted", "resourceId", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_delete_preview": ["success", "operationCommitState", "operationCommitted", "retrySafe", "statusCode", "message", "operation", "write_outcome", "mutationAttempted", "resourceId", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_delete_preview_set": ["success", "operation", "operationCommitState", "operationCommitted", "retrySafe", "statusCode", "setId", "message", "write_outcome", "mutationAttempted", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_delete_set": ["success", "operation", "operationCommitState", "operationCommitted", "retrySafe", "statusCode", "setId", "message", "write_outcome", "mutationAttempted", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_get_preview_set": ["success", "preview_set"],
            "screenshots_get_set": ["success", "screenshot_set"],
            "screenshots_get": ["success", "screenshot", "screenshot.assetDeliveryState.warnings", "screenshot.selfLink", "screenshot.screenshotSet"],
            "screenshots_get_preview": ["success", "preview", "preview.previewFrameTimeCode", "preview.previewFrameImage", "preview.previewImage", "preview.assetDeliveryState.warnings", "preview.videoDeliveryState.warnings", "preview.selfLink", "preview.previewSet"],
            "screenshots_list": ["success", "screenshots", "count", "next_url", "total", "screenshots.*.assetDeliveryState.warnings", "screenshots.*.selfLink", "screenshots.*.screenshotSet"],
            "screenshots_list_preview_sets": ["success", "preview_sets", "count", "parent", "next_url", "total", "preview_sets.*.selfLink", "preview_sets.*.parent"],
            "screenshots_list_previews": ["success", "previews", "count", "previews.*.previewFrameTimeCode", "previews.*.previewFrameImage", "previews.*.previewImage", "previews.*.assetDeliveryState.warnings", "previews.*.videoDeliveryState.warnings", "previews.*.selfLink", "previews.*.previewSet", "next_url", "total"],
            "screenshots_list_sets": ["success", "screenshot_sets", "count", "parent", "next_url", "total", "screenshot_sets.*.selfLink", "screenshot_sets.*.parent"],
            "screenshots_reorder": ["success", "operation", "operationCommitted", "operationCommitState", "retrySafe", "statusCode", "setId", "order", "write_outcome", "mutationAttempted", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_reorder_previews": ["success", "operation", "operationCommitted", "operationCommitState", "retrySafe", "statusCode", "setId", "order", "write_outcome", "mutationAttempted", "error", "inspection", "outcomeUnknown", "inspectionRequired"],
            "screenshots_upload": ["success", "screenshot", "screenshot.assetDeliveryState.warnings", "uploadCommitted", "processingComplete", "deliveryPending", "retrySafe", "cleanup", "reservationFingerprint", "sourceFileChecksumReceipt", "operationCommitState", "inspection", "reconciledAfterCommit", "error", "resourceId", "screenshot_id", "reservationCreated", "reservationDeleted", "reservationState", "reservationIdKnown", "operationCommitted", "outcomeUnknown", "inspectionRequired", "statusCode"],
            "screenshots_upload_batch": ["success", "total", "uploaded", "failed", "results", "results.*.file", "results.*.screenshot_id", "results.*.state", "results.*.upload_committed", "results.*.delivery_pending", "results.*.retry_safe", "results.*.inspection", "results.*.success", "results.*.processing_complete", "results.*.reconciled_after_commit", "results.*.inspect_tool", "results.*.inspect_arguments", "results.*.inspect_arguments.screenshot_id", "results.*.error", "results.*.screenshot", "results.*.resourceId", "results.*.reservationCreated", "results.*.reservationDeleted", "results.*.reservationState", "results.*.reservationIdKnown", "results.*.operationCommitState", "results.*.operationCommitted", "results.*.outcomeUnknown", "results.*.inspectionRequired", "results.*.retrySafe", "results.*.cleanup", "results.*.reservationFingerprint", "results.*.sourceFileChecksumReceipt", "results.*.statusCode", "results.*.uploadCommitted", "results.*.processingComplete", "results.*.deliveryPending"],
            "screenshots_upload_preview": ["success", "preview", "preview.previewFrameTimeCode", "preview.previewFrameImage", "preview.previewImage", "preview.assetDeliveryState.warnings", "preview.videoDeliveryState.warnings", "uploadCommitted", "processingComplete", "deliveryPending", "retrySafe", "cleanup", "reservationFingerprint", "sourceFileChecksumReceipt", "operationCommitState", "inspection", "reconciledAfterCommit", "error", "resourceId", "preview_id", "reservationCreated", "reservationDeleted", "reservationState", "reservationIdKnown", "operationCommitted", "outcomeUnknown", "inspectionRequired", "statusCode"]
        ]
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mappings = manifest.tools.filter { $0.tool.hasPrefix("screenshots_") }
        #expect(mappings.count == 19)
        #expect(Set(mappings.map(\.tool)) == Set(expected.keys))
        for mapping in mappings {
            #expect(!mapping.response.fields.isEmpty)
            #expect(Set(mapping.response.fields.map(\.outputField)) == expected[mapping.tool])
        }
    }

    @Test("batch validation rejects the complete malformed request before network")
    func batchPreflight() async throws {
        let tooMany = (0...ScreenshotsWorker.maximumBatchUploadCount).map { Value.string("/tmp/\($0).png") }
        let fixtures: [[String: Value]] = [
            ["set_id": .string("set-1"), "file_paths": .array([])],
            ["set_id": .string("set-1"), "file_paths": .array([.string("/tmp/a.png"), .int(1)])],
            ["set_id": .string("set-1"), "file_paths": .array([.string("")])],
            ["set_id": .string("set-1"), "file_paths": .array([.string(" ")])],
            ["set_id": .string("set-1"), "file_paths": .array([.string("/tmp/a.png"), .string("/tmp/a.png")])],
            ["set_id": .string("set-1"), "file_paths": .array(tooMany)],
            ["set_id": .string("set/1"), "file_paths": .array([.string("/tmp/a.png")])],
            ["set_id": .string("set-1"), "file_paths": .array([.string("/tmp/a.png")]), "unexpected": .bool(true)]
        ]

        for arguments in fixtures {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_upload_batch",
                arguments: arguments
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("batch snapshots every local file before the first reservation")
    func batchSnapshotPreflightIsAtomic() async throws {
        let valid = try screenshotsV319File(Data("valid".utf8))
        let empty = try screenshotsV319File(Data())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-screenshots-v319-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: valid)
            try? FileManager.default.removeItem(at: empty)
            try? FileManager.default.removeItem(at: directory)
        }

        let invalidSecondPaths = [
            empty.path,
            directory.path,
            directory.appendingPathComponent("missing.png").path,
            "relative.png"
        ]
        for invalidPath in invalidSecondPaths {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_upload_batch",
                arguments: [
                    "set_id": .string("set-1"),
                    "file_paths": .array([.string(valid.path), .string(invalidPath)])
                ]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("single uploads reject unknown arguments and non-absolute paths before network")
    func strictSingleUploadArguments() async throws {
        for toolName in ["screenshots_upload", "screenshots_upload_preview"] {
            for arguments: [String: Value] in [
                ["set_id": .string("set-1"), "file_path": .string("relative.bin")],
                [
                    "set_id": .string("set-1"),
                    "file_path": .string("/tmp/missing.bin"),
                    "unexpected": .bool(true)
                ]
            ] {
                let transport = TestHTTPTransport(responses: [])
                let worker = try await screenshotsV319Worker(transport: transport)
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: toolName,
                    arguments: arguments
                ))
                #expect(result.isError == true)
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("reservation snapshot state and set mismatches roll back before transfer")
    func reservationMismatchesRollback() async throws {
        let file = try screenshotsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let mismatches: [(String, String, Int, String, String, String?)] = [
            ("appScreenshots", "other.bin", 5, "AWAITING_UPLOAD", "set-1", nil),
            ("appScreenshots", file.lastPathComponent, 6, "AWAITING_UPLOAD", "set-1", nil),
            ("appScreenshots", file.lastPathComponent, 5, "PROCESSING", "set-1", nil),
            ("appScreenshots", file.lastPathComponent, 5, "AWAITING_UPLOAD", "set-2", nil),
            ("appScreenshots", file.lastPathComponent, 5, "AWAITING_UPLOAD", "set-1", "00000000000000000000000000000000"),
            ("appPreviews", file.lastPathComponent, 5, "PROCESSING", "set-1", nil),
            ("appPreviews", file.lastPathComponent, 5, "AWAITING_UPLOAD", "set-2", nil),
            ("appPreviews", file.lastPathComponent, 5, "AWAITING_UPLOAD", "set-1", "00000000000000000000000000000000")
        ]

        for mismatch in mismatches {
            let isScreenshot = mismatch.0 == "appScreenshots"
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: screenshotsV319UploadResponse(
                    type: mismatch.0,
                    id: isScreenshot ? "shot-1" : "preview-1",
                    setID: mismatch.4,
                    fileName: mismatch.1,
                    fileSize: mismatch.2,
                    state: mismatch.3,
                    sourceFileChecksum: mismatch.5
                )),
                .init(statusCode: 204, body: "")
            ])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: isScreenshot ? "screenshots_upload" : "screenshots_upload_preview",
                arguments: ["set_id": .string("set-1"), "file_path": .string(file.path)]
            ))

            #expect(result.isError == true)
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("ambiguous reservations publish paged file identity guidance with a separate checksum receipt")
    func ambiguousReservationGuidance() async throws {
        let file = try screenshotsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let apiTransport = TestHTTPTransport(responses: [.init(statusCode: 202, body: "")])
        let worker = try await screenshotsV319Worker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload",
            arguments: ["set_id": .string("set-1"), "file_path": .string(file.path)]
        ))
        let root = try screenshotsV319Object(result.structuredContent)
        let fingerprint = try screenshotsV319Object(root["reservationFingerprint"])
        let inspection = try screenshotsV319Object(root["inspection"])
        let inspectionArguments = try screenshotsV319Object(inspection["arguments"])
        let candidateMatch = try screenshotsV319Object(inspection["candidate_match"])

        #expect(result.isError == true)
        #expect(fingerprint["file_name"] == .string(file.lastPathComponent))
        #expect(fingerprint["file_size"] == .int(5))
        #expect(fingerprint["checksum"] == nil)
        #expect(root["sourceFileChecksumReceipt"]?.stringValue?.count == 32)
        #expect(inspectionArguments["limit"] == .int(200))
        #expect(inspection["next_url_argument"] == .string("next_url"))
        #expect(candidateMatch["candidate_fields"] == .array([.string("fileName"), .string("fileSize")]))
    }

    @Test("set lists select the exact parent endpoint and parent-specific filters")
    func parentAwareSetLists() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                [],
                documentSelf: "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets?filter%5BscreenshotDisplayType%5D=APP_IPHONE_67&filter%5BappCustomProductPageLocalization%5D=cpp-loc-1&filter%5BappStoreVersionExperimentTreatmentLocalization%5D=ppo-loc-1&limit=17",
                limit: 17
            )),
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                [],
                parentType: "appCustomProductPageLocalizations",
                parentID: "cpp-loc-1",
                documentSelf: "/v1/appCustomProductPageLocalizations/cpp-loc-1/appScreenshotSets?filter%5BappStoreVersionLocalization%5D=version-loc-1&filter%5BappStoreVersionExperimentTreatmentLocalization%5D=ppo-loc-1&limit=25",
                limit: 25
            )),
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                [],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1",
                documentSelf: "/v1/appStoreVersionExperimentTreatmentLocalizations/ppo-loc-1/appScreenshotSets?filter%5BappStoreVersionLocalization%5D=version-loc-1&filter%5BappCustomProductPageLocalization%5D=cpp-loc-1&limit=25",
                limit: 25
            )),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                documentSelf: "/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets?limit=25",
                limit: 25
            )),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                parentType: "appCustomProductPageLocalizations",
                parentID: "cpp-loc-1",
                documentSelf: "/v1/appCustomProductPageLocalizations/cpp-loc-1/appPreviewSets?limit=25",
                limit: 25
            )),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1",
                documentSelf: "/v1/appStoreVersionExperimentTreatmentLocalizations/ppo-loc-1/appPreviewSets?limit=25",
                limit: 25
            ))
        ])
        let worker = try await screenshotsV319Worker(transport: transport)
        let fixtures: [(String, [String: Value], String, [String: String])] = [
            (
                "screenshots_list_sets",
                [
                    "app_store_version_localization_id": .string("version-loc-1"),
                    "display_types": .array([.string("APP_IPHONE_67")]),
                    "custom_product_page_localization_ids": .array([.string("cpp-loc-1")]),
                    "treatment_localization_ids": .array([.string("ppo-loc-1")]),
                    "limit": .int(17)
                ],
                "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets",
                [
                    "filter[screenshotDisplayType]": "APP_IPHONE_67",
                    "filter[appCustomProductPageLocalization]": "cpp-loc-1",
                    "filter[appStoreVersionExperimentTreatmentLocalization]": "ppo-loc-1",
                    "limit": "17"
                ]
            ),
            (
                "screenshots_list_sets",
                [
                    "custom_product_page_localization_id": .string("cpp-loc-1"),
                    "app_store_version_localization_ids": .array([.string("version-loc-1")]),
                    "treatment_localization_ids": .array([.string("ppo-loc-1")])
                ],
                "/v1/appCustomProductPageLocalizations/cpp-loc-1/appScreenshotSets",
                [
                    "filter[appStoreVersionLocalization]": "version-loc-1",
                    "filter[appStoreVersionExperimentTreatmentLocalization]": "ppo-loc-1",
                    "limit": "25"
                ]
            ),
            (
                "screenshots_list_sets",
                [
                    "treatment_localization_id": .string("ppo-loc-1"),
                    "app_store_version_localization_ids": .array([.string("version-loc-1")]),
                    "custom_product_page_localization_ids": .array([.string("cpp-loc-1")])
                ],
                "/v1/appStoreVersionExperimentTreatmentLocalizations/ppo-loc-1/appScreenshotSets",
                [
                    "filter[appStoreVersionLocalization]": "version-loc-1",
                    "filter[appCustomProductPageLocalization]": "cpp-loc-1",
                    "limit": "25"
                ]
            ),
            (
                "screenshots_list_preview_sets",
                ["localization_id": .string("version-loc-1")],
                "/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets",
                ["limit": "25"]
            ),
            (
                "screenshots_list_preview_sets",
                ["custom_product_page_localization_id": .string("cpp-loc-1")],
                "/v1/appCustomProductPageLocalizations/cpp-loc-1/appPreviewSets",
                ["limit": "25"]
            ),
            (
                "screenshots_list_preview_sets",
                ["treatment_localization_id": .string("ppo-loc-1")],
                "/v1/appStoreVersionExperimentTreatmentLocalizations/ppo-loc-1/appPreviewSets",
                ["limit": "25"]
            )
        ]

        for fixture in fixtures {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: fixture.0,
                arguments: fixture.1
            ))
            #expect(result.isError != true)
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == fixtures.count)
        for (request, fixture) in zip(requests, fixtures) {
            #expect(request.url?.path == fixture.2)
            #expect(screenshotsV319Query(request) == fixture.3)
        }
    }

    @Test("filtered set lists reject Apple resources outside the requested media types")
    func filteredSetListsRejectDrift() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                ["set-1"],
                documentSelf: "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets?filter%5BscreenshotDisplayType%5D=APP_DESKTOP&limit=25",
                limit: 25
            )),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                ["preview-set-1"],
                documentSelf: "/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets?filter%5BpreviewType%5D=DESKTOP&limit=25",
                limit: 25
            ))
        ])
        let worker = try await screenshotsV319Worker(transport: transport)
        let screenshot = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_sets",
            arguments: [
                "app_store_version_localization_id": .string("version-loc-1"),
                "display_types": .array([.string("APP_DESKTOP")])
            ]
        ))
        let preview = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_list_preview_sets",
            arguments: [
                "app_store_version_localization_id": .string("version-loc-1"),
                "preview_types": .array([.string("DESKTOP")])
            ]
        ))
        #expect(screenshot.isError == true)
        #expect(preview.isError == true)
    }

    @Test("set lists reject ambiguous parents invalid limits and parent-inapplicable filters")
    func strictParentListPreflight() async throws {
        let fixtures: [(String, [String: Value])] = [
            (
                "screenshots_list_sets",
                [
                    "localization_id": .string("version-loc-1"),
                    "custom_product_page_localization_id": .string("cpp-loc-1")
                ]
            ),
            (
                "screenshots_list_sets",
                [
                    "custom_product_page_localization_id": .string("cpp-loc-1"),
                    "custom_product_page_localization_ids": .array([.string("cpp-loc-2")])
                ]
            ),
            (
                "screenshots_list_preview_sets",
                ["treatment_localization_id": .string("ppo-loc-1"), "limit": .int(0)]
            ),
            (
                "screenshots_list_preview_sets",
                ["app_store_version_localization_id": .string("version/loc")]
            )
        ]

        for fixture in fixtures {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: fixture.0,
                arguments: fixture.1
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("set get operations enforce exact path type and identity")
    func setGets() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSet("screenshot-set-1")),
            .init(statusCode: 200, body: screenshotsV319PreviewSet("preview-set-1")),
            .init(statusCode: 200, body: screenshotsV319ScreenshotSet("other-set"))
        ])
        let worker = try await screenshotsV319Worker(transport: transport)

        let screenshot = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_get_set",
            arguments: ["set_id": .string("screenshot-set-1")]
        ))
        let preview = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_get_preview_set",
            arguments: ["set_id": .string("preview-set-1")]
        ))
        let mismatch = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_get_set",
            arguments: ["set_id": .string("screenshot-set-1")]
        ))

        #expect(screenshot.isError != true)
        #expect(preview.isError != true)
        #expect(mismatch.isError == true)
        let requests = await transport.recordedRequests()
        #expect(requests[0].url?.path == "/v1/appScreenshotSets/screenshot-set-1")
        #expect(requests[1].url?.path == "/v1/appPreviewSets/preview-set-1")
    }

    @Test("screenshot set create uses full parent preflight exact 201 and scoped postflight")
    func screenshotSetCreate() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                [],
                parentType: "appCustomProductPageLocalizations",
                parentID: "cpp-loc-1"
            )),
            .init(statusCode: 201, body: screenshotsV319ScreenshotSet(
                "set-1",
                parentType: "appCustomProductPageLocalizations",
                parentID: "cpp-loc-1"
            )),
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                ["set-1"],
                parentType: "appCustomProductPageLocalizations",
                parentID: "cpp-loc-1"
            ))
        ])
        let worker = try await screenshotsV319Worker(transport: transport)
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_create_set",
            arguments: [
                "custom_product_page_localization_id": .string("cpp-loc-1"),
                "display_type": .string("APP_IPHONE_67")
            ]
        ))

        #expect(result.isError != true)
        let root = try screenshotsV319Object(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed"))
        #expect(root["statusCode"] == .int(201))
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(requests[0].url?.path == "/v1/appCustomProductPageLocalizations/cpp-loc-1/appScreenshotSets")
        #expect(screenshotsV319Query(requests[0]) == [
            "filter[screenshotDisplayType]": "APP_IPHONE_67",
            "limit": "200"
        ])
        #expect(requests[1].url?.path == "/v1/appScreenshotSets")
        let relationship = try screenshotsV319RequestRelationship(
            requests[1],
            name: "appCustomProductPageLocalization"
        )
        #expect(relationship["type"] as? String == "appCustomProductPageLocalizations")
        #expect(relationship["id"] as? String == "cpp-loc-1")
    }

    @Test("set create never attributes rejected or malformed outcomes to the invocation")
    func createFailureClassification() async throws {
        let rejectedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1"
            )),
            .init(statusCode: 422, body: #"{"errors":[{"status":"422","title":"Invalid"}]}"#),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1"
            ))
        ])
        let rejectedWorker = try await screenshotsV319Worker(transport: rejectedTransport)
        let rejected = try await rejectedWorker.handleTool(CallTool.Parameters(
            name: "screenshots_create_preview_set",
            arguments: [
                "treatment_localization_id": .string("ppo-loc-1"),
                "preview_type": .string("IPHONE_67")
            ]
        ))
        let rejectedRoot = try screenshotsV319Object(rejected.structuredContent)
        #expect(rejected.isError == true)
        #expect(rejectedRoot["operationCommitState"] == .string("rejected"))
        #expect(rejectedRoot["operationCommitted"] == .bool(false))

        let malformedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                [],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1"
            )),
            .init(statusCode: 201, body: screenshotsV319PreviewSet(
                "set/invalid",
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1"
            )),
            .init(statusCode: 200, body: screenshotsV319PreviewSets(
                ["observed-set"],
                parentType: "appStoreVersionExperimentTreatmentLocalizations",
                parentID: "ppo-loc-1"
            ))
        ])
        let malformedWorker = try await screenshotsV319Worker(transport: malformedTransport)
        let malformed = try await malformedWorker.handleTool(CallTool.Parameters(
            name: "screenshots_create_preview_set",
            arguments: [
                "treatment_localization_id": .string("ppo-loc-1"),
                "preview_type": .string("IPHONE_67")
            ]
        ))
        let malformedRoot = try screenshotsV319Object(malformed.structuredContent)
        #expect(malformed.isError == true)
        #expect(malformedRoot["operationCommitState"] == .string("committed_unverified"))
        #expect(malformedRoot["candidateAttributionConfirmed"] == .bool(false))
        #expect(malformedRoot["createdByInvocation"] == .bool(false))
    }

    @Test("full set inventory fails closed on truncation total drift and duplicate IDs")
    func fullSetInventoryPagingSafety() async throws {
        for isScreenshot in [true, false] {
            let tool = isScreenshot ? "screenshots_create_set" : "screenshots_create_preview_set"
            let arguments: [String: Value] = isScreenshot
                ? [
                    "app_store_version_localization_id": .string("version-loc-1"),
                    "display_type": .string("APP_IPHONE_67")
                ]
                : [
                    "app_store_version_localization_id": .string("version-loc-1"),
                    "preview_type": .string("IPHONE_67")
                ]
            let next = isScreenshot
                ? "https://api.example.test/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets?filter%5BscreenshotDisplayType%5D=APP_IPHONE_67&limit=200&cursor=next"
                : "https://api.example.test/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets?filter%5BpreviewType%5D=IPHONE_67&limit=200&cursor=next"
            let scenarios: [[TestHTTPTransport.Response]] = [
                [
                    .init(statusCode: 200, body: screenshotsV319InventorySetPage(
                        isScreenshot: isScreenshot,
                        ids: [],
                        total: 1
                    ))
                ],
                [
                    .init(statusCode: 200, body: screenshotsV319InventorySetPage(
                        isScreenshot: isScreenshot,
                        ids: [],
                        total: 1,
                        next: next,
                        nextCursor: "next"
                    )),
                    .init(statusCode: 200, body: screenshotsV319InventorySetPage(
                        isScreenshot: isScreenshot,
                        ids: [],
                        total: 2,
                        requestedCursor: "next"
                    ))
                ],
                [
                    .init(statusCode: 200, body: screenshotsV319InventorySetPage(
                        isScreenshot: isScreenshot,
                        ids: ["set-existing"],
                        total: 2,
                        next: next,
                        nextCursor: "next"
                    )),
                    .init(statusCode: 200, body: screenshotsV319InventorySetPage(
                        isScreenshot: isScreenshot,
                        ids: ["set-existing"],
                        total: 2,
                        requestedCursor: "next"
                    ))
                ]
            ]

            for responses in scenarios {
                let transport = TestHTTPTransport(responses: responses)
                let worker = try await screenshotsV319Worker(transport: transport)
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: tool,
                    arguments: arguments
                ))
                #expect(result.isError == true)
                let methods = await transport.recordedRequests().map(\.httpMethod)
                #expect(methods.allSatisfy { $0 == "GET" })
                #expect(!methods.contains("POST"))
            }
        }
    }

    @Test("cascade set deletes require exact confirmation preflight and 204")
    func cascadeDeletes() async throws {
        for toolName in ["screenshots_delete_set", "screenshots_delete_preview_set"] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: toolName,
                arguments: ["set_id": .string("set-1"), "confirm_set_id": .string("other")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSet("set-1")),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await screenshotsV319Worker(transport: transport)
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_delete_set",
            arguments: ["set_id": .string("set-1"), "confirm_set_id": .string("set-1")]
        ))
        let root = try screenshotsV319Object(result.structuredContent)
        #expect(result.isError != true)
        #expect(root["statusCode"] == .int(204))
        let methods = await transport.recordedRequests().map(\.httpMethod)
        #expect(methods == ["GET", "DELETE"])

        let unverifiedTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319PreviewSet("set-1")),
            .init(statusCode: 200, body: "")
        ])
        let unverifiedWorker = try await screenshotsV319Worker(transport: unverifiedTransport)
        let unverified = try await unverifiedWorker.handleTool(CallTool.Parameters(
            name: "screenshots_delete_preview_set",
            arguments: ["set_id": .string("set-1"), "confirm_set_id": .string("set-1")]
        ))
        let unverifiedRoot = try screenshotsV319Object(unverified.structuredContent)
        #expect(unverified.isError == true)
        #expect(unverifiedRoot["operationCommitState"] == .string("committed_unverified"))
    }

    @Test("individual media deletes require exact confirmation and exact 204")
    func individualDeletes() async throws {
        for fixture in [
            ("screenshots_delete", "screenshot_id", "confirm_screenshot_id"),
            ("screenshots_delete_preview", "preview_id", "confirm_preview_id")
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: fixture.0,
                arguments: [fixture.1: .string("media-1"), fixture.2: .string("other")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        let successTransport = TestHTTPTransport(responses: [.init(statusCode: 204, body: "")])
        let successWorker = try await screenshotsV319Worker(transport: successTransport)
        let success = try await successWorker.handleTool(CallTool.Parameters(
            name: "screenshots_delete",
            arguments: [
                "screenshot_id": .string("shot-1"),
                "confirm_screenshot_id": .string("shot-1")
            ]
        ))
        #expect(success.isError != true)
        #expect(try screenshotsV319Object(success.structuredContent)["statusCode"] == .int(204))

        let unverifiedTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let unverifiedWorker = try await screenshotsV319Worker(transport: unverifiedTransport)
        let unverified = try await unverifiedWorker.handleTool(CallTool.Parameters(
            name: "screenshots_delete_preview",
            arguments: [
                "preview_id": .string("preview-1"),
                "confirm_preview_id": .string("preview-1")
            ]
        ))
        #expect(unverified.isError == true)
        #expect(try screenshotsV319Object(unverified.structuredContent)["operationCommitState"] == .string("committed_unverified"))
    }

    @Test("child lists and gets reject loose arguments before network")
    func strictChildReadArguments() async throws {
        let fixtures: [(String, [String: Value])] = [
            ("screenshots_list", ["set_id": .string("set-1"), "limit": .int(0)]),
            ("screenshots_list_previews", ["set_id": .string("set-1"), "limit": .int(201)]),
            ("screenshots_get", ["screenshot_id": .string("shot/1")]),
            ("screenshots_get_preview", ["preview_id": .int(1)]),
            ("screenshots_list", ["set_id": .string("set-1"), "unexpected": .bool(true)])
        ]
        for fixture in fixtures {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: fixture.0,
                arguments: fixture.1
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("collections require configured-origin self and next links plus exact child lineage")
    func collectionLinksAndLineageAreStrict() async throws {
        let fixtures = [
            #"{"data":[]}"#,
            screenshotsV319Screenshots(
                [],
                documentSelf: "https://hostile.example/v1/appScreenshotSets/set-1/appScreenshots"
            ),
            screenshotsV319Screenshots(
                [],
                next: "https://hostile.example/v1/appScreenshotSets/set-1/appScreenshots?limit=25&cursor=next"
            ),
            screenshotsV319Screenshots(["shot-1"], resourceSetID: "set-2"),
            screenshotsV319Screenshots(["shot-1"], resourceSelfID: "other-shot")
        ]

        for body in fixtures {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_list",
                arguments: ["set_id": .string("set-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("schema-valid optional lineage and resource self omissions remain usable with scoped proof")
    func optionalLineageAndResourceSelf() async throws {
        let setTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319ScreenshotSets(
                ["set-1"],
                documentSelf: "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets?limit=25",
                limit: 25,
                includeLineage: false,
                includeResourceSelf: false
            )),
            .init(statusCode: 200, body: screenshotsV319Previews(
                ["preview-1"],
                documentSelf: "/v1/appPreviewSets/set-1/appPreviews?limit=25",
                limit: 25,
                includeLineage: false,
                includeResourceSelf: false
            ))
        ])
        let setWorker = try await screenshotsV319Worker(transport: setTransport)
        let sets = try await setWorker.handleTool(CallTool.Parameters(
            name: "screenshots_list_sets",
            arguments: ["app_store_version_localization_id": .string("version-loc-1")]
        ))
        let previews = try await setWorker.handleTool(CallTool.Parameters(
            name: "screenshots_list_previews",
            arguments: ["set_id": .string("set-1")]
        ))
        #expect(sets.isError != true)
        #expect(previews.isError != true)

        let file = try screenshotsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        for type in ["appScreenshots", "appPreviews"] {
            let isScreenshot = type == "appScreenshots"
            let id = isScreenshot ? "shot-1" : "preview-1"
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true,
                    includeLineage: false,
                    includeResourceSelf: false
                )),
                .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                    isScreenshot: isScreenshot,
                    ids: [id],
                    total: 1,
                    includeLineage: false,
                    includeResourceSelf: false
                )),
                .init(statusCode: 200, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "COMPLETE",
                    includeLineage: false,
                    includeResourceSelf: false
                ))
            ])
            let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
            let worker = try await screenshotsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: isScreenshot ? "screenshots_upload" : "screenshots_upload_preview",
                arguments: ["set_id": .string("set-1"), "file_path": .string(file.path)]
            ))
            #expect(result.isError != true)
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "GET", "PATCH"])
            #expect(await uploadTransport.requestCount() == 1)
        }
    }

    @Test("a confirmed semantic upload conflict cannot be laundered by a valid GET")
    func semanticUploadConflictRemainsUnresolved() async throws {
        let file = try screenshotsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        for type in ["appScreenshots", "appPreviews"] {
            let isScreenshot = type == "appScreenshots"
            let id = isScreenshot ? "shot-1" : "preview-1"
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true
                )),
                .init(statusCode: 200, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-2",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "COMPLETE"
                )),
                .init(statusCode: 200, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "COMPLETE"
                ))
            ])
            let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
            let worker = try await screenshotsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: isScreenshot ? "screenshots_upload" : "screenshots_upload_preview",
                arguments: ["set_id": .string("set-1"), "file_path": .string(file.path)]
            ))
            let root = try screenshotsV319Object(result.structuredContent)

            #expect(result.isError == true)
            #expect(root["success"] == .bool(false))
            #expect(root["retrySafe"] == .bool(false))
            #expect(root["uploadCommitted"] != .bool(true))
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
            #expect(await uploadTransport.requestCount() == 1)
        }
    }

    @Test("a committed snapshot mismatch cannot be laundered by a later valid GET")
    func committedSnapshotMismatchRemainsUnresolved() async throws {
        let file = try screenshotsV319File(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        for type in ["appScreenshots", "appPreviews"] {
            let isScreenshot = type == "appScreenshots"
            let id = isScreenshot ? "shot-1" : "preview-1"
            let apiTransport = TestHTTPTransport(responses: [
                .init(statusCode: 201, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true
                )),
                .init(statusCode: 200, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 6,
                    state: "COMPLETE",
                    sourceFileChecksum: "00000000000000000000000000000000"
                )),
                .init(statusCode: 200, body: screenshotsV319UploadResponse(
                    type: type,
                    id: id,
                    setID: "set-1",
                    fileName: file.lastPathComponent,
                    fileSize: 5,
                    state: "COMPLETE"
                ))
            ])
            let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
            let worker = try await screenshotsV319Worker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
            let result = try await worker.handleTool(CallTool.Parameters(
                name: isScreenshot ? "screenshots_upload" : "screenshots_upload_preview",
                arguments: ["set_id": .string("set-1"), "file_path": .string(file.path)]
            ))
            let root = try screenshotsV319Object(result.structuredContent)

            #expect(result.isError == true)
            #expect(root["retrySafe"] == .bool(false))
            #expect(root["uploadCommitted"] != .bool(true))
            #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        }
    }

    @Test("screenshot reorder fully paginates membership and verifies exact final order")
    func screenshotReorder() async throws {
        let next = "https://api.example.test/v1/appScreenshotSets/set-1/appScreenshots?limit=200&cursor=next"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319Screenshots(
                ["shot-1"],
                next: next,
                total: 2,
                nextCursor: "next"
            )),
            .init(statusCode: 200, body: screenshotsV319Screenshots(
                ["shot-2"],
                total: 2,
                requestedCursor: "next"
            )),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 200, body: screenshotsV319Screenshots(["shot-2", "shot-1"]))
        ])
        let worker = try await screenshotsV319Worker(transport: transport)
        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_reorder",
            arguments: [
                "set_id": .string("set-1"),
                "screenshot_ids": .array([.string("shot-2"), .string("shot-1")])
            ]
        ))

        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "PATCH", "GET"])
        #expect(requests[2].url?.path == "/v1/appScreenshotSets/set-1/relationships/appScreenshots")
        let linkage = try screenshotsV319RequestDataArray(requests[2])
        #expect(linkage.compactMap { $0["id"] as? String } == ["shot-2", "shot-1"])
        #expect(linkage.allSatisfy { $0["type"] as? String == "appScreenshots" })
        let root = try screenshotsV319Object(result.structuredContent)
        #expect(root["statusCode"] == .int(204))
    }

    @Test("reorder rejects incomplete duplicate and wrong-type arrays before PATCH")
    func reorderPreflightFailures() async throws {
        let malformed: [[String: Value]] = [
            ["set_id": .string("set-1"), "screenshot_ids": .array([])],
            ["set_id": .string("set-1"), "screenshot_ids": .array([.string("shot-1"), .string("shot-1")])],
            ["set_id": .string("set-1"), "screenshot_ids": .array([.int(1)])],
            ["set_id": .string("set-1"), "screenshot_ids": .array([.string("shot/1")])]
        ]
        for arguments in malformed {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await screenshotsV319Worker(transport: transport)
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "screenshots_reorder",
                arguments: arguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }

        let incompleteTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319Screenshots(["shot-1", "shot-2"]))
        ])
        let incompleteWorker = try await screenshotsV319Worker(transport: incompleteTransport)
        let incomplete = try await incompleteWorker.handleTool(CallTool.Parameters(
            name: "screenshots_reorder",
            arguments: [
                "set_id": .string("set-1"),
                "screenshot_ids": .array([.string("shot-1")])
            ]
        ))
        #expect(incomplete.isError == true)
        let incompleteMethods = await incompleteTransport.recordedRequests().map(\.httpMethod)
        #expect(incompleteMethods == ["GET"])

        let missingLinksTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319JSON([
                "data": [[
                    "type": "appScreenshots",
                    "id": "shot-1",
                    "relationships": [
                        "appScreenshotSet": [
                            "data": ["type": "appScreenshotSets", "id": "set-1"]
                        ]
                    ],
                    "links": ["self": "/v1/appScreenshots/shot-1"]
                ]]
            ]))
        ])
        let missingLinksWorker = try await screenshotsV319Worker(transport: missingLinksTransport)
        let missingLinks = try await missingLinksWorker.handleTool(CallTool.Parameters(
            name: "screenshots_reorder",
            arguments: [
                "set_id": .string("set-1"),
                "screenshot_ids": .array([.string("shot-1")])
            ]
        ))
        #expect(missingLinks.isError == true)
        #expect(await missingLinksTransport.recordedRequests().map(\.httpMethod) == ["GET"])
    }

    @Test("full membership inventory fails closed on truncation total drift and duplicate IDs")
    func fullMembershipPagingSafety() async throws {
        for isScreenshot in [true, false] {
            let tool = isScreenshot ? "screenshots_reorder" : "screenshots_reorder_previews"
            let idsArgument = isScreenshot ? "screenshot_ids" : "preview_ids"
            let firstID = isScreenshot ? "shot-1" : "preview-1"
            let secondID = isScreenshot ? "shot-2" : "preview-2"
            let next = isScreenshot
                ? "https://api.example.test/v1/appScreenshotSets/set-1/appScreenshots?limit=200&cursor=next"
                : "https://api.example.test/v1/appPreviewSets/set-1/appPreviews?limit=200&cursor=next"
            let scenarios: [[TestHTTPTransport.Response]] = [
                [
                    .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                        isScreenshot: isScreenshot,
                        ids: [firstID],
                        total: 2
                    ))
                ],
                [
                    .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                        isScreenshot: isScreenshot,
                        ids: [firstID],
                        total: 2,
                        next: next,
                        nextCursor: "next"
                    )),
                    .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                        isScreenshot: isScreenshot,
                        ids: [secondID],
                        total: 3,
                        requestedCursor: "next"
                    ))
                ],
                [
                    .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                        isScreenshot: isScreenshot,
                        ids: [firstID],
                        total: 2,
                        next: next,
                        nextCursor: "next"
                    )),
                    .init(statusCode: 200, body: screenshotsV319InventoryChildrenPage(
                        isScreenshot: isScreenshot,
                        ids: [firstID],
                        total: 2,
                        requestedCursor: "next"
                    ))
                ]
            ]

            for responses in scenarios {
                let transport = TestHTTPTransport(responses: responses)
                let worker = try await screenshotsV319Worker(transport: transport)
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: tool,
                    arguments: [
                        "set_id": .string("set-1"),
                        idsArgument: .array([.string(firstID)])
                    ]
                ))
                #expect(result.isError == true)
                let methods = await transport.recordedRequests().map(\.httpMethod)
                #expect(methods.allSatisfy { $0 == "GET" })
                #expect(!methods.contains("PATCH"))
            }
        }
    }

    @Test("preview reorder uses the preview relationship and reports postflight mismatch")
    func previewReorder() async throws {
        let successTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319Previews(["preview-1", "preview-2"])),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 200, body: screenshotsV319Previews(["preview-2", "preview-1"]))
        ])
        let successWorker = try await screenshotsV319Worker(transport: successTransport)
        let success = try await successWorker.handleTool(CallTool.Parameters(
            name: "screenshots_reorder_previews",
            arguments: [
                "set_id": .string("set-1"),
                "preview_ids": .array([.string("preview-2"), .string("preview-1")])
            ]
        ))
        #expect(success.isError != true)
        let successRequests = await successTransport.recordedRequests()
        #expect(successRequests[1].url?.path == "/v1/appPreviewSets/set-1/relationships/appPreviews")
        let linkage = try screenshotsV319RequestDataArray(successRequests[1])
        #expect(linkage.allSatisfy { $0["type"] as? String == "appPreviews" })

        let mismatchTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: screenshotsV319Previews(["preview-1", "preview-2"])),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 200, body: screenshotsV319Previews(["preview-1", "preview-2"]))
        ])
        let mismatchWorker = try await screenshotsV319Worker(transport: mismatchTransport)
        let mismatch = try await mismatchWorker.handleTool(CallTool.Parameters(
            name: "screenshots_reorder_previews",
            arguments: [
                "set_id": .string("set-1"),
                "preview_ids": .array([.string("preview-2"), .string("preview-1")])
            ]
        ))
        let root = try screenshotsV319Object(mismatch.structuredContent)
        #expect(mismatch.isError == true)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["retrySafe"] == .bool(false))
    }
}

private func screenshotsV319Worker(
    responses: [TestHTTPTransport.Response]
) async throws -> ScreenshotsWorker {
    try await screenshotsV319Worker(transport: TestHTTPTransport(responses: responses))
}

private func screenshotsV319Worker(
    transport: TestHTTPTransport
) async throws -> ScreenshotsWorker {
    try await screenshotsV319Worker(
        apiTransport: transport,
        uploadTransport: TestHTTPTransport(responses: [])
    )
}

private func screenshotsV319Worker(
    apiTransport: TestHTTPTransport,
    uploadTransport: TestHTTPTransport
) async throws -> ScreenshotsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 1
    )
    return ScreenshotsWorker(
        httpClient: client,
        uploadService: UploadService(transport: uploadTransport, batchSize: 1)
    )
}

private func screenshotsV319File(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-mcp-screenshots-v319-\(UUID().uuidString).bin")
    try data.write(to: url)
    return url
}

private func screenshotsV319ToolSchema(_ name: String, in tools: [Tool]) throws -> [String: Value] {
    try screenshotsV319Object(try #require(tools.first { $0.name == name }).inputSchema)
}

private func screenshotsV319Property(_ name: String, in schema: [String: Value]) throws -> [String: Value] {
    let properties = try screenshotsV319Object(schema["properties"])
    return try screenshotsV319Object(properties[name])
}

private func screenshotsV319Object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw ScreenshotsV319TestError.unexpectedValue
    }
    return object
}

private func screenshotsV319Array(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw ScreenshotsV319TestError.unexpectedValue
    }
    return array
}

private func screenshotsV319Query(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func screenshotsV319RequestRelationship(
    _ request: URLRequest,
    name: String
) throws -> [String: Any] {
    let body = try screenshotsV319RequestBody(request)
    let data = try screenshotsV319JSONObject(body["data"])
    let relationships = try screenshotsV319JSONObject(data["relationships"])
    let relationship = try screenshotsV319JSONObject(relationships[name])
    return try screenshotsV319JSONObject(relationship["data"])
}

private func screenshotsV319RequestDataArray(_ request: URLRequest) throws -> [[String: Any]] {
    let body = try screenshotsV319RequestBody(request)
    guard let data = body["data"] as? [[String: Any]] else {
        throw ScreenshotsV319TestError.unexpectedValue
    }
    return data
}

private func screenshotsV319RequestBody(_ request: URLRequest) throws -> [String: Any] {
    guard let data = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ScreenshotsV319TestError.unexpectedValue
    }
    return object
}

private func screenshotsV319JSONObject(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
        throw ScreenshotsV319TestError.unexpectedValue
    }
    return value
}

private func screenshotsV319ScreenshotSet(
    _ id: String,
    parentType: String = "appStoreVersionLocalizations",
    parentID: String = "version-loc-1",
    documentSelf: String? = nil,
    resourceSelf: String? = nil
) -> String {
    let resource = screenshotsV319SetResource(
        type: "appScreenshotSets",
        id: id,
        attributeName: "screenshotDisplayType",
        attributeValue: "APP_IPHONE_67",
        parentType: parentType,
        parentID: parentID,
        resourceSelf: resourceSelf,
        includeLineage: true,
        includeResourceSelf: true
    )
    return screenshotsV319JSON([
        "data": resource,
        "links": ["self": documentSelf ?? "/v1/appScreenshotSets/\(id)"]
    ])
}

private func screenshotsV319ScreenshotSets(
    _ ids: [String],
    parentType: String = "appStoreVersionLocalizations",
    parentID: String = "version-loc-1",
    documentSelf: String? = nil,
    limit: Int = 200,
    total: Int? = nil,
    next: String? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    let path = screenshotsV319SetCollectionPath(
        parentType: parentType,
        parentID: parentID,
        setType: "appScreenshotSets"
    )
    let filter = "filter%5BscreenshotDisplayType%5D=APP_IPHONE_67"
    var links = [
        "self": documentSelf ?? "\(path)?\(filter)&limit=\(limit)"
            + (requestedCursor.map { "&cursor=\($0)" } ?? "")
    ]
    links["next"] = next
    var paging: [String: Any] = ["total": total ?? ids.count, "limit": limit]
    paging["nextCursor"] = nextCursor
    return screenshotsV319JSON([
        "data": ids.map {
            screenshotsV319SetResource(
                type: "appScreenshotSets",
                id: $0,
                attributeName: "screenshotDisplayType",
                attributeValue: "APP_IPHONE_67",
                parentType: parentType,
                parentID: parentID,
                resourceSelf: nil,
                includeLineage: includeLineage,
                includeResourceSelf: includeResourceSelf
            )
        },
        "links": links,
        "meta": ["paging": paging]
    ])
}

private func screenshotsV319PreviewSet(
    _ id: String,
    parentType: String = "appStoreVersionLocalizations",
    parentID: String = "version-loc-1",
    documentSelf: String? = nil,
    resourceSelf: String? = nil
) -> String {
    let resource = screenshotsV319SetResource(
        type: "appPreviewSets",
        id: id,
        attributeName: "previewType",
        attributeValue: "IPHONE_67",
        parentType: parentType,
        parentID: parentID,
        resourceSelf: resourceSelf,
        includeLineage: true,
        includeResourceSelf: true
    )
    return screenshotsV319JSON([
        "data": resource,
        "links": ["self": documentSelf ?? "/v1/appPreviewSets/\(id)"]
    ])
}

private func screenshotsV319PreviewSets(
    _ ids: [String],
    parentType: String = "appStoreVersionLocalizations",
    parentID: String = "version-loc-1",
    documentSelf: String? = nil,
    limit: Int = 200,
    total: Int? = nil,
    next: String? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    let path = screenshotsV319SetCollectionPath(
        parentType: parentType,
        parentID: parentID,
        setType: "appPreviewSets"
    )
    let filter = "filter%5BpreviewType%5D=IPHONE_67"
    var links = [
        "self": documentSelf ?? "\(path)?\(filter)&limit=\(limit)"
            + (requestedCursor.map { "&cursor=\($0)" } ?? "")
    ]
    links["next"] = next
    var paging: [String: Any] = ["total": total ?? ids.count, "limit": limit]
    paging["nextCursor"] = nextCursor
    return screenshotsV319JSON([
        "data": ids.map {
            screenshotsV319SetResource(
                type: "appPreviewSets",
                id: $0,
                attributeName: "previewType",
                attributeValue: "IPHONE_67",
                parentType: parentType,
                parentID: parentID,
                resourceSelf: nil,
                includeLineage: includeLineage,
                includeResourceSelf: includeResourceSelf
            )
        },
        "links": links,
        "meta": ["paging": paging]
    ])
}

private func screenshotsV319InventorySetPage(
    isScreenshot: Bool,
    ids: [String],
    total: Int,
    next: String? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil
) -> String {
    if isScreenshot {
        return screenshotsV319ScreenshotSets(
            ids,
            total: total,
            next: next,
            nextCursor: nextCursor,
            requestedCursor: requestedCursor
        )
    }
    return screenshotsV319PreviewSets(
        ids,
        total: total,
        next: next,
        nextCursor: nextCursor,
        requestedCursor: requestedCursor
    )
}

private func screenshotsV319Screenshots(
    _ ids: [String],
    next: String? = nil,
    setID: String = "set-1",
    documentSelf: String? = nil,
    resourceSetID: String? = nil,
    resourceSelfID: String? = nil,
    limit: Int = 200,
    total: Int? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    screenshotsV319ChildCollection(
        type: "appScreenshots",
        relationshipName: "appScreenshotSet",
        setType: "appScreenshotSets",
        ids: ids,
        setID: setID,
        next: next,
        documentSelf: documentSelf,
        resourceSetID: resourceSetID,
        resourceSelfID: resourceSelfID,
        limit: limit,
        total: total,
        nextCursor: nextCursor,
        requestedCursor: requestedCursor,
        includeLineage: includeLineage,
        includeResourceSelf: includeResourceSelf
    )
}

private func screenshotsV319Previews(
    _ ids: [String],
    next: String? = nil,
    setID: String = "set-1",
    documentSelf: String? = nil,
    resourceSetID: String? = nil,
    resourceSelfID: String? = nil,
    limit: Int = 200,
    total: Int? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    screenshotsV319ChildCollection(
        type: "appPreviews",
        relationshipName: "appPreviewSet",
        setType: "appPreviewSets",
        ids: ids,
        setID: setID,
        next: next,
        documentSelf: documentSelf,
        resourceSetID: resourceSetID,
        resourceSelfID: resourceSelfID,
        limit: limit,
        total: total,
        nextCursor: nextCursor,
        requestedCursor: requestedCursor,
        includeLineage: includeLineage,
        includeResourceSelf: includeResourceSelf
    )
}

private func screenshotsV319InventoryChildrenPage(
    isScreenshot: Bool,
    ids: [String],
    total: Int,
    next: String? = nil,
    nextCursor: String? = nil,
    requestedCursor: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    if isScreenshot {
        return screenshotsV319Screenshots(
            ids,
            next: next,
            total: total,
            nextCursor: nextCursor,
            requestedCursor: requestedCursor,
            includeLineage: includeLineage,
            includeResourceSelf: includeResourceSelf
        )
    }
    return screenshotsV319Previews(
        ids,
        next: next,
        total: total,
        nextCursor: nextCursor,
        requestedCursor: requestedCursor,
        includeLineage: includeLineage,
        includeResourceSelf: includeResourceSelf
    )
}

private func screenshotsV319UploadResponse(
    type: String,
    id: String,
    setID: String,
    fileName: String,
    fileSize: Int,
    state: String,
    includeUploadOperation: Bool = false,
    documentSelf: String? = nil,
    resourceSelf: String? = nil,
    sourceFileChecksum: String? = nil,
    includeLineage: Bool = true,
    includeResourceSelf: Bool = true
) -> String {
    let isScreenshot = type == "appScreenshots"
    let relationshipName = isScreenshot ? "appScreenshotSet" : "appPreviewSet"
    let setType = isScreenshot ? "appScreenshotSets" : "appPreviewSets"
    let stateName = isScreenshot ? "assetDeliveryState" : "videoDeliveryState"
    let path = isScreenshot ? "/v1/appScreenshots/\(id)" : "/v1/appPreviews/\(id)"
    let uploadOperations: [[String: Any]] = includeUploadOperation ? [[
        "method": "PUT",
        "url": "https://upload.example.test/chunk?token=signed-secret",
        "length": fileSize,
        "offset": 0,
        "requestHeaders": []
    ]] : []
    var attributes: [String: Any] = [
        "fileName": fileName,
        "fileSize": fileSize,
        stateName: ["state": state],
        "uploadOperations": uploadOperations
    ]
    attributes["sourceFileChecksum"] = sourceFileChecksum
    let relationship: [String: Any] = includeLineage
        ? ["data": ["type": setType, "id": setID]]
        : ["links": ["related": "/v1/\(setType)/\(setID)"]]
    var resource: [String: Any] = [
        "type": type,
        "id": id,
        "attributes": attributes,
        "relationships": [relationshipName: relationship]
    ]
    if includeResourceSelf {
        resource["links"] = ["self": resourceSelf ?? path]
    }
    return screenshotsV319JSON([
        "data": resource,
        "links": ["self": documentSelf ?? path]
    ])
}

private func screenshotsV319SetResource(
    type: String,
    id: String,
    attributeName: String,
    attributeValue: String,
    parentType: String,
    parentID: String,
    resourceSelf: String?,
    includeLineage: Bool,
    includeResourceSelf: Bool
) -> [String: Any] {
    let relationshipName: String
    switch parentType {
    case "appCustomProductPageLocalizations":
        relationshipName = "appCustomProductPageLocalization"
    case "appStoreVersionExperimentTreatmentLocalizations":
        relationshipName = "appStoreVersionExperimentTreatmentLocalization"
    default:
        relationshipName = "appStoreVersionLocalization"
    }
    let resourcePath = type == "appScreenshotSets"
        ? "/v1/appScreenshotSets/\(id)"
        : "/v1/appPreviewSets/\(id)"
    var resource: [String: Any] = [
        "type": type,
        "id": id,
        "attributes": [attributeName: attributeValue]
    ]
    if includeLineage {
        resource["relationships"] = [
            relationshipName: ["data": ["type": parentType, "id": parentID]]
        ]
    }
    if includeResourceSelf {
        resource["links"] = ["self": resourceSelf ?? resourcePath]
    }
    return resource
}

private func screenshotsV319SetCollectionPath(
    parentType: String,
    parentID: String,
    setType: String
) -> String {
    "/v1/\(parentType)/\(parentID)/\(setType)"
}

private func screenshotsV319ChildCollection(
    type: String,
    relationshipName: String,
    setType: String,
    ids: [String],
    setID: String,
    next: String?,
    documentSelf: String?,
    resourceSetID: String?,
    resourceSelfID: String?,
    limit: Int,
    total: Int?,
    nextCursor: String?,
    requestedCursor: String?,
    includeLineage: Bool,
    includeResourceSelf: Bool
) -> String {
    let childPath = type == "appScreenshots" ? "appScreenshots" : "appPreviews"
    let path = "/v1/\(setType)/\(setID)/\(childPath)"
    var links = [
        "self": documentSelf ?? "\(path)?limit=\(limit)"
            + (requestedCursor.map { "&cursor=\($0)" } ?? "")
    ]
    links["next"] = next
    var paging: [String: Any] = ["total": total ?? ids.count, "limit": limit]
    paging["nextCursor"] = nextCursor
    return screenshotsV319JSON([
        "data": ids.map { id in
            var resource: [String: Any] = [
                "type": type,
                "id": id
            ]
            if includeLineage {
                resource["relationships"] = [
                    relationshipName: ["data": ["type": setType, "id": resourceSetID ?? setID]]
                ]
            }
            if includeResourceSelf {
                resource["links"] = ["self": "/v1/\(type)/\(resourceSelfID ?? id)"]
            }
            return resource
        },
        "links": links,
        "meta": ["paging": paging]
    ])
}

private func screenshotsV319JSON(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private enum ScreenshotsV319TestError: Error {
    case unexpectedValue
}
