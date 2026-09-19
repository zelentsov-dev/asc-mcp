import Foundation

/// Runtime options selected at process startup.
public struct AppRuntimeOptions: Sendable {
    /// Worker keys enabled through `--workers`; `nil` means all workers are available.
    public let enabledWorkers: Set<String>?
    /// Blocks App Store Connect mutation tools while keeping read-only inspection tools available.
    public let readOnlyMode: Bool
    /// Exposes only the bounded Code Mode discovery and execution tools.
    public let codeMode: Bool

    /// Creates runtime options for the MCP server process.
    /// - Parameters:
    ///   - enabledWorkers: Worker keys enabled through `--workers`; `nil` means all workers are available.
    ///   - readOnlyMode: Whether mutation tools should be blocked before handler execution.
    ///   - codeMode: Whether to replace the domain catalog with Code Mode tools.
    public init(enabledWorkers: Set<String>? = nil, readOnlyMode: Bool = false, codeMode: Bool = false) {
        self.enabledWorkers = enabledWorkers
        self.readOnlyMode = readOnlyMode
        self.codeMode = codeMode
    }
}
