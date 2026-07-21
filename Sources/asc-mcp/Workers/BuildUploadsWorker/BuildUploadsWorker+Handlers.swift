import Foundation
import MCP

let defaultBuildUploadFields = BuildUploadsWorker.buildUploadFieldValues.joined(separator: ",")
let safeBuildUploadFileFields = [
    "assetDeliveryState", "assetType", "fileName", "fileSize", "sourceFileChecksums", "uti"
].joined(separator: ",")
let sensitiveBuildUploadFileFields = BuildUploadsWorker.buildUploadFileFieldValues.joined(separator: ",")

struct BuildUploadFingerprint: Sendable, Equatable {
    let appID: String
    let shortVersion: String
    let buildVersion: String
    let platform: String
}

struct BuildUploadFileFingerprint: Sendable, Equatable {
    let buildUploadID: String
    let assetType: String
    let fileName: String
    let fileSize: Int
    let uti: String
}

enum BuildUploadParentCreationOutcome: Sendable {
    case beforeRequest(String)
    case rejected(String)
    case created(ASCBuildUpload)
    case recovered(
        ASCBuildUpload,
        commitState: ASCNonIdempotentWriteFailureDisposition
    )
    case unresolved(
        String,
        candidateIDs: [String],
        commitState: ASCNonIdempotentWriteFailureDisposition
    )
}

enum BuildUploadFileReservationOutcome: Sendable {
    case beforeRequest(String)
    case rejected(String)
    case created(ASCBuildUploadFile)
    case recovered(
        ASCBuildUploadFile,
        commitState: ASCNonIdempotentWriteFailureDisposition
    )
    case unresolved(
        String,
        candidateIDs: [String],
        commitState: ASCNonIdempotentWriteFailureDisposition
    )
}

enum BuildUploadFileCommitOutcome: Sendable {
    case beforeRequest(String)
    case rejected(String)
    case committed(ASCBuildUploadFile, reconciled: Bool)
    case terminalFailure(String, ASCBuildUploadFile)
    case unresolved(
        String,
        fileID: String,
        file: ASCBuildUploadFile?,
        commitState: ASCNonIdempotentWriteFailureDisposition
    )
}

extension BuildUploadsWorker {
    func listBuildUploads(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let appID = try canonicalIdentifier(arguments["app_id"], field: "app_id")
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/buildUploads"
            let query = try buildUploadListQuery(arguments)
            let response: ASCBuildUploadsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: .strict(path: path, query: query),
                    as: ASCBuildUploadsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCBuildUploadsResponse.self
                )
            }
            try validateBuildUploadsDocument(response, expectedPath: path, context: "build uploads list")

            let includeSensitive = try boolean(
                arguments["include_sensitive_details"],
                field: "include_sensitive_details",
                defaultValue: false
            )
            var result: [String: Any] = [
                "success": true,
                "buildUploads": response.data.map(formatBuildUpload),
                "count": response.data.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let included = response.included, !included.isEmpty {
                result["included"] = included.map { formatIncluded($0, includeSensitive: includeSensitive) }
            }
            return MCPResult.jsonObject(
                result,
                explicitlySensitivePaths: sensitivePaths(roots: [["included", "*"]]),
                explicitlyAllowedSensitivePaths: includeSensitive
                    ? sensitivePaths(roots: [["included", "*"]])
                    : []
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list build uploads")
        }
    }

    func getBuildUpload(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'build_upload_id' is missing")
        }

        do {
            let buildUploadID = try canonicalIdentifier(
                arguments["build_upload_id"],
                field: "build_upload_id"
            )
            let endpoint = "/v1/buildUploads/\(try ASCPathSegment.encode(buildUploadID, field: "build_upload_id"))"
            var query = try buildUploadReadQuery(arguments)
            if query["fields[buildUploads]"] == nil {
                query["fields[buildUploads]"] = defaultBuildUploadFields
            }
            let response: ASCBuildUploadResponse = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCBuildUploadResponse.self
            )
            try validateBuildUploadDocument(
                response,
                expectedID: buildUploadID,
                expectedPath: endpoint,
                fingerprint: nil,
                context: "build upload get"
            )

            let includeSensitive = try boolean(
                arguments["include_sensitive_details"],
                field: "include_sensitive_details",
                defaultValue: false
            )
            var result: [String: Any] = [
                "success": true,
                "buildUpload": formatBuildUpload(response.data)
            ]
            if let included = response.included, !included.isEmpty {
                result["included"] = included.map { formatIncluded($0, includeSensitive: includeSensitive) }
            }
            return MCPResult.jsonObject(
                result,
                explicitlySensitivePaths: sensitivePaths(roots: [["included", "*"]]),
                explicitlyAllowedSensitivePaths: includeSensitive
                    ? sensitivePaths(roots: [["included", "*"]])
                    : []
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get build upload")
        }
    }

    func createBuildUpload(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters: app_id, short_version, build_version, platform")
        }

        do {
            let fingerprint = try buildUploadFingerprint(arguments)
            let outcome = await createBuildUploadParent(fingerprint)
            return buildUploadCreationResult(outcome, fingerprint: fingerprint)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create build upload")
        }
    }

    func deleteBuildUpload(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error(
                "Required parameters: build_upload_id, confirm_build_upload_id"
            )
        }

        let buildUploadID: String
        let endpoint: String
        do {
            buildUploadID = try canonicalIdentifier(
                arguments["build_upload_id"],
                field: "build_upload_id"
            )
            let confirmationID = try canonicalIdentifier(
                arguments["confirm_build_upload_id"],
                field: "confirm_build_upload_id"
            )
            guard confirmationID == buildUploadID else {
                throw BuildUploadArgumentError(
                    "Deleting a build upload is destructive. Set confirm_build_upload_id to the exact build_upload_id to continue."
                )
            }
            endpoint = "/v1/buildUploads/\(try ASCPathSegment.encode(buildUploadID, field: "build_upload_id"))"
        } catch {
            return preRequestWriteResult(
                "Failed to validate build upload deletion: \(Redactor.redact(error.localizedDescription))"
            )
        }

        if Task.isCancelled {
            return preRequestWriteResult("Build upload deletion was cancelled before the request.")
        }

        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(endpoint)
        } catch {
            let commitState = ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            )
            if commitState == .rejected {
                return rejectedWriteResult(
                    "Apple rejected the build upload deletion: \(Redactor.redact(error.localizedDescription))"
                )
            }
            return buildUploadDeleteAmbiguousResult(
                buildUploadID: buildUploadID,
                message: "The build upload deletion outcome is unknown: \(Redactor.redact(error.localizedDescription))",
                commitState: commitState
            )
        }
        guard receipt.statusCode == 204 else {
            return buildUploadDeleteAmbiguousResult(
                buildUploadID: buildUploadID,
                message: "Apple returned unexpected successful HTTP status \(receipt.statusCode) for build upload deletion; exact 204 is required.",
                commitState: .committedUnverified
            )
        }
        return MCPResult.jsonObject([
            "success": true,
            "buildUploadId": buildUploadID,
            "operationCommitState": "committed"
        ])
    }

    func listBuildUploadFiles(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'build_upload_id' is missing")
        }

        do {
            let buildUploadID = try canonicalIdentifier(
                arguments["build_upload_id"],
                field: "build_upload_id"
            )
            let path = "/v1/buildUploads/\(try ASCPathSegment.encode(buildUploadID, field: "build_upload_id"))/buildUploadFiles"
            let query = try buildUploadFileListQuery(arguments)
            let response: ASCBuildUploadFilesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: .strict(path: path, query: query),
                    as: ASCBuildUploadFilesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCBuildUploadFilesResponse.self
                )
            }
            try validateBuildUploadFilesDocument(
                response,
                expectedPath: path,
                context: "build upload files list"
            )

            let includeSensitive = try boolean(
                arguments["include_sensitive_details"],
                field: "include_sensitive_details",
                defaultValue: false
            )
            var result: [String: Any] = [
                "success": true,
                "buildUploadFiles": response.data.map {
                    formatBuildUploadFile($0, includeSensitive: includeSensitive)
                },
                "count": response.data.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            return MCPResult.jsonObject(
                result,
                explicitlySensitivePaths: sensitivePaths(roots: [["buildUploadFiles", "*"]]),
                explicitlyAllowedSensitivePaths: includeSensitive
                    ? sensitivePaths(roots: [["buildUploadFiles", "*"]])
                    : []
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list build upload files")
        }
    }

    func getBuildUploadFile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'file_id' is missing")
        }

        do {
            let fileID = try canonicalIdentifier(arguments["file_id"], field: "file_id")
            let includeSensitive = try boolean(
                arguments["include_sensitive_details"],
                field: "include_sensitive_details",
                defaultValue: false
            )
            let fields = try stringList(
                arguments["fields_build_upload_files"],
                field: "fields_build_upload_files",
                allowedValues: Set(Self.buildUploadFileFieldValues)
            )?.joined(separator: ",") ?? (includeSensitive ? sensitiveBuildUploadFileFields : safeBuildUploadFileFields)
            try validateSensitiveFieldSelection(
                arguments["fields_build_upload_files"],
                includeSensitive: includeSensitive
            )
            let endpoint = "/v1/buildUploadFiles/\(try ASCPathSegment.encode(fileID, field: "file_id"))"
            let response: ASCBuildUploadFileResponse = try await httpClient.get(
                endpoint,
                parameters: ["fields[buildUploadFiles]": fields],
                as: ASCBuildUploadFileResponse.self
            )
            try validateBuildUploadFileDocument(
                response,
                expectedID: fileID,
                expectedPath: endpoint,
                fingerprint: nil,
                context: "build upload file get"
            )
            return MCPResult.jsonObject(
                [
                    "success": true,
                    "buildUploadFile": formatBuildUploadFile(
                        response.data,
                        includeSensitive: includeSensitive
                    )
                ],
                explicitlySensitivePaths: sensitivePaths(roots: [["buildUploadFile"]]),
                explicitlyAllowedSensitivePaths: includeSensitive
                    ? sensitivePaths(roots: [["buildUploadFile"]])
                    : []
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get build upload file")
        }
    }

    func reserveBuildUploadFile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error(
                "Required parameters: build_upload_id, asset_type, file_name, file_size, uti"
            )
        }

        do {
            let fingerprint = try buildUploadFileFingerprint(arguments)
            let includeSensitive = try boolean(
                arguments["include_sensitive_details"],
                field: "include_sensitive_details",
                defaultValue: false
            )
            let outcome = await reserveBuildUploadFileResource(fingerprint)
            return buildUploadFileReservationResult(
                outcome,
                buildUploadID: fingerprint.buildUploadID,
                includeSensitive: includeSensitive
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to reserve build upload file")
        }
    }

    func commitBuildUploadFile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'file_id' is missing")
        }

        do {
            let fileID = try canonicalIdentifier(arguments["file_id"], field: "file_id")
            let attributes = try commitAttributes(arguments)
            guard !attributes.isEmpty else {
                throw BuildUploadArgumentError(
                    "At least one of source_file_checksums or uploaded is required"
                )
            }
            return buildUploadFileCommitResult(
                await commitBuildUploadFileResource(fileID: fileID, attributes: attributes)
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to commit build upload file")
        }
    }
}

extension BuildUploadsWorker {
    func buildUploadListQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let includeSensitive = try boolean(
            arguments["include_sensitive_details"],
            field: "include_sensitive_details",
            defaultValue: false
        )
        try validateSensitiveFieldSelection(
            arguments["fields_build_upload_files"],
            includeSensitive: includeSensitive
        )
        var query: [String: String] = [
            "fields[buildUploads]": defaultBuildUploadFields,
            "fields[buildUploadFiles]": includeSensitive
                ? sensitiveBuildUploadFileFields
                : safeBuildUploadFileFields,
            "limit": String(try boundedInteger(
                arguments["limit"],
                field: "limit",
                range: 1...200,
                defaultValue: 25
            ))
        ]
        try applyStringList(
            arguments["short_version_strings"],
            field: "short_version_strings",
            appleName: "filter[cfBundleShortVersionString]",
            to: &query
        )
        try applyStringList(
            arguments["build_versions"],
            field: "build_versions",
            appleName: "filter[cfBundleVersion]",
            to: &query
        )
        try applyStringList(
            arguments["platforms"],
            field: "platforms",
            appleName: "filter[platform]",
            allowedValues: Set(Self.platformValues),
            to: &query
        )
        try applyStringList(
            arguments["states"],
            field: "states",
            appleName: "filter[state]",
            to: &query
        )
        try applyStringList(
            arguments["sort"],
            field: "sort",
            appleName: "sort",
            allowedValues: Set(["cfBundleVersion", "-cfBundleVersion", "uploadedDate", "-uploadedDate"]),
            to: &query
        )
        try applyStringList(
            arguments["fields_build_uploads"],
            field: "fields_build_uploads",
            appleName: "fields[buildUploads]",
            allowedValues: Set(Self.buildUploadFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["fields_builds"],
            field: "fields_builds",
            appleName: "fields[builds]",
            allowedValues: Set(Self.buildFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["fields_build_upload_files"],
            field: "fields_build_upload_files",
            appleName: "fields[buildUploadFiles]",
            allowedValues: Set(Self.buildUploadFileFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["include"],
            field: "include",
            appleName: "include",
            allowedValues: Set(Self.buildUploadIncludeValues),
            to: &query
        )
        return query
    }

    func buildUploadReadQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let includeSensitive = try boolean(
            arguments["include_sensitive_details"],
            field: "include_sensitive_details",
            defaultValue: false
        )
        try validateSensitiveFieldSelection(
            arguments["fields_build_upload_files"],
            includeSensitive: includeSensitive
        )
        var query: [String: String] = [
            "fields[buildUploadFiles]": includeSensitive
                ? sensitiveBuildUploadFileFields
                : safeBuildUploadFileFields
        ]
        try applyStringList(
            arguments["fields_build_uploads"],
            field: "fields_build_uploads",
            appleName: "fields[buildUploads]",
            allowedValues: Set(Self.buildUploadFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["fields_builds"],
            field: "fields_builds",
            appleName: "fields[builds]",
            allowedValues: Set(Self.buildFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["fields_build_upload_files"],
            field: "fields_build_upload_files",
            appleName: "fields[buildUploadFiles]",
            allowedValues: Set(Self.buildUploadFileFieldValues),
            to: &query
        )
        try applyStringList(
            arguments["include"],
            field: "include",
            appleName: "include",
            allowedValues: Set(Self.buildUploadIncludeValues),
            to: &query
        )
        return query
    }

    func buildUploadFileListQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let includeSensitive = try boolean(
            arguments["include_sensitive_details"],
            field: "include_sensitive_details",
            defaultValue: false
        )
        try validateSensitiveFieldSelection(
            arguments["fields_build_upload_files"],
            includeSensitive: includeSensitive
        )
        var query: [String: String] = [
            "fields[buildUploadFiles]": includeSensitive
                ? sensitiveBuildUploadFileFields
                : safeBuildUploadFileFields,
            "limit": String(try boundedInteger(
                arguments["limit"],
                field: "limit",
                range: 1...200,
                defaultValue: 25
            ))
        ]
        try applyStringList(
            arguments["fields_build_upload_files"],
            field: "fields_build_upload_files",
            appleName: "fields[buildUploadFiles]",
            allowedValues: Set(Self.buildUploadFileFieldValues),
            to: &query
        )
        return query
    }

    func formatBuildUpload(_ upload: ASCBuildUpload) -> [String: Any] {
        var result: [String: Any] = [
            "id": upload.id,
            "type": upload.type,
            "shortVersion": (upload.attributes?.cfBundleShortVersionString).jsonSafe,
            "buildVersion": (upload.attributes?.cfBundleVersion).jsonSafe,
            "createdDate": (upload.attributes?.createdDate).jsonSafe,
            "platform": (upload.attributes?.platform).jsonSafe,
            "uploadedDate": (upload.attributes?.uploadedDate).jsonSafe
        ]
        if let state = upload.attributes?.state {
            result["state"] = [
                "state": state.state.jsonSafe,
                "errors": formatStateDetails(state.errors),
                "warnings": formatStateDetails(state.warnings),
                "infos": formatStateDetails(state.infos)
            ]
        }
        if let relationships = upload.relationships {
            result["relationships"] = [
                "buildId": (relationships.build?.data?.id).jsonSafe,
                "assetFileId": (relationships.assetFile?.data?.id).jsonSafe,
                "assetDescriptionFileId": (relationships.assetDescriptionFile?.data?.id).jsonSafe,
                "assetSpiFileId": (relationships.assetSpiFile?.data?.id).jsonSafe,
                "buildUploadFilesURL": (relationships.buildUploadFiles?.links?.related).jsonSafe
            ]
        }
        return result
    }

    func formatBuildUploadFile(
        _ file: ASCBuildUploadFile,
        includeSensitive: Bool
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": file.id,
            "type": file.type,
            "assetType": (file.attributes?.assetType).jsonSafe,
            "fileName": (file.attributes?.fileName).jsonSafe,
            "fileSize": (file.attributes?.fileSize).jsonSafe,
            "uti": (file.attributes?.uti).jsonSafe
        ]
        if let checksums = file.attributes?.sourceFileChecksums {
            result["sourceFileChecksums"] = formatChecksums(checksums)
        }
        if let delivery = file.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": delivery.state.jsonSafe,
                "errors": formatAssetErrors(delivery.errors),
                "warnings": formatAssetErrors(delivery.warnings)
            ]
        }
        if includeSensitive {
            result["assetToken"] = (file.attributes?.assetToken).jsonSafe
            if let operations = file.attributes?.uploadOperations {
                result["uploadOperations"] = operations.map(formatUploadOperation)
            }
        } else if file.attributes?.assetToken != nil || file.attributes?.uploadOperations != nil {
            result["sensitiveDetailsRedacted"] = true
        }
        return result
    }

    func formatTransferReceipts(_ receipts: [UploadPartReceipt]) -> [[String: Any]] {
        receipts.map { receipt in
            [
                "operationIndex": receipt.operationIndex,
                "method": receipt.method,
                "offset": receipt.offset,
                "length": receipt.length,
                "attempts": receipt.attempts,
                "statusCode": receipt.statusCode,
                "expiration": receipt.expiration.jsonSafe,
                "partNumber": receipt.partNumber.jsonSafe,
                "entityTag": receipt.entityTag.jsonSafe,
                "responseEntityTag": receipt.responseEntityTag.jsonSafe
            ]
        }
    }

    func buildUploadFingerprint(_ arguments: [String: Value]) throws -> BuildUploadFingerprint {
        let appID = try canonicalIdentifier(arguments["app_id"], field: "app_id")
        let shortVersion = try requiredString(arguments["short_version"], field: "short_version")
        let buildVersion = try requiredString(arguments["build_version"], field: "build_version")
        let platform = try requiredString(arguments["platform"], field: "platform")
        guard Self.platformValues.contains(platform) else {
            throw BuildUploadArgumentError("'platform' has an unsupported value")
        }
        return BuildUploadFingerprint(
            appID: appID,
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            platform: platform
        )
    }

    func buildUploadFileFingerprint(
        _ arguments: [String: Value]
    ) throws -> BuildUploadFileFingerprint {
        let buildUploadID = try canonicalIdentifier(
            arguments["build_upload_id"],
            field: "build_upload_id"
        )
        let assetType = try requiredString(arguments["asset_type"], field: "asset_type")
        guard Self.assetTypeValues.contains(assetType) else {
            throw BuildUploadArgumentError("'asset_type' has an unsupported value")
        }
        let fileName = try canonicalFileName(
            try requiredString(arguments["file_name"], field: "file_name"),
            field: "file_name"
        )
        guard let fileSizeValue = arguments["file_size"] else {
            throw BuildUploadArgumentError("Required parameter 'file_size' is missing")
        }
        let fileSize = try boundedInteger(
            fileSizeValue,
            field: "file_size",
            range: 1...Self.maximumFileSize,
            defaultValue: 0
        )
        let uti = try requiredString(arguments["uti"], field: "uti")
        guard Self.utiValues.contains(uti) else {
            throw BuildUploadArgumentError("'uti' has an unsupported value")
        }
        return BuildUploadFileFingerprint(
            buildUploadID: buildUploadID,
            assetType: assetType,
            fileName: fileName,
            fileSize: fileSize,
            uti: uti
        )
    }

    func boundedInteger(
        _ value: Value?,
        field: String,
        range: ClosedRange<Int>,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let integer = value.intValue, range.contains(integer) else {
            throw BuildUploadArgumentError(
                "'\(field)' must be between \(range.lowerBound) and \(range.upperBound)"
            )
        }
        return integer
    }

    func nonemptyString(_ value: Value?) -> String? {
        guard let string = value?.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return string
    }

    func canonicalFileName(_ value: String, field: String) throws -> String {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BuildUploadArgumentError("'\(field)' must be one canonical file name")
        }
        return value
    }

}

extension BuildUploadsWorker {
    func matchingBuildUploads(
        _ fingerprint: BuildUploadFingerprint
    ) async throws -> [ASCBuildUpload] {
        let path = "/v1/apps/\(try ASCPathSegment.encode(fingerprint.appID, field: "app_id"))/buildUploads"
        let query = [
            "filter[cfBundleShortVersionString]": fingerprint.shortVersion,
            "filter[cfBundleVersion]": fingerprint.buildVersion,
            "filter[platform]": fingerprint.platform,
            "fields[buildUploads]": defaultBuildUploadFields,
            "limit": "200"
        ]
        var response: ASCBuildUploadsResponse = try await httpClient.get(
            path,
            parameters: query,
            as: ASCBuildUploadsResponse.self
        )
        var matchesByID: [String: ASCBuildUpload] = [:]
        var seenResourceIDs = Set<String>()
        var seenContinuations = Set<String>()
        var pageCount = 0
        var expectedTotal: Int?

        while true {
            pageCount += 1
            guard pageCount <= 20 else {
                throw ASCError.parsing("Build upload recovery exceeded 20 pages")
            }
            try validateBuildUploadsDocument(
                response,
                expectedPath: path,
                context: "build upload recovery page \(pageCount)"
            )
            try validateStableTotal(
                response.meta?.paging?.total,
                expectedTotal: &expectedTotal,
                context: "build upload recovery"
            )
            for upload in response.data {
                guard seenResourceIDs.insert(upload.id).inserted else {
                    throw ASCError.parsing(
                        "Apple returned duplicate build upload identity '\(upload.id)' across recovery pages"
                    )
                }
                if self.matches(upload, fingerprint: fingerprint) {
                    matchesByID[upload.id] = upload
                }
            }
            guard let next = response.links.next else { break }
            guard pageCount < 20 else {
                throw ASCError.parsing("Build upload recovery exceeded 20 pages")
            }
            guard seenContinuations.insert(next).inserted else {
                throw ASCError.parsing("Apple repeated a build upload recovery continuation URL")
            }
            response = try await httpClient.getPage(
                next,
                scope: .strict(path: path, query: query),
                as: ASCBuildUploadsResponse.self
            )
        }
        if let expectedTotal, seenResourceIDs.count != expectedTotal {
            throw ASCError.parsing(
                "Build upload recovery completed with \(seenResourceIDs.count) resources, expected \(expectedTotal)"
            )
        }
        return matchesByID.values.sorted { $0.id < $1.id }
    }

    func allBuildUploadFiles(
        _ buildUploadID: String
    ) async throws -> [ASCBuildUploadFile] {
        let canonicalID = try canonicalIdentifier(.string(buildUploadID), field: "build_upload_id")
        let path = "/v1/buildUploads/\(try ASCPathSegment.encode(canonicalID, field: "build_upload_id"))/buildUploadFiles"
        let query = [
            "fields[buildUploadFiles]": sensitiveBuildUploadFileFields,
            "limit": "200"
        ]
        var response: ASCBuildUploadFilesResponse = try await httpClient.get(
            path,
            parameters: query,
            as: ASCBuildUploadFilesResponse.self
        )
        var resources: [ASCBuildUploadFile] = []
        var seenResourceIDs = Set<String>()
        var seenContinuations = Set<String>()
        var pageCount = 0
        var expectedTotal: Int?

        while true {
            pageCount += 1
            guard pageCount <= 20 else {
                throw ASCError.parsing("Build upload file recovery exceeded 20 pages")
            }
            try validateBuildUploadFilesDocument(
                response,
                expectedPath: path,
                context: "build upload file recovery page \(pageCount)"
            )
            try validateStableTotal(
                response.meta?.paging?.total,
                expectedTotal: &expectedTotal,
                context: "build upload file recovery"
            )
            for file in response.data {
                guard seenResourceIDs.insert(file.id).inserted else {
                    throw ASCError.parsing(
                        "Apple returned duplicate build upload file identity '\(file.id)' across recovery pages"
                    )
                }
                resources.append(file)
            }
            guard let next = response.links.next else { break }
            guard pageCount < 20 else {
                throw ASCError.parsing("Build upload file recovery exceeded 20 pages")
            }
            guard seenContinuations.insert(next).inserted else {
                throw ASCError.parsing("Apple repeated a build upload file recovery continuation URL")
            }
            response = try await httpClient.getPage(
                next,
                scope: .strict(path: path, query: query),
                as: ASCBuildUploadFilesResponse.self
            )
        }
        if let expectedTotal, seenResourceIDs.count != expectedTotal {
            throw ASCError.parsing(
                "Build upload file recovery completed with \(seenResourceIDs.count) resources, expected \(expectedTotal)"
            )
        }
        return resources
    }

    func fetchBuildUpload(_ id: String) async throws -> ASCBuildUpload {
        let canonicalID = try canonicalIdentifier(.string(id), field: "build_upload_id")
        let endpoint = "/v1/buildUploads/\(try ASCPathSegment.encode(canonicalID, field: "build_upload_id"))"
        let response: ASCBuildUploadResponse = try await httpClient.get(
            endpoint,
            parameters: ["fields[buildUploads]": defaultBuildUploadFields],
            as: ASCBuildUploadResponse.self
        )
        try validateBuildUploadDocument(
            response,
            expectedID: canonicalID,
            expectedPath: endpoint,
            fingerprint: nil,
            context: "build upload inspection"
        )
        return response.data
    }

    func fetchBuildUploadFile(_ id: String) async throws -> ASCBuildUploadFile {
        let canonicalID = try canonicalIdentifier(.string(id), field: "file_id")
        let endpoint = "/v1/buildUploadFiles/\(try ASCPathSegment.encode(canonicalID, field: "file_id"))"
        let response: ASCBuildUploadFileResponse = try await httpClient.get(
            endpoint,
            parameters: ["fields[buildUploadFiles]": sensitiveBuildUploadFileFields],
            as: ASCBuildUploadFileResponse.self
        )
        try validateBuildUploadFileDocument(
            response,
            expectedID: canonicalID,
            expectedPath: endpoint,
            fingerprint: nil,
            context: "build upload file inspection"
        )
        return response.data
    }

    func matches(
        _ upload: ASCBuildUpload,
        fingerprint: BuildUploadFingerprint
    ) -> Bool {
        upload.type == "buildUploads" &&
            !upload.id.isEmpty &&
            upload.attributes?.cfBundleShortVersionString == fingerprint.shortVersion &&
            upload.attributes?.cfBundleVersion == fingerprint.buildVersion &&
            upload.attributes?.platform == fingerprint.platform
    }

    func matches(
        _ file: ASCBuildUploadFile,
        fingerprint: BuildUploadFileFingerprint
    ) -> Bool {
        file.type == "buildUploadFiles" &&
            !file.id.isEmpty &&
            file.attributes?.assetType == fingerprint.assetType &&
            file.attributes?.fileName == fingerprint.fileName &&
            file.attributes?.fileSize == fingerprint.fileSize &&
            file.attributes?.uti == fingerprint.uti
    }

    func canonicalIdentifier(
        _ value: Value?,
        field: String
    ) throws -> String {
        guard let string = value?.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw BuildUploadArgumentError("'\(field)' must be a non-empty canonical identifier")
        }
        let encoded = try ASCPathSegment.encode(string, field: field)
        guard encoded == string else {
            throw BuildUploadArgumentError("'\(field)' must be a canonical App Store Connect resource ID")
        }
        return string
    }
}

extension BuildUploadsWorker {
    private func reconcileBuildUploadCreation(
        _ fingerprint: BuildUploadFingerprint,
        excluding beforeIDs: Set<String>,
        context: String,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) async -> BuildUploadParentCreationOutcome {
        do {
            let candidates = try await matchingBuildUploads(fingerprint).filter {
                !beforeIDs.contains($0.id)
            }
            if candidates.count == 1, let candidate = candidates.first {
                return .recovered(candidate, commitState: commitState)
            }
            return .unresolved(
                context,
                candidateIDs: candidates.map(\.id).sorted(),
                commitState: commitState
            )
        } catch {
            return .unresolved(
                "\(context) Postflight reconciliation also failed: \(Redactor.redact(error.localizedDescription))",
                candidateIDs: [],
                commitState: commitState
            )
        }
    }

    private func reconcileBuildUploadFileReservation(
        _ fingerprint: BuildUploadFileFingerprint,
        excluding beforeIDs: Set<String>,
        context: String,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) async -> BuildUploadFileReservationOutcome {
        do {
            let candidates = try await allBuildUploadFiles(fingerprint.buildUploadID).filter {
                !beforeIDs.contains($0.id) && matches($0, fingerprint: fingerprint)
            }
            if candidates.count == 1, let candidate = candidates.first {
                return .recovered(candidate, commitState: commitState)
            }
            return .unresolved(
                context,
                candidateIDs: candidates.map(\.id).sorted(),
                commitState: commitState
            )
        } catch {
            return .unresolved(
                "\(context) Postflight reconciliation also failed: \(Redactor.redact(error.localizedDescription))",
                candidateIDs: [],
                commitState: commitState
            )
        }
    }

    private func reconcileBuildUploadFileCommit(
        fileID: String,
        context: String,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) async -> BuildUploadFileCommitOutcome {
        do {
            let file = try await fetchBuildUploadFile(fileID)
            return .unresolved(
                "\(context) A follow-up GET cannot prove whether this PATCH was applied; the file was retained for inspection.",
                fileID: fileID,
                file: file,
                commitState: commitState
            )
        } catch {
            return .unresolved(
                "\(context) Follow-up inspection also failed: \(Redactor.redact(error.localizedDescription))",
                fileID: fileID,
                file: nil,
                commitState: commitState
            )
        }
    }

    private func rejectedWriteResult(_ message: String) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "operationCommitState": "rejected",
                "write_outcome": "rejected",
                "retrySafe": false
            ],
            text: "Error: \(message)",
            isError: true
        )
    }

    private func preRequestWriteResult(_ message: String) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "requestAttempted": false,
                "operationCommitState": "not_attempted",
                "retrySafe": true
            ],
            text: "Error: \(message)",
            isError: true
        )
    }

    private func buildUploadDeleteAmbiguousResult(
        buildUploadID: String,
        message: String,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "buildUploadId": buildUploadID,
            "requestAttempted": true,
            "operationCommitState": commitState.rawValue,
            "write_outcome": commitState.rawValue,
            "inspectionRequired": true,
            "inspection": [
                "tool": "build_uploads_get",
                "arguments": ["build_upload_id": buildUploadID]
            ],
            "retrySafe": false
        ]
        appendAmbiguousWriteState(commitState, to: &payload)
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) Inspect build upload '\(buildUploadID)' before any retry.",
            isError: true
        )
    }

    private func unresolvedWriteResult(
        message: String,
        commitState: ASCNonIdempotentWriteFailureDisposition,
        candidateIDs: [String],
        inspection: [String: Any]
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "identityState": "unknown",
            "candidateIds": candidateIDs,
            "operationCommitState": commitState.rawValue,
            "write_outcome": commitState.rawValue,
            "retrySafe": false,
            "inspectionRequired": true,
            "inspection": inspection
        ]
        if commitState == .outcomeUnknown {
            payload["outcomeUnknown"] = true
        } else if commitState == .committedUnverified {
            payload["operationCommitted"] = true
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) Inspect the exact fingerprint before retrying.",
            isError: true
        )
    }

    private func buildUploadInspectionArguments(
        _ fingerprint: BuildUploadFingerprint
    ) -> [String: Any] {
        [
            "app_id": fingerprint.appID,
            "short_version_strings": [fingerprint.shortVersion],
            "build_versions": [fingerprint.buildVersion],
            "platforms": [fingerprint.platform],
            "limit": 200
        ]
    }

    private func validateStableTotal(
        _ total: Int?,
        expectedTotal: inout Int?,
        context: String
    ) throws {
        guard let total else { return }
        guard total >= 0 else {
            throw ASCError.parsing("Apple returned a negative paging total in \(context)")
        }
        if let expectedTotal, expectedTotal != total {
            throw ASCError.parsing("Apple changed the paging total across \(context) pages")
        }
        expectedTotal = total
    }
}

extension BuildUploadsWorker {
    private func validateBuildUploadsDocument(
        _ response: ASCBuildUploadsResponse,
        expectedPath: String,
        context: String
    ) throws {
        try validateDocumentSelf(response.links.`self`, expectedPath: expectedPath, context: context)
        try validateBuildUploads(response.data, context: context)
        try validateIncludedResources(response.included, context: context)
        try validatePaging(
            response.meta,
            pageCount: response.data.count,
            nextURL: response.links.next,
            context: context
        )
    }

    private func validateBuildUploadDocument(
        _ response: ASCBuildUploadResponse,
        expectedID: String?,
        expectedPath: String,
        fingerprint: BuildUploadFingerprint?,
        context: String
    ) throws {
        try validateDocumentSelf(response.links.`self`, expectedPath: expectedPath, context: context)
        try validateBuildUpload(
            response.data,
            expectedID: expectedID,
            fingerprint: fingerprint,
            context: context
        )
        try validateIncludedResources(response.included, context: context)
    }

    private func validateBuildUploadFilesDocument(
        _ response: ASCBuildUploadFilesResponse,
        expectedPath: String,
        context: String
    ) throws {
        try validateDocumentSelf(response.links.`self`, expectedPath: expectedPath, context: context)
        try validateBuildUploadFiles(response.data, context: context)
        try validatePaging(
            response.meta,
            pageCount: response.data.count,
            nextURL: response.links.next,
            context: context
        )
    }

    private func validateBuildUploadFileDocument(
        _ response: ASCBuildUploadFileResponse,
        expectedID: String?,
        expectedPath: String,
        fingerprint: BuildUploadFileFingerprint?,
        context: String
    ) throws {
        try validateDocumentSelf(response.links.`self`, expectedPath: expectedPath, context: context)
        try validateBuildUploadFile(
            response.data,
            expectedID: expectedID,
            fingerprint: fingerprint,
            context: context
        )
    }

    private func validateBuildUploads(
        _ uploads: [ASCBuildUpload],
        context: String
    ) throws {
        var identities = Set<String>()
        for upload in uploads {
            try validateBuildUpload(
                upload,
                expectedID: nil,
                fingerprint: nil,
                context: context
            )
            guard identities.insert(upload.id).inserted else {
                throw ASCError.parsing(
                    "Apple returned duplicate build upload identity '\(upload.id)' in \(context)"
                )
            }
        }
    }

    private func validateBuildUpload(
        _ upload: ASCBuildUpload,
        expectedID: String?,
        fingerprint: BuildUploadFingerprint?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: upload.type,
            id: upload.id,
            expectedType: "buildUploads",
            expectedID: expectedID,
            context: context
        )
        if let fingerprint, !matches(upload, fingerprint: fingerprint) {
            throw ASCError.parsing("Apple returned a build upload outside the exact requested fingerprint")
        }
        if let platform = upload.attributes?.platform,
           !Self.platformValues.contains(platform) {
            throw ASCError.parsing("Apple returned an unsupported build upload platform in \(context)")
        }
        if let state = upload.attributes?.state?.state,
           !Self.buildUploadStateValues.contains(state) {
            throw ASCError.parsing("Apple returned an unsupported build upload state in \(context)")
        }
        if let selfURL = upload.links?.`self` {
            try validateDocumentSelf(
                selfURL,
                expectedPath: "/v1/buildUploads/\(try ASCPathSegment.encode(upload.id))",
                context: "\(context) resource links"
            )
        }
        try validateRelationship(
            upload.relationships?.build?.data,
            expectedType: "builds",
            context: "\(context) build relationship"
        )
        try validateRelationship(
            upload.relationships?.assetFile?.data,
            expectedType: "buildUploadFiles",
            context: "\(context) assetFile relationship"
        )
        try validateRelationship(
            upload.relationships?.assetDescriptionFile?.data,
            expectedType: "buildUploadFiles",
            context: "\(context) assetDescriptionFile relationship"
        )
        try validateRelationship(
            upload.relationships?.assetSpiFile?.data,
            expectedType: "buildUploadFiles",
            context: "\(context) assetSpiFile relationship"
        )
    }

    private func validateBuildUploadFiles(
        _ files: [ASCBuildUploadFile],
        context: String
    ) throws {
        var identities = Set<String>()
        for file in files {
            try validateBuildUploadFile(
                file,
                expectedID: nil,
                fingerprint: nil,
                context: context
            )
            guard identities.insert(file.id).inserted else {
                throw ASCError.parsing(
                    "Apple returned duplicate build upload file identity '\(file.id)' in \(context)"
                )
            }
        }
    }

    private func validateBuildUploadFile(
        _ file: ASCBuildUploadFile,
        expectedID: String?,
        fingerprint: BuildUploadFileFingerprint?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: file.type,
            id: file.id,
            expectedType: "buildUploadFiles",
            expectedID: expectedID,
            context: context
        )
        if let fingerprint, !matches(file, fingerprint: fingerprint) {
            throw ASCError.parsing(
                "Apple returned a build upload file outside the exact requested parent/file fingerprint"
            )
        }
        if let assetType = file.attributes?.assetType,
           !Self.assetTypeValues.contains(assetType) {
            throw ASCError.parsing("Apple returned an unsupported build upload file assetType in \(context)")
        }
        if let fileSize = file.attributes?.fileSize,
           !(1...Self.maximumFileSize).contains(fileSize) {
            throw ASCError.parsing("Apple returned an invalid build upload file size in \(context)")
        }
        if let uti = file.attributes?.uti,
           !Self.utiValues.contains(uti) {
            throw ASCError.parsing("Apple returned an unsupported build upload file UTI in \(context)")
        }
        if let state = file.attributes?.assetDeliveryState?.state,
           !Self.buildUploadFileStateValues.contains(state) {
            throw ASCError.parsing("Apple returned an unsupported build upload file state in \(context)")
        }
        if let selfURL = file.links?.`self` {
            try validateDocumentSelf(
                selfURL,
                expectedPath: "/v1/buildUploadFiles/\(try ASCPathSegment.encode(file.id))",
                context: "\(context) resource links"
            )
        }
    }

    private func validateRelationship(
        _ identifier: ASCResourceIdentifier?,
        expectedType: String,
        context: String
    ) throws {
        guard let identifier else { return }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            context: context
        )
    }

    private func validateIncludedResources(
        _ resources: [JSONValue]?,
        context: String
    ) throws {
        var identities = Set<String>()
        for resource in resources ?? [] {
            guard case .object(let object) = resource,
                  case .string(let type)? = object["type"],
                  case .string(let id)? = object["id"],
                  Self.buildUploadIncludedTypes.contains(type) else {
                throw ASCError.parsing("Apple returned an unsupported included resource in \(context)")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: type,
                id: id,
                expectedType: type,
                context: "\(context) included resources"
            )
            guard identities.insert("\(type):\(id)").inserted else {
                throw ASCError.parsing(
                    "Apple returned duplicate included resource '\(type):\(id)' in \(context)"
                )
            }
        }
    }

    private func validatePaging(
        _ meta: ASCPagingInformation?,
        pageCount: Int,
        nextURL: String?,
        context: String
    ) throws {
        guard let meta else {
            if let nextURL,
               nextURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ASCError.parsing("Apple returned an empty continuation URL in \(context)")
            }
            return
        }
        guard let paging = meta.paging, let limit = paging.limit else {
            throw ASCError.parsing("Apple returned incomplete paging metadata in \(context)")
        }
        guard limit > 0, limit >= pageCount else {
            throw ASCError.parsing("Apple returned invalid paging limit in \(context)")
        }
        if let total = paging.total, total < pageCount {
            throw ASCError.parsing("Apple returned paging total below the page count in \(context)")
        }
        if let cursor = paging.nextCursor {
            guard !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  nextURL != nil else {
                throw ASCError.parsing("Apple returned inconsistent paging cursor state in \(context)")
            }
        }
        if let nextURL,
           nextURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ASCError.parsing("Apple returned an empty continuation URL in \(context)")
        }
    }

    private func validateDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String
    ) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              components.fragment == nil,
              components.user == nil,
              components.password == nil else {
            throw ASCError.parsing("Apple returned an invalid required links.self in \(context)")
        }
        if components.scheme != nil || components.host != nil {
            guard components.scheme == "https",
                  let host = components.host,
                  !host.isEmpty else {
                throw ASCError.parsing("Apple returned a non-HTTPS required links.self in \(context)")
            }
        }
        guard components.percentEncodedPath == expectedPath else {
            throw ASCError.parsing("Apple returned required links.self outside \(context)")
        }
        _ = try validatedASCAPIEndpoint(components.percentEncodedPath)
    }
}

extension BuildUploadsWorker {
    private func formatUploadOperation(_ operation: ASCUploadOperation) -> [String: Any] {
        [
            "method": operation.method.jsonSafe,
            "url": operation.url.jsonSafe,
            "length": operation.length.jsonSafe,
            "offset": operation.offset.jsonSafe,
            "requestHeaders": (operation.requestHeaders ?? []).map {
                ["name": $0.name.jsonSafe, "value": $0.value.jsonSafe]
            },
            "expiration": operation.expiration.jsonSafe,
            "partNumber": operation.partNumber.jsonSafe,
            "entityTag": operation.entityTag.jsonSafe
        ]
    }

    private func formatIncluded(_ value: JSONValue, includeSensitive: Bool) -> Any {
        includeSensitive ? value.asAny : redactBuildUploadSecrets(value).asAny
    }

    private func redactBuildUploadSecrets(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var redacted: [String: JSONValue] = [:]
            for (key, child) in object where key != "assetToken" && key != "uploadOperations" {
                redacted[key] = redactBuildUploadSecrets(child)
            }
            return .object(redacted)
        case .array(let values):
            return .array(values.map(redactBuildUploadSecrets))
        default:
            return value
        }
    }

    private func formatChecksums(_ checksums: ASCBuildUploadChecksums) -> [String: Any] {
        [
            "file": formatChecksum(checksums.file),
            "composite": formatChecksum(checksums.composite)
        ]
    }

    private func formatChecksum(_ checksum: ASCBuildUploadChecksums.Checksum?) -> Any {
        guard let checksum else { return NSNull() }
        return [
            "hash": checksum.hash.jsonSafe,
            "algorithm": checksum.algorithm.jsonSafe
        ]
    }

    private func formatStateDetails(
        _ details: [ASCBuildUploadStateDetail]?
    ) -> [[String: Any]] {
        (details ?? []).map {
            ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe]
        }
    }

    private func formatAssetErrors(
        _ errors: [ASCAssetDeliveryError]?
    ) -> [[String: Any]] {
        (errors ?? []).map {
            ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe]
        }
    }

    private func commitAttributes(
        _ arguments: [String: Value]
    ) throws -> [String: JSONValue] {
        var attributes: [String: JSONValue] = [:]
        if let checksums = arguments["source_file_checksums"] {
            attributes["sourceFileChecksums"] = try checksumValue(checksums)
        }
        if let uploaded = arguments["uploaded"] {
            if uploaded.isNull {
                attributes["uploaded"] = .null
            } else if let bool = uploaded.boolValue {
                attributes["uploaded"] = .bool(bool)
            } else {
                throw BuildUploadArgumentError("'uploaded' must be a boolean or null")
            }
        }
        return attributes
    }

    private func checksumValue(_ value: Value) throws -> JSONValue {
        if value.isNull { return .null }
        guard let object = value.objectValue else {
            throw BuildUploadArgumentError("'source_file_checksums' must be an object or null")
        }
        let allowedRoot: Set<String> = ["file", "composite"]
        if let unknown = object.keys.sorted().first(where: { !allowedRoot.contains($0) }) {
            throw BuildUploadArgumentError(
                "source_file_checksums contains unsupported field '\(unknown)'"
            )
        }
        var result: [String: JSONValue] = [:]
        if let file = object["file"] {
            result["file"] = try checksumObject(
                file,
                field: "file",
                algorithms: ["MD5", "SHA_256"]
            )
        }
        if let composite = object["composite"] {
            result["composite"] = try checksumObject(
                composite,
                field: "composite",
                algorithms: ["MD5"]
            )
        }
        return .object(result)
    }

    private func checksumObject(
        _ value: Value,
        field: String,
        algorithms: Set<String>
    ) throws -> JSONValue {
        guard let object = value.objectValue else {
            throw BuildUploadArgumentError(
                "source_file_checksums.\(field) must be an object"
            )
        }
        let allowed: Set<String> = ["hash", "algorithm"]
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw BuildUploadArgumentError(
                "source_file_checksums.\(field) contains unsupported field '\(unknown)'"
            )
        }
        var result: [String: JSONValue] = [:]
        if let hashValue = object["hash"] {
            result["hash"] = .string(try requiredString(
                hashValue,
                field: "source_file_checksums.\(field).hash"
            ))
        }
        if let algorithmValue = object["algorithm"] {
            let algorithm = try requiredString(
                algorithmValue,
                field: "source_file_checksums.\(field).algorithm"
            )
            guard algorithms.contains(algorithm) else {
                throw BuildUploadArgumentError(
                    "source_file_checksums.\(field).algorithm has an unsupported value"
                )
            }
            result["algorithm"] = .string(algorithm)
        }
        return .object(result)
    }

    private func applyStringList(
        _ value: Value?,
        field: String,
        appleName: String,
        allowedValues: Set<String>? = nil,
        to query: inout [String: String]
    ) throws {
        if let values = try stringList(
            value,
            field: field,
            allowedValues: allowedValues
        ) {
            query[appleName] = values.joined(separator: ",")
        }
    }

    private func stringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value else { return nil }
        guard let array = value.arrayValue else {
            throw BuildUploadArgumentError("'\(field)' must be an array of strings")
        }
        let values = array.compactMap(\.stringValue)
        guard values.count == array.count,
              !values.isEmpty,
              values.allSatisfy({
                      !$0.isEmpty &&
                      $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) &&
                      !$0.contains(",") &&
                      !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }),
              Set(values).count == values.count else {
            throw BuildUploadArgumentError(
                "'\(field)' must contain unique non-empty strings without commas"
            )
        }
        if let allowedValues,
           let unsupported = values.first(where: { !allowedValues.contains($0) }) {
            throw BuildUploadArgumentError(
                "'\(field)' contains unsupported value '\(unsupported)'"
            )
        }
        return values
    }

    private func validateSensitiveFieldSelection(
        _ value: Value?,
        includeSensitive: Bool
    ) throws {
        guard !includeSensitive,
              let fields = try stringList(
                  value,
                  field: "fields_build_upload_files",
                  allowedValues: Set(Self.buildUploadFileFieldValues)
              ),
              fields.contains(where: { Self.sensitiveBuildUploadFileFieldValues.contains($0) }) else {
            return
        }
        throw BuildUploadArgumentError(
            "Set include_sensitive_details to true before requesting assetToken or uploadOperations"
        )
    }

    private func requiredString(
        _ value: Value?,
        field: String
    ) throws -> String {
        guard let string = nonemptyString(value) else {
            throw BuildUploadArgumentError("Required parameter '\(field)' is missing or invalid")
        }
        return string
    }

    private func boolean(
        _ value: Value?,
        field: String,
        defaultValue: Bool
    ) throws -> Bool {
        guard let value else { return defaultValue }
        guard let boolean = value.boolValue else {
            throw BuildUploadArgumentError("'\(field)' must be a boolean")
        }
        return boolean
    }

    private func sensitivePaths(
        roots: [[String]]
    ) -> Set<MCPSensitiveValuePath> {
        var paths = Set<MCPSensitiveValuePath>()
        for root in roots {
            paths.insert(makeSensitivePath(root + ["assetToken"]))
            paths.insert(makeSensitivePath(root + ["uploadOperations"]))
            paths.insert(makeSensitivePath(root + ["attributes", "assetToken"]))
            paths.insert(makeSensitivePath(root + ["attributes", "uploadOperations"]))
        }
        return paths
    }

    private func makeSensitivePath(_ components: [String]) -> MCPSensitiveValuePath {
        switch components.count {
        case 2:
            MCPSensitiveValuePath(components[0], components[1])
        case 3:
            MCPSensitiveValuePath(components[0], components[1], components[2])
        case 4:
            MCPSensitiveValuePath(components[0], components[1], components[2], components[3])
        default:
            preconditionFailure("Unsupported build upload sensitive path")
        }
    }
}

struct BuildUploadArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private extension Value {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension BuildUploadsWorker {
    func createBuildUploadParent(
        _ fingerprint: BuildUploadFingerprint
    ) async -> BuildUploadParentCreationOutcome {
        if Task.isCancelled {
            return .beforeRequest("Build upload creation was cancelled before the request.")
        }

        let beforeIDs: Set<String>
        do {
            beforeIDs = Set(try await matchingBuildUploads(fingerprint).map(\.id))
        } catch {
            return .beforeRequest(
                "Build upload preflight failed before any create request: \(Redactor.redact(error.localizedDescription))"
            )
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(ASCBuildUploadCreateRequest(
                appID: fingerprint.appID,
                shortVersion: fingerprint.shortVersion,
                buildVersion: fingerprint.buildVersion,
                platform: fingerprint.platform
            ))
        } catch {
            return .beforeRequest(
                "Failed to encode the build upload request: \(Redactor.redact(error.localizedDescription))"
            )
        }

        if Task.isCancelled {
            return .beforeRequest("Build upload creation was cancelled before the request.")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/buildUploads", body: body)
        } catch {
            let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            )
            if disposition == .rejected {
                return .rejected(
                    "Apple rejected the build upload create request: \(Redactor.redact(error.localizedDescription))"
                )
            }
            return await reconcileBuildUploadCreation(
                fingerprint,
                excluding: beforeIDs,
                context: "The build upload create request did not return a confirmed response: \(Redactor.redact(error.localizedDescription))",
                commitState: disposition
            )
        }

        let response: ASCBuildUploadResponse
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Build upload creation"
            )
            response = try JSONDecoder().decode(ASCBuildUploadResponse.self, from: receipt.data)
            let endpoint = "/v1/buildUploads/\(try ASCPathSegment.encode(response.data.id))"
            try validateBuildUploadDocument(
                response,
                expectedID: nil,
                expectedPath: endpoint,
                fingerprint: fingerprint,
                context: "build upload create"
            )
        } catch {
            return await reconcileBuildUploadCreation(
                fingerprint,
                excluding: beforeIDs,
                context: "Apple accepted the build upload create request, but its response was not contract-valid: \(Redactor.redact(error.localizedDescription))",
                commitState: .committedUnverified
            )
        }

        let scopedCandidates: [ASCBuildUpload]
        do {
            scopedCandidates = try await matchingBuildUploads(fingerprint)
        } catch {
            return .unresolved(
                "Apple returned a contract-valid build upload create response, but app-membership verification failed: \(Redactor.redact(error.localizedDescription))",
                candidateIDs: [],
                commitState: .committedUnverified
            )
        }
        let newCandidateIDs = scopedCandidates
            .filter { !beforeIDs.contains($0.id) }
            .map(\.id)
            .sorted()
        guard !beforeIDs.contains(response.data.id),
              let confirmed = scopedCandidates.first(where: { $0.id == response.data.id }) else {
            return .unresolved(
                "Apple returned a build upload create identity whose new membership in the requested app could not be confirmed.",
                candidateIDs: newCandidateIDs,
                commitState: .committedUnverified
            )
        }
        return .created(confirmed)
    }

    func reserveBuildUploadFileResource(
        _ fingerprint: BuildUploadFileFingerprint
    ) async -> BuildUploadFileReservationOutcome {
        if Task.isCancelled {
            return .beforeRequest("Build upload file reservation was cancelled before the request.")
        }

        let beforeIDs: Set<String>
        do {
            beforeIDs = Set(try await allBuildUploadFiles(fingerprint.buildUploadID).map(\.id))
        } catch {
            return .beforeRequest(
                "Build upload file preflight failed before any reservation request: \(Redactor.redact(error.localizedDescription))"
            )
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(ASCBuildUploadFileCreateRequest(
                buildUploadID: fingerprint.buildUploadID,
                assetType: fingerprint.assetType,
                fileName: fingerprint.fileName,
                fileSize: fingerprint.fileSize,
                uti: fingerprint.uti
            ))
        } catch {
            return .beforeRequest(
                "Failed to encode the build upload file reservation: \(Redactor.redact(error.localizedDescription))"
            )
        }

        if Task.isCancelled {
            return .beforeRequest("Build upload file reservation was cancelled before the request.")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/buildUploadFiles", body: body)
        } catch {
            let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            )
            if disposition == .rejected {
                return .rejected(
                    "Apple rejected the build upload file reservation: \(Redactor.redact(error.localizedDescription))"
                )
            }
            return await reconcileBuildUploadFileReservation(
                fingerprint,
                excluding: beforeIDs,
                context: "The build upload file reservation did not return a confirmed response: \(Redactor.redact(error.localizedDescription))",
                commitState: disposition
            )
        }

        let response: ASCBuildUploadFileResponse
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Build upload file reservation"
            )
            response = try JSONDecoder().decode(ASCBuildUploadFileResponse.self, from: receipt.data)
            let endpoint = "/v1/buildUploadFiles/\(try ASCPathSegment.encode(response.data.id))"
            try validateBuildUploadFileDocument(
                response,
                expectedID: nil,
                expectedPath: endpoint,
                fingerprint: fingerprint,
                context: "build upload file reservation"
            )
        } catch {
            return await reconcileBuildUploadFileReservation(
                fingerprint,
                excluding: beforeIDs,
                context: "Apple accepted the build upload file reservation, but its response was not contract-valid: \(Redactor.redact(error.localizedDescription))",
                commitState: .committedUnverified
            )
        }

        let scopedFiles: [ASCBuildUploadFile]
        do {
            scopedFiles = try await allBuildUploadFiles(fingerprint.buildUploadID)
        } catch {
            return .unresolved(
                "Apple returned a contract-valid file reservation response, but parent-membership verification failed: \(Redactor.redact(error.localizedDescription))",
                candidateIDs: [],
                commitState: .committedUnverified
            )
        }
        let matchingFiles = scopedFiles.filter { matches($0, fingerprint: fingerprint) }
        let newCandidateIDs = matchingFiles
            .filter { !beforeIDs.contains($0.id) }
            .map(\.id)
            .sorted()
        guard !beforeIDs.contains(response.data.id),
              let confirmed = matchingFiles.first(where: { $0.id == response.data.id }) else {
            return .unresolved(
                "Apple returned a build upload file identity whose new membership in the requested parent could not be confirmed.",
                candidateIDs: newCandidateIDs,
                commitState: .committedUnverified
            )
        }
        return .created(confirmed)
    }

    func commitBuildUploadFileResource(
        fileID: String,
        attributes: [String: JSONValue]
    ) async -> BuildUploadFileCommitOutcome {
        if Task.isCancelled {
            return .beforeRequest("Build upload file commit was cancelled before the request.")
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(ASCBuildUploadFileUpdateRequest(
                fileID: fileID,
                attributes: attributes
            ))
        } catch {
            return .beforeRequest(
                "Failed to encode the build upload file commit: \(Redactor.redact(error.localizedDescription))"
            )
        }

        let endpoint: String
        do {
            endpoint = "/v1/buildUploadFiles/\(try ASCPathSegment.encode(fileID, field: "file_id"))"
        } catch {
            return .beforeRequest(Redactor.redact(error.localizedDescription))
        }
        if Task.isCancelled {
            return .beforeRequest("Build upload file commit was cancelled before the request.")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: body)
        } catch {
            let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(
                for: error,
                phase: .request
            )
            if disposition == .rejected {
                return .rejected(
                    "Apple rejected the build upload file commit: \(Redactor.redact(error.localizedDescription))"
                )
            }
            return await reconcileBuildUploadFileCommit(
                fileID: fileID,
                context: "The build upload file commit did not return a confirmed response: \(Redactor.redact(error.localizedDescription))",
                commitState: disposition
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Build upload file commit"
            )
            let response = try JSONDecoder().decode(ASCBuildUploadFileResponse.self, from: receipt.data)
            try validateBuildUploadFileDocument(
                response,
                expectedID: fileID,
                expectedPath: endpoint,
                fingerprint: nil,
                context: "build upload file commit"
            )
            if response.data.attributes?.assetDeliveryState?.state == "FAILED" {
                return .terminalFailure(
                    "Apple reported FAILED for the committed build upload file.",
                    response.data
                )
            }
            return .committed(response.data, reconciled: false)
        } catch {
            return await reconcileBuildUploadFileCommit(
                fileID: fileID,
                context: "Apple accepted the build upload file commit, but its response was not contract-valid: \(Redactor.redact(error.localizedDescription))",
                commitState: .committedUnverified
            )
        }
    }

    func buildUploadCreationResult(
        _ outcome: BuildUploadParentCreationOutcome,
        fingerprint: BuildUploadFingerprint
    ) -> CallTool.Result {
        switch outcome {
        case .beforeRequest(let message):
            return MCPResult.jsonObject(
                [
                    "success": false,
                    "error": message,
                    "requestAttempted": false,
                    "operationCommitState": "not_attempted",
                    "retrySafe": true
                ],
                text: "Error: \(message)",
                isError: true
            )
        case .rejected(let message):
            return rejectedWriteResult(message)
        case .created(let upload):
            return MCPResult.jsonObject([
                "success": true,
                "buildUpload": formatBuildUpload(upload),
                "createdByInvocation": true,
                "reconciledAfterCreate": false,
                "operationCommitState": "committed"
            ])
        case .recovered(let upload, let commitState):
            let message = "A unique build upload candidate was observed after an ambiguous create, but this invocation cannot attribute it safely."
            var payload: [String: Any] = [
                "success": false,
                "error": message,
                "workflowState": "candidate_inspection_required",
                "buildUpload": formatBuildUpload(upload),
                "candidateId": upload.id,
                "candidateAttributionConfirmed": false,
                "createdByInvocation": false,
                "reconciledAfterCreate": true,
                "automaticDeletionAllowed": false,
                "operationCommitState": commitState.rawValue,
                "write_outcome": commitState.rawValue,
                "inspectionRequired": true,
                "inspection": [
                    "tool": "build_uploads_get",
                    "arguments": ["build_upload_id": upload.id]
                ],
                "retrySafe": false
            ]
            appendAmbiguousWriteState(commitState, to: &payload)
            return MCPResult.jsonObject(
                payload,
                text: "Error: \(message) Inspect build upload '\(upload.id)' before any continuation.",
                isError: true
            )
        case .unresolved(let message, let candidateIDs, let commitState):
            return unresolvedWriteResult(
                message: message,
                commitState: commitState,
                candidateIDs: candidateIDs,
                inspection: [
                    "tool": "build_uploads_list",
                    "arguments": buildUploadInspectionArguments(fingerprint)
                ]
            )
        }
    }

    func buildUploadFileReservationResult(
        _ outcome: BuildUploadFileReservationOutcome,
        buildUploadID: String,
        includeSensitive: Bool
    ) -> CallTool.Result {
        switch outcome {
        case .beforeRequest(let message):
            return MCPResult.jsonObject(
                [
                    "success": false,
                    "error": message,
                    "requestAttempted": false,
                    "operationCommitState": "not_attempted",
                    "retrySafe": true
                ],
                text: "Error: \(message)",
                isError: true
            )
        case .rejected(let message):
            return rejectedWriteResult(message)
        case .created(let file):
            return MCPResult.jsonObject(
                [
                    "success": true,
                    "buildUploadFile": formatBuildUploadFile(file, includeSensitive: includeSensitive),
                    "createdByInvocation": true,
                    "reconciledAfterCreate": false,
                    "operationCommitState": "committed"
                ],
                explicitlySensitivePaths: sensitivePaths(roots: [["buildUploadFile"]]),
                explicitlyAllowedSensitivePaths: includeSensitive
                    ? sensitivePaths(roots: [["buildUploadFile"]])
                    : []
            )
        case .recovered(let file, let commitState):
            let message = "A unique BuildUploadFile candidate was observed after an ambiguous reservation, but this invocation cannot attribute it safely."
            var payload: [String: Any] = [
                "success": false,
                "error": message,
                "workflowState": "candidate_inspection_required",
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "candidateId": file.id,
                "candidateAttributionConfirmed": false,
                "createdByInvocation": false,
                "reconciledAfterCreate": true,
                "automaticDeletionAllowed": false,
                "operationCommitState": commitState.rawValue,
                "write_outcome": commitState.rawValue,
                "inspectionRequired": true,
                "inspection": [
                    "tool": "build_uploads_get_file",
                    "arguments": ["file_id": file.id]
                ],
                "retrySafe": false
            ]
            appendAmbiguousWriteState(commitState, to: &payload)
            return MCPResult.jsonObject(
                payload,
                text: "Error: \(message) Inspect build upload file '\(file.id)' before any continuation.",
                isError: true
            )
        case .unresolved(let message, let candidateIDs, let commitState):
            return unresolvedWriteResult(
                message: message,
                commitState: commitState,
                candidateIDs: candidateIDs,
                inspection: [
                    "tool": "build_uploads_list_files",
                    "arguments": ["build_upload_id": buildUploadID, "limit": 200]
                ]
            )
        }
    }

    func buildUploadFileCommitResult(
        _ outcome: BuildUploadFileCommitOutcome
    ) -> CallTool.Result {
        switch outcome {
        case .beforeRequest(let message):
            return preRequestWriteResult(message)
        case .rejected(let message):
            return rejectedWriteResult(message)
        case .committed(let file, let reconciled):
            return MCPResult.jsonObject([
                "success": true,
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "commitConfirmed": true,
                "reconciledAfterCommit": reconciled,
                "operationCommitState": "committed"
            ])
        case .terminalFailure(let message, let file):
            return MCPResult.jsonObject(
                [
                    "success": false,
                    "error": message,
                    "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                    "fileId": file.id,
                    "operationCommitState": "committed",
                    "retrySafe": false,
                    "automaticDeletionAttempted": false,
                    "inspection": [
                        "tool": "build_uploads_get_file",
                        "arguments": ["file_id": file.id]
                    ]
                ],
                text: "Error: \(message) The file was retained for inspection.",
                isError: true
            )
        case .unresolved(let message, let fileID, let file, let commitState):
            var payload: [String: Any] = [
                "success": false,
                "error": message,
                "commitState": commitState.rawValue,
                "operationCommitState": commitState.rawValue,
                "fileId": fileID,
                "retrySafe": false,
                "automaticDeletionAttempted": false,
                "inspectionRequired": true,
                "inspection": [
                    "tool": "build_uploads_get_file",
                    "arguments": ["file_id": fileID]
                ]
            ]
            if commitState == .outcomeUnknown {
                payload["outcomeUnknown"] = true
            } else if commitState == .committedUnverified {
                payload["operationCommitted"] = true
            }
            if let file {
                payload["buildUploadFile"] = formatBuildUploadFile(file, includeSensitive: false)
            }
            return MCPResult.jsonObject(
                payload,
                text: "Error: \(message) Inspect the existing file before any retry or parent deletion.",
                isError: true
            )
        }
    }

    func appendAmbiguousWriteState(
        _ commitState: ASCNonIdempotentWriteFailureDisposition,
        to payload: inout [String: Any]
    ) {
        if commitState == .outcomeUnknown {
            payload["outcomeUnknown"] = true
        } else if commitState == .committedUnverified {
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
        }
    }
}
