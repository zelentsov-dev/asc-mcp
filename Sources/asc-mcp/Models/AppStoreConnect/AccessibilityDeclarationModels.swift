import Foundation

enum ASCAccessibilityDeclarationFields {
    static let all = [
        "deviceFamily",
        "state",
        "supportsAudioDescriptions",
        "supportsCaptions",
        "supportsDarkInterface",
        "supportsDifferentiateWithoutColorAlone",
        "supportsLargerText",
        "supportsReducedMotion",
        "supportsSufficientContrast",
        "supportsVoiceControl",
        "supportsVoiceover"
    ]
}

public enum ASCAccessibilityDeviceFamily: Codable, Equatable, Sendable {
    case iPhone
    case iPad
    case appleTV
    case appleWatch
    case mac
    case vision
    case unknown(String)

    public static let validRawValues = ["IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION"]

    public init?(rawValue: String) {
        switch rawValue {
        case "IPHONE": self = .iPhone
        case "IPAD": self = .iPad
        case "APPLE_TV": self = .appleTV
        case "APPLE_WATCH": self = .appleWatch
        case "MAC": self = .mac
        case "VISION": self = .vision
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .iPhone: "IPHONE"
        case .iPad: "IPAD"
        case .appleTV: "APPLE_TV"
        case .appleWatch: "APPLE_WATCH"
        case .mac: "MAC"
        case .vision: "VISION"
        case .unknown(let value): value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ASCAccessibilityDeviceFamily(rawValue: value) ?? .unknown(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ASCAccessibilityDeclarationState: Codable, Equatable, Sendable {
    case draft
    case published
    case replaced
    case unknown(String)

    public static let validRawValues = ["DRAFT", "PUBLISHED", "REPLACED"]

    public init?(rawValue: String) {
        switch rawValue {
        case "DRAFT": self = .draft
        case "PUBLISHED": self = .published
        case "REPLACED": self = .replaced
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .draft: "DRAFT"
        case .published: "PUBLISHED"
        case .replaced: "REPLACED"
        case .unknown(let value): value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = ASCAccessibilityDeclarationState(rawValue: value) ?? .unknown(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ASCAccessibilityDeclarationSupportAttributes: Codable, Sendable {
    public let supportsAudioDescriptions: Bool?
    public let supportsCaptions: Bool?
    public let supportsDarkInterface: Bool?
    public let supportsDifferentiateWithoutColorAlone: Bool?
    public let supportsLargerText: Bool?
    public let supportsReducedMotion: Bool?
    public let supportsSufficientContrast: Bool?
    public let supportsVoiceControl: Bool?
    public let supportsVoiceover: Bool?

    /// Creates accessibility support flags matching Apple's accessibility declaration attributes.
    /// - Parameters:
    ///   - supportsAudioDescriptions: Whether the app supports audio descriptions.
    ///   - supportsCaptions: Whether the app supports captions.
    ///   - supportsDarkInterface: Whether the app supports a dark interface.
    ///   - supportsDifferentiateWithoutColorAlone: Whether the app can differentiate without color alone.
    ///   - supportsLargerText: Whether the app supports larger text.
    ///   - supportsReducedMotion: Whether the app supports reduced motion.
    ///   - supportsSufficientContrast: Whether the app supports sufficient contrast.
    ///   - supportsVoiceControl: Whether the app supports Voice Control.
    ///   - supportsVoiceover: Whether the app supports VoiceOver.
    public init(
        supportsAudioDescriptions: Bool? = nil,
        supportsCaptions: Bool? = nil,
        supportsDarkInterface: Bool? = nil,
        supportsDifferentiateWithoutColorAlone: Bool? = nil,
        supportsLargerText: Bool? = nil,
        supportsReducedMotion: Bool? = nil,
        supportsSufficientContrast: Bool? = nil,
        supportsVoiceControl: Bool? = nil,
        supportsVoiceover: Bool? = nil
    ) {
        self.supportsAudioDescriptions = supportsAudioDescriptions
        self.supportsCaptions = supportsCaptions
        self.supportsDarkInterface = supportsDarkInterface
        self.supportsDifferentiateWithoutColorAlone = supportsDifferentiateWithoutColorAlone
        self.supportsLargerText = supportsLargerText
        self.supportsReducedMotion = supportsReducedMotion
        self.supportsSufficientContrast = supportsSufficientContrast
        self.supportsVoiceControl = supportsVoiceControl
        self.supportsVoiceover = supportsVoiceover
    }

    public var hasAnyValue: Bool {
        supportsAudioDescriptions != nil ||
            supportsCaptions != nil ||
            supportsDarkInterface != nil ||
            supportsDifferentiateWithoutColorAlone != nil ||
            supportsLargerText != nil ||
            supportsReducedMotion != nil ||
            supportsSufficientContrast != nil ||
            supportsVoiceControl != nil ||
            supportsVoiceover != nil
    }
}

public struct ASCAccessibilityDeclarationResponse: Codable, Sendable {
    public let data: ASCAccessibilityDeclaration
    public let links: ASCResourceLinks?
}

public struct ASCAccessibilityDeclarationsResponse: Codable, Sendable {
    public let data: [ASCAccessibilityDeclaration]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCAccessibilityDeclarationLinkagesResponse: Codable, Sendable {
    public let data: [ASCResourceIdentifier]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

public struct ASCAccessibilityDeclaration: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?
    public let links: ASCResourceLinks?

    public struct Attributes: Codable, Sendable {
        public let deviceFamily: ASCAccessibilityDeviceFamily?
        public let state: ASCAccessibilityDeclarationState?
        public let supportsAudioDescriptions: Bool?
        public let supportsCaptions: Bool?
        public let supportsDarkInterface: Bool?
        public let supportsDifferentiateWithoutColorAlone: Bool?
        public let supportsLargerText: Bool?
        public let supportsReducedMotion: Bool?
        public let supportsSufficientContrast: Bool?
        public let supportsVoiceControl: Bool?
        public let supportsVoiceover: Bool?
    }
}

public struct ASCAccessibilityDeclarationCreateRequest: Codable, Sendable {
    public let data: ResourceData

    /// Creates a JSON:API request for an App Store accessibility declaration.
    /// - Parameters:
    ///   - appID: App Store Connect app identifier.
    ///   - deviceFamily: Device family covered by the declaration.
    ///   - supports: Optional accessibility support flags.
    public init(
        appID: String,
        deviceFamily: ASCAccessibilityDeviceFamily,
        supports: ASCAccessibilityDeclarationSupportAttributes = .init()
    ) {
        self.data = ResourceData(
            attributes: Attributes(deviceFamily: deviceFamily, supports: supports),
            relationships: Relationships(
                app: Relationship(data: ASCResourceIdentifier(type: "apps", id: appID))
            )
        )
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let attributes: Attributes
        public let relationships: Relationships

        public init(attributes: Attributes, relationships: Relationships) {
            self.type = "accessibilityDeclarations"
            self.attributes = attributes
            self.relationships = relationships
        }
    }

    public struct Attributes: Codable, Sendable {
        public let deviceFamily: ASCAccessibilityDeviceFamily
        public let supportsAudioDescriptions: Bool?
        public let supportsCaptions: Bool?
        public let supportsDarkInterface: Bool?
        public let supportsDifferentiateWithoutColorAlone: Bool?
        public let supportsLargerText: Bool?
        public let supportsReducedMotion: Bool?
        public let supportsSufficientContrast: Bool?
        public let supportsVoiceControl: Bool?
        public let supportsVoiceover: Bool?

        public init(deviceFamily: ASCAccessibilityDeviceFamily, supports: ASCAccessibilityDeclarationSupportAttributes) {
            self.deviceFamily = deviceFamily
            self.supportsAudioDescriptions = supports.supportsAudioDescriptions
            self.supportsCaptions = supports.supportsCaptions
            self.supportsDarkInterface = supports.supportsDarkInterface
            self.supportsDifferentiateWithoutColorAlone = supports.supportsDifferentiateWithoutColorAlone
            self.supportsLargerText = supports.supportsLargerText
            self.supportsReducedMotion = supports.supportsReducedMotion
            self.supportsSufficientContrast = supports.supportsSufficientContrast
            self.supportsVoiceControl = supports.supportsVoiceControl
            self.supportsVoiceover = supports.supportsVoiceover
        }
    }

    public struct Relationships: Codable, Sendable {
        public let app: Relationship
    }

    public struct Relationship: Codable, Sendable {
        public let data: ASCResourceIdentifier
    }
}

public struct ASCAccessibilityDeclarationUpdateRequest: Codable, Sendable {
    public let data: ResourceData

    /// Creates a JSON:API update request for an accessibility declaration.
    /// - Parameters:
    ///   - declarationID: Accessibility declaration identifier.
    ///   - attributes: Publish flag and support attributes to update.
    public init(declarationID: String, attributes: Attributes) {
        self.data = ResourceData(id: declarationID, attributes: attributes)
    }

    public struct ResourceData: Codable, Sendable {
        public let type: String
        public let id: String
        public let attributes: Attributes

        public init(id: String, attributes: Attributes) {
            self.type = "accessibilityDeclarations"
            self.id = id
            self.attributes = attributes
        }
    }

    public struct Attributes: Codable, Sendable {
        public let publish: Bool?
        public let supportsAudioDescriptions: Bool?
        public let supportsCaptions: Bool?
        public let supportsDarkInterface: Bool?
        public let supportsDifferentiateWithoutColorAlone: Bool?
        public let supportsLargerText: Bool?
        public let supportsReducedMotion: Bool?
        public let supportsSufficientContrast: Bool?
        public let supportsVoiceControl: Bool?
        public let supportsVoiceover: Bool?

        /// Creates update attributes for an accessibility declaration.
        /// - Parameters:
        ///   - publish: Whether Apple should publish the declaration.
        ///   - supports: Optional accessibility support flags to update.
        public init(publish: Bool? = nil, supports: ASCAccessibilityDeclarationSupportAttributes = .init()) {
            self.publish = publish
            self.supportsAudioDescriptions = supports.supportsAudioDescriptions
            self.supportsCaptions = supports.supportsCaptions
            self.supportsDarkInterface = supports.supportsDarkInterface
            self.supportsDifferentiateWithoutColorAlone = supports.supportsDifferentiateWithoutColorAlone
            self.supportsLargerText = supports.supportsLargerText
            self.supportsReducedMotion = supports.supportsReducedMotion
            self.supportsSufficientContrast = supports.supportsSufficientContrast
            self.supportsVoiceControl = supports.supportsVoiceControl
            self.supportsVoiceover = supports.supportsVoiceover
        }

        public var hasChanges: Bool {
            publish != nil ||
                supportsAudioDescriptions != nil ||
                supportsCaptions != nil ||
                supportsDarkInterface != nil ||
                supportsDifferentiateWithoutColorAlone != nil ||
                supportsLargerText != nil ||
                supportsReducedMotion != nil ||
                supportsSufficientContrast != nil ||
                supportsVoiceControl != nil ||
                supportsVoiceover != nil
        }
    }
}
