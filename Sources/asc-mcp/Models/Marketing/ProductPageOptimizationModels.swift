import Foundation

// MARK: - App Store Version Experiment Models

/// Experiments list response
public struct ASCExperimentsResponse: Codable, Sendable {
    public let data: [ASCExperiment]
    public let links: ASCPagedDocumentLinks?
}

/// Single experiment response
public struct ASCExperimentResponse: Codable, Sendable {
    public let data: ASCExperiment
}

/// App Store Version Experiment resource
public struct ASCExperiment: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ExperimentAttributes?
}

/// Experiment attributes
public struct ExperimentAttributes: Codable, Sendable {
    public let name: String?
    public let trafficProportion: Int?
    public let state: String?
    public let reviewRequired: Bool?
    public let startDate: String?
    public let endDate: String?
}

// MARK: - Experiment Treatment Models

/// Treatments list response
public struct ASCTreatmentsResponse: Codable, Sendable {
    public let data: [ASCTreatment]
    public let links: ASCPagedDocumentLinks?
}

/// Single treatment response
public struct ASCTreatmentResponse: Codable, Sendable {
    public let data: ASCTreatment
}

/// Experiment treatment resource
public struct ASCTreatment: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: TreatmentAttributes?
}

/// Treatment attributes
public struct TreatmentAttributes: Codable, Sendable {
    public let name: String?
    public let appIconName: String?
}

// MARK: - Treatment Localization Models

/// Treatment localizations list response
public struct ASCTreatmentLocalizationsResponse: Codable, Sendable {
    public let data: [ASCTreatmentLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Single treatment localization response
public struct ASCTreatmentLocalizationResponse: Codable, Sendable {
    public let data: ASCTreatmentLocalization
}

/// Treatment localization resource
public struct ASCTreatmentLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: TreatmentLocalizationAttributes?
}

/// Treatment localization attributes
public struct TreatmentLocalizationAttributes: Codable, Sendable {
    public let locale: String?
}

// MARK: - Request Models

/// Create experiment request
public struct CreateExperimentRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appStoreVersionExperiments"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
        public let trafficProportion: Int
        public let platform: String
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update experiment request
public struct UpdateExperimentRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "appStoreVersionExperiments"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let name: String?
        public let trafficProportion: Int?
        public let state: String?
    }
}

/// Create treatment request
public struct CreateTreatmentRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appStoreVersionExperimentTreatments"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let name: String
    }

    public struct Relationships: Codable, Sendable {
        public let appStoreVersionExperiment: ExperimentRelationship
    }

    public struct ExperimentRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Create treatment localization request
public struct CreateTreatmentLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "appStoreVersionExperimentTreatmentLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
    }

    public struct Relationships: Codable, Sendable {
        public let appStoreVersionExperimentTreatment: TreatmentRelationship
    }

    public struct TreatmentRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}
