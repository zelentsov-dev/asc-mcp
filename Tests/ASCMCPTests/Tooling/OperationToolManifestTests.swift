import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Operation Tool Manifest Tests")
struct OperationToolManifestTests {
    @Test("manifest bundle loads worker fragments deterministically")
    func manifestBundleLoadsWorkerFragments() throws {
        let manifest = try loadValidManifest()

        #expect(manifest.index.schemaVersion == 1)
        #expect(manifest.index.specPin.version == "4.3-test")
        #expect(manifest.workers.map(\.workerKey) == ["apps", "local"])
        #expect(manifest.tools.map(\.tool) == ["apps_list", "apps_update", "local_status"])
        #expect(manifest.tools.allSatisfy { $0.implementationState == .asBuilt })
        #expect(manifest.mapping(for: "apps_list")?.operations.first?.operationID == "apps_getCollection")
        #expect(
            manifest.mapping(for: "apps_list")?.operations.first?.inputs?.first?.fixedValue == .string("IOS")
        )
        #expect(
            manifest.mapping(for: "apps_list")?.operations.first?.inputs?.last?.fixedValue == .boolean(true)
        )
        #expect(
            manifest.mapping(for: "apps_update")?.operations.first?.inputs?.first?.jsonPointer == "/data/type"
        )
        #expect(
            manifest.mapping(for: "apps_update")?.response.sources.last?.mediaType == nil
        )
    }

    @Test("typed fixed null remains distinct from a missing value")
    func typedFixedNullRemainsDistinctFromMissingValue() throws {
        let data = Data(
            #"{"sourceKind":"fixed","jsonPointer":"/data/attributes/value","fixedValue":null}"#.utf8
        )
        let binding = try JSONDecoder().decode(ASCOperationInputBinding.self, from: data)
        let encoded = try JSONEncoder().encode(binding)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(binding.fixedValue == .null)
        #expect(object.keys.contains("fixedValue"))
        #expect(object["fixedValue"] is NSNull)
    }

    @Test("valid three-way contract has no error diagnostics")
    func validContractHasNoErrorDiagnostics() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let tools = fixtureTools().map(ToolMetadataPolicy.apply)

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: manifest,
            tools: tools
        )

        #expect(!diagnostics.contains { $0.severity == .error }, "Unexpected error diagnostics: \(diagnostics)")
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed &&
            diagnostic.operationID == "apps_getCollection" &&
            diagnostic.field == "filter[name]"
        })
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .requestBodyOptionalPropertyUnbound &&
            diagnostic.operationID == "apps_updateInstance" &&
            diagnostic.field == "/data/attributes/reviewNote"
        })
    }

    @Test("exact optional parameter classification closes only its reviewed gap")
    func exactOptionalParameterClassification() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let operation = try #require(list.operations.first)
        let classification = ASCOptionalParameterClassification(
            location: "query",
            appleName: "filter[name]",
            disposition: .intentionallyOmitted,
            reason: "The fixture intentionally omits name filtering.",
            reviewAtSpec: spec.version
        )
        let classified = replacing(
            operation,
            optionalParameterClassifications: [classification]
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: 2,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )
        let classifiedManifest = replacingIndex(
            in: replacingTool(
                in: manifest,
                with: replacing(list, operations: [classified])
            ),
            with: index
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: classifiedManifest,
            tools: fixtureTools().map(ToolMetadataPolicy.apply)
        )
        let coverage = ASCOperationToolAnalyzer().optionalInputCoverage(
            spec: spec,
            manifest: classifiedManifest
        )

        #expect(!diagnostics.contains { $0.code == .parameterUnexposed })
        #expect(coverage.bound == 1)
        #expect(coverage.intentionallyOmitted == 1)
        #expect(coverage.unclassified == 1)
    }

    @Test("exact request-body classification closes only its reviewed optional input")
    func exactOptionalRequestBodyClassification() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let update = try #require(manifest.mapping(for: "apps_update"))
        let operation = try #require(update.operations.first)
        let classification = ASCOptionalParameterClassification(
            location: "body",
            appleName: "/data/attributes/reviewNote",
            disposition: .intentionallyOmitted,
            reason: "The fixture intentionally omits the optional review note.",
            reviewAtSpec: spec.version
        )
        let classified = replacing(
            operation,
            optionalParameterClassifications: [classification]
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: 2,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )
        let classifiedManifest = replacingIndex(
            in: replacingTool(
                in: manifest,
                with: replacing(update, operations: [classified])
            ),
            with: index
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: classifiedManifest,
            tools: fixtureTools().map(ToolMetadataPolicy.apply)
        )
        let coverage = ASCOperationToolAnalyzer().optionalInputCoverage(
            spec: spec,
            manifest: classifiedManifest
        )

        #expect(!diagnostics.contains { $0.code == .requestBodyOptionalPropertyUnbound })
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed && diagnostic.field == "filter[name]"
        })
        #expect(coverage.bound == 1)
        #expect(coverage.intentionallyOmitted == 1)
        #expect(coverage.unclassified == 1)
    }

    @Test("optional parameter classifications reject typos overlaps and stale reviews")
    func invalidOptionalParameterClassifications() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let operation = try #require(list.operations.first)
        let classifications = [
            ASCOptionalParameterClassification(
                location: "query",
                appleName: "filter[typo]",
                disposition: .intentionallyOmitted,
                reason: "Misspelled fixture target.",
                reviewAtSpec: spec.version
            ),
            ASCOptionalParameterClassification(
                location: "query",
                appleName: "limit",
                disposition: .internalControl,
                reason: "Overlaps the public limit field.",
                reviewAtSpec: spec.version
            ),
            ASCOptionalParameterClassification(
                location: "query",
                appleName: "filter[name]",
                disposition: .intentionallyOmitted,
                reason: "Stale fixture classification.",
                reviewAtSpec: "0.1"
            )
        ]
        let classified = replacing(
            operation,
            optionalParameterClassifications: classifications
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: 2,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )
        let classifiedManifest = replacingIndex(
            in: replacingTool(
                in: manifest,
                with: replacing(list, operations: [classified])
            ),
            with: index
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: classifiedManifest
        )

        #expect(diagnostics.contains { $0.code == .parameterClassificationTargetMissing })
        #expect(diagnostics.contains { $0.code == .parameterClassificationOverlap })
        #expect(diagnostics.contains { $0.code == .parameterClassificationExpired })
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed && diagnostic.field == "filter[name]"
        })
    }

    @Test("future reviews and unsupported manifest versions cannot hide optional gaps")
    func optionalParameterPolicyRequiresExactVersion() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let operation = try #require(list.operations.first)

        func classifiedManifest(
            reviewAtSpec: String,
            schemaVersion: Int
        ) -> ASCOperationManifestBundle {
            let classification = ASCOptionalParameterClassification(
                location: "query",
                appleName: "filter[name]",
                disposition: .intentionallyOmitted,
                reason: "Fixture classification.",
                reviewAtSpec: reviewAtSpec
            )
            let classified = replacing(
                operation,
                optionalParameterClassifications: [classification]
            )
            let index = ASCOperationManifestIndex(
                schemaVersion: schemaVersion,
                specPin: manifest.index.specPin,
                scopeRules: manifest.index.scopeRules,
                waivers: manifest.index.waivers
            )
            return replacingIndex(
                in: replacingTool(
                    in: manifest,
                    with: replacing(list, operations: [classified])
                ),
                with: index
            )
        }

        let futureManifest = classifiedManifest(
            reviewAtSpec: "999.0",
            schemaVersion: 2
        )
        let futureDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: futureManifest,
            tools: fixtureTools().map(ToolMetadataPolicy.apply)
        )
        let futureCoverage = ASCOperationToolAnalyzer().optionalInputCoverage(
            spec: spec,
            manifest: futureManifest
        )

        #expect(futureDiagnostics.contains { $0.code == .parameterClassificationInvalid })
        #expect(futureDiagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed && diagnostic.field == "filter[name]"
        })
        #expect(futureCoverage.intentionallyOmitted == 0)
        #expect(futureCoverage.unclassified == 2)

        let unsupportedManifest = classifiedManifest(
            reviewAtSpec: spec.version,
            schemaVersion: 3
        )
        let unsupportedDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: unsupportedManifest,
            tools: fixtureTools().map(ToolMetadataPolicy.apply)
        )
        let unsupportedCoverage = ASCOperationToolAnalyzer().optionalInputCoverage(
            spec: spec,
            manifest: unsupportedManifest
        )

        #expect(unsupportedDiagnostics.contains { $0.code == .manifestUnsupportedVersion })
        #expect(unsupportedDiagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed && diagnostic.field == "filter[name]"
        })
        #expect(unsupportedCoverage.intentionallyOmitted == 0)
        #expect(unsupportedCoverage.unclassified == 2)
    }

    @Test("strict operation contract requires schema version two")
    func strictOperationContractRequiresSchemaVersionTwo() {
        let legacy = ASCOperationContractCommand.strictSchemaDiagnostic(schemaVersion: 1)
        let current = ASCOperationContractCommand.strictSchemaDiagnostic(schemaVersion: 2)

        #expect(legacy?.severity == .error)
        #expect(legacy?.code == .manifestStrictSchemaVersion)
        #expect(current == nil)
    }

    @Test("strict operation contract pins optional input coverage")
    func strictOperationContractPinsOptionalInputCoverage() {
        let coverage = ASCOptionalInputCoverage(
            total: 5,
            bound: 2,
            internalControl: 1,
            intentionallyOmitted: 1,
            unclassified: 1,
            identitySHA256: String(repeating: "a", count: 64)
        )
        let missing = ASCOperationContractCommand.strictOptionalInputCoverageDiagnostic(
            pin: nil,
            actual: coverage
        )
        let exact = ASCOperationContractCommand.strictOptionalInputCoverageDiagnostic(
            pin: coverage,
            actual: coverage
        )
        let drifted = ASCOperationContractCommand.strictOptionalInputCoverageDiagnostic(
            pin: ASCOptionalInputCoverage(
                total: 5,
                bound: 1,
                internalControl: 1,
                intentionallyOmitted: 1,
                unclassified: 2,
                identitySHA256: String(repeating: "a", count: 64)
            ),
            actual: coverage
        )
        let identityDrifted = ASCOperationContractCommand.strictOptionalInputCoverageDiagnostic(
            pin: ASCOptionalInputCoverage(
                total: 5,
                bound: 2,
                internalControl: 1,
                intentionallyOmitted: 1,
                unclassified: 1,
                identitySHA256: String(repeating: "b", count: 64)
            ),
            actual: coverage
        )
        let invalid = ASCOperationContractCommand.strictOptionalInputCoverageDiagnostic(
            pin: ASCOptionalInputCoverage(
                total: 5,
                bound: 2,
                internalControl: 1,
                intentionallyOmitted: 1,
                unclassified: 1
            ),
            actual: coverage
        )

        #expect(missing?.severity == .error)
        #expect(missing?.code == .manifestOptionalInputCoveragePinMissing)
        #expect(exact == nil)
        #expect(drifted?.severity == .error)
        #expect(drifted?.code == .manifestOptionalInputCoverageDrift)
        #expect(identityDrifted?.severity == .error)
        #expect(identityDrifted?.code == .manifestOptionalInputCoverageDrift)
        #expect(invalid?.severity == .error)
        #expect(invalid?.code == .manifestOptionalInputCoveragePinInvalid)
    }

    @Test("reviewed sparse fields do not hide includes or relationship limits")
    func reviewedSparseFieldFamily() throws {
        let originalSpec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let originalOperation = try #require(originalSpec.operation(id: "apps_getCollection"))
        let template = try #require(
            originalOperation.parameters.first { $0.name == "filter[name]" }
        )
        let familyParameters = [
            ASCOpenAPIParameter(
                name: "fields[apps]",
                location: .query,
                description: nil,
                required: false,
                deprecated: false,
                style: template.style,
                explode: template.explode,
                schema: template.schema
            ),
            ASCOpenAPIParameter(
                name: "include",
                location: .query,
                description: nil,
                required: false,
                deprecated: false,
                style: template.style,
                explode: template.explode,
                schema: template.schema
            ),
            ASCOpenAPIParameter(
                name: "limit[builds]",
                location: .query,
                description: nil,
                required: false,
                deprecated: false,
                style: template.style,
                explode: template.explode,
                schema: template.schema
            )
        ]
        let expandedOperation = ASCOpenAPIOperation(
            method: originalOperation.method,
            path: originalOperation.path,
            operationID: originalOperation.operationID,
            summary: originalOperation.summary,
            tags: originalOperation.tags,
            deprecated: originalOperation.deprecated,
            parameters: originalOperation.parameters + familyParameters,
            requestBody: originalOperation.requestBody,
            responses: originalOperation.responses
        )
        let spec = ASCOpenAPISpec(
            title: originalSpec.title,
            version: originalSpec.version,
            openAPIVersion: originalSpec.openAPIVersion,
            sha256: originalSpec.sha256,
            paths: originalSpec.paths,
            operations: originalSpec.operations.map {
                $0.operationID == expandedOperation.operationID ? expandedOperation : $0
            },
            schemas: originalSpec.schemas
        )
        let manifest = try loadValidManifest()
        let familyRules = [
            ASCOptionalParameterFamilyRule(
                family: .sparseFields,
                disposition: .intentionallyOmitted,
                reason: "Fixture sparse fields are intentionally omitted.",
                owner: "tests",
                reviewAtSpec: spec.version
            )
        ]
        let index = ASCOperationManifestIndex(
            schemaVersion: 2,
            specPin: manifest.index.specPin,
            optionalParameterFamilyRules: familyRules,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )
        let classifiedManifest = replacingIndex(in: manifest, with: index)

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: classifiedManifest
        )
        let coverage = ASCOperationToolAnalyzer().optionalInputCoverage(
            spec: spec,
            manifest: classifiedManifest
        )

        let unexposedFields = Set(diagnostics.filter {
            $0.code == .parameterUnexposed
        }.compactMap(\.field))
        #expect(unexposedFields == Set(["filter[name]", "include", "limit[builds]"]))
        #expect(coverage.bound == 1)
        #expect(coverage.intentionallyOmitted == 1)
        #expect(coverage.unclassified == 4)

        let futureIndex = ASCOperationManifestIndex(
            schemaVersion: 2,
            specPin: manifest.index.specPin,
            optionalParameterFamilyRules: [
                ASCOptionalParameterFamilyRule(
                    family: .sparseFields,
                    disposition: .intentionallyOmitted,
                    reason: "Fixture sparse fields are intentionally omitted.",
                    owner: "tests",
                    reviewAtSpec: "999.0"
                )
            ],
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )
        let futureManifest = replacingIndex(in: manifest, with: futureIndex)
        let futureDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: futureManifest
        )

        #expect(futureDiagnostics.contains { $0.code == .parameterFamilyRuleInvalid })
        #expect(futureDiagnostics.contains { diagnostic in
            diagnostic.code == .parameterUnexposed && diagnostic.field == "fields[apps]"
        })
    }

    @Test("public tool without manifest entry fails the gate")
    func missingManifestEntryFailsGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let extraTool = Tool(
            name: "orphan_list",
            description: "Fixture orphan",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
        let tools = (fixtureTools() + [extraTool]).map(ToolMetadataPolicy.apply)

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: manifest,
            tools: tools
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .toolMissingManifest && diagnostic.tool == "orphan_list"
        })
    }

    @Test("spec pin drift fails the gate")
    func specPinDriftFailsGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let driftedIndex = ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: ASCSpecPin(
                version: "4.4-test",
                sha256: String(repeating: "0", count: 64),
                pathCount: manifest.index.specPin.pathCount + 1,
                operationCount: manifest.index.specPin.operationCount + 1
            ),
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingIndex(in: manifest, with: driftedIndex)
        )

        #expect(diagnostics.contains { $0.code == .specVersionMismatch })
        #expect(diagnostics.contains { $0.code == .specChecksumMismatch })
        #expect(diagnostics.contains { $0.code == .specPathCountMismatch })
        #expect(diagnostics.contains { $0.code == .specOperationCountMismatch })
    }

    @Test("missing required request-body property fails the gate")
    func missingRequiredRequestBodyPropertyFailsGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let update = try #require(manifest.mapping(for: "apps_update"))
        let withoutName = replacing(
            update,
            fields: update.fields.filter { $0.toolField != "name" }
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(in: manifest, with: withoutName)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .requestBodyRequiredPropertyUnbound &&
            diagnostic.operationID == "apps_updateInstance" &&
            diagnostic.field == "/data/attributes/name"
        })
    }

    @Test("repeated operations require unique invocation identifiers")
    func repeatedOperationsRequireUniqueInvocationIdentifiers() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let operation = try #require(list.operations.first)

        let missingInvocation = replacing(
            list,
            operations: [
                replacing(operation, invocationID: nil, role: .primary),
                replacing(operation, invocationID: "secondary", role: .supporting)
            ]
        )
        let missingDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(in: manifest, with: missingInvocation)
        )

        let duplicateInvocation = replacing(
            list,
            operations: [
                replacing(operation, invocationID: "same", role: .primary),
                replacing(operation, invocationID: "same", role: .supporting)
            ]
        )
        let duplicateDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(in: manifest, with: duplicateInvocation)
        )

        #expect(missingDiagnostics.contains { $0.code == .operationInvocationMissing })
        #expect(duplicateDiagnostics.contains { $0.code == .operationInvocationDuplicate })
    }

    @Test("invalid fixed Apple enum value fails the gate")
    func invalidFixedAppleEnumValueFailsGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let operation = try #require(list.operations.first)
        let invalidPlatform = ASCOperationInputBinding(
            sourceKind: .fixed,
            location: "query",
            appleName: "filter[platform]",
            jsonPointer: nil,
            fixedValue: .string("TV_OS"),
            derivedFrom: nil,
            localRole: nil
        )
        let inputs = [invalidPlatform] + Array((operation.inputs ?? []).dropFirst())
        let invalidMapping = replacing(
            list,
            operations: [replacing(operation, inputs: inputs)]
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(in: manifest, with: invalidMapping)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .fieldFixedValueInvalid &&
            diagnostic.operationID == "apps_getCollection" &&
            diagnostic.field == "filter[platform]"
        })
    }

    @Test("fixed null is valid for a nullable Apple field")
    func fixedNullIsValidForNullableAppleField() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let update = try #require(manifest.mapping(for: "apps_update"))
        let operation = try #require(update.operations.first)
        let fixedNull = ASCOperationInputBinding(
            sourceKind: .fixed,
            location: nil,
            appleName: nil,
            jsonPointer: "/data/attributes/reviewNote",
            fixedValue: .null,
            derivedFrom: nil,
            localRole: nil
        )
        let replacement = replacing(
            update,
            operations: [
                replacing(
                    operation,
                    inputs: (operation.inputs ?? []) + [fixedNull]
                )
            ]
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(in: manifest, with: replacement)
        )

        #expect(
            !diagnostics.contains { $0.severity == .error },
            "Unexpected nullable fixed-value diagnostics: \(diagnostics)"
        )
    }

    @Test("invalid response source and pointer fail the gate")
    func invalidResponseSourceAndPointerFailGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))
        let invalidSource = ASCResponseMapping(
            mode: list.response.mode,
            sources: [
                ASCResponseSource(
                    operationID: "apps_getCollection",
                    invocationIDs: nil,
                    statusCode: "201",
                    mediaType: "application/json"
                )
            ],
            fields: list.response.fields,
            waiverID: list.response.waiverID
        )
        let sourceDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(
                in: manifest,
                with: replacing(list, response: invalidSource)
            )
        )

        let missingMediaType = ASCResponseMapping(
            mode: list.response.mode,
            sources: [
                ASCResponseSource(
                    operationID: "apps_getCollection",
                    invocationIDs: nil,
                    statusCode: "200",
                    mediaType: nil
                )
            ],
            fields: list.response.fields,
            waiverID: list.response.waiverID
        )
        let mediaTypeDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(
                in: manifest,
                with: replacing(list, response: missingMediaType)
            )
        )

        let invalidPointer = ASCResponseMapping(
            mode: list.response.mode,
            sources: list.response.sources,
            fields: [
                ASCResponseFieldBinding(
                    outputField: "missing",
                    operationID: "apps_getCollection",
                    invocationIDs: nil,
                    jsonPointer: "/data/missing",
                    localRole: nil
                )
            ],
            waiverID: list.response.waiverID
        )
        let pointerDiagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(
                in: manifest,
                with: replacing(list, response: invalidPointer)
            )
        )

        #expect(sourceDiagnostics.contains { $0.code == .responseSourceMissing })
        #expect(mediaTypeDiagnostics.contains { $0.code == .responseSourceMissing })
        #expect(pointerDiagnostics.contains { diagnostic in
            diagnostic.code == .responseFieldPointerMissing &&
            diagnostic.field == "missing"
        })
    }

    @Test("response pointer must belong to every declared invocation")
    func responsePointerMustBelongToDeclaredInvocation() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let update = try #require(manifest.mapping(for: "apps_update"))
        let operation = try #require(update.operations.first)
        let repeatedOperations = [
            replacing(operation, invocationID: "content", role: .primary),
            replacing(operation, invocationID: "no-content", role: .supporting)
        ]
        let response = ASCResponseMapping(
            mode: .aggregate,
            sources: [
                ASCResponseSource(
                    operationID: operation.operationID,
                    invocationIDs: ["content"],
                    statusCode: "200",
                    mediaType: "application/json"
                ),
                ASCResponseSource(
                    operationID: operation.operationID,
                    invocationIDs: ["no-content"],
                    statusCode: "204",
                    mediaType: nil
                )
            ],
            fields: [
                ASCResponseFieldBinding(
                    outputField: "invalidNoContentProjection",
                    operationID: operation.operationID,
                    invocationIDs: ["no-content"],
                    jsonPointer: "/",
                    localRole: nil
                )
            ],
            waiverID: nil
        )
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingTool(
                in: manifest,
                with: replacing(
                    update,
                    operations: repeatedOperations,
                    response: response
                )
            )
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .responseFieldPointerMissing &&
            diagnostic.field == "invalidNoContentProjection"
        })
    }

    @Test("waiver cannot overlap a mapped operation")
    func waiverCannotOverlapMappedOperation() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let overlap = ASCOperationWaiver(
            id: "fixture-mapped-overlap",
            operationID: "apps_getCollection",
            method: nil,
            path: nil,
            disposition: .deferred,
            reason: "Fixture overlap must be rejected.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers + [overlap]
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingIndex(in: manifest, with: index)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .waiverMappedOverlap &&
            diagnostic.operationID == "apps_getCollection"
        })
    }

    @Test("method-and-path waiver cannot overlap a mapped operation")
    func methodPathWaiverCannotOverlapMappedOperation() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let overlap = ASCOperationWaiver(
            id: "fixture-mapped-method-path-overlap",
            operationID: nil,
            method: "GET",
            path: "/v1/apps",
            disposition: .deferred,
            reason: "Fixture overlap must be rejected.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules,
            waivers: manifest.index.waivers + [overlap]
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingIndex(in: manifest, with: index)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .waiverMappedOverlap &&
            diagnostic.operationID == "apps_getCollection"
        })
    }

    @Test("coverage buckets reject duplicate waiver and scope ownership")
    func coverageBucketsRejectDuplicateOwnership() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let duplicateWaiver = ASCOperationWaiver(
            id: "fixture-apps-get-instance-duplicate",
            operationID: "apps_getInstance",
            method: nil,
            path: nil,
            disposition: .deferred,
            reason: "Fixture duplicate must be rejected.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let scopedWaiver = ASCOperationWaiver(
            id: "fixture-scoped-operation-overlap",
            operationID: "gameCenterAchievements_createInstance",
            method: nil,
            path: nil,
            disposition: .deferred,
            reason: "Fixture scope overlap must be rejected.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let overlappingScope = ASCOperationScopeRule(
            pathPrefix: "/v1/gameCenterAchievements",
            disposition: .outOfScope,
            reason: "Fixture nested scope overlap must be rejected.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules + [overlappingScope],
            waivers: manifest.index.waivers + [duplicateWaiver, scopedWaiver]
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingIndex(in: manifest, with: index)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .waiverTargetOverlap &&
            diagnostic.operationID == "apps_getInstance"
        })
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .waiverScopeOverlap &&
            diagnostic.operationID == "gameCenterAchievements_createInstance"
        })
        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .scopeRuleOverlap &&
            diagnostic.operationID == "gameCenterAchievements_createInstance"
        })
    }

    @Test("scope rules require the out-of-scope disposition")
    func scopeRulesRequireOutOfScopeDisposition() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let invalidRule = ASCOperationScopeRule(
            pathPrefix: "/v1/future",
            disposition: .deferred,
            reason: "A broad scope rule cannot represent deferred work.",
            owner: "tests",
            reviewAtSpec: spec.version
        )
        let index = ASCOperationManifestIndex(
            schemaVersion: manifest.index.schemaVersion,
            specPin: manifest.index.specPin,
            scopeRules: manifest.index.scopeRules + [invalidRule],
            waivers: manifest.index.waivers
        )

        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: replacingIndex(in: manifest, with: index)
        )

        #expect(diagnostics.contains { diagnostic in
            diagnostic.code == .scopeRuleInvalidDisposition
        })
    }

    @Test("non-as-built implementation state fails the gate")
    func nonAsBuiltImplementationStateFailsGate() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let manifest = try loadValidManifest()
        let list = try #require(manifest.mapping(for: "apps_list"))

        for implementationState in [ASCImplementationState.target, .broken] {
            let replacement = replacing(
                list,
                implementationState: implementationState
            )
            let diagnostics = ASCOperationToolAnalyzer().analyze(
                spec: spec,
                manifest: replacingTool(in: manifest, with: replacement)
            )

            #expect(diagnostics.contains { diagnostic in
                diagnostic.code == .toolImplementationDrift &&
                diagnostic.tool == "apps_list"
            })
        }
    }

    @Test("bundled manifest tracks the exact public MCP catalog")
    func bundledManifestTracksPublicCatalog() async throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let snapshots = try await TestFactory.collectWorkerToolSnapshots().map { snapshot in
            ASCWorkerToolSnapshot(
                key: snapshot.key,
                readmeName: snapshot.readmeName,
                tools: snapshot.tools.map(ToolMetadataPolicy.apply)
            )
        }
        let tools = snapshots.flatMap(\.tools)
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            manifest: manifest,
            workerSnapshots: snapshots
        )

        #expect(manifest.index.schemaVersion == 2)
        #expect(manifest.index.optionalInputCoveragePin != nil)
        #expect(manifest.tools.count == 502)
        #expect(Set(manifest.tools.map(\.tool)) == Set(tools.map(\.name)))
        #expect(Set(manifest.workers.map(\.workerKey)) == Set(snapshots.map(\.key)))
        for snapshot in snapshots {
            let manifestWorker = try #require(
                manifest.workers.first { $0.workerKey == snapshot.key }
            )
            #expect(
                Set(manifestWorker.tools.map(\.tool)) == Set(snapshot.tools.map(\.name)),
                "Worker manifest drift: \(snapshot.key)"
            )
        }
        let expectedBroken: Set<String> = []
        let expectedTarget: Set<String> = []
        let expectedImplementationStates = Dictionary(uniqueKeysWithValues:
            expectedBroken.map { ($0, ASCImplementationState.broken) } +
                expectedTarget.map { ($0, ASCImplementationState.target) }
        )
        let implementationDrift = diagnostics.filter {
            $0.code == .toolImplementationDrift
        }
        let actualImplementationStates = Dictionary(uniqueKeysWithValues:
            manifest.tools
                .filter { $0.implementationState != .asBuilt }
                .map { ($0.tool, $0.implementationState) }
        )
        #expect(
            implementationDrift.count == expectedImplementationStates.count
        )
        #expect(
            Set(implementationDrift.compactMap(\.tool)) == Set(expectedImplementationStates.keys)
        )
        #expect(actualImplementationStates == expectedImplementationStates)
        let unexpectedDiagnostics = diagnostics.filter {
            $0.code != .toolImplementationDrift
        }
        #expect(
            unexpectedDiagnostics.isEmpty,
            "Unexpected catalog diagnostics: \(unexpectedDiagnostics)"
        )
    }

    private func loadValidManifest() throws -> ASCOperationManifestBundle {
        guard let url = Bundle.module.url(
            forResource: "operation_manifest_valid",
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound("operation_manifest_valid")
        }
        return try ASCOperationManifestBundle.load(from: url)
    }

    private func fixtureTools() -> [Tool] {
        [
            Tool(
                name: "apps_list",
                description: "Fixture app list",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object(["type": .string("integer")]),
                        "next_url": .object(["type": .string("string")])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "local_status",
                description: "Fixture local status",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("string")])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "apps_update",
                description: "Fixture app update",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "name": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id"), .string("name")])
                ])
            )
        ]
    }

    private func replacingIndex(
        in manifest: ASCOperationManifestBundle,
        with index: ASCOperationManifestIndex
    ) -> ASCOperationManifestBundle {
        ASCOperationManifestBundle(index: index, workers: manifest.workers)
    }

    private func replacingTool(
        in manifest: ASCOperationManifestBundle,
        with replacement: ASCToolOperationMapping
    ) -> ASCOperationManifestBundle {
        let workers = manifest.workers.map { worker in
            ASCWorkerToolManifest(
                workerKey: worker.workerKey,
                tools: worker.tools.map { mapping in
                    mapping.tool == replacement.tool ? replacement : mapping
                },
                implementationAliases: worker.implementationAliases
            )
        }
        return ASCOperationManifestBundle(index: manifest.index, workers: workers)
    }

    private func replacing(
        _ mapping: ASCToolOperationMapping,
        implementationState: ASCImplementationState? = nil,
        operations: [ASCOperationUse]? = nil,
        fields: [ASCToolFieldBinding]? = nil,
        response: ASCResponseMapping? = nil
    ) -> ASCToolOperationMapping {
        ASCToolOperationMapping(
            tool: mapping.tool,
            kind: mapping.kind,
            status: mapping.status,
            effect: mapping.effect,
            implementationState: implementationState ?? mapping.implementationState,
            replacementTool: mapping.replacementTool,
            operations: operations ?? mapping.operations,
            fields: fields ?? mapping.fields,
            response: response ?? mapping.response,
            note: mapping.note
        )
    }

    private func replacing(
        _ operation: ASCOperationUse,
        invocationID: String? = nil,
        role: ASCOperationRole? = nil,
        inputs: [ASCOperationInputBinding]? = nil,
        optionalParameterClassifications: [ASCOptionalParameterClassification]? = nil
    ) -> ASCOperationUse {
        ASCOperationUse(
            invocationID: invocationID,
            operationID: operation.operationID,
            method: operation.method,
            path: operation.path,
            role: role ?? operation.role,
            condition: operation.condition,
            inputs: inputs ?? operation.inputs,
            optionalParameterClassifications: optionalParameterClassifications ??
                operation.optionalParameterClassifications
        )
    }
}
