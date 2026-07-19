import Testing
@testable import asc_mcp

@Suite("ASC Command Line Info Tests")
struct ASCCommandLineInfoTests {
    @Test("version commands do not require server configuration")
    func versionCommands() {
        for command in ["--version", "-V", "version"] {
            #expect(
                ASCCommandLineInfo.output(arguments: ["asc-mcp", command]) ==
                    "asc-mcp \(ServerVersion.current)"
            )
        }
    }

    @Test("root help documents runtime options and every worker")
    func rootHelp() throws {
        let output = try #require(
            ASCCommandLineInfo.output(arguments: ["asc-mcp", "--help"])
        )

        #expect(output.contains("--companies PATH"))
        #expect(output.contains("--workers LIST"))
        #expect(output.contains("--read-only"))
        for worker in WorkerManager.validWorkerFilterKeys {
            #expect(output.contains(worker))
        }
    }

    @Test("subcommand help remains owned by the subcommand")
    func subcommandHelp() {
        #expect(
            ASCCommandLineInfo.output(
                arguments: ["asc-mcp", "openapi-contract-check", "--help"]
            ) == nil
        )
        #expect(
            ASCCommandLineInfo.output(arguments: ["asc-mcp", "--read-only"]) == nil
        )
    }
}
