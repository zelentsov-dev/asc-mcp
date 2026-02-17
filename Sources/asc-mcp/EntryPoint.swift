import Foundation
import MCP

@main
struct ASCMCPApp {
    static func main() async throws {
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

        // Parse --workers flag for tool filtering (e.g. --workers apps,builds,versions)
        let enabledWorkers = parseWorkersFlag()

        do {
            try await runApplication(enabledWorkers: enabledWorkers)
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

    /// Parse --workers flag from command line arguments
    /// - Returns: Set of enabled worker names, or nil if flag not provided (all workers enabled)
    private static func parseWorkersFlag() -> Set<String>? {
        guard let index = CommandLine.arguments.firstIndex(of: "--workers"),
              index + 1 < CommandLine.arguments.count else {
            return nil
        }

        let validWorkers: Set<String> = [
            "company", "auth", "apps", "builds", "build_processing", "build_beta",
            "versions", "reviews", "beta_groups", "beta_testers", "iap",
            "provisioning", "app_info", "pricing", "users", "app_events", "analytics"
        ]

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
