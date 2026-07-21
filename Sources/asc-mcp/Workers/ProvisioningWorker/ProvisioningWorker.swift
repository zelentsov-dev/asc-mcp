import Foundation
import MCP

/// ProvisioningWorker manages certificates, devices, profiles and bundle IDs
public final class ProvisioningWorker: Sendable {
    static let bundleIdPlatforms = ["IOS", "MAC_OS", "UNIVERSAL"]
    static let bundleIdSortValues = [
        "name", "-name", "platform", "-platform", "identifier", "-identifier",
        "seedId", "-seedId", "id", "-id"
    ]
    static let deviceStatuses = ["ENABLED", "DISABLED"]
    static let deviceSortValues = [
        "name", "-name", "platform", "-platform", "udid", "-udid",
        "status", "-status", "id", "-id"
    ]
    static let certificateTypes = [
        "APPLE_PAY",
        "APPLE_PAY_MERCHANT_IDENTITY",
        "APPLE_PAY_PSP_IDENTITY",
        "APPLE_PAY_RSA",
        "DEVELOPER_ID_KEXT",
        "DEVELOPER_ID_KEXT_G2",
        "DEVELOPER_ID_APPLICATION",
        "DEVELOPER_ID_APPLICATION_G2",
        "DEVELOPMENT",
        "DISTRIBUTION",
        "IDENTITY_ACCESS",
        "IOS_DEVELOPMENT",
        "IOS_DISTRIBUTION",
        "MAC_APP_DISTRIBUTION",
        "MAC_INSTALLER_DISTRIBUTION",
        "MAC_APP_DEVELOPMENT",
        "PASS_TYPE_ID",
        "PASS_TYPE_ID_WITH_NFC"
    ]
    static let certificateSortValues = [
        "displayName", "-displayName", "certificateType", "-certificateType",
        "serialNumber", "-serialNumber", "id", "-id"
    ]
    static let profileTypes = [
        "IOS_APP_DEVELOPMENT",
        "IOS_APP_STORE",
        "IOS_APP_ADHOC",
        "IOS_APP_INHOUSE",
        "MAC_APP_DEVELOPMENT",
        "MAC_APP_STORE",
        "MAC_APP_DIRECT",
        "TVOS_APP_DEVELOPMENT",
        "TVOS_APP_STORE",
        "TVOS_APP_ADHOC",
        "TVOS_APP_INHOUSE",
        "MAC_CATALYST_APP_DEVELOPMENT",
        "MAC_CATALYST_APP_STORE",
        "MAC_CATALYST_APP_DIRECT"
    ]
    static let profileStates = ["ACTIVE", "INVALID"]
    static let profileSortValues = [
        "name", "-name", "profileType", "-profileType", "profileState", "-profileState", "id", "-id"
    ]
    static let capabilityTypes = [
        "ICLOUD",
        "IN_APP_PURCHASE",
        "GAME_CENTER",
        "PUSH_NOTIFICATIONS",
        "WALLET",
        "INTER_APP_AUDIO",
        "MAPS",
        "ASSOCIATED_DOMAINS",
        "PERSONAL_VPN",
        "APP_GROUPS",
        "HEALTHKIT",
        "HOMEKIT",
        "WIRELESS_ACCESSORY_CONFIGURATION",
        "APPLE_PAY",
        "DATA_PROTECTION",
        "SIRIKIT",
        "NETWORK_EXTENSIONS",
        "MULTIPATH",
        "HOT_SPOT",
        "NFC_TAG_READING",
        "CLASSKIT",
        "AUTOFILL_CREDENTIAL_PROVIDER",
        "ACCESS_WIFI_INFORMATION",
        "NETWORK_CUSTOM_PROTOCOL",
        "COREMEDIA_HLS_LOW_LATENCY",
        "SYSTEM_EXTENSION_INSTALL",
        "USER_MANAGEMENT",
        "APPLE_ID_AUTH"
    ]
    static let capabilitySettingKeys = [
        "ICLOUD_VERSION",
        "DATA_PROTECTION_PERMISSION_LEVEL",
        "APPLE_ID_AUTH_APP_CONSENT"
    ]
    static let capabilityAllowedInstances = ["ENTRY", "SINGLE", "MULTIPLE"]
    static let capabilityOptionKeys = [
        "XCODE_5",
        "XCODE_6",
        "COMPLETE_PROTECTION",
        "PROTECTED_UNLESS_OPEN",
        "PROTECTED_UNTIL_FIRST_USER_AUTH",
        "PRIMARY_APP_CONSENT"
    ]

    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listBundleIdsTool(),
            getBundleIdTool(),
            createBundleIdTool(),
            deleteBundleIdTool(),
            listDevicesTool(),
            registerDeviceTool(),
            updateDeviceTool(),
            listCertificatesTool(),
            getCertificateTool(),
            revokeCertificateTool(),
            listProfilesTool(),
            getProfileTool(),
            deleteProfileTool(),
            createProfileTool(),
            listCapabilitiesTool(),
            enableCapabilityTool(),
            disableCapabilityTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "provisioning_list_bundle_ids":
            return try await listBundleIds(params)
        case "provisioning_get_bundle_id":
            return try await getBundleId(params)
        case "provisioning_create_bundle_id":
            return try await createBundleId(params)
        case "provisioning_delete_bundle_id":
            return try await deleteBundleId(params)
        case "provisioning_list_devices":
            return try await listDevices(params)
        case "provisioning_register_device":
            return try await registerDevice(params)
        case "provisioning_update_device":
            return try await updateDevice(params)
        case "provisioning_list_certificates":
            return try await listCertificates(params)
        case "provisioning_get_certificate":
            return try await getCertificate(params)
        case "provisioning_revoke_certificate":
            return try await revokeCertificate(params)
        case "provisioning_list_profiles":
            return try await listProfiles(params)
        case "provisioning_get_profile":
            return try await getProfile(params)
        case "provisioning_delete_profile":
            return try await deleteProfile(params)
        case "provisioning_create_profile":
            return try await createProfile(params)
        case "provisioning_list_capabilities":
            return try await listCapabilities(params)
        case "provisioning_enable_capability":
            return try await enableCapability(params)
        case "provisioning_disable_capability":
            return try await disableCapability(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
