import Foundation
import Testing
@testable import asc_mcp

@Suite("Build Upload Model Contract Tests")
struct BuildUploadModelContractTests {
    @Test("build upload documents decode Apple 4.4.1 fields")
    func decodesBuildUploadDocuments() throws {
        let singular = try JSONDecoder().decode(
            ASCBuildUploadResponse.self,
            from: Data(buildUploadResponseBody.utf8)
        )
        let list = try JSONDecoder().decode(
            ASCBuildUploadsResponse.self,
            from: Data(buildUploadsResponseBody.utf8)
        )

        #expect(singular.links.`self` == "https://api.example.test/v1/buildUploads/upload-1")
        #expect(singular.data.type == "buildUploads")
        #expect(singular.data.id == "upload-1")
        #expect(singular.data.attributes?.cfBundleShortVersionString == "2.0")
        #expect(singular.data.attributes?.cfBundleVersion == "42")
        #expect(singular.data.attributes?.state?.state == "COMPLETE")
        #expect(singular.data.attributes?.state?.warnings?.first?.code == "WARN-1")
        #expect(singular.data.relationships?.build?.data?.type == "builds")
        #expect(singular.data.relationships?.build?.data?.id == "build-1")
        #expect(singular.data.relationships?.assetFile?.data?.type == "buildUploadFiles")
        #expect(singular.data.relationships?.assetFile?.data?.id == "file-1")
        #expect(singular.data.relationships?.buildUploadFiles?.links?.related == "https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles")
        #expect(list.data.map(\.id) == ["upload-1"])
        #expect(list.links.`self` == "https://api.example.test/v1/apps/app-1/buildUploads")
        #expect(list.meta?.paging?.total == 1)
    }

    @Test("build upload file documents decode upload metadata and checksums")
    func decodesBuildUploadFileDocuments() throws {
        let singular = try JSONDecoder().decode(
            ASCBuildUploadFileResponse.self,
            from: Data(buildUploadFileResponseBody.utf8)
        )
        let list = try JSONDecoder().decode(
            ASCBuildUploadFilesResponse.self,
            from: Data(buildUploadFilesResponseBody.utf8)
        )

        #expect(singular.links.`self` == "https://api.example.test/v1/buildUploadFiles/file-1")
        #expect(singular.data.type == "buildUploadFiles")
        #expect(singular.data.id == "file-1")
        #expect(singular.data.attributes?.assetType == "ASSET")
        #expect(singular.data.attributes?.fileSize == 1_024)
        #expect(singular.data.attributes?.sourceFileChecksums?.file?.hash == "file-md5")
        #expect(singular.data.attributes?.sourceFileChecksums?.file?.algorithm == "MD5")
        #expect(singular.data.attributes?.sourceFileChecksums?.composite?.algorithm == "MD5")
        #expect(singular.data.attributes?.assetDeliveryState?.state == "UPLOAD_COMPLETE")
        #expect(singular.data.attributes?.uploadOperations?.first?.method == "PUT")
        #expect(list.data.map(\.id) == ["file-1"])
        #expect(list.links.`self` == "https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles")
        #expect(list.meta?.paging?.limit == 25)
    }

    @Test("singular and list document links and links.self are required")
    func requiresDocumentLinksSelf() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadResponse.self,
                from: Data(#"{"data":{"type":"buildUploads","id":"upload-1"}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadResponse.self,
                from: Data(#"{"data":{"type":"buildUploads","id":"upload-1"},"links":{}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadsResponse.self,
                from: Data(#"{"data":[]}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadsResponse.self,
                from: Data(#"{"data":[],"links":{}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadFileResponse.self,
                from: Data(#"{"data":{"type":"buildUploadFiles","id":"file-1"}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadFileResponse.self,
                from: Data(#"{"data":{"type":"buildUploadFiles","id":"file-1"},"links":{}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadFilesResponse.self,
                from: Data(#"{"data":[]}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCBuildUploadFilesResponse.self,
                from: Data(#"{"data":[],"links":{}}"#.utf8)
            )
        }
    }

    @Test("create requests pin canonical resource types and relationship IDs")
    func createRequestsUseCanonicalTypesAndIDs() throws {
        let upload = ASCBuildUploadCreateRequest(
            appID: "app-1",
            shortVersion: "2.0",
            buildVersion: "42",
            platform: "IOS"
        )
        let file = ASCBuildUploadFileCreateRequest(
            buildUploadID: "upload-1",
            assetType: "ASSET",
            fileName: "App.ipa",
            fileSize: 1_024,
            uti: "com.apple.ipa"
        )

        let uploadData = try buildUploadModelObject(try buildUploadModelJSON(upload)["data"])
        let uploadAttributes = try buildUploadModelObject(uploadData["attributes"])
        let uploadRelationships = try buildUploadModelObject(uploadData["relationships"])
        let app = try buildUploadModelObject(
            try buildUploadModelObject(uploadRelationships["app"])["data"]
        )
        #expect(uploadData["type"] as? String == "buildUploads")
        #expect(uploadAttributes["cfBundleShortVersionString"] as? String == "2.0")
        #expect(uploadAttributes["cfBundleVersion"] as? String == "42")
        #expect(uploadAttributes["platform"] as? String == "IOS")
        #expect(app["type"] as? String == "apps")
        #expect(app["id"] as? String == "app-1")

        let fileData = try buildUploadModelObject(try buildUploadModelJSON(file)["data"])
        let fileRelationships = try buildUploadModelObject(fileData["relationships"])
        let parent = try buildUploadModelObject(
            try buildUploadModelObject(fileRelationships["buildUpload"])["data"]
        )
        #expect(fileData["type"] as? String == "buildUploadFiles")
        #expect(parent["type"] as? String == "buildUploads")
        #expect(parent["id"] as? String == "upload-1")
    }

    @Test("file update preserves omitted, value, and explicit null attributes")
    func fileUpdatePreservesNullableAttributes() throws {
        let omitted = ASCBuildUploadFileUpdateRequest(
            fileID: "file-1",
            attributes: nil
        )
        let values = ASCBuildUploadFileUpdateRequest(
            fileID: "file-1",
            attributes: [
                "sourceFileChecksums": .object([
                    "file": .object([
                        "hash": .string("file-md5"),
                        "algorithm": .string("MD5")
                    ])
                ]),
                "uploaded": .bool(true)
            ]
        )
        let nulls = ASCBuildUploadFileUpdateRequest(
            fileID: "file-1",
            attributes: [
                "sourceFileChecksums": .null,
                "uploaded": .null
            ]
        )

        let omittedData = try buildUploadModelObject(try buildUploadModelJSON(omitted)["data"])
        let valueData = try buildUploadModelObject(try buildUploadModelJSON(values)["data"])
        let nullData = try buildUploadModelObject(try buildUploadModelJSON(nulls)["data"])

        #expect(omittedData["type"] as? String == "buildUploadFiles")
        #expect(omittedData["id"] as? String == "file-1")
        #expect(omittedData["attributes"] == nil)
        let valueAttributes = try buildUploadModelObject(valueData["attributes"])
        #expect(valueAttributes["uploaded"] as? Bool == true)
        #expect(valueAttributes["sourceFileChecksums"] is [String: Any])
        let nullAttributes = try buildUploadModelObject(nullData["attributes"])
        #expect(nullAttributes["sourceFileChecksums"] is NSNull)
        #expect(nullAttributes["uploaded"] is NSNull)
    }

    @Test("build included resources support build uploads")
    func buildIncludedResourceRoundTripsBuildUpload() throws {
        let body = Data(
            #"{"type":"buildUploads","id":"upload-1","attributes":{"cfBundleVersion":"42"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}}}}"#.utf8
        )
        let included = try JSONDecoder().decode(ASCBuildIncludedResource.self, from: body)

        guard case .buildUpload(let upload) = included else {
            Issue.record("Expected buildUpload included resource")
            return
        }
        #expect(upload.id == "upload-1")
        #expect(upload.attributes?.cfBundleVersion == "42")
        #expect(upload.relationships?.build?.data?.id == "build-1")

        let roundTrip = try JSONDecoder().decode(
            ASCBuildIncludedResource.self,
            from: JSONEncoder().encode(included)
        )
        guard case .buildUpload(let decoded) = roundTrip else {
            Issue.record("Expected buildUpload after round trip")
            return
        }
        #expect(decoded.type == "buildUploads")
        #expect(decoded.id == "upload-1")
    }
}

private let buildUploadResponseBody = #"{"data":{"type":"buildUploads","id":"upload-1","attributes":{"cfBundleShortVersionString":"2.0","cfBundleVersion":"42","createdDate":"2026-07-21T00:00:00Z","state":{"state":"COMPLETE","warnings":[{"code":"WARN-1","description":"Warning"}]},"platform":"IOS","uploadedDate":"2026-07-21T00:01:00Z"},"relationships":{"build":{"data":{"type":"builds","id":"build-1"}},"assetFile":{"data":{"type":"buildUploadFiles","id":"file-1"}},"buildUploadFiles":{"links":{"related":"https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles"}}}},"included":[],"links":{"self":"https://api.example.test/v1/buildUploads/upload-1"}}"#

private let buildUploadsResponseBody = #"{"data":[{"type":"buildUploads","id":"upload-1"}],"included":[],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"},"meta":{"paging":{"total":1,"limit":25}}}"#

private let buildUploadFileResponseBody = #"{"data":{"type":"buildUploadFiles","id":"file-1","attributes":{"assetDeliveryState":{"state":"UPLOAD_COMPLETE","errors":[],"warnings":[]},"assetToken":"token","assetType":"ASSET","fileName":"App.ipa","fileSize":1024,"sourceFileChecksums":{"file":{"hash":"file-md5","algorithm":"MD5"},"composite":{"hash":"composite-md5","algorithm":"MD5"}},"uploadOperations":[{"method":"PUT","url":"https://uploads.example.test/part","length":1024,"offset":0,"requestHeaders":[]}],"uti":"com.apple.ipa"}},"links":{"self":"https://api.example.test/v1/buildUploadFiles/file-1"}}"#

private let buildUploadFilesResponseBody = #"{"data":[{"type":"buildUploadFiles","id":"file-1"}],"links":{"self":"https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles"},"meta":{"paging":{"total":1,"limit":25}}}"#

private func buildUploadModelJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func buildUploadModelObject(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}
