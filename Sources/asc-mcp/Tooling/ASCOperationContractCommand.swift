import Foundation

enum ASCOperationContractCommand {
    /// Run the strict operation-contract command when requested by command-line arguments.
    /// - Parameter arguments: Full command-line argument list including executable path.
    /// - Returns: `true` when the command was handled and the MCP server should not start.
    /// - Throws: File, parse, manifest, or strict contract errors.
    static func runIfRequested(arguments: [String]) async throws -> Bool {
        let args = Array(arguments.dropFirst())
        guard args.first == "openapi-contract-check" else {
            return false
        }

        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return true
        }

        guard let specPath = value(after: "--spec", in: args) else {
            throw ASCOperationContractCommandError.missingRequiredFlag("--spec")
        }

        let specData = try Data(contentsOf: fileURL(from: specPath))
        let spec = try ASCOpenAPISpec.parse(specData)
        let manifest: ASCOperationManifestBundle
        if let manifestPath = value(after: "--manifest", in: args) {
            manifest = try ASCOperationManifestBundle.load(from: fileURL(from: manifestPath))
        } else {
            manifest = try ASCOperationManifestBundle.loadBundled()
        }

        let workerSnapshots = try await ASCToolCatalogFactory.collectWorkerToolSnapshots().map { snapshot in
            ASCWorkerToolSnapshot(
                key: snapshot.key,
                readmeName: snapshot.readmeName,
                tools: snapshot.tools.map(ToolMetadataPolicy.apply)
            )
        }
        let publicToolCount = workerSnapshots.flatMap(\.tools).count
        let diagnostics = ASCOperationToolAnalyzer().analyze(
            spec: spec,
            manifest: manifest,
            workerSnapshots: workerSnapshots
        )
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        let warningCount = diagnostics.filter { $0.severity == .warning }.count
        let implementationDriftCount = diagnostics.filter {
            $0.severity == .error && $0.code == .toolImplementationDrift
        }.count
        let structuralErrorCount = diagnostics.filter {
            $0.severity == .error && $0.code != .toolImplementationDrift
        }.count
        let unresolvedCount = manifest.tools.filter { $0.status == .unresolved }.count
        let fullCount = manifest.tools.filter { $0.status == .full }.count
        let partialCount = manifest.tools.filter { $0.status == .partial }.count
        let deprecatedCount = manifest.tools.filter { $0.status == .deprecated }.count
        let mappedOperationIDs = Set(manifest.tools.flatMap(\.operations).map(\.operationID))
        let mappedOperationCount = mappedOperationIDs.count
        let waivedOperations = spec.operations.filter { operation in
            !mappedOperationIDs.contains(operation.operationID) &&
                manifest.index.waivers.contains {
                    Self.waiver($0, matches: operation)
                }
        }
        let waivedOperationCount = waivedOperations.count
        let deferredWaiverCount = waivedOperations.filter { operation in
            manifest.index.waivers.contains {
                $0.disposition == .deferred && Self.waiver($0, matches: operation)
            }
        }.count
        let unsupportedWaiverCount = waivedOperations.filter { operation in
            manifest.index.waivers.contains {
                $0.disposition == .unsupported && Self.waiver($0, matches: operation)
            }
        }.count
        let outOfScopeWaiverCount = waivedOperations.filter { operation in
            manifest.index.waivers.contains {
                $0.disposition == .outOfScope && Self.waiver($0, matches: operation)
            }
        }.count
        let scopedOperationCount = spec.operations.filter { operation in
            !mappedOperationIDs.contains(operation.operationID) &&
            manifest.index.scopeRules.contains { operation.path.hasPrefix($0.pathPrefix) }
        }.count

        if let outputPath = value(after: "--json-output", in: args) {
            let output = ASCOperationContractJSONReport(
                specVersion: spec.version,
                specSHA256: spec.sha256,
                pathCount: spec.paths.count,
                operationCount: spec.operations.count,
                manifestToolCount: manifest.tools.count,
                publicToolCount: publicToolCount,
                workerCount: workerSnapshots.count,
                fullToolCount: fullCount,
                partialToolCount: partialCount,
                deprecatedToolCount: deprecatedCount,
                unresolvedToolCount: unresolvedCount,
                mappedOperationCount: mappedOperationCount,
                waivedOperationCount: waivedOperationCount,
                deferredWaiverCount: deferredWaiverCount,
                unsupportedWaiverCount: unsupportedWaiverCount,
                outOfScopeWaiverCount: outOfScopeWaiverCount,
                scopedOperationCount: scopedOperationCount,
                errorCount: errorCount,
                structuralErrorCount: structuralErrorCount,
                implementationDriftCount: implementationDriftCount,
                warningCount: warningCount,
                diagnostics: diagnostics
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(output)
            try write(data, to: fileURL(from: outputPath))
        }

        if let outputPath = value(after: "--markdown-output", in: args) {
            let markdown = renderMarkdown(
                spec: spec,
                manifest: manifest,
                publicToolCount: publicToolCount,
                workerCount: workerSnapshots.count,
                mappedOperationCount: mappedOperationCount,
                waivedOperationCount: waivedOperationCount,
                deferredWaiverCount: deferredWaiverCount,
                unsupportedWaiverCount: unsupportedWaiverCount,
                outOfScopeWaiverCount: outOfScopeWaiverCount,
                scopedOperationCount: scopedOperationCount,
                diagnostics: diagnostics
            )
            try write(Data(markdown.utf8), to: fileURL(from: outputPath))
        }

        print(
            "Operation contract \(spec.version): \(publicToolCount) public tools, \(mappedOperationCount) mapped, \(waivedOperationCount) waived (\(deferredWaiverCount) deferred, \(unsupportedWaiverCount) unsupported, \(outOfScopeWaiverCount) exact out of scope), \(scopedOperationCount) scope-rule out of scope, \(structuralErrorCount) structural errors, \(implementationDriftCount) implementation drift, \(warningCount) warnings",
            to: &standardError
        )

        if args.contains("--strict"), errorCount > 0 {
            throw ASCOperationContractCommandError.contractFailed(errorCount)
        }
        if args.contains("--structural-strict"), structuralErrorCount > 0 {
            throw ASCOperationContractCommandError.contractFailed(structuralErrorCount)
        }
        return true
    }

    private static func renderMarkdown(
        spec: ASCOpenAPISpec,
        manifest: ASCOperationManifestBundle,
        publicToolCount: Int,
        workerCount: Int,
        mappedOperationCount: Int,
        waivedOperationCount: Int,
        deferredWaiverCount: Int,
        unsupportedWaiverCount: Int,
        outOfScopeWaiverCount: Int,
        scopedOperationCount: Int,
        diagnostics: [ASCContractDiagnostic]
    ) -> String {
        var lines = [
            "# App Store Connect Operation Contract",
            "",
            "Apple API: \(spec.version)",
            "",
            "Apple spec SHA-256: `\(spec.sha256)`",
            "",
            "Public tools: \(publicToolCount)",
            "",
            "Manifest tools: \(manifest.tools.count)",
            "",
            "Workers: \(workerCount)",
            "",
            "Tool mapping status: \(manifest.tools.filter { $0.status == .full }.count) full, \(manifest.tools.filter { $0.status == .partial }.count) partial, \(manifest.tools.filter { $0.status == .deprecated }.count) deprecated, \(manifest.tools.filter { $0.status == .unresolved }.count) unresolved",
            "",
            "Mapped Apple operations: \(mappedOperationCount) / \(spec.operations.count)",
            "",
            "Waived Apple operations: \(waivedOperationCount)",
            "",
            "Waiver dispositions: \(deferredWaiverCount) deferred, \(unsupportedWaiverCount) unsupported, \(outOfScopeWaiverCount) exact out of scope",
            "",
            "Scope-rule out-of-scope Apple operations: \(scopedOperationCount)",
            "",
            "Errors: \(diagnostics.filter { $0.severity == .error }.count)",
            "",
            "Structural errors: \(diagnostics.filter { $0.severity == .error && $0.code != .toolImplementationDrift }.count)",
            "",
            "Known implementation drift: \(diagnostics.filter { $0.severity == .error && $0.code == .toolImplementationDrift }.count)",
            "",
            "Warnings: \(diagnostics.filter { $0.severity == .warning }.count)",
            "",
            "| Severity | Code | Tool | Operation | Field | Message |",
            "|---|---|---|---|---|---|"
        ]

        for diagnostic in diagnostics {
            lines.append([
                diagnostic.severity.rawValue,
                diagnostic.code.rawValue,
                diagnostic.tool ?? "",
                diagnostic.operationID ?? "",
                diagnostic.field ?? "",
                diagnostic.message
            ]
            .map { escapeMarkdownCell($0) }
            .joined(separator: " | ")
            .withTableDelimiters)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func escapeMarkdownCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func printUsage() {
        print(
            """
            Usage:
              asc-mcp openapi-contract-check --spec /path/to/openapi.oas.json [options]

            Options:
              --manifest PATH          OperationManifest directory. Uses the bundled manifest by default.
              --json-output PATH       Write a machine-readable diagnostics report.
              --markdown-output PATH   Write a review-friendly Markdown report.
              --structural-strict      Fail on contract errors other than declared target/broken implementations.
              --strict                 Exit with failure when any error diagnostic exists.
            """
        )
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    private static func waiver(
        _ waiver: ASCOperationWaiver,
        matches operation: ASCOpenAPIOperation
    ) -> Bool {
        waiver.operationID == operation.operationID ||
            (waiver.operationID == nil &&
                waiver.method?.lowercased() == operation.method &&
                waiver.path == operation.path)
    }

    private static func fileURL(from path: String) -> URL {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}

private struct ASCOperationContractJSONReport: Codable {
    let specVersion: String
    let specSHA256: String
    let pathCount: Int
    let operationCount: Int
    let manifestToolCount: Int
    let publicToolCount: Int
    let workerCount: Int
    let fullToolCount: Int
    let partialToolCount: Int
    let deprecatedToolCount: Int
    let unresolvedToolCount: Int
    let mappedOperationCount: Int
    let waivedOperationCount: Int
    let deferredWaiverCount: Int
    let unsupportedWaiverCount: Int
    let outOfScopeWaiverCount: Int
    let scopedOperationCount: Int
    let errorCount: Int
    let structuralErrorCount: Int
    let implementationDriftCount: Int
    let warningCount: Int
    let diagnostics: [ASCContractDiagnostic]
}

private extension String {
    var withTableDelimiters: String {
        "| \(self) |"
    }
}

enum ASCOperationContractCommandError: Error, LocalizedError, Equatable {
    case missingRequiredFlag(String)
    case contractFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingRequiredFlag(let flag):
            "Missing required flag: \(flag). Run `asc-mcp openapi-contract-check --help` for usage."
        case .contractFailed(let count):
            "Operation contract check failed with \(count) error diagnostics."
        }
    }
}
