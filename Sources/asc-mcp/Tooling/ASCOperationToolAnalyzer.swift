import Foundation
import MCP

enum ASCContractDiagnosticSeverity: String, Codable, Sendable {
    case error
    case warning
}

enum ASCContractDiagnosticCode: String, Codable, Sendable {
    case manifestUnsupportedVersion = "manifest.unsupported_version"
    case specVersionMismatch = "spec.version_mismatch"
    case specChecksumMismatch = "spec.checksum_mismatch"
    case specPathCountMismatch = "spec.path_count_mismatch"
    case specOperationCountMismatch = "spec.operation_count_mismatch"
    case operationDuplicateID = "operation.duplicate_id"
    case operationMissing = "operation.missing"
    case operationIdentityDrift = "operation.identity_drift"
    case operationDeprecated = "operation.deprecated"
    case operationUntriaged = "operation.untriaged"
    case operationMissingPrimary = "operation.missing_primary"
    case operationMultiplePrimary = "operation.multiple_primary"
    case operationUnexpectedCount = "operation.unexpected_count"
    case operationInvocationMissing = "operation.invocation_missing"
    case operationInvocationDuplicate = "operation.invocation_duplicate"
    case toolMissingManifest = "tool.missing_manifest"
    case toolOrphanManifest = "tool.orphan_manifest"
    case toolDuplicatePublic = "tool.duplicate_public"
    case workerMissingManifest = "worker.missing_manifest"
    case workerOrphanManifest = "worker.orphan_manifest"
    case toolWorkerMismatch = "tool.worker_mismatch"
    case toolUnresolved = "tool.unresolved"
    case toolLocalHasOperation = "tool.local_has_operation"
    case toolAliasMissingReplacement = "tool.alias_missing_replacement"
    case toolEffectMismatch = "tool.effect_mismatch"
    case toolAppleEffectMismatch = "tool.apple_effect_mismatch"
    case toolImplementationDrift = "tool.implementation_drift"
    case fieldUnbound = "field.unbound"
    case fieldOrphanBinding = "field.orphan_binding"
    case fieldDuplicateBinding = "field.duplicate_binding"
    case fieldTargetMissing = "field.target_missing"
    case fieldFixedValueInvalid = "field.fixed_value_invalid"
    case fieldInvocationInvalid = "field.invocation_invalid"
    case parameterUnexposed = "parameter.unexposed"
    case parameterRequiredUnbound = "parameter.required_unbound"
    case requestBodyUnmodeled = "request_body.unmodeled"
    case requestBodyRequiredUnbound = "request_body.required_unbound"
    case requestBodyRequiredPropertyUnbound = "request_body.required_property_unbound"
    case responseMissingSchema = "response.missing_schema"
    case responseSourceMissing = "response.source_missing"
    case responseSourceUnmodeled = "response.source_unmodeled"
    case responseFieldInvalid = "response.field_invalid"
    case responseFieldPointerMissing = "response.field_pointer_missing"
    case responseInvocationInvalid = "response.invocation_invalid"
    case responseWaiverMissing = "response.waiver_missing"
    case waiverDuplicateID = "waiver.duplicate_id"
    case waiverTargetMissing = "waiver.target_missing"
    case waiverTargetOverlap = "waiver.target_overlap"
    case waiverMappedOverlap = "waiver.mapped_overlap"
    case waiverScopeOverlap = "waiver.scope_overlap"
    case waiverExpired = "waiver.expired"
    case scopeRuleInvalidDisposition = "scope_rule.invalid_disposition"
    case scopeRuleExpired = "scope_rule.expired"
    case scopeRuleMappedOverlap = "scope_rule.mapped_overlap"
    case scopeRuleOverlap = "scope_rule.overlap"
}

struct ASCContractDiagnostic: Codable, Sendable, Equatable {
    let severity: ASCContractDiagnosticSeverity
    let code: ASCContractDiagnosticCode
    let message: String
    let tool: String?
    let operationID: String?
    let field: String?

    enum CodingKeys: String, CodingKey {
        case severity
        case code
        case message
        case tool
        case operationID = "operationId"
        case field
    }
}

struct ASCOperationToolAnalyzer: Sendable {
    /// Compare the Apple OpenAPI catalog with the semantic operation manifest.
    /// - Parameters:
    ///   - spec: Parsed Apple OpenAPI specification.
    ///   - manifest: Checked-in semantic operation manifest.
    /// - Returns: Operation-level diagnostics that don't require constructing MCP workers.
    func analyze(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        diagnostics += validateSpecPin(spec: spec, manifest: manifest)
        diagnostics += validateOperationIDs(spec: spec)
        diagnostics += validateManifestMappings(spec: spec, manifest: manifest)
        diagnostics += validateFieldTargets(spec: spec, manifest: manifest)
        diagnostics += validateOperationCoverage(spec: spec, manifest: manifest)
        diagnostics += validateWaivers(spec: spec, manifest: manifest)
        return sorted(diagnostics)
    }

    /// Compare the Apple OpenAPI catalog, semantic manifest, and actual MCP tool schemas.
    /// - Parameters:
    ///   - spec: Parsed Apple OpenAPI specification.
    ///   - manifest: Checked-in semantic operation manifest.
    ///   - tools: Actual public tools after applying `ToolMetadataPolicy`.
    /// - Returns: Deterministically sorted diagnostics suitable for CI and reports.
    func analyze(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle,
        tools: [Tool]
    ) -> [ASCContractDiagnostic] {
        var diagnostics = analyze(spec: spec, manifest: manifest)
        diagnostics += analyze(manifest: manifest, tools: tools)
        return sorted(diagnostics)
    }

    /// Compare Apple OpenAPI, manifest fragments, and the live credential-free worker catalog.
    /// - Parameters:
    ///   - spec: Parsed Apple OpenAPI specification.
    ///   - manifest: Checked-in semantic operation manifest.
    ///   - workerSnapshots: Actual public tools grouped by their production worker key.
    /// - Returns: Deterministically sorted operation, tool, and worker diagnostics.
    func analyze(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle,
        workerSnapshots: [ASCWorkerToolSnapshot]
    ) -> [ASCContractDiagnostic] {
        var diagnostics = analyze(spec: spec, manifest: manifest)
        diagnostics += analyze(manifest: manifest, workerSnapshots: workerSnapshots)
        return sorted(diagnostics)
    }

    /// Compare manifest fragments with the live worker ownership and public tool schemas.
    /// - Parameters:
    ///   - manifest: Checked-in semantic operation manifest.
    ///   - workerSnapshots: Actual public tools grouped by their production worker key.
    /// - Returns: Deterministically sorted tool and worker diagnostics.
    func analyze(
        manifest: ASCOperationManifestBundle,
        workerSnapshots: [ASCWorkerToolSnapshot]
    ) -> [ASCContractDiagnostic] {
        var diagnostics = analyze(
            manifest: manifest,
            tools: workerSnapshots.flatMap(\.tools)
        )
        diagnostics += validateWorkerCatalog(
            manifest: manifest,
            workerSnapshots: workerSnapshots
        )
        return sorted(diagnostics)
    }

    /// Compare the semantic operation manifest with the actual public MCP tool catalog.
    /// - Parameters:
    ///   - manifest: Checked-in semantic operation manifest.
    ///   - tools: Actual public tools after applying `ToolMetadataPolicy`.
    /// - Returns: Catalog diagnostics that can run without downloading the Apple specification.
    func analyze(
        manifest: ASCOperationManifestBundle,
        tools: [Tool]
    ) -> [ASCContractDiagnostic] {
        var diagnostics = validateToolSet(manifest: manifest, tools: tools)
        diagnostics += manifest.tools.compactMap { mapping in
            guard mapping.status == .unresolved else {
                return nil
            }
            return error(
                .toolUnresolved,
                "Tool '\(mapping.tool)' still has an unresolved operation mapping.",
                tool: mapping.tool
            )
        }
        diagnostics += manifest.tools
            .filter { $0.status != .unresolved }
            .flatMap { validateKind($0) }
        diagnostics += validateToolContracts(manifest: manifest, tools: tools)
        return sorted(diagnostics)
    }

    private func validateSpecPin(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        if manifest.index.schemaVersion != 1 {
            diagnostics.append(error(
                .manifestUnsupportedVersion,
                "Unsupported manifest schema version \(manifest.index.schemaVersion); expected 1."
            ))
        }
        if manifest.index.specPin.version != spec.version {
            diagnostics.append(error(
                .specVersionMismatch,
                "Manifest pins Apple API \(manifest.index.specPin.version), but the supplied spec is \(spec.version)."
            ))
        }
        if manifest.index.specPin.sha256 != spec.sha256 {
            diagnostics.append(error(
                .specChecksumMismatch,
                "Manifest pins Apple spec SHA-256 \(manifest.index.specPin.sha256), but the supplied spec is \(spec.sha256)."
            ))
        }
        if manifest.index.specPin.pathCount != spec.paths.count {
            diagnostics.append(error(
                .specPathCountMismatch,
                "Manifest pins \(manifest.index.specPin.pathCount) Apple paths, but the supplied spec has \(spec.paths.count)."
            ))
        }
        if manifest.index.specPin.operationCount != spec.operations.count {
            diagnostics.append(error(
                .specOperationCountMismatch,
                "Manifest pins \(manifest.index.specPin.operationCount) Apple operations, but the supplied spec has \(spec.operations.count)."
            ))
        }
        return diagnostics
    }

    private func validateOperationIDs(spec: ASCOpenAPISpec) -> [ASCContractDiagnostic] {
        duplicateValues(spec.operations.map(\.operationID)).map { operationID in
            error(
                .operationDuplicateID,
                "Apple specification contains duplicate operationId '\(operationID)'.",
                operationID: operationID
            )
        }
    }

    private func validateToolSet(
        manifest: ASCOperationManifestBundle,
        tools: [Tool]
    ) -> [ASCContractDiagnostic] {
        let actualNames = Set(tools.map(\.name))
        let manifestNames = Set(manifest.tools.map(\.tool))
        let missing = actualNames.subtracting(manifestNames).sorted()
        let orphan = manifestNames.subtracting(actualNames).sorted()
        let duplicates = duplicateValues(tools.map(\.name))

        return duplicates.map { toolName in
            error(
                .toolDuplicatePublic,
                "Public MCP catalog contains duplicate tool name '\(toolName)'.",
                tool: toolName
            )
        } + missing.map { toolName in
            error(
                .toolMissingManifest,
                "Public tool '\(toolName)' has no operation manifest entry.",
                tool: toolName
            )
        } + orphan.map { toolName in
            error(
                .toolOrphanManifest,
                "Manifest entry '\(toolName)' is not present in the public MCP catalog.",
                tool: toolName
            )
        }
    }

    private func validateWorkerCatalog(
        manifest: ASCOperationManifestBundle,
        workerSnapshots: [ASCWorkerToolSnapshot]
    ) -> [ASCContractDiagnostic] {
        let actualWorkerKeys = Set(workerSnapshots.map(\.key))
        let manifestWorkerKeys = Set(manifest.workers.map(\.workerKey))
        var diagnostics = actualWorkerKeys.subtracting(manifestWorkerKeys).sorted().map { key in
            error(
                .workerMissingManifest,
                "Public worker '\(key)' has no operation manifest fragment."
            )
        }
        diagnostics += manifestWorkerKeys.subtracting(actualWorkerKeys).sorted().map { key in
            error(
                .workerOrphanManifest,
                "Manifest worker '\(key)' is absent from the public worker catalog."
            )
        }

        let manifestByKey = Dictionary(uniqueKeysWithValues: manifest.workers.map {
            ($0.workerKey, Set($0.tools.map(\.tool)))
        })
        for snapshot in workerSnapshots {
            let actualTools = Set(snapshot.tools.map(\.name))
            let manifestTools = manifestByKey[snapshot.key] ?? []
            for tool in actualTools.subtracting(manifestTools).sorted() {
                diagnostics.append(error(
                    .toolWorkerMismatch,
                    "Public tool belongs to worker '\(snapshot.key)' but is absent from that manifest fragment.",
                    tool: tool
                ))
            }
            for tool in manifestTools.subtracting(actualTools).sorted() {
                diagnostics.append(error(
                    .toolWorkerMismatch,
                    "Manifest assigns tool to worker '\(snapshot.key)', but that worker does not publish it.",
                    tool: tool
                ))
            }
        }
        return diagnostics
    }

    private func validateManifestMappings(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        let operationsByID = operationDictionary(spec.operations)
        var diagnostics: [ASCContractDiagnostic] = []

        for mapping in manifest.tools {
            if mapping.status == .unresolved {
                diagnostics.append(error(
                    .toolUnresolved,
                    "Tool '\(mapping.tool)' still has an unresolved operation mapping.",
                    tool: mapping.tool
                ))
                continue
            }
            diagnostics += validateKind(mapping)
            diagnostics += validateOperations(mapping, operationsByID: operationsByID)
            diagnostics += validateAppleEffect(mapping)
            diagnostics += validateAppleInputCoverage(
                mapping,
                operationsByID: operationsByID,
                spec: spec
            )
            diagnostics += validateResponseMapping(
                mapping,
                operationsByID: operationsByID,
                spec: spec,
                waiverIDs: Set(manifest.index.waivers.map(\.id))
            )
        }
        return diagnostics
    }

    private func validateToolContracts(
        manifest: ASCOperationManifestBundle,
        tools: [Tool]
    ) -> [ASCContractDiagnostic] {
        let toolsByName = tools.reduce(into: [String: Tool]()) { result, tool in
            if result[tool.name] == nil {
                result[tool.name] = tool
            }
        }
        var diagnostics: [ASCContractDiagnostic] = []

        for mapping in manifest.tools {
            if mapping.status == .unresolved {
                continue
            }

            guard let tool = toolsByName[mapping.tool] else {
                continue
            }
            diagnostics += validateEffect(mapping, tool: tool)
            diagnostics += validateFieldCatalog(mapping, tool: tool)
            diagnostics += validateOutputSchema(mapping, tool: tool)
        }

        return diagnostics
    }

    private func validateKind(_ mapping: ASCToolOperationMapping) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        let primaryCount = mapping.operations.filter { $0.role == .primary }.count

        if mapping.implementationState != .asBuilt {
            diagnostics.append(error(
                .toolImplementationDrift,
                "Manifest mapping is '\(mapping.implementationState.rawValue)', not verified as-built behavior. \(mapping.note ?? "")",
                tool: mapping.tool
            ))
        }

        switch mapping.kind {
        case .direct:
            if mapping.operations.count != 1 {
                diagnostics.append(error(
                    .operationUnexpectedCount,
                    "Direct tool must bind exactly one Apple operation.",
                    tool: mapping.tool
                ))
            }
            if primaryCount == 0 {
                diagnostics.append(error(
                    .operationMissingPrimary,
                    "Direct tool has no primary Apple operation.",
                    tool: mapping.tool
                ))
            }
        case .compound:
            if mapping.operations.isEmpty {
                diagnostics.append(error(
                    .operationUnexpectedCount,
                    "Compound tool must bind at least one Apple operation.",
                    tool: mapping.tool
                ))
            }
            if primaryCount == 0 {
                diagnostics.append(error(
                    .operationMissingPrimary,
                    "Compound tool has no primary Apple operation.",
                    tool: mapping.tool
                ))
            }
        case .local:
            if !mapping.operations.isEmpty {
                diagnostics.append(error(
                    .toolLocalHasOperation,
                    "Local tool must not claim Apple operation coverage.",
                    tool: mapping.tool
                ))
            }
        case .alias:
            if mapping.replacementTool?.isEmpty != false {
                diagnostics.append(error(
                    .toolAliasMissingReplacement,
                    "Alias tool must declare a replacement tool.",
                    tool: mapping.tool
                ))
            }
        }

        if primaryCount > 1 {
            diagnostics.append(error(
                .operationMultiplePrimary,
                "Tool binds more than one primary Apple operation.",
                tool: mapping.tool
            ))
        }
        for (operationID, uses) in Dictionary(grouping: mapping.operations, by: { $0.operationID })
            where uses.count > 1 {
            let invocationIDs = uses.compactMap(\.invocationID)
            if invocationIDs.count != uses.count || invocationIDs.contains(where: { $0.isEmpty }) {
                diagnostics.append(error(
                    .operationInvocationMissing,
                    "Repeated operation use requires a non-empty invocationId on every invocation.",
                    tool: mapping.tool,
                    operationID: operationID
                ))
            }
            if Set(invocationIDs).count != invocationIDs.count {
                diagnostics.append(error(
                    .operationInvocationDuplicate,
                    "Repeated operation use contains duplicate invocationId values.",
                    tool: mapping.tool,
                    operationID: operationID
                ))
            }
        }
        return diagnostics
    }

    private func validateOperations(
        _ mapping: ASCToolOperationMapping,
        operationsByID: [String: ASCOpenAPIOperation]
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        for use in mapping.operations {
            guard let operation = operationsByID[use.operationID] else {
                diagnostics.append(error(
                    .operationMissing,
                    "Manifest references an operation that is absent from the Apple specification.",
                    tool: mapping.tool,
                    operationID: use.operationID
                ))
                continue
            }
            if operation.method != use.method.lowercased() || operation.path != use.path {
                diagnostics.append(error(
                    .operationIdentityDrift,
                    "Expected \(use.method.uppercased()) \(use.path), found \(operation.method.uppercased()) \(operation.path).",
                    tool: mapping.tool,
                    operationID: use.operationID
                ))
            }
            if operation.deprecated && mapping.status != .deprecated {
                diagnostics.append(error(
                    .operationDeprecated,
                    "Tool binds a deprecated Apple operation without a deprecated mapping status.",
                    tool: mapping.tool,
                    operationID: use.operationID
                ))
            }
        }
        return diagnostics
    }

    private func validateEffect(
        _ mapping: ASCToolOperationMapping,
        tool: Tool
    ) -> [ASCContractDiagnostic] {
        let declaredReadOnly = tool.annotations.readOnlyHint ?? false
        let declaredDestructive = tool.annotations.destructiveHint ?? false
        let matches: Bool
        switch mapping.effect {
        case .read, .local:
            matches = declaredReadOnly && !declaredDestructive
        case .write:
            matches = !declaredReadOnly
        case .destructive:
            matches = !declaredReadOnly && declaredDestructive
        }
        guard matches else {
            return [error(
                .toolEffectMismatch,
                "Manifest effect '\(mapping.effect.rawValue)' disagrees with MCP readOnlyHint=\(declaredReadOnly), destructiveHint=\(declaredDestructive).",
                tool: mapping.tool
            )]
        }
        return []
    }

    private func validateAppleEffect(
        _ mapping: ASCToolOperationMapping
    ) -> [ASCContractDiagnostic] {
        guard !mapping.operations.isEmpty else {
            return []
        }
        let methods = Set(mapping.operations.map { $0.method.lowercased() })
        let readMethods: Set<String> = ["get", "head", "options", "trace"]
        let manifestReadOnly = mapping.effect == .read || mapping.effect == .local

        if methods.isSubset(of: readMethods) && !manifestReadOnly {
            return [warning(
                .toolAppleEffectMismatch,
                "Tool only calls read-only Apple HTTP operations but is published as a mutation.",
                tool: mapping.tool
            )]
        }
        if !methods.isSubset(of: readMethods) && manifestReadOnly {
            return [error(
                .toolAppleEffectMismatch,
                "Tool calls a mutating Apple operation but is published as read-only.",
                tool: mapping.tool
            )]
        }
        return []
    }

    private func validateAppleInputCoverage(
        _ mapping: ASCToolOperationMapping,
        operationsByID: [String: ASCOpenAPIOperation],
        spec: ASCOpenAPISpec
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []

        for use in mapping.operations {
            let operationID = use.operationID
            guard let operation = operationsByID[operationID] else {
                continue
            }
            var boundParameters = Set(mapping.fields.compactMap { binding -> String? in
                guard fieldBinding(binding, appliesTo: use),
                      let location = binding.location,
                      let appleName = binding.appleName else {
                    return nil
                }
                return "\(location):\(appleName)"
            })
            boundParameters.formUnion((use.inputs ?? []).compactMap { input -> String? in
                guard let location = input.location, let appleName = input.appleName else {
                    return nil
                }
                return "\(location):\(appleName)"
            })
            let invocation = use.invocationID ?? operationID

            for parameter in operation.parameters {
                let identity = "\(parameter.location.rawValue):\(parameter.name)"
                if !boundParameters.contains(identity) {
                    if parameter.required {
                        diagnostics.append(error(
                            .parameterRequiredUnbound,
                            "Required Apple parameter '\(identity)' is unbound for invocation '\(invocation)'.",
                            tool: mapping.tool,
                            operationID: operationID,
                            field: parameter.name
                        ))
                    } else {
                        diagnostics.append(warning(
                            .parameterUnexposed,
                            "Apple parameter '\(identity)' is not exposed for invocation '\(invocation)'.",
                            tool: mapping.tool,
                            operationID: operationID,
                            field: parameter.name
                        ))
                    }
                }
            }

            let hasRequestBodyBinding = mapping.fields.contains {
                fieldBinding($0, appliesTo: use) && $0.jsonPointer != nil
            } || (use.inputs ?? []).contains { $0.jsonPointer != nil }
            if let requestBody = operation.requestBody, !hasRequestBodyBinding {
                if requestBody.required {
                    diagnostics.append(error(
                        .requestBodyRequiredUnbound,
                        "Required Apple request body is unbound for invocation '\(invocation)'.",
                        tool: mapping.tool,
                        operationID: operationID
                    ))
                } else {
                    diagnostics.append(warning(
                        .requestBodyUnmodeled,
                        "Optional Apple request body is unmodeled for invocation '\(invocation)'.",
                        tool: mapping.tool,
                        operationID: operationID
                    ))
                }
            } else if operation.requestBody != nil {
                let bodyPointers = mapping.fields.compactMap { binding -> String? in
                    guard fieldBinding(binding, appliesTo: use) else {
                        return nil
                    }
                    return binding.jsonPointer
                } + (use.inputs ?? []).compactMap(\.jsonPointer)
                for requiredPointer in requiredRequestBodyPointers(operation, spec: spec)
                    where !bodyPointers.contains(where: {
                        pointer($0, covers: requiredPointer)
                    }) {
                    diagnostics.append(error(
                        .requestBodyRequiredPropertyUnbound,
                        "Required Apple request-body property '\(requiredPointer)' has no explicit binding for invocation '\(invocation)'.",
                        tool: mapping.tool,
                        operationID: operationID,
                        field: requiredPointer
                    ))
                }
            }
        }
        return diagnostics
    }

    private func validateFieldCatalog(
        _ mapping: ASCToolOperationMapping,
        tool: Tool
    ) -> [ASCContractDiagnostic] {
        let actualFields = inputPropertyNames(tool.inputSchema)
        let boundFields = Set(mapping.fields.map(\.toolField))
        var diagnostics: [ASCContractDiagnostic] = []

        for field in actualFields.subtracting(boundFields).sorted() {
            diagnostics.append(error(
                .fieldUnbound,
                "MCP input property is not classified by the operation manifest.",
                tool: mapping.tool,
                field: field
            ))
        }
        for field in boundFields.subtracting(actualFields).sorted() {
            diagnostics.append(error(
                .fieldOrphanBinding,
                "Manifest field binding does not exist in the MCP input schema.",
                tool: mapping.tool,
                field: field
            ))
        }
        let duplicateBindings = Dictionary(grouping: mapping.fields) { fieldBindingIdentity($0) }
            .values
            .filter { $0.count > 1 }
            .compactMap(\.first)
            .sorted { $0.toolField < $1.toolField }
        for binding in duplicateBindings {
            diagnostics.append(error(
                .fieldDuplicateBinding,
                "MCP input property has an identical manifest binding more than once.",
                tool: mapping.tool,
                operationID: binding.operationID,
                field: binding.toolField
            ))
        }

        return diagnostics
    }

    private func validateFieldTargets(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        let operationsByID = operationDictionary(spec.operations)
        var diagnostics: [ASCContractDiagnostic] = []

        for mapping in manifest.tools where mapping.status != .unresolved {
            diagnostics += validateFieldTargets(
                mapping,
                operationsByID: operationsByID,
                spec: spec
            )
        }
        return diagnostics
    }

    private func validateFieldTargets(
        _ mapping: ASCToolOperationMapping,
        operationsByID: [String: ASCOpenAPIOperation],
        spec: ASCOpenAPISpec
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        let claimedOperations = Set(mapping.operations.map(\.operationID))
        let usesByOperationID = Dictionary(grouping: mapping.operations, by: \.operationID)

        for binding in mapping.fields {
            let targetIsParameter = binding.location != nil && binding.appleName != nil
            let targetIsRequestBody = binding.jsonPointer != nil
            let isComplete: Bool
            switch binding.sourceKind {
            case .parameter:
                isComplete = binding.operationID != nil && targetIsParameter && !targetIsRequestBody
            case .requestBody:
                isComplete = binding.operationID != nil && targetIsRequestBody && !targetIsParameter
            case .derived:
                isComplete = binding.operationID != nil &&
                    (targetIsParameter != targetIsRequestBody) &&
                    binding.derivedFrom?.isEmpty == false &&
                    binding.localRole?.isEmpty == false
            case .fixed:
                isComplete = binding.operationID != nil &&
                    (targetIsParameter != targetIsRequestBody) &&
                    binding.fixedValue != nil
            case .local:
                isComplete = binding.operationID == nil && binding.localRole?.isEmpty == false
            }
            if !isComplete {
                diagnostics.append(error(
                    .fieldTargetMissing,
                    "Field binding is incomplete for sourceKind '\(binding.sourceKind.rawValue)'.",
                    tool: mapping.tool,
                    operationID: binding.operationID,
                    field: binding.toolField
                ))
            }
            if let operationID = binding.operationID {
                let uses = usesByOperationID[operationID] ?? []
                if uses.count > 1, binding.invocationID == nil {
                    diagnostics.append(error(
                        .fieldInvocationInvalid,
                        "Field binding for a repeated operation requires invocationId.",
                        tool: mapping.tool,
                        operationID: operationID,
                        field: binding.toolField
                    ))
                } else if let invocationID = binding.invocationID,
                          !uses.contains(where: { $0.invocationID == invocationID }) {
                    diagnostics.append(error(
                        .fieldInvocationInvalid,
                        "Field binding references unknown invocationId '\(invocationID)'.",
                        tool: mapping.tool,
                        operationID: operationID,
                        field: binding.toolField
                    ))
                }
            } else if binding.invocationID != nil {
                diagnostics.append(error(
                    .fieldInvocationInvalid,
                    "Local field binding cannot declare invocationId.",
                    tool: mapping.tool,
                    field: binding.toolField
                ))
            }
        }

        for binding in mapping.fields where binding.operationID != nil && binding.location != nil {
            guard let operationID = binding.operationID,
                  claimedOperations.contains(operationID),
                  let operation = operationsByID[operationID],
                  let appleName = binding.appleName,
                  let location = binding.location else {
                diagnostics.append(error(
                    .fieldTargetMissing,
                    "Apple parameter binding is incomplete.",
                    tool: mapping.tool,
                    operationID: binding.operationID,
                    field: binding.toolField
                ))
                continue
            }
            let exists = operation.parameters.contains {
                $0.name == appleName && $0.location.rawValue == location
            }
            if !exists {
                diagnostics.append(error(
                    .fieldTargetMissing,
                    "Apple parameter '\(location):\(appleName)' does not exist on the bound operation.",
                    tool: mapping.tool,
                    operationID: operationID,
                    field: binding.toolField
                ))
            }
        }
        for binding in mapping.fields where binding.operationID != nil && binding.jsonPointer != nil {
            guard let operationID = binding.operationID,
                  claimedOperations.contains(operationID),
                  let operation = operationsByID[operationID],
                  let jsonPointer = binding.jsonPointer,
                  operation.requestBody != nil else {
                diagnostics.append(error(
                    .fieldTargetMissing,
                    "Apple request-body binding is incomplete or targets an operation without a request body.",
                    tool: mapping.tool,
                    operationID: binding.operationID,
                    field: binding.toolField
                ))
                continue
            }
            if !requestBody(operation, contains: jsonPointer, spec: spec) {
                diagnostics.append(error(
                    .fieldTargetMissing,
                    "Request-body JSON pointer '\(jsonPointer)' does not exist on the bound operation.",
                    tool: mapping.tool,
                    operationID: operationID,
                    field: binding.toolField
                ))
            }
        }

        for use in mapping.operations {
            guard let operation = operationsByID[use.operationID] else {
                continue
            }
            for input in use.inputs ?? [] {
                let targetIsParameter = input.location != nil && input.appleName != nil
                let targetIsRequestBody = input.jsonPointer != nil
                let valueIsComplete: Bool
                switch input.sourceKind {
                case .fixed:
                    valueIsComplete = input.fixedValue != nil
                case .derived:
                    valueIsComplete = input.derivedFrom?.isEmpty == false &&
                        input.localRole?.isEmpty == false
                case .parameter, .requestBody, .local:
                    valueIsComplete = false
                }
                if targetIsParameter == targetIsRequestBody || !valueIsComplete {
                    diagnostics.append(error(
                        .fieldTargetMissing,
                        "Invocation input must define one Apple target and a complete fixed or derived value.",
                        tool: mapping.tool,
                        operationID: use.operationID,
                        field: input.appleName ?? input.jsonPointer
                    ))
                    continue
                }
                if targetIsParameter {
                    let exists = operation.parameters.contains {
                        $0.name == input.appleName && $0.location.rawValue == input.location
                    }
                    if !exists {
                        diagnostics.append(error(
                            .fieldTargetMissing,
                            "Invocation input targets an Apple parameter that does not exist.",
                            tool: mapping.tool,
                            operationID: use.operationID,
                            field: input.appleName
                        ))
                    }
                } else if let jsonPointer = input.jsonPointer,
                          !requestBody(operation, contains: jsonPointer, spec: spec) {
                    diagnostics.append(error(
                        .fieldTargetMissing,
                        "Invocation input request-body JSON pointer '\(jsonPointer)' does not exist.",
                        tool: mapping.tool,
                        operationID: use.operationID,
                        field: jsonPointer
                    ))
                }
                if input.sourceKind == .fixed, let fixedValue = input.fixedValue {
                    diagnostics += validateFixedValue(
                        fixedValue,
                        tool: mapping.tool,
                        operation: operation,
                        location: input.location,
                        appleName: input.appleName,
                        jsonPointer: input.jsonPointer,
                        spec: spec
                    )
                }
            }
        }
        for binding in mapping.fields where binding.sourceKind == .fixed {
            guard let operationID = binding.operationID,
                  let operation = operationsByID[operationID],
                  let fixedValue = binding.fixedValue else {
                continue
            }
            diagnostics += validateFixedValue(
                fixedValue,
                tool: mapping.tool,
                operation: operation,
                location: binding.location,
                appleName: binding.appleName,
                jsonPointer: binding.jsonPointer,
                spec: spec
            )
        }
        return diagnostics
    }

    private func validateFixedValue(
        _ fixedValue: ASCJSONValue,
        tool: String,
        operation: ASCOpenAPIOperation,
        location: String?,
        appleName: String?,
        jsonPointer: String?,
        spec: ASCOpenAPISpec
    ) -> [ASCContractDiagnostic] {
        let constraints: [ASCOpenAPIValueConstraint]
        let itemConstraints: [ASCOpenAPIValueConstraint]
        let field: String?
        if let location, let appleName {
            let parameters = operation.parameters.filter {
                $0.location.rawValue == location && $0.name == appleName
            }
            constraints = parameters.flatMap {
                valueConstraints($0.schema, at: "", spec: spec, visited: [])
            }
            itemConstraints = parameters.flatMap {
                valueConstraints($0.schema, at: "/*", spec: spec, visited: [])
            }
            field = appleName
        } else if let jsonPointer, let requestBody = operation.requestBody {
            constraints = requestBody.content.flatMap {
                valueConstraints($0.schema, at: jsonPointer, spec: spec, visited: [])
            }
            itemConstraints = requestBody.content.flatMap {
                valueConstraints($0.schema, at: "\(jsonPointer)/*", spec: spec, visited: [])
            }
            field = jsonPointer
        } else {
            return []
        }

        let allowedTypes = Set(constraints.flatMap(\.types))
        if fixedValue == .null, allowedTypes.contains("null") {
            return []
        }

        let allowedValues = Set(constraints.flatMap(\.enumValues))
        if !allowedValues.isEmpty,
           !allowedValues.contains(fixedValue.canonicalDescription) {
            return [error(
                .fieldFixedValueInvalid,
                "Fixed value '\(fixedValue.canonicalDescription)' is outside the Apple enum [\(allowedValues.sorted().joined(separator: ", "))].",
                tool: tool,
                operationID: operation.operationID,
                field: field
            )]
        }

        if !allowedTypes.isEmpty,
           !allowedTypes.contains(where: { fixedValue.matches(openAPIType: $0) }) {
            return [error(
                .fieldFixedValueInvalid,
                "Fixed value '\(fixedValue.canonicalDescription)' does not match Apple type [\(allowedTypes.sorted().joined(separator: ", "))].",
                tool: tool,
                operationID: operation.operationID,
                field: field
            )]
        }

        if case .array(let values) = fixedValue, !itemConstraints.isEmpty {
            let allowedItemValues = Set(itemConstraints.flatMap(\.enumValues))
            let allowedItemTypes = Set(itemConstraints.flatMap(\.types))
            for (index, value) in values.enumerated() {
                if value == .null, allowedItemTypes.contains("null") {
                    continue
                }
                if !allowedItemValues.isEmpty,
                   !allowedItemValues.contains(value.canonicalDescription) {
                    return [error(
                        .fieldFixedValueInvalid,
                        "Fixed array item \(index) value '\(value.canonicalDescription)' is outside the Apple enum [\(allowedItemValues.sorted().joined(separator: ", "))].",
                        tool: tool,
                        operationID: operation.operationID,
                        field: field
                    )]
                }
                if !allowedItemTypes.isEmpty,
                   !allowedItemTypes.contains(where: { value.matches(openAPIType: $0) }) {
                    return [error(
                        .fieldFixedValueInvalid,
                        "Fixed array item \(index) value '\(value.canonicalDescription)' does not match Apple type [\(allowedItemTypes.sorted().joined(separator: ", "))].",
                        tool: tool,
                        operationID: operation.operationID,
                        field: field
                    )]
                }
            }
        }
        return []
    }

    private func validateOutputSchema(
        _ mapping: ASCToolOperationMapping,
        tool: Tool
    ) -> [ASCContractDiagnostic] {
        if mapping.status == .full && tool.outputSchema == nil {
            return [error(
                .responseMissingSchema,
                "A full mapping requires an MCP outputSchema.",
                tool: mapping.tool
            )]
        }
        return []
    }

    private func validateResponseMapping(
        _ mapping: ASCToolOperationMapping,
        operationsByID: [String: ASCOpenAPIOperation],
        spec: ASCOpenAPISpec,
        waiverIDs: Set<String>
    ) -> [ASCContractDiagnostic] {
        var diagnostics: [ASCContractDiagnostic] = []
        let claimedOperations = Set(mapping.operations.map(\.operationID))
        let sourcedOperations = Set(mapping.response.sources.map(\.operationID))
        let usesByOperationID = Dictionary(grouping: mapping.operations, by: \.operationID)
        for operationID in claimedOperations.subtracting(sourcedOperations).sorted() {
            diagnostics.append(error(
                .responseSourceUnmodeled,
                "Claimed Apple operation has no declared success response source.",
                tool: mapping.tool,
                operationID: operationID
            ))
        }
        for source in mapping.response.sources {
            guard claimedOperations.contains(source.operationID),
                  let operation = operationsByID[source.operationID],
                  let response = operation.responses.first(where: { $0.statusCode == source.statusCode }),
                  response.isSuccess else {
                diagnostics.append(error(
                    .responseSourceMissing,
                    "Declared Apple response source does not exist.",
                    tool: mapping.tool,
                    operationID: source.operationID
                ))
                continue
            }
            if response.content.isEmpty, source.mediaType != nil {
                diagnostics.append(error(
                    .responseSourceMissing,
                    "Contentless Apple success response must not declare a media type.",
                    tool: mapping.tool,
                    operationID: source.operationID
                ))
            } else if !response.content.isEmpty {
                guard let mediaType = source.mediaType else {
                    diagnostics.append(error(
                        .responseSourceMissing,
                        "Contentful Apple success response requires an explicit media type.",
                        tool: mapping.tool,
                        operationID: source.operationID
                    ))
                    continue
                }
                if !response.content.contains(where: { $0.contentType == mediaType }) {
                    diagnostics.append(error(
                        .responseSourceMissing,
                        "Declared Apple response media type '\(mediaType)' does not exist.",
                        tool: mapping.tool,
                        operationID: source.operationID
                    ))
                }
            }
            let uses = usesByOperationID[source.operationID] ?? []
            if uses.count > 1 {
                let expected = Set(uses.compactMap(\.invocationID))
                guard let invocationIDs = source.invocationIDs, !invocationIDs.isEmpty else {
                    diagnostics.append(error(
                        .responseInvocationInvalid,
                        "Response source for a repeated operation requires invocationIds.",
                        tool: mapping.tool,
                        operationID: source.operationID
                    ))
                    continue
                }
                if Set(invocationIDs).count != invocationIDs.count ||
                    !Set(invocationIDs).isSubset(of: expected) {
                    diagnostics.append(error(
                        .responseInvocationInvalid,
                        "Response source contains duplicate or unknown invocationIds.",
                        tool: mapping.tool,
                        operationID: source.operationID
                    ))
                }
            } else if source.invocationIDs != nil {
                diagnostics.append(error(
                    .responseInvocationInvalid,
                    "Response source declares invocationIds for a non-repeated operation.",
                    tool: mapping.tool,
                    operationID: source.operationID
                ))
            }
        }

        for (operationID, uses) in usesByOperationID where uses.count > 1 {
            let expected = Set(uses.compactMap(\.invocationID))
            let covered = Set(mapping.response.sources
                .filter { $0.operationID == operationID }
                .flatMap { $0.invocationIDs ?? [] })
            if covered != expected {
                diagnostics.append(error(
                    .responseInvocationInvalid,
                    "Response sources do not cover every repeated invocation; expected [\(expected.sorted().joined(separator: ", "))].",
                    tool: mapping.tool,
                    operationID: operationID
                ))
            }
        }

        for field in mapping.response.fields {
            let hasLocalSource = field.localRole?.isEmpty == false
            let hasAppleSource = field.operationID != nil && field.jsonPointer != nil
            if !hasLocalSource && !hasAppleSource {
                diagnostics.append(error(
                    .responseFieldInvalid,
                    "Response field must declare an Apple source or a non-empty localRole.",
                    tool: mapping.tool,
                    operationID: field.operationID,
                    field: field.outputField
                ))
                continue
            }
            if field.operationID == nil && field.jsonPointer != nil ||
                field.operationID != nil && field.jsonPointer == nil {
                diagnostics.append(error(
                    .responseFieldInvalid,
                    "Apple response field requires both operationId and jsonPointer.",
                    tool: mapping.tool,
                    operationID: field.operationID,
                    field: field.outputField
                ))
                continue
            }
            guard let operationID = field.operationID,
                  let pointer = field.jsonPointer else {
                continue
            }
            guard claimedOperations.contains(operationID), sourcedOperations.contains(operationID),
                  let operation = operationsByID[operationID] else {
                diagnostics.append(error(
                    .responseFieldInvalid,
                    "Response field references an unclaimed or unsourced Apple operation.",
                    tool: mapping.tool,
                    operationID: operationID,
                    field: field.outputField
                ))
                continue
            }
            let uses = usesByOperationID[operationID] ?? []
            if uses.count > 1 {
                let expected = Set(uses.compactMap(\.invocationID))
                guard let invocationIDs = field.invocationIDs, !invocationIDs.isEmpty,
                      Set(invocationIDs).count == invocationIDs.count,
                      Set(invocationIDs).isSubset(of: expected) else {
                    diagnostics.append(error(
                        .responseInvocationInvalid,
                        "Response field for a repeated operation requires unique known invocationIds.",
                        tool: mapping.tool,
                        operationID: operationID,
                        field: field.outputField
                    ))
                    continue
                }
            } else if field.invocationIDs != nil {
                diagnostics.append(error(
                    .responseInvocationInvalid,
                    "Response field declares invocationIds for a non-repeated operation.",
                    tool: mapping.tool,
                    operationID: operationID,
                    field: field.outputField
                ))
                continue
            }
            let sources = mapping.response.sources.filter {
                $0.operationID == operationID
            }
            let fieldInvocationIDs = field.invocationIDs ?? []
            let pointerExists: Bool
            if fieldInvocationIDs.isEmpty {
                pointerExists = sources.contains {
                    responseSource(
                        $0,
                        contains: pointer,
                        operation: operation,
                        spec: spec
                    )
                }
            } else {
                pointerExists = fieldInvocationIDs.allSatisfy { invocationID in
                    sources
                        .filter { $0.invocationIDs?.contains(invocationID) == true }
                        .contains {
                            responseSource(
                                $0,
                                contains: pointer,
                                operation: operation,
                                spec: spec
                            )
                        }
                }
            }
            if !pointerExists {
                diagnostics.append(error(
                    .responseFieldPointerMissing,
                    "Apple response JSON pointer '\(pointer)' does not exist in a declared success response.",
                    tool: mapping.tool,
                    operationID: operationID,
                    field: field.outputField
                ))
            }
        }

        if let waiverID = mapping.response.waiverID, !waiverIDs.contains(waiverID) {
            diagnostics.append(error(
                .responseWaiverMissing,
                "Response mapping references unknown waiverId '\(waiverID)'.",
                tool: mapping.tool
            ))
        }
        return diagnostics
    }

    private func responseSource(
        _ source: ASCResponseSource,
        contains pointer: String,
        operation: ASCOpenAPIOperation,
        spec: ASCOpenAPISpec
    ) -> Bool {
        guard let mediaType = source.mediaType,
              let response = operation.responses.first(where: {
                  $0.statusCode == source.statusCode
              }),
              let media = response.content.first(where: {
                  $0.contentType == mediaType
              }) else {
            return false
        }
        return responseSchema(media.schema, contains: pointer, spec: spec)
    }

    private func validateOperationCoverage(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        let mapped = Set(manifest.tools.flatMap(\.operations).map(\.operationID))
        return spec.operations.compactMap { operation in
            guard !mapped.contains(operation.operationID),
                  !isWaived(operation, manifest: manifest),
                  !isOutOfScope(operation, manifest: manifest) else {
                return nil
            }
            return error(
                .operationUntriaged,
                "Apple operation is neither mapped nor explicitly deferred/out of scope.",
                operationID: operation.operationID
            )
        }
    }

    private func validateWaivers(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle
    ) -> [ASCContractDiagnostic] {
        var diagnostics = duplicateValues(manifest.index.waivers.map(\.id)).map { waiverID in
            error(
                .waiverDuplicateID,
                "Operation waiver id '\(waiverID)' is duplicated."
            )
        }
        let mappedOperationIDs = Set(manifest.tools.flatMap(\.operations).map(\.operationID))
        var waiverIDsByOperation: [String: [String]] = [:]

        for waiver in manifest.index.waivers {
            let target = waiverTarget(waiver, spec: spec)
            if target == nil {
                diagnostics.append(error(
                    .waiverTargetMissing,
                    "Waiver '\(waiver.id)' must identify exactly one operation in the supplied Apple specification.",
                    operationID: waiver.operationID
                ))
            }
            if let target {
                waiverIDsByOperation[target.operationID, default: []].append(waiver.id)
            }
            if let target, mappedOperationIDs.contains(target.operationID) {
                diagnostics.append(error(
                    .waiverMappedOverlap,
                    "Waiver '\(waiver.id)' targets an operation already mapped by a public tool.",
                    operationID: target.operationID
                ))
            }
            if let target,
               manifest.index.scopeRules.contains(where: {
                   target.path.hasPrefix($0.pathPrefix)
               }) {
                diagnostics.append(error(
                    .waiverScopeOverlap,
                    "Waiver '\(waiver.id)' targets an operation already covered by an out-of-scope rule.",
                    operationID: target.operationID
                ))
            }

            if compareVersions(waiver.reviewAtSpec, spec.version) < 0 {
                diagnostics.append(error(
                    .waiverExpired,
                    "Waiver '\(waiver.id)' expired at Apple spec \(waiver.reviewAtSpec).",
                    operationID: waiver.operationID
                ))
            }
        }
        for (operationID, waiverIDs) in waiverIDsByOperation where waiverIDs.count > 1 {
            diagnostics.append(error(
                .waiverTargetOverlap,
                "Operation is covered by multiple waivers: \(waiverIDs.sorted().joined(separator: ", ")).",
                operationID: operationID
            ))
        }

        for rule in manifest.index.scopeRules where compareVersions(rule.reviewAtSpec, spec.version) < 0 {
            diagnostics.append(error(
                .scopeRuleExpired,
                "Scope rule '\(rule.pathPrefix)' expired at Apple spec \(rule.reviewAtSpec)."
            ))
        }
        for rule in manifest.index.scopeRules where rule.disposition != .outOfScope {
            diagnostics.append(error(
                .scopeRuleInvalidDisposition,
                "Scope rule '\(rule.pathPrefix)' must use the outOfScope disposition."
            ))
        }
        for operation in spec.operations where mappedOperationIDs.contains(operation.operationID) {
            for rule in manifest.index.scopeRules where operation.path.hasPrefix(rule.pathPrefix) {
                diagnostics.append(error(
                    .scopeRuleMappedOverlap,
                    "Mapped operation is also covered by out-of-scope rule '\(rule.pathPrefix)'.",
                    operationID: operation.operationID
                ))
            }
        }
        for operation in spec.operations {
            let matchingRules = manifest.index.scopeRules.filter {
                operation.path.hasPrefix($0.pathPrefix)
            }
            if matchingRules.count > 1 {
                diagnostics.append(error(
                    .scopeRuleOverlap,
                    "Operation is covered by multiple scope rules: \(matchingRules.map(\.pathPrefix).sorted().joined(separator: ", ")).",
                    operationID: operation.operationID
                ))
            }
        }
        return diagnostics
    }

    private func waiverTarget(
        _ waiver: ASCOperationWaiver,
        spec: ASCOpenAPISpec
    ) -> ASCOpenAPIOperation? {
        if let operationID = waiver.operationID,
           waiver.method == nil,
           waiver.path == nil {
            return spec.operation(id: operationID)
        }
        if waiver.operationID == nil,
           let method = waiver.method,
           let path = waiver.path {
            return spec.operation(method: method, path: path)
        }
        return nil
    }

    private func isWaived(
        _ operation: ASCOpenAPIOperation,
        manifest: ASCOperationManifestBundle
    ) -> Bool {
        manifest.index.waivers.contains { waiver in
            if waiver.operationID == operation.operationID {
                return true
            }
            if let method = waiver.method, let path = waiver.path {
                return method.lowercased() == operation.method && path == operation.path
            }
            return false
        }
    }

    private func isOutOfScope(
        _ operation: ASCOpenAPIOperation,
        manifest: ASCOperationManifestBundle
    ) -> Bool {
        manifest.index.scopeRules.contains { rule in
            operation.path.hasPrefix(rule.pathPrefix)
        }
    }

    private func inputPropertyNames(_ schema: Value) -> Set<String> {
        guard case .object(let object) = schema,
              case .object(let properties)? = object["properties"] else {
            return []
        }
        return Set(properties.keys)
    }

    private func requiredRequestBodyPointers(
        _ operation: ASCOpenAPIOperation,
        spec: ASCOpenAPISpec
    ) -> [String] {
        guard let requestBody = operation.requestBody else {
            return []
        }
        return Set(requestBody.content.flatMap { media in
            requiredPointers(
                media.schema,
                spec: spec,
                prefix: "",
                visited: []
            )
        }).sorted()
    }

    private func requiredPointers(
        _ summary: ASCOpenAPISchemaSummary,
        spec: ASCOpenAPISpec,
        prefix: String,
        visited: Set<String>
    ) -> [String] {
        var pointers = summary.requiredPropertyPointers.map { prefixed($0, by: prefix) }
        for referencePointer in summary.requiredReferencePointers {
            let reference = referencePointer.reference
            guard reference.hasPrefix("#/components/schemas/") else {
                continue
            }
            let encodedName = String(reference.dropFirst("#/components/schemas/".count))
            let name = encodedName.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            let nextPrefix = prefixed(referencePointer.pointer, by: prefix)
            guard !visited.contains(name), let referenced = spec.schemas[name] else {
                continue
            }
            var nextVisited = visited
            nextVisited.insert(name)
            pointers += requiredPointers(
                referenced,
                spec: spec,
                prefix: nextPrefix,
                visited: nextVisited
            )
        }
        return pointers
    }

    private func prefixed(_ pointer: String, by prefix: String) -> String {
        if prefix.isEmpty {
            return pointer
        }
        if pointer.isEmpty {
            return prefix
        }
        return "\(prefix)\(pointer)"
    }

    private func pointer(_ binding: String, covers required: String) -> Bool {
        let normalized = binding.hasPrefix("#") ? String(binding.dropFirst()) : binding
        return normalized == "/" ||
            normalized == required ||
            normalized.hasPrefix("\(required)/") ||
            required.hasPrefix("\(normalized)/")
    }

    private func requestBody(
        _ operation: ASCOpenAPIOperation,
        contains rawPointer: String,
        spec: ASCOpenAPISpec
    ) -> Bool {
        guard let requestBody = operation.requestBody else {
            return false
        }
        let pointer = rawPointer.hasPrefix("#") ? String(rawPointer.dropFirst()) : rawPointer
        if pointer == "" || pointer == "/" {
            return true
        }
        return requestBody.content.contains { mediaType in
            schema(mediaType.schema, contains: pointer, spec: spec, visited: [])
        }
    }

    private func responseSchema(
        _ summary: ASCOpenAPISchemaSummary,
        contains rawPointer: String,
        spec: ASCOpenAPISpec
    ) -> Bool {
        let pointer = rawPointer.hasPrefix("#") ? String(rawPointer.dropFirst()) : rawPointer
        if pointer == "" || pointer == "/" {
            return true
        }
        return schema(summary, contains: pointer, spec: spec, visited: [])
    }

    private func schema(
        _ summary: ASCOpenAPISchemaSummary,
        contains pointer: String,
        spec: ASCOpenAPISpec,
        visited: Set<String>
    ) -> Bool {
        if summary.propertyPointers.contains(pointer) {
            return true
        }

        for referencePointer in summary.referencePointers {
            let reference = referencePointer.reference
            guard reference.hasPrefix("#/components/schemas/") else {
                continue
            }
            let prefix = referencePointer.pointer
            let relativePointer: String
            if prefix.isEmpty {
                relativePointer = pointer
            } else if pointer == prefix {
                return true
            } else if pointer.hasPrefix("\(prefix)/") {
                relativePointer = String(pointer.dropFirst(prefix.count))
            } else {
                continue
            }
            let encodedName = String(reference.dropFirst("#/components/schemas/".count))
            let name = encodedName.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard !visited.contains(name), let referenced = spec.schemas[name] else {
                continue
            }
            var nextVisited = visited
            nextVisited.insert(name)
            if schema(referenced, contains: relativePointer, spec: spec, visited: nextVisited) {
                return true
            }
        }
        return false
    }

    private func valueConstraints(
        _ summary: ASCOpenAPISchemaSummary,
        at rawPointer: String,
        spec: ASCOpenAPISpec,
        visited: Set<String>
    ) -> [ASCOpenAPIValueConstraint] {
        let pointer = rawPointer.hasPrefix("#") ? String(rawPointer.dropFirst()) : rawPointer
        var constraints = summary.valueConstraints[pointer].map { [$0] } ?? []

        for referencePointer in summary.referencePointers {
            let reference = referencePointer.reference
            guard reference.hasPrefix("#/components/schemas/") else {
                continue
            }
            let prefix = referencePointer.pointer
            let relativePointer: String
            if prefix.isEmpty {
                relativePointer = pointer
            } else if pointer == prefix {
                relativePointer = ""
            } else if pointer.hasPrefix("\(prefix)/") {
                relativePointer = String(pointer.dropFirst(prefix.count))
            } else {
                continue
            }
            let encodedName = String(reference.dropFirst("#/components/schemas/".count))
            let name = encodedName.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard !visited.contains(name), let referenced = spec.schemas[name] else {
                continue
            }
            var nextVisited = visited
            nextVisited.insert(name)
            constraints += valueConstraints(
                referenced,
                at: relativePointer,
                spec: spec,
                visited: nextVisited
            )
        }
        return constraints
    }

    private func duplicateValues(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private func fieldBindingIdentity(_ binding: ASCToolFieldBinding) -> String {
        [
            binding.toolField,
            binding.sourceKind.rawValue,
            binding.operationID ?? "",
            binding.invocationID ?? "",
            binding.location ?? "",
            binding.appleName ?? "",
            binding.jsonPointer ?? "",
            binding.localRole ?? "",
            binding.fixedValue?.canonicalIdentity ?? "",
            binding.derivedFrom?.joined(separator: ",") ?? "",
            binding.omissionReason ?? ""
        ].joined(separator: "\u{1F}")
    }

    private func fieldBinding(
        _ binding: ASCToolFieldBinding,
        appliesTo use: ASCOperationUse
    ) -> Bool {
        guard binding.operationID == use.operationID else {
            return false
        }
        return binding.invocationID == nil || binding.invocationID == use.invocationID
    }

    private func operationDictionary(_ operations: [ASCOpenAPIOperation]) -> [String: ASCOpenAPIOperation] {
        operations.reduce(into: [String: ASCOpenAPIOperation]()) { result, operation in
            if result[operation.operationID] == nil {
                result[operation.operationID] = operation
            }
        }
    }

    private func sorted(_ diagnostics: [ASCContractDiagnostic]) -> [ASCContractDiagnostic] {
        var seen: Set<String> = []
        return diagnostics.sorted { lhs, rhs in
            let lhsKey = [lhs.severity.rawValue, lhs.code.rawValue, lhs.tool ?? "", lhs.operationID ?? "", lhs.field ?? "", lhs.message]
            let rhsKey = [rhs.severity.rawValue, rhs.code.rawValue, rhs.tool ?? "", rhs.operationID ?? "", rhs.field ?? "", rhs.message]
            return lhsKey.lexicographicallyPrecedes(rhsKey)
        }.filter { diagnostic in
            let key = [
                diagnostic.severity.rawValue,
                diagnostic.code.rawValue,
                diagnostic.tool ?? "",
                diagnostic.operationID ?? "",
                diagnostic.field ?? "",
                diagnostic.message
            ].joined(separator: "\u{1F}")
            return seen.insert(key).inserted
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue != rightValue {
                return leftValue < rightValue ? -1 : 1
            }
        }
        return 0
    }

    private func error(
        _ code: ASCContractDiagnosticCode,
        _ message: String,
        tool: String? = nil,
        operationID: String? = nil,
        field: String? = nil
    ) -> ASCContractDiagnostic {
        ASCContractDiagnostic(
            severity: .error,
            code: code,
            message: message,
            tool: tool,
            operationID: operationID,
            field: field
        )
    }

    private func warning(
        _ code: ASCContractDiagnosticCode,
        _ message: String,
        tool: String? = nil,
        operationID: String? = nil,
        field: String? = nil
    ) -> ASCContractDiagnostic {
        ASCContractDiagnostic(
            severity: .warning,
            code: code,
            message: message,
            tool: tool,
            operationID: operationID,
            field: field
        )
    }
}
