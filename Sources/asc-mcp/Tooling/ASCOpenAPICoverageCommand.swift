import Foundation

enum ASCOpenAPICoverageCommand {
    /// Run the OpenAPI coverage command if requested by command-line arguments.
    /// - Parameter arguments: Full command-line argument list including executable path.
    /// - Returns: `true` when the command was handled and the MCP server should not start.
    /// - Throws: File, parse, or argument errors surfaced to the CLI.
    static func runIfRequested(arguments: [String]) throws -> Bool {
        let args = Array(arguments.dropFirst())
        guard args.first == "openapi-coverage" else {
            return false
        }

        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return true
        }

        guard let specPath = value(after: "--spec", in: args) else {
            throw ASCOpenAPICoverageCommandError.missingRequiredFlag("--spec")
        }

        let outputPath = value(after: "--output", in: args) ?? "ASC-OPENAPI-COVERAGE-GENERATED.md"
        let generatedAt = value(after: "--generated-at", in: args) ?? Self.defaultGeneratedDate()
        let maxExamples = Int(value(after: "--max-unclassified-examples", in: args) ?? "") ?? 80

        let specURL = fileURL(from: specPath)
        let outputURL = fileURL(from: outputPath)
        let data = try Data(contentsOf: specURL)
        let spec = try ASCOpenAPISpec.parse(data)
        let report = ASCOpenAPICoverageAnalyzer(rules: ASCOpenAPICoverageRules.defaultRules)
            .analyze(spec: spec, generatedAt: generatedAt)
        let markdown = ASCOpenAPICoverageMarkdownRenderer.render(
            report,
            maxUnclassifiedExamples: maxExamples
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)

        print("Generated OpenAPI coverage report: \(outputURL.path)", to: &standardError)
        print("Spec \(spec.version): \(spec.paths.count) paths, \(spec.operations.count) operations", to: &standardError)
        print("Unclassified paths: \(report.unclassifiedPathCount)", to: &standardError)
        return true
    }

    private static func printUsage() {
        print(
            """
            Usage:
              asc-mcp openapi-coverage --spec /path/to/openapi.oas.json [--output ASC-OPENAPI-COVERAGE-GENERATED.md]

            Options:
              --spec PATH                         Extracted Apple openapi.oas.json file.
              --output PATH                       Markdown output path. Defaults to ASC-OPENAPI-COVERAGE-GENERATED.md.
              --generated-at YYYY-MM-DD           Fixed report date for reproducible docs.
              --max-unclassified-examples NUMBER  Cap unclassified path examples. Defaults to 80.

            Apple spec download:
              curl -L --fail -o /tmp/asc-openapi/spec.zip https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
              unzip -q /tmp/asc-openapi/spec.zip -d /tmp/asc-openapi
            """
        )
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    private static func fileURL(from path: String) -> URL {
        let expandedPath: String
        if path == "~" {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("~/") {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        } else {
            expandedPath = path
        }
        return URL(fileURLWithPath: expandedPath)
    }

    private static func defaultGeneratedDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
    }
}

enum ASCOpenAPICoverageCommandError: Error, LocalizedError, Equatable {
    case missingRequiredFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredFlag(let flag):
            "Missing required flag: \(flag). Run `asc-mcp openapi-coverage --help` for usage."
        }
    }
}
