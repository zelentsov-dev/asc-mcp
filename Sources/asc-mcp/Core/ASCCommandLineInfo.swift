enum ASCCommandLineInfo {
    static func output(arguments: [String]) -> String? {
        guard arguments.count > 1 else {
            return nil
        }

        switch arguments[1] {
        case "--version", "-V", "version":
            return "asc-mcp \(ServerVersion.current)"
        case "--help", "-h", "help":
            return usage
        default:
            return nil
        }
    }

    private static var usage: String {
        let workers = WorkerManager.validWorkerFilterKeys.sorted().joined(separator: ",")
        return """
        Usage:
          asc-mcp [--companies PATH] [--workers LIST] [--read-only]
          asc-mcp openapi-contract-check --spec PATH [options]
          asc-mcp openapi-coverage --spec PATH --output PATH [options]

        Options:
          --companies PATH   Load App Store Connect companies from a JSON file.
          --workers LIST     Enable a comma-separated worker subset plus company and auth.
          --read-only        Block App Store Connect mutation tools.
          --version, -V      Print the asc-mcp version without loading credentials.
          --help, -h         Show this help without loading credentials.

        Workers:
          \(workers)
        """
    }
}
