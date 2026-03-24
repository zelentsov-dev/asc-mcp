import Foundation

// MARK: - Beta App Localization Models

/// Beta app localizations list response
public struct ASCBetaAppLocalizationsResponse: Codable, Sendable {
    public let data: [ASCBetaAppLocalization]
    public let links: ASCPagedDocumentLinks?
}

/// Beta app localization single response
public struct ASCBetaAppLocalizationResponse: Codable, Sendable {
    public let data: ASCBetaAppLocalization
}

/// Beta app localization resource
public struct ASCBetaAppLocalization: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaAppLocalizationAttributes
}

/// Beta app localization attributes
public struct BetaAppLocalizationAttributes: Codable, Sendable {
    public let feedbackEmail: String?
    public let marketingUrl: String?
    public let privacyPolicyUrl: String?
    public let tvOsPrivacyPolicy: String?
    public let description: String?
    public let locale: String?
}

// MARK: - Beta App Localization Request Models

/// Create beta app localization request
public struct CreateBetaAppLocalizationRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "betaAppLocalizations"
        public let attributes: Attributes
        public let relationships: Relationships
    }

    public struct Attributes: Codable, Sendable {
        public let locale: String
        public let feedbackEmail: String?
        public let marketingUrl: String?
        public let privacyPolicyUrl: String?
        public let tvOsPrivacyPolicy: String?
        public let description: String?
    }

    public struct Relationships: Codable, Sendable {
        public let app: AppRelationship
    }

    public struct AppRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

/// Update beta app localization request
public struct UpdateBetaAppLocalizationRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "betaAppLocalizations"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let feedbackEmail: String?
        public let marketingUrl: String?
        public let privacyPolicyUrl: String?
        public let tvOsPrivacyPolicy: String?
        public let description: String?
    }
}

// MARK: - Beta App Review Submission Models

/// Beta app review submissions list response
public struct ASCBetaAppReviewSubmissionsResponse: Codable, Sendable {
    public let data: [ASCBetaAppReviewSubmission]
    public let links: ASCPagedDocumentLinks?
}

/// Beta app review submission single response
public struct ASCBetaAppReviewSubmissionResponse: Codable, Sendable {
    public let data: ASCBetaAppReviewSubmission
}

/// Beta app review submission resource
public struct ASCBetaAppReviewSubmission: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaAppReviewSubmissionAttributes
}

/// Beta app review submission attributes
public struct BetaAppReviewSubmissionAttributes: Codable, Sendable {
    public let betaReviewState: String?
    public let submittedDate: String?
}

// MARK: - Beta App Review Submission Request Models

/// Create beta app review submission request
public struct CreateBetaAppReviewSubmissionRequest: Codable, Sendable {
    public let data: CreateData

    public struct CreateData: Codable, Sendable {
        public let type: String = "betaAppReviewSubmissions"
        public let relationships: Relationships
    }

    public struct Relationships: Codable, Sendable {
        public let build: BuildRelationship
    }

    public struct BuildRelationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

// MARK: - Beta App Review Detail Models

/// Beta app review detail single response
public struct ASCBetaAppReviewDetailResponse: Codable, Sendable {
    public let data: ASCBetaAppReviewDetail
}

/// Beta app review detail resource
public struct ASCBetaAppReviewDetail: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BetaAppReviewDetailAttributes
}

/// Beta app review detail attributes
public struct BetaAppReviewDetailAttributes: Codable, Sendable {
    public let contactFirstName: String?
    public let contactLastName: String?
    public let contactPhone: String?
    public let contactEmail: String?
    public let demoAccountName: String?
    public let demoAccountPassword: String?
    public let demoAccountRequired: Bool?
    public let notes: String?
}

// MARK: - Beta App Review Detail Request Models

/// Update beta app review detail request
public struct UpdateBetaAppReviewDetailRequest: Codable, Sendable {
    public let data: UpdateData

    public struct UpdateData: Codable, Sendable {
        public let type: String = "betaAppReviewDetails"
        public let id: String
        public let attributes: Attributes
    }

    public struct Attributes: Codable, Sendable {
        public let contactFirstName: String?
        public let contactLastName: String?
        public let contactPhone: String?
        public let contactEmail: String?
        public let demoAccountName: String?
        public let demoAccountPassword: String?
        public let demoAccountRequired: Bool?
        public let notes: String?
    }
}
