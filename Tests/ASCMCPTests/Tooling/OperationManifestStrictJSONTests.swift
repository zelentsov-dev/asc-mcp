import Foundation
import Testing
@testable import asc_mcp

@Suite("Operation Manifest Strict JSON Tests")
struct OperationManifestStrictJSONTests {
    @Test("index rejects an unknown nested key with its JSON path")
    func indexRejectsUnknownNestedKey() {
        let data = Data(
            #"{"schemaVersion":1,"specPin":{"version":"4.4","sha265":"bad","pathCount":1,"operationCount":1},"scopeRules":[],"waivers":[]}"#.utf8
        )

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "manifest.json",
            path: "$.specPin",
            key: "sha265"
        )) {
            try ASCOperationManifestJSONValidator.validateIndex(data, source: "manifest.json")
        }
    }

    @Test("worker rejects an unknown deeply nested field key")
    func workerRejectsUnknownDeeplyNestedKey() {
        let data = Data(
            #"{"workerKey":"apps","tools":[{"tool":"apps_list","kind":"direct","status":"partial","effect":"read","implementationState":"asBuilt","operations":[],"fields":[{"toolField":"limit","sourceKind":"parameter","operationId":"apps_getCollection","location":"query","applName":"limit"}],"response":{"mode":"direct","sources":[],"fields":[]}}],"implementationAliases":[]}"#.utf8
        )

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$.tools[0].fields[0]",
            key: "applName"
        )) {
            try ASCOperationManifestJSONValidator.validateWorker(data, source: "tools/apps.json")
        }
    }

    @Test("operation input rejects an unknown key")
    func operationInputRejectsUnknownKey() {
        let data = Data(
            #"{"workerKey":"apps","tools":[{"tool":"apps_list","kind":"direct","status":"partial","effect":"read","implementationState":"asBuilt","operations":[{"operationId":"apps_getCollection","method":"GET","path":"/v1/apps","role":"primary","inputs":[{"sourceKind":"parameter","location":"query","appleNames":"limit"}]}],"fields":[],"response":{"mode":"direct","sources":[],"fields":[]}}],"implementationAliases":[]}"#.utf8
        )

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$.tools[0].operations[0].inputs[0]",
            key: "appleNames"
        )) {
            try ASCOperationManifestJSONValidator.validateWorker(data, source: "tools/apps.json")
        }
    }

    @Test("optional parameter policy objects reject unknown keys")
    func optionalParameterPolicyRejectsUnknownKeys() {
        let indexData = Data(
            #"{"schemaVersion":2,"specPin":{"version":"4.4","sha256":"bad","pathCount":1,"operationCount":1},"optionalParameterFamilyRules":[{"family":"sparseFields","disposition":"intentionallyOmitted","reasons":"typo","owner":"tests","reviewAtSpec":"4.4"}],"scopeRules":[],"waivers":[]}"#.utf8
        )
        let workerData = Data(
            #"{"workerKey":"apps","tools":[{"tool":"apps_list","kind":"direct","status":"partial","effect":"read","implementationState":"asBuilt","operations":[{"operationId":"apps_getCollection","method":"GET","path":"/v1/apps","role":"primary","optionalParameterClassifications":[{"location":"query","appleNames":"filter[name]","disposition":"intentionallyOmitted","reason":"fixture","reviewAtSpec":"4.4"}]}],"fields":[],"response":{"mode":"direct","sources":[],"fields":[]}}],"implementationAliases":[]}"#.utf8
        )

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "manifest.json",
            path: "$.optionalParameterFamilyRules[0]",
            key: "reasons"
        )) {
            try ASCOperationManifestJSONValidator.validateIndex(indexData, source: "manifest.json")
        }
        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$.tools[0].operations[0].optionalParameterClassifications[0]",
            key: "appleNames"
        )) {
            try ASCOperationManifestJSONValidator.validateWorker(workerData, source: "tools/apps.json")
        }
    }

    @Test("response and alias objects reject unknown keys")
    func responseAndAliasObjectsRejectUnknownKeys() {
        let responseData = Data(
            #"{"workerKey":"apps","tools":[{"tool":"apps_list","kind":"direct","status":"partial","effect":"read","implementationState":"asBuilt","operations":[],"fields":[],"response":{"mode":"direct","sources":[{"operationId":"apps_getCollection","statusCodes":"200"}],"fields":[]}}],"implementationAliases":[]}"#.utf8
        )
        let aliasData = Data(
            #"{"workerKey":"apps","tools":[],"implementationAliases":[{"publicTool":"apps_list","internalTools":"apps_list_impl"}]}"#.utf8
        )

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$.tools[0].response.sources[0]",
            key: "statusCodes"
        )) {
            try ASCOperationManifestJSONValidator.validateWorker(
                responseData,
                source: "tools/apps.json"
            )
        }
        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$.implementationAliases[0]",
            key: "internalTools"
        )) {
            try ASCOperationManifestJSONValidator.validateWorker(
                aliasData,
                source: "tools/apps.json"
            )
        }
    }

    @Test("fixedValue accepts arbitrary nested JSON keys")
    func fixedValueAcceptsArbitraryNestedJSONKeys() throws {
        let data = Data(
            #"{"workerKey":"apps","tools":[{"tool":"apps_list","kind":"direct","status":"partial","effect":"read","implementationState":"asBuilt","operations":[{"operationId":"apps_getCollection","method":"GET","path":"/v1/apps","role":"primary","inputs":[{"sourceKind":"fixed","jsonPointer":"/data/attributes/value","fixedValue":{"arbitrary":{"keys":[{"remainUnchecked":true}]}}}]}],"fields":[],"response":{"mode":"direct","sources":[],"fields":[]}}],"implementationAliases":[]}"#.utf8
        )

        try ASCOperationManifestJSONValidator.validateWorker(
            data,
            source: "tools/apps.json"
        )
    }

    @Test("bundle loader rejects an unknown worker key before decoding")
    func bundleLoaderRejectsUnknownWorkerKey() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-operation-manifest-\(UUID().uuidString)", isDirectory: true)
        let toolsURL = directoryURL.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: toolsURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let indexData = Data(
            #"{"schemaVersion":1,"specPin":{"version":"test","sha256":"0","pathCount":0,"operationCount":0},"scopeRules":[],"waivers":[]}"#.utf8
        )
        let workerData = Data(
            #"{"workerKey":"apps","workerKye":"apps","tools":[],"implementationAliases":[]}"#.utf8
        )
        try indexData.write(to: directoryURL.appendingPathComponent("manifest.json"))
        try workerData.write(to: toolsURL.appendingPathComponent("apps.json"))

        #expect(throws: ASCOperationManifestError.unknownKey(
            source: "tools/apps.json",
            path: "$",
            key: "workerKye"
        )) {
            try ASCOperationManifestBundle.load(from: directoryURL)
        }
    }

    @Test("valid fixture passes strict validation through the bundle loader")
    func validFixturePassesStrictValidation() throws {
        let directoryURL = try #require(Bundle.module.url(
            forResource: "operation_manifest_valid",
            withExtension: nil,
            subdirectory: "Fixtures"
        ))

        _ = try ASCOperationManifestBundle.load(from: directoryURL)
    }
}
