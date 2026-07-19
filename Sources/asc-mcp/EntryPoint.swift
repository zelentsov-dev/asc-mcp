import Foundation
import MCP

@main
struct ASCMCPApp {
    static func main() async throws {
        if let output = ASCCommandLineInfo.output(arguments: CommandLine.arguments) {
            print(output)
            return
        }

        do {
            if try await ASCOperationContractCommand.runIfRequested(arguments: CommandLine.arguments) {
                return
            }
            if try ASCOpenAPICoverageCommand.runIfRequested(arguments: CommandLine.arguments) {
                return
            }
        } catch {
            print("OpenAPI tooling error: \(error.localizedDescription)", to: &standardError)
            exit(1)
        }

        #if DEBUG
        if CommandLine.arguments.contains("--test") {
            print("Test mode activated", to: &standardError)

            if CommandLine.arguments.contains("--test-metadata") {
                try await testAppMetadata()
            } else if CommandLine.arguments.contains("--test-switch") {
                try await testCompanySwitching()
            } else {
                try await testCompanySwitching()
            }
            return
        }
        #endif

        // Parse runtime flags for tool filtering and safe read-only operation.
        let runtimeOptions = parseRuntimeOptions()

        do {
            try await runApplication(options: runtimeOptions)
        } catch let error as CompanyError {
            print("Error loading companies: \(error.errorDescription ?? error.localizedDescription)", to: &standardError)
            exit(1)
        } catch let error as ASCError {
            print("App Store Connect error: \(error.errorDescription ?? error.localizedDescription)", to: &standardError)
            exit(1)
        } catch {
            print("Error: \(error.localizedDescription)", to: &standardError)
            exit(1)
        }
    }

    /// Parse supported command line runtime options.
    /// - Returns: Runtime options used to configure the MCP server.
    private static func parseRuntimeOptions() -> AppRuntimeOptions {
        let enabledWorkers = parseWorkersFlag()
        let readOnlyMode = CommandLine.arguments.contains("--read-only")

        if readOnlyMode {
            print("🔒 Read-only mode enabled: App Store Connect mutation tools will be blocked", to: &standardError)
        }

        return AppRuntimeOptions(enabledWorkers: enabledWorkers, readOnlyMode: readOnlyMode)
    }

    /// Parse --workers flag from command line arguments.
    /// - Returns: Set of enabled worker names, or nil if flag not provided (all workers enabled).
    private static func parseWorkersFlag() -> Set<String>? {
        guard let index = CommandLine.arguments.firstIndex(of: "--workers"),
              index + 1 < CommandLine.arguments.count else {
            return nil
        }

        let validWorkers = WorkerManager.validWorkerFilterKeys

        let requested = CommandLine.arguments[index + 1]
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        // Always include core workers
        var enabled: Set<String> = ["company", "auth"]
        for name in requested {
            if validWorkers.contains(name) {
                enabled.insert(name)
            } else {
                print("⚠️ Unknown worker: '\(name)'. Valid: \(validWorkers.sorted().joined(separator: ", "))", to: &standardError)
            }
        }

        print("🔧 Enabled workers: \(enabled.sorted().joined(separator: ", "))", to: &standardError)
        return enabled
    }
}
