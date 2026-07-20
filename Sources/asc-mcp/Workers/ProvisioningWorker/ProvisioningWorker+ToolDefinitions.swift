import Foundation
import MCP

// MARK: - Tool Definitions
extension ProvisioningWorker {

    func listBundleIdsTool() -> Tool {
        return Tool(
            name: "provisioning_list_bundle_ids",
            description: "List registered bundle identifiers",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more platforms (comma-separated): IOS, MAC_OS, UNIVERSAL")
                    ]),
                    "filter_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more bundle identifiers (comma-separated)")
                    ]),
                    "filter_name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more names (comma-separated)")
                    ]),
                    "filter_seed_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more seed IDs (comma-separated)")
                    ]),
                    "filter_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more bundle ID resource IDs (comma-separated)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated sort fields: name, -name, platform, -platform, identifier, -identifier, seedId, -seedId, id, -id")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getBundleIdTool() -> Tool {
        return Tool(
            name: "provisioning_get_bundle_id",
            description: "Get details of a bundle identifier",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id_resource_id": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID resource ID (not the identifier string)")
                    ])
                ]),
                "required": .array([.string("bundle_id_resource_id")])
            ])
        )
    }

    func createBundleIdTool() -> Tool {
        return Tool(
            name: "provisioning_create_bundle_id",
            description: "Register a new bundle identifier",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID name")
                    ]),
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Bundle identifier (e.g. com.example.app)")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform: IOS, MAC_OS, UNIVERSAL")
                    ]),
                    "seed_id": .object([
                        "type": .string("string"),
                        "description": .string("Optional Apple Developer Program seed ID")
                    ])
                ]),
                "required": .array([.string("name"), .string("identifier"), .string("platform")])
            ])
        )
    }

    func deleteBundleIdTool() -> Tool {
        return Tool(
            name: "provisioning_delete_bundle_id",
            description: "Delete a bundle identifier",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id_resource_id": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID resource ID to delete")
                    ])
                ]),
                "required": .array([.string("bundle_id_resource_id")])
            ])
        )
    }

    func listDevicesTool() -> Tool {
        return Tool(
            name: "provisioning_list_devices",
            description: "List registered devices",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more platforms (comma-separated): IOS, MAC_OS, UNIVERSAL")
                    ]),
                    "filter_status": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more statuses (comma-separated): ENABLED, DISABLED")
                    ]),
                    "filter_name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more device names (comma-separated)")
                    ]),
                    "filter_udid": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more device UDIDs (comma-separated)")
                    ]),
                    "filter_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more device resource IDs (comma-separated)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated sort fields: name, -name, platform, -platform, udid, -udid, status, -status, id, -id")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func registerDeviceTool() -> Tool {
        return Tool(
            name: "provisioning_register_device",
            description: "Register a new device for development",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Device name")
                    ]),
                    "udid": .object([
                        "type": .string("string"),
                        "description": .string("Device UDID")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform: IOS, MAC_OS, UNIVERSAL")
                    ])
                ]),
                "required": .array([.string("name"), .string("udid"), .string("platform")])
            ])
        )
    }

    func updateDeviceTool() -> Tool {
        return Tool(
            name: "provisioning_update_device",
            description: "Update device name or status",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device_id": .object([
                        "type": .string("string"),
                        "description": .string("Device resource ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("New device name")
                    ]),
                    "status": .object([
                        "type": .string("string"),
                        "description": .string("New status: ENABLED, DISABLED")
                    ])
                ]),
                "required": .array([.string("device_id")])
            ])
        )
    }

    func listCertificatesTool() -> Tool {
        return Tool(
            name: "provisioning_list_certificates",
            description: "List signing certificates",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more certificate types (comma-separated, e.g. IOS_DISTRIBUTION,DISTRIBUTION)")
                    ]),
                    "filter_display_name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more certificate display names (comma-separated)")
                    ]),
                    "filter_serial_number": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more certificate serial numbers (comma-separated)")
                    ]),
                    "filter_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more certificate resource IDs (comma-separated)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated sort fields: displayName, -displayName, certificateType, -certificateType, serialNumber, -serialNumber, id, -id")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getCertificateTool() -> Tool {
        return Tool(
            name: "provisioning_get_certificate",
            description: "Get signing-certificate details, including Base64-encoded certificateContent when Apple returns it",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "certificate_id": .object([
                        "type": .string("string"),
                        "description": .string("Certificate resource ID")
                    ])
                ]),
                "required": .array([.string("certificate_id")])
            ])
        )
    }

    func revokeCertificateTool() -> Tool {
        return Tool(
            name: "provisioning_revoke_certificate",
            description: "Revoke a signing certificate",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "certificate_id": .object([
                        "type": .string("string"),
                        "description": .string("Certificate resource ID to revoke")
                    ])
                ]),
                "required": .array([.string("certificate_id")])
            ])
        )
    }

    func getProfileTool() -> Tool {
        return Tool(
            name: "provisioning_get_profile",
            description: "Get provisioning-profile details, including Base64-encoded profileContent when Apple returns it",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "profile_id": .object([
                        "type": .string("string"),
                        "description": .string("Profile resource ID")
                    ])
                ]),
                "required": .array([.string("profile_id")])
            ])
        )
    }

    func deleteProfileTool() -> Tool {
        return Tool(
            name: "provisioning_delete_profile",
            description: "Delete a provisioning profile",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "profile_id": .object([
                        "type": .string("string"),
                        "description": .string("Profile resource ID to delete")
                    ])
                ]),
                "required": .array([.string("profile_id")])
            ])
        )
    }

    func createProfileTool() -> Tool {
        return Tool(
            name: "provisioning_create_profile",
            description: "Create a provisioning profile and return its details, including Base64-encoded profileContent when Apple returns it",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Profile name")
                    ]),
                    "profile_type": .object([
                        "type": .string("string"),
                        "description": .string("Profile type: IOS_APP_DEVELOPMENT, IOS_APP_STORE, IOS_APP_ADHOC, IOS_APP_INHOUSE, MAC_APP_DEVELOPMENT, MAC_APP_STORE, MAC_APP_DIRECT, TVOS_APP_DEVELOPMENT, TVOS_APP_STORE, TVOS_APP_ADHOC, TVOS_APP_INHOUSE, MAC_CATALYST_APP_DEVELOPMENT, MAC_CATALYST_APP_STORE, MAC_CATALYST_APP_DIRECT")
                    ]),
                    "bundle_id_resource_id": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID resource ID to associate with the profile")
                    ]),
                    "certificate_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "description": .string("Non-empty array of unique certificate resource IDs to include in the profile")
                    ]),
                    "device_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true),
                        "description": .string("Optional non-empty array of unique device resource IDs; omit for App Store and Direct profiles")
                    ])
                ]),
                "required": .array([.string("name"), .string("profile_type"), .string("bundle_id_resource_id"), .string("certificate_ids")])
            ])
        )
    }

    func listCapabilitiesTool() -> Tool {
        return Tool(
            name: "provisioning_list_capabilities",
            description: "List capabilities enabled for a bundle ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id_resource_id": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID resource ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("bundle_id_resource_id")])
            ])
        )
    }

    func enableCapabilityTool() -> Tool {
        return Tool(
            name: "provisioning_enable_capability",
            description: "Enable a capability on a bundle ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id_resource_id": .object([
                        "type": .string("string"),
                        "description": .string("Bundle ID resource ID")
                    ]),
                    "capability_type": .object([
                        "type": .string("string"),
                        "description": .string("Capability type: ICLOUD, IN_APP_PURCHASE, GAME_CENTER, PUSH_NOTIFICATIONS, WALLET, INTER_APP_AUDIO, MAPS, ASSOCIATED_DOMAINS, PERSONAL_VPN, APP_GROUPS, HEALTHKIT, HOMEKIT, WIRELESS_ACCESSORY_CONFIGURATION, APPLE_PAY, DATA_PROTECTION, SIRIKIT, NETWORK_EXTENSIONS, MULTIPATH, HOT_SPOT, NFC_TAG_READING, CLASSKIT, AUTOFILL_CREDENTIAL_PROVIDER, ACCESS_WIFI_INFORMATION, NETWORK_CUSTOM_PROTOCOL, COREMEDIA_HLS_LOW_LATENCY, SYSTEM_EXTENSION_INSTALL, USER_MANAGEMENT, APPLE_ID_AUTH")
                    ]),
                    "settings": .object([
                        "type": .string("string"),
                        "description": .string("Optional JSON string with capability settings array")
                    ])
                ]),
                "required": .array([.string("bundle_id_resource_id"), .string("capability_type")])
            ])
        )
    }

    func disableCapabilityTool() -> Tool {
        return Tool(
            name: "provisioning_disable_capability",
            description: "Disable a capability on a bundle ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "capability_id": .object([
                        "type": .string("string"),
                        "description": .string("Capability resource ID to disable")
                    ])
                ]),
                "required": .array([.string("capability_id")])
            ])
        )
    }

    func listProfilesTool() -> Tool {
        return Tool(
            name: "provisioning_list_profiles",
            description: "List provisioning profiles",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_profile_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more profile types (comma-separated, e.g. IOS_APP_STORE,MAC_APP_STORE)")
                    ]),
                    "filter_profile_state": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more states (comma-separated): ACTIVE, INVALID")
                    ]),
                    "filter_name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more profile names (comma-separated)")
                    ]),
                    "filter_id": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one or more profile resource IDs (comma-separated)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Comma-separated sort fields: name, -name, profileType, -profileType, profileState, -profileState, id, -id")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }
}
