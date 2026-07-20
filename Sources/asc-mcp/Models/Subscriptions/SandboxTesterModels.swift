import Foundation

// MARK: - Sandbox Tester Models

/// Territory codes accepted by Apple 4.4.1 for sandbox tester updates.
public enum SandboxTesterTerritoryValues {
    public static let all: [String] = [
        "ABW", "AFG", "AGO", "AIA", "ALB", "AND", "ANT", "ARE", "ARG", "ARM", "ASM", "ATG",
        "AUS", "AUT", "AZE", "BDI", "BEL", "BEN", "BES", "BFA", "BGD", "BGR", "BHR", "BHS",
        "BIH", "BLR", "BLZ", "BMU", "BOL", "BRA", "BRB", "BRN", "BTN", "BWA", "CAF", "CAN",
        "CHE", "CHL", "CHN", "CIV", "CMR", "COD", "COG", "COK", "COL", "COM", "CPV", "CRI",
        "CUB", "CUW", "CXR", "CYM", "CYP", "CZE", "DEU", "DJI", "DMA", "DNK", "DOM", "DZA",
        "ECU", "EGY", "ERI", "ESP", "EST", "ETH", "FIN", "FJI", "FLK", "FRA", "FRO", "FSM",
        "GAB", "GBR", "GEO", "GGY", "GHA", "GIB", "GIN", "GLP", "GMB", "GNB", "GNQ", "GRC",
        "GRD", "GRL", "GTM", "GUF", "GUM", "GUY", "HKG", "HND", "HRV", "HTI", "HUN", "IDN",
        "IMN", "IND", "IRL", "IRQ", "ISL", "ISR", "ITA", "JAM", "JEY", "JOR", "JPN", "KAZ",
        "KEN", "KGZ", "KHM", "KIR", "KNA", "KOR", "KWT", "LAO", "LBN", "LBR", "LBY", "LCA",
        "LIE", "LKA", "LSO", "LTU", "LUX", "LVA", "MAC", "MAR", "MCO", "MDA", "MDG", "MDV",
        "MEX", "MHL", "MKD", "MLI", "MLT", "MMR", "MNE", "MNG", "MNP", "MOZ", "MRT", "MSR",
        "MTQ", "MUS", "MWI", "MYS", "MYT", "NAM", "NCL", "NER", "NFK", "NGA", "NIC", "NIU",
        "NLD", "NOR", "NPL", "NRU", "NZL", "OMN", "PAK", "PAN", "PER", "PHL", "PLW", "PNG",
        "POL", "PRI", "PRT", "PRY", "PSE", "PYF", "QAT", "REU", "ROU", "RUS", "RWA", "SAU",
        "SEN", "SGP", "SHN", "SLB", "SLE", "SLV", "SMR", "SOM", "SPM", "SRB", "SSD", "STP",
        "SUR", "SVK", "SVN", "SWE", "SWZ", "SXM", "SYC", "TCA", "TCD", "TGO", "THA", "TJK",
        "TKM", "TLS", "TON", "TTO", "TUN", "TUR", "TUV", "TWN", "TZA", "UGA", "UKR", "UMI",
        "URY", "USA", "UZB", "VAT", "VCT", "VEN", "VGB", "VIR", "VNM", "VUT", "WLF", "WSM",
        "XKS", "YEM", "ZAF", "ZMB", "ZWE"
    ]
}

/// Sandbox testers list response
public struct ASCSandboxTestersResponse: Codable, Sendable {
    public let data: [ASCSandboxTester]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Sandbox tester single response
public struct ASCSandboxTesterResponse: Codable, Sendable {
    public let data: ASCSandboxTester
}

/// Sandbox tester resource
public struct ASCSandboxTester: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: SandboxTesterAttributes?
}

/// Sandbox tester attributes
public struct SandboxTesterAttributes: Codable, Sendable {
    public let firstName: String?
    public let lastName: String?
    public let acAccountName: String?
    public let territory: String?
    public let applePayCompatible: Bool?
    public let interruptPurchases: Bool?
    public let subscriptionRenewalRate: String?
}

// MARK: - Sandbox Tester Request Models

/// Update sandbox tester request
public struct UpdateSandboxTesterRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public var type: String = "sandboxTesters"
        public let id: String
        public let attributes: [String: JSONValue]
    }
}

/// Clear purchase history request
public struct ClearPurchaseHistoryRequest: Codable, Sendable {
    public let data: RequestData

    public struct RequestData: Codable, Sendable {
        public var type: String = "sandboxTestersClearPurchaseHistoryRequest"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let sandboxTesters: SandboxTestersRelationship
    }

    public struct SandboxTestersRelationship: Codable, Sendable {
        public let data: [ASCResourceIdentifier]
    }
}

/// Clear purchase history response
public struct ASCClearPurchaseHistoryResponse: Codable, Sendable {
    public let data: Resource

    public struct Resource: Codable, Sendable {
        public let type: String
        public let id: String
    }
}
