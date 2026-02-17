import Foundation
import MCP

/// ProvisioningWorker manages certificates, devices, profiles and bundle IDs
public final class ProvisioningWorker: Sendable {
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
