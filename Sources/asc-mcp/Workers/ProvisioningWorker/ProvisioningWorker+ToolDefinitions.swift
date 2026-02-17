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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by platform: IOS, MAC_OS, UNIVERSAL")
                    ]),
                    "filter_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Filter by bundle identifier")
                    ]),
                    "filter_name": .object([
                        "type": .string("string"),
                        "description": .string("Filter by name")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort: name, -name, platform, -platform, seedId, -seedId")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_platform": .object([
                        "type": .string("string"),
                        "description": .string("Filter by platform: IOS, MAC_OS")
                    ]),
                    "filter_status": .object([
                        "type": .string("string"),
                        "description": .string("Filter by status: ENABLED, DISABLED")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort: name, -name, platform, -platform, udid, -udid, status, -status")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
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
                        "description": .string("Platform: IOS, MAC_OS")
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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by certificate type (e.g. IOS_DISTRIBUTION)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort: displayName, -displayName, serialNumber, -serialNumber")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getCertificateTool() -> Tool {
        return Tool(
            name: "provisioning_get_certificate",
            description: "Get details of a signing certificate",
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
            description: "Get details of a provisioning profile",
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
            description: "Create a new provisioning profile",
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
                        "description": .string("Array of certificate resource IDs to include in the profile")
                    ]),
                    "device_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of device resource IDs (optional, not needed for App Store/Direct profiles)")
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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
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
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "filter_profile_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by type (e.g. IOS_APP_STORE)")
                    ]),
                    "filter_profile_state": .object([
                        "type": .string("string"),
                        "description": .string("Filter by state: ACTIVE, INVALID")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort: name, -name, profileState, -profileState")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }
}
