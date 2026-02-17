import Foundation

// MARK: - Bundle ID Models

/// Bundle IDs list response
public struct ASCBundleIdsResponse: Codable, Sendable {
    public let data: [ASCBundleId]
    public let links: ASCPagedDocumentLinks?
}

/// Bundle ID single response
public struct ASCBundleIdResponse: Codable, Sendable {
    public let data: ASCBundleId
}

/// Bundle ID resource
public struct ASCBundleId: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BundleIdAttributes
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
        public let type: String = "bundleIds"
        public let attributes: CreateBundleIdAttributes
    }

    public struct CreateBundleIdAttributes: Codable, Sendable {
        public let name: String
        public let identifier: String
        public let platform: String
    }
}

// MARK: - Device Models

/// Devices list response
public struct ASCDevicesResponse: Codable, Sendable {
    public let data: [ASCDevice]
    public let links: ASCPagedDocumentLinks?
}

/// Device single response
public struct ASCDeviceResponse: Codable, Sendable {
    public let data: ASCDevice
}

/// Device resource
public struct ASCDevice: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: DeviceAttributes
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
        public let type: String = "devices"
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
        public let type: String = "devices"
        public let id: String
        public let attributes: UpdateDeviceAttributes
    }

    public struct UpdateDeviceAttributes: Codable, Sendable {
        public let name: String?
        public let status: String?
    }
}

// MARK: - Certificate Models

/// Certificates list response
public struct ASCCertificatesResponse: Codable, Sendable {
    public let data: [ASCCertificate]
    public let links: ASCPagedDocumentLinks?
}

/// Certificate resource
public struct ASCCertificate: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: CertificateAttributes
}

/// Certificate attributes
public struct CertificateAttributes: Codable, Sendable {
    public let name: String?
    public let certificateType: String?
    public let displayName: String?
    public let serialNumber: String?
    public let platform: String?
    public let expirationDate: String?
    // certificateContent omitted - too large for MCP responses
}

// MARK: - Profile Models

/// Profiles list response
public struct ASCProfilesResponse: Codable, Sendable {
    public let data: [ASCProfile]
    public let links: ASCPagedDocumentLinks?
}

/// Profile resource
public struct ASCProfile: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: ProfileAttributes
}

/// Profile attributes
public struct ProfileAttributes: Codable, Sendable {
    public let name: String?
    public let platform: String?
    public let profileType: String?
    public let profileState: String?
    public let uuid: String?
    public let expirationDate: String?
    // profileContent omitted - base64 blob too large for MCP responses
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
        public let type: String = "profiles"
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
}

/// Single bundle ID capability response
public struct ASCBundleIdCapabilityResponse: Codable, Sendable {
    public let data: ASCBundleIdCapability
}

/// Bundle ID capability resource
public struct ASCBundleIdCapability: Codable, Sendable {
    public let type: String
    public let id: String
    public let attributes: BundleIdCapabilityAttributes
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
    public let allowedInstances: String?
    public let minInstances: Int?
    public let options: [CapabilityOption]?
}

/// Capability option
public struct CapabilityOption: Codable, Sendable {
    public let key: String?
    public let name: String?
    public let description: String?
    public let enabled: Bool?
}

// MARK: - Enable Capability Request

/// Request body for enabling a capability on a bundle ID
public struct EnableCapabilityRequest: Codable, Sendable {
    public let data: EnableCapabilityData

    public struct EnableCapabilityData: Codable, Sendable {
        public let type: String = "bundleIdCapabilities"
        public let attributes: EnableCapabilityAttributes
        public let relationships: EnableCapabilityRelationships
    }

    public struct EnableCapabilityAttributes: Codable, Sendable {
        public let capabilityType: String
        public let settings: [CapabilitySetting]?
    }

    public struct EnableCapabilityRelationships: Codable, Sendable {
        public let bundleId: EnableCapabilityBundleIdData
    }

    public struct EnableCapabilityBundleIdData: Codable, Sendable {
        public let data: EnableCapabilityBundleIdItem
    }

    public struct EnableCapabilityBundleIdItem: Codable, Sendable {
        public let type: String = "bundleIds"
        public let id: String
    }
}
