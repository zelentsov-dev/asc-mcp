import Foundation

/// Model for company configuration
public struct Company: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let keyID: String
    public let issuerID: String
    public let privateKeyPath: String
    /// Private key content (PEM string). If set, takes priority over `privateKeyPath`.
    public let privateKeyContent: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case keyID = "key_id"
        case issuerID = "issuer_id"
        case privateKeyPath = "key_path"
        case privateKeyContent = "key_content"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        keyID = try container.decode(String.self, forKey: .keyID)
        issuerID = try container.decode(String.self, forKey: .issuerID)
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        privateKeyContent = try container.decodeIfPresent(String.self, forKey: .privateKeyContent)
    }

    public init(
        id: String, name: String,
        keyID: String, issuerID: String,
        privateKeyPath: String = "",
        privateKeyContent: String? = nil
    ) {
        self.id = id
        self.name = name
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyPath = privateKeyPath
        self.privateKeyContent = privateKeyContent
    }
}

/// Container for all companies
public struct CompaniesConfig: Codable, Sendable {
    public let defaultURL: String
    public let companies: [Company]

    enum CodingKeys: String, CodingKey {
        case defaultURL = "defaultURL"
        case companies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultURL = try container.decodeIfPresent(String.self, forKey: .defaultURL)
            ?? "https://api.appstoreconnect.apple.com"
        companies = try container.decode([Company].self, forKey: .companies)
    }

    public init(companies: [Company], defaultURL: String = "https://api.appstoreconnect.apple.com") {
        self.companies = companies
        self.defaultURL = defaultURL
    }
}
