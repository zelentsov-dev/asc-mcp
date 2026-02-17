import Foundation

/// Manager for handling multiple companies
public actor CompaniesManager {
    public let config: CompaniesConfig
    private var currentCompany: Company?
    /// Source description (e.g. file path or "environment variables")
    public let configSource: String

    public init(configPath: String? = nil) throws {
        // 1. CLI argument: --companies /path
        let args = ProcessInfo.processInfo.arguments
        var configFilePath: String? = nil

        if let index = args.firstIndex(of: "--companies"), index + 1 < args.count {
            configFilePath = args[index + 1]
        }

        // 2. Constructor parameter
        if configFilePath == nil {
            configFilePath = configPath
        }

        // 3. Environment variable: path to JSON
        if configFilePath == nil {
            configFilePath = ProcessInfo.processInfo.environment["ASC_MCP_COMPANIES"]
        }

        // 4. Try loading from JSON file (explicit path or default locations)
        if let loaded = Self.loadFromFile(explicitPath: configFilePath) {
            print("✅ Loaded config from: \(loaded.path)", to: &standardError)
            self.configSource = loaded.path
            self.config = loaded.config
            if !config.companies.isEmpty {
                self.currentCompany = config.companies[0]
            }
            return
        }

        // 5. If no explicit path was given, try environment variables
        if configFilePath == nil, let envConfig = Self.loadFromEnvironment() {
            print("✅ Loaded config from environment variables", to: &standardError)
            self.configSource = "environment variables"
            self.config = envConfig
            if !config.companies.isEmpty {
                self.currentCompany = config.companies[0]
            }
            return
        }

        // Nothing found — show help
        let searchedPaths = configFilePath.map { [$0] } ?? Self.defaultPaths()
        print("❌ Failed to load configuration", to: &standardError)
        print("", to: &standardError)
        if !searchedPaths.isEmpty {
            print("Searched files:", to: &standardError)
            for path in searchedPaths {
                print("   • \(path)", to: &standardError)
            }
            print("", to: &standardError)
        }
        print("You can configure asc-mcp using:", to: &standardError)
        print("  1. Environment variables (single company):", to: &standardError)
        print("     ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (or ASC_PRIVATE_KEY)", to: &standardError)
        print("  2. Environment variables (multiple companies):", to: &standardError)
        print("     ASC_COMPANY_1_KEY_ID, ASC_COMPANY_1_ISSUER_ID, ASC_COMPANY_1_KEY_PATH, ...", to: &standardError)
        print("  3. Config file: --companies /path/to/companies.json", to: &standardError)
        print("  4. Environment: ASC_MCP_COMPANIES=/path/to/companies.json", to: &standardError)
        print("  5. Default path: ~/.config/asc-mcp/companies.json", to: &standardError)
        throw CompanyError.configFileNotFound
    }

    // MARK: - File-based loading

    private static func defaultPaths() -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(homeDir)/.config/asc-mcp/companies.json",
            "\(homeDir)/Library/Application Support/asc-mcp/companies.json",
            "companies.json",
        ]
    }

    private static func loadFromFile(explicitPath: String?) -> (config: CompaniesConfig, path: String)? {
        let paths: [String]
        if let explicit = explicitPath {
            paths = [explicit]
        } else {
            paths = defaultPaths()
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(CompaniesConfig.self, from: data) else {
                continue
            }
            return (config, path)
        }
        return nil
    }

    // MARK: - Environment-based loading

    /// Load company configuration from environment variables.
    ///
    /// Priority:
    /// 1. Multi-company: ASC_COMPANY_1_KEY_ID, ASC_COMPANY_2_KEY_ID, ...
    /// 2. Single-company: ASC_KEY_ID, ASC_ISSUER_ID
    /// - Returns: CompaniesConfig if env vars found, nil otherwise
    private static func loadFromEnvironment() -> CompaniesConfig? {
        let env = ProcessInfo.processInfo.environment

        // Multi-company mode: ASC_COMPANY_N_KEY_ID
        var companies: [Company] = []
        var index = 1
        while let keyID = env["ASC_COMPANY_\(index)_KEY_ID"],
              let issuerID = env["ASC_COMPANY_\(index)_ISSUER_ID"] {
            let keyPath = env["ASC_COMPANY_\(index)_KEY_PATH"] ?? ""
            let keyContent = env["ASC_COMPANY_\(index)_KEY"]
            let name = env["ASC_COMPANY_\(index)_NAME"] ?? "Company \(index)"
            let vendorNumber = env["ASC_COMPANY_\(index)_VENDOR_NUMBER"]

            // Skip if neither key path nor key content provided
            guard !keyPath.isEmpty || keyContent != nil else {
                index += 1
                continue
            }

            companies.append(Company(
                id: "\(index)", name: name,
                keyID: keyID, issuerID: issuerID,
                privateKeyPath: keyPath, privateKeyContent: keyContent,
                vendorNumber: vendorNumber
            ))
            index += 1
        }
        if !companies.isEmpty {
            return CompaniesConfig(companies: companies)
        }

        // Single-company mode: ASC_KEY_ID, ASC_ISSUER_ID
        guard let keyID = env["ASC_KEY_ID"],
              let issuerID = env["ASC_ISSUER_ID"] else { return nil }
        let keyPath = env["ASC_PRIVATE_KEY_PATH"] ?? ""
        let keyContent = env["ASC_PRIVATE_KEY"]
        guard !keyPath.isEmpty || keyContent != nil else { return nil }

        let name = env["ASC_COMPANY_NAME"] ?? "Default"
        let vendorNumber = env["ASC_VENDOR_NUMBER"]
        let company = Company(
            id: "1", name: name,
            keyID: keyID, issuerID: issuerID,
            privateKeyPath: keyPath, privateKeyContent: keyContent,
            vendorNumber: vendorNumber
        )
        return CompaniesConfig(companies: [company])
    }

    // MARK: - Public API

    /// Get list of all companies
    public func listCompanies() -> [Company] {
        return config.companies
    }

    /// Switch to specific company by ID or name
    public func switchToCompany(_ idOrName: String) throws -> Company {
        if let company = config.companies.first(where: { $0.id.lowercased() == idOrName.lowercased() }) {
            currentCompany = company
            return company
        }

        if let company = config.companies.first(where: { $0.name.lowercased().contains(idOrName.lowercased()) }) {
            currentCompany = company
            return company
        }

        throw CompanyError.companyNotFound(idOrName)
    }

    /// Get current company configuration
    public func getCurrentCompany() throws -> Company {
        guard let company = currentCompany else {
            throw CompanyError.noCompanySelected
        }
        return company
    }

    /// Get default URL for API
    public func getDefaultURL() -> String {
        return config.defaultURL
    }
}

/// Errors for company management
public enum CompanyError: LocalizedError, Sendable {
    case companyNotFound(String)
    case noCompanySelected
    case configFileNotFound

    public var errorDescription: String? {
        switch self {
        case .companyNotFound(let name):
            return "Company not found: \(name)"
        case .noCompanySelected:
            return "No company selected. Use company_switch to select a company."
        case .configFileNotFound:
            return "Configuration not found. Set environment variables or provide companies.json."
        }
    }
}

