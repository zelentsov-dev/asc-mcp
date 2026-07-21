import Foundation

// MARK: - Bundle ID Models

/// Bundle IDs list response
public struct ASCBundleIdsResponse: Codable, Sendable {
    public let data: [ASCBundleId]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Bundle ID single response
public struct ASCBundleIdResponse: Codable, Sendable {
    public let data: ASCBundleId
}

/// Bundle ID resource
public struct ASCBundleId: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BundleIdAttributes?
}

/// Bundle ID attributes
public struct BundleIdAttributes: Codable, Sendable {
    public let name: String?
    public let identifier: String?
    public let platform: String?
    public let seedId: String?
}

/// Create bundle ID request
public struct CreateBundleIdRequest: Codable, Sendable {
    public let data: CreateBundleIdData

    public struct CreateBundleIdData: Codable, Sendable {
        public var type: String = "bundleIds"
        public let attributes: CreateBundleIdAttributes
    }

    public struct CreateBundleIdAttributes: Codable, Sendable {
        public let name: String
        public let identifier: String
        public let platform: String
        public let seedId: ASCNullable<String>?

        /// Creates bundle ID attributes from ordinary optional values.
        public init(name: String, identifier: String, platform: String, seedId: String?) {
            self.name = name
            self.identifier = identifier
            self.platform = platform
            self.seedId = seedId.map { .value($0) }
        }

        /// Creates bundle ID attributes while preserving omission and explicit null.
        public init(
            name: String,
            identifier: String,
            platform: String,
            nullableSeedId: ASCNullable<String>?
        ) {
            self.name = name
            self.identifier = identifier
            self.platform = platform
            self.seedId = nullableSeedId
        }

        enum CodingKeys: String, CodingKey {
            case name
            case identifier
            case platform
            case seedId
        }

        /// Decodes bundle ID attributes while preserving an explicit null seed ID.
        /// - Parameter decoder: Decoder containing the bundle ID attributes.
        /// - Throws: A decoding error when a present attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            identifier = try container.decode(String.self, forKey: .identifier)
            platform = try container.decode(String.self, forKey: .platform)
            seedId = try container.decodeASCNullable(String.self, forKey: .seedId)
        }
    }
}

// MARK: - Device Models

/// Devices list response
public struct ASCDevicesResponse: Codable, Sendable {
    public let data: [ASCDevice]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Device single response
public struct ASCDeviceResponse: Codable, Sendable {
    public let data: ASCDevice
}

/// Device resource
public struct ASCDevice: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: DeviceAttributes?
}

/// Device attributes
public struct DeviceAttributes: Codable, Sendable {
    public let name: String?
    public let platform: String?
    public let udid: String?
    public let deviceClass: String?
    public let status: String?
    public let model: String?
    public let addedDate: String?
}

/// Register device request
public struct RegisterDeviceRequest: Codable, Sendable {
    public let data: RegisterDeviceData

    public struct RegisterDeviceData: Codable, Sendable {
        public var type: String = "devices"
        public let attributes: RegisterDeviceAttributes
    }

    public struct RegisterDeviceAttributes: Codable, Sendable {
        public let name: String
        public let udid: String
        public let platform: String
    }
}

/// Update device request
public struct UpdateDeviceRequest: Codable, Sendable {
    public let data: UpdateDeviceData

    public struct UpdateDeviceData: Codable, Sendable {
        public var type: String = "devices"
        public let id: String
        public let attributes: UpdateDeviceAttributes
    }

    public struct UpdateDeviceAttributes: Codable, Sendable {
        public let name: ASCNullable<String>?
        public let status: ASCNullable<String>?

        /// Creates device update attributes from ordinary optional values.
        public init(name: String? = nil, status: String? = nil) {
            self.name = name.map { .value($0) }
            self.status = status.map { .value($0) }
        }

        /// Creates device update attributes while preserving omission and explicit null.
        public init(
            nullableName: ASCNullable<String>?,
            nullableStatus: ASCNullable<String>?
        ) {
            self.name = nullableName
            self.status = nullableStatus
        }

        enum CodingKeys: String, CodingKey {
            case name
            case status
        }

        /// Decodes device update attributes while preserving explicit null values.
        /// - Parameter decoder: Decoder containing the device update attributes.
        /// - Throws: A decoding error when a present attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeASCNullable(String.self, forKey: .name)
            status = try container.decodeASCNullable(String.self, forKey: .status)
        }
    }
}

// MARK: - Certificate Models

/// Certificates list response
public struct ASCCertificatesResponse: Codable, Sendable {
    public let data: [ASCCertificate]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Certificate resource
public struct ASCCertificate: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CertificateAttributes?
}

/// Certificate attributes
public struct CertificateAttributes: Codable, Sendable {
    public let name: String?
    public let certificateType: String?
    public let displayName: String?
    public let serialNumber: String?
    public let platform: String?
    public let expirationDate: String?
    public let certificateContent: String?
    public let activated: Bool?
}

// MARK: - Profile Models

/// Profiles list response
public struct ASCProfilesResponse: Codable, Sendable {
    public let data: [ASCProfile]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Profile resource
public struct ASCProfile: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ProfileAttributes?
}

/// Profile attributes
public struct ProfileAttributes: Codable, Sendable {
    public let name: String?
    public let platform: String?
    public let profileType: String?
    public let profileState: String?
    public let profileContent: String?
    public let uuid: String?
    public let createdDate: String?
    public let expirationDate: String?
}

// MARK: - Single Certificate Response

/// Single certificate response
public struct ASCCertificateResponse: Codable, Sendable {
    public let data: ASCCertificate
}

// MARK: - Single Profile Response

/// Single profile response
public struct ASCProfileResponse: Codable, Sendable {
    public let data: ASCProfile
}

// MARK: - Create Profile Request

/// Request body for creating a provisioning profile
public struct CreateProfileRequest: Codable, Sendable {
    public let data: CreateProfileData

    public struct CreateProfileData: Codable, Sendable {
        public var type: String = "profiles"
        public let attributes: CreateProfileAttributes
        public let relationships: CreateProfileRelationships
    }

    public struct CreateProfileAttributes: Codable, Sendable {
        public let name: String
        public let profileType: String
    }

    public struct CreateProfileRelationships: Codable, Sendable {
        public let bundleId: RelationshipData
        public let certificates: RelationshipDataArray
        public let devices: RelationshipDataArray?
    }

    public struct RelationshipData: Codable, Sendable {
        public let data: RelationshipItem
    }

    public struct RelationshipDataArray: Codable, Sendable {
        public let data: [RelationshipItem]
    }

    public struct RelationshipItem: Codable, Sendable {
        public let type: String
        public let id: String
    }
}

// MARK: - Bundle ID Capability Models

/// Bundle ID capabilities list response
public struct ASCBundleIdCapabilitiesResponse: Codable, Sendable {
    public let data: [ASCBundleIdCapability]
    public let links: ASCPagedDocumentLinks?
    public let meta: ASCPagingInformation?
}

/// Single bundle ID capability response
public struct ASCBundleIdCapabilityResponse: Codable, Sendable {
    public let data: ASCBundleIdCapability
}

/// Bundle ID capability resource
public struct ASCBundleIdCapability: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BundleIdCapabilityAttributes?
}

/// Bundle ID capability attributes
public struct BundleIdCapabilityAttributes: Codable, Sendable {
    public let capabilityType: String?
    public let settings: [CapabilitySetting]?
}

/// Capability setting
public struct CapabilitySetting: Codable, Sendable {
    public let key: String?
    public let name: String?
    public let description: String?
    public let enabledByDefault: Bool?
    public let visible: Bool?
    public let allowedInstances: String?
    public let minInstances: Int?
    public let options: [CapabilityOption]?
}

/// Capability option
public struct CapabilityOption: Codable, Sendable {
    public let key: String?
    public let name: String?
    public let description: String?
    public let enabledByDefault: Bool?
    public let enabled: Bool?
    public let supportsWildcard: Bool?
}

// MARK: - Enable Capability Request

/// Request body for enabling a capability on a bundle ID
public struct EnableCapabilityRequest: Codable, Sendable {
    public let data: EnableCapabilityData

    public struct EnableCapabilityData: Codable, Sendable {
        public var type: String = "bundleIdCapabilities"
        public let attributes: EnableCapabilityAttributes
        public let relationships: EnableCapabilityRelationships
    }

    public struct EnableCapabilityAttributes: Codable, Sendable {
        public let capabilityType: String
        public let settings: ASCNullable<[CapabilitySetting]>?

        /// Creates capability attributes from ordinary optional settings.
        public init(capabilityType: String, settings: [CapabilitySetting]?) {
            self.capabilityType = capabilityType
            self.settings = settings.map { .value($0) }
        }

        /// Creates capability attributes while preserving omission and explicit null.
        public init(
            capabilityType: String,
            nullableSettings: ASCNullable<[CapabilitySetting]>?
        ) {
            self.capabilityType = capabilityType
            self.settings = nullableSettings
        }

        enum CodingKeys: String, CodingKey {
            case capabilityType
            case settings
        }

        /// Decodes capability attributes while preserving explicit null settings.
        /// - Parameter decoder: Decoder containing capability attributes.
        /// - Throws: A decoding error when a present attribute has an invalid type.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            capabilityType = try container.decode(String.self, forKey: .capabilityType)
            settings = try container.decodeASCNullable([CapabilitySetting].self, forKey: .settings)
        }
    }

    public struct EnableCapabilityRelationships: Codable, Sendable {
        public let bundleId: EnableCapabilityBundleIdData
    }

    public struct EnableCapabilityBundleIdData: Codable, Sendable {
        public let data: EnableCapabilityBundleIdItem
    }

    public struct EnableCapabilityBundleIdItem: Codable, Sendable {
        public var type: String = "bundleIds"
        public let id: String
    }
}
