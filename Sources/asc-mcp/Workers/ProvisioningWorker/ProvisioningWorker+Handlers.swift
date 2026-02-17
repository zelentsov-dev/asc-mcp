import Foundation
import MCP

// MARK: - Tool Handlers
extension ProvisioningWorker {

    /// Lists bundle identifiers
    /// - Returns: JSON array of bundle IDs
    func listBundleIds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCBundleIdsResponse

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBundleIdsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let platformValue = arguments?["filter_platform"],
                   let platform = platformValue.stringValue {
                    queryParams["filter[platform]"] = platform
                }

                if let identifierValue = arguments?["filter_identifier"],
                   let identifier = identifierValue.stringValue {
                    queryParams["filter[identifier]"] = identifier
                }

                if let nameValue = arguments?["filter_name"],
                   let name = nameValue.stringValue {
                    queryParams["filter[name]"] = name
                }

                if let sortValue = arguments?["sort"],
                   let sort = sortValue.stringValue {
                    queryParams["sort"] = sort
                }

                response = try await httpClient.get(
                    "/v1/bundleIds",
                    parameters: queryParams,
                    as: ASCBundleIdsResponse.self
                )
            }

            let bundleIds = response.data.map { formatBundleId($0) }

            var result: [String: Any] = [
                "success": true,
                "bundle_ids": bundleIds,
                "count": bundleIds.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list bundle IDs: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a bundle identifier
    /// - Returns: JSON with bundle ID details
    func getBundleId(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["bundle_id_resource_id"],
              let resourceId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBundleIdResponse = try await httpClient.get(
                "/v1/bundleIds/\(resourceId)",
                as: ASCBundleIdResponse.self
            )

            let bundleId = formatBundleId(response.data)

            let result = [
                "success": true,
                "bundle_id": bundleId
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get bundle ID: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new bundle identifier
    /// - Returns: JSON with created bundle ID
    func createBundleId(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue,
              let identifierValue = arguments["identifier"],
              let identifier = identifierValue.stringValue,
              let platformValue = arguments["platform"],
              let platform = platformValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: name, identifier, platform")],
                isError: true
            )
        }

        do {
            let request = CreateBundleIdRequest(
                data: CreateBundleIdRequest.CreateBundleIdData(
                    attributes: CreateBundleIdRequest.CreateBundleIdAttributes(
                        name: name,
                        identifier: identifier,
                        platform: platform
                    )
                )
            )

            let response: ASCBundleIdResponse = try await httpClient.post(
                "/v1/bundleIds",
                body: request,
                as: ASCBundleIdResponse.self
            )

            let bundleId = formatBundleId(response.data)

            let result = [
                "success": true,
                "bundle_id": bundleId
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create bundle ID: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a bundle identifier
    /// - Returns: JSON confirmation
    func deleteBundleId(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["bundle_id_resource_id"],
              let resourceId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/bundleIds/\(resourceId)")

            let result = [
                "success": true,
                "message": "Bundle ID '\(resourceId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete bundle ID: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists registered devices
    /// - Returns: JSON array of devices
    func listDevices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCDevicesResponse

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCDevicesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let platformValue = arguments?["filter_platform"],
                   let platform = platformValue.stringValue {
                    queryParams["filter[platform]"] = platform
                }

                if let statusValue = arguments?["filter_status"],
                   let status = statusValue.stringValue {
                    queryParams["filter[status]"] = status
                }

                if let sortValue = arguments?["sort"],
                   let sort = sortValue.stringValue {
                    queryParams["sort"] = sort
                }

                response = try await httpClient.get(
                    "/v1/devices",
                    parameters: queryParams,
                    as: ASCDevicesResponse.self
                )
            }

            let devices = response.data.map { formatDevice($0) }

            var result: [String: Any] = [
                "success": true,
                "devices": devices,
                "count": devices.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list devices: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Registers a new device
    /// - Returns: JSON with registered device details
    func registerDevice(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue,
              let udidValue = arguments["udid"],
              let udid = udidValue.stringValue,
              let platformValue = arguments["platform"],
              let platform = platformValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: name, udid, platform")],
                isError: true
            )
        }

        do {
            let request = RegisterDeviceRequest(
                data: RegisterDeviceRequest.RegisterDeviceData(
                    attributes: RegisterDeviceRequest.RegisterDeviceAttributes(
                        name: name,
                        udid: udid,
                        platform: platform
                    )
                )
            )

            let response: ASCDeviceResponse = try await httpClient.post(
                "/v1/devices",
                body: request,
                as: ASCDeviceResponse.self
            )

            let device = formatDevice(response.data)

            let result = [
                "success": true,
                "device": device
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to register device: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a device's name or status
    /// - Returns: JSON with updated device details
    func updateDevice(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let deviceIdValue = arguments["device_id"],
              let deviceId = deviceIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'device_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateDeviceRequest(
                data: UpdateDeviceRequest.UpdateDeviceData(
                    id: deviceId,
                    attributes: UpdateDeviceRequest.UpdateDeviceAttributes(
                        name: arguments["name"]?.stringValue,
                        status: arguments["status"]?.stringValue
                    )
                )
            )

            let response: ASCDeviceResponse = try await httpClient.patch(
                "/v1/devices/\(deviceId)",
                body: request,
                as: ASCDeviceResponse.self
            )

            let device = formatDevice(response.data)

            let result = [
                "success": true,
                "device": device
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update device: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists signing certificates
    /// - Returns: JSON array of certificates (without private content)
    func listCertificates(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCCertificatesResponse

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCCertificatesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let typeValue = arguments?["filter_type"],
                   let type = typeValue.stringValue {
                    queryParams["filter[certificateType]"] = type
                }

                if let sortValue = arguments?["sort"],
                   let sort = sortValue.stringValue {
                    queryParams["sort"] = sort
                }

                response = try await httpClient.get(
                    "/v1/certificates",
                    parameters: queryParams,
                    as: ASCCertificatesResponse.self
                )
            }

            let certificates = response.data.map { formatCertificate($0) }

            var result: [String: Any] = [
                "success": true,
                "certificates": certificates,
                "count": certificates.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list certificates: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists provisioning profiles
    /// - Returns: JSON array of profiles (without content blob)
    func listProfiles(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCProfilesResponse

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCProfilesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments?["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                if let typeValue = arguments?["filter_profile_type"],
                   let type = typeValue.stringValue {
                    queryParams["filter[profileType]"] = type
                }

                if let stateValue = arguments?["filter_profile_state"],
                   let state = stateValue.stringValue {
                    queryParams["filter[profileState]"] = state
                }

                if let sortValue = arguments?["sort"],
                   let sort = sortValue.stringValue {
                    queryParams["sort"] = sort
                }

                response = try await httpClient.get(
                    "/v1/profiles",
                    parameters: queryParams,
                    as: ASCProfilesResponse.self
                )
            }

            let profiles = response.data.map { formatProfile($0) }

            var result: [String: Any] = [
                "success": true,
                "profiles": profiles,
                "count": profiles.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list profiles: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Certificate Get/Revoke

    /// Gets details of a signing certificate
    /// - Returns: JSON with certificate details
    func getCertificate(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["certificate_id"],
              let certificateId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'certificate_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCertificateResponse = try await httpClient.get(
                "/v1/certificates/\(certificateId)",
                as: ASCCertificateResponse.self
            )

            let certificate = formatCertificate(response.data)

            let result = [
                "success": true,
                "certificate": certificate
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get certificate: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Revokes a signing certificate
    /// - Returns: JSON confirmation
    func revokeCertificate(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["certificate_id"],
              let certificateId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'certificate_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/certificates/\(certificateId)")

            let result = [
                "success": true,
                "message": "Certificate '\(certificateId)' revoked"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to revoke certificate: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Profile Get/Delete/Create

    /// Gets details of a provisioning profile
    /// - Returns: JSON with profile details
    func getProfile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["profile_id"],
              let profileId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'profile_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCProfileResponse = try await httpClient.get(
                "/v1/profiles/\(profileId)",
                as: ASCProfileResponse.self
            )

            let profile = formatProfile(response.data)

            let result = [
                "success": true,
                "profile": profile
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get profile: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a provisioning profile
    /// - Returns: JSON confirmation
    func deleteProfile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["profile_id"],
              let profileId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'profile_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/profiles/\(profileId)")

            let result = [
                "success": true,
                "message": "Profile '\(profileId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete profile: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new provisioning profile
    /// - Returns: JSON with created profile details
    func createProfile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let nameValue = arguments["name"],
              let name = nameValue.stringValue,
              let profileTypeValue = arguments["profile_type"],
              let profileType = profileTypeValue.stringValue,
              let bundleIdValue = arguments["bundle_id_resource_id"],
              let bundleIdResourceId = bundleIdValue.stringValue,
              let certIdsValue = arguments["certificate_ids"],
              let certIdsArray = certIdsValue.arrayValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: name, profile_type, bundle_id_resource_id, certificate_ids")],
                isError: true
            )
        }

        do {
            let certificateItems = certIdsArray.compactMap { value -> CreateProfileRequest.RelationshipItem? in
                guard let id = value.stringValue else { return nil }
                return CreateProfileRequest.RelationshipItem(type: "certificates", id: id)
            }

            var deviceItems: [CreateProfileRequest.RelationshipItem]? = nil
            if let deviceIdsValue = arguments["device_ids"],
               let deviceIdsArray = deviceIdsValue.arrayValue {
                deviceItems = deviceIdsArray.compactMap { value -> CreateProfileRequest.RelationshipItem? in
                    guard let id = value.stringValue else { return nil }
                    return CreateProfileRequest.RelationshipItem(type: "devices", id: id)
                }
            }

            let devicesRelationship: CreateProfileRequest.RelationshipDataArray? =
                deviceItems.map { CreateProfileRequest.RelationshipDataArray(data: $0) }

            let request = CreateProfileRequest(
                data: CreateProfileRequest.CreateProfileData(
                    attributes: CreateProfileRequest.CreateProfileAttributes(
                        name: name,
                        profileType: profileType
                    ),
                    relationships: CreateProfileRequest.CreateProfileRelationships(
                        bundleId: CreateProfileRequest.RelationshipData(
                            data: CreateProfileRequest.RelationshipItem(type: "bundleIds", id: bundleIdResourceId)
                        ),
                        certificates: CreateProfileRequest.RelationshipDataArray(data: certificateItems),
                        devices: devicesRelationship
                    )
                )
            )

            let response: ASCProfileResponse = try await httpClient.post(
                "/v1/profiles",
                body: request,
                as: ASCProfileResponse.self
            )

            let profile = formatProfile(response.data)

            let result = [
                "success": true,
                "profile": profile
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create profile: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Capability Handlers

    /// Lists capabilities for a bundle ID
    /// - Returns: JSON array of capabilities with pagination
    func listCapabilities(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["bundle_id_resource_id"],
              let bundleIdResourceId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBundleIdCapabilitiesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBundleIdCapabilitiesResponse.self)
            } else {
                // Note: Apple API does not support limit parameter for this endpoint despite documentation
                let queryParams: [String: String] = [:]

                response = try await httpClient.get(
                    "/v1/bundleIds/\(bundleIdResourceId)/bundleIdCapabilities",
                    parameters: queryParams,
                    as: ASCBundleIdCapabilitiesResponse.self
                )
            }

            let capabilities = response.data.map { formatCapability($0) }

            var result: [String: Any] = [
                "success": true,
                "capabilities": capabilities,
                "count": capabilities.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list capabilities: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Enables a capability on a bundle ID
    /// - Returns: JSON with enabled capability details
    func enableCapability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let bundleIdValue = arguments["bundle_id_resource_id"],
              let bundleIdResourceId = bundleIdValue.stringValue,
              let capTypeValue = arguments["capability_type"],
              let capabilityType = capTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: bundle_id_resource_id, capability_type")],
                isError: true
            )
        }

        do {
            var settings: [CapabilitySetting]? = nil
            if let settingsValue = arguments["settings"],
               let settingsString = settingsValue.stringValue,
               let settingsData = settingsString.data(using: .utf8) {
                settings = try JSONDecoder().decode([CapabilitySetting].self, from: settingsData)
            }

            let request = EnableCapabilityRequest(
                data: EnableCapabilityRequest.EnableCapabilityData(
                    attributes: EnableCapabilityRequest.EnableCapabilityAttributes(
                        capabilityType: capabilityType,
                        settings: settings
                    ),
                    relationships: EnableCapabilityRequest.EnableCapabilityRelationships(
                        bundleId: EnableCapabilityRequest.EnableCapabilityBundleIdData(
                            data: EnableCapabilityRequest.EnableCapabilityBundleIdItem(
                                id: bundleIdResourceId
                            )
                        )
                    )
                )
            )

            let response: ASCBundleIdCapabilityResponse = try await httpClient.post(
                "/v1/bundleIdCapabilities",
                body: request,
                as: ASCBundleIdCapabilityResponse.self
            )

            let capability = formatCapability(response.data)

            let result = [
                "success": true,
                "capability": capability
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to enable capability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Disables a capability on a bundle ID
    /// - Returns: JSON confirmation
    func disableCapability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["capability_id"],
              let capabilityId = idValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'capability_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/bundleIdCapabilities/\(capabilityId)")

            let result = [
                "success": true,
                "message": "Capability '\(capabilityId)' disabled"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to disable capability: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatBundleId(_ bundleId: ASCBundleId) -> [String: Any] {
        return [
            "id": bundleId.id,
            "type": bundleId.type,
            "name": bundleId.attributes.name.jsonSafe,
            "identifier": bundleId.attributes.identifier.jsonSafe,
            "platform": bundleId.attributes.platform.jsonSafe,
            "seedId": bundleId.attributes.seedId.jsonSafe
        ]
    }

    private func formatDevice(_ device: ASCDevice) -> [String: Any] {
        return [
            "id": device.id,
            "type": device.type,
            "name": device.attributes.name.jsonSafe,
            "platform": device.attributes.platform.jsonSafe,
            "udid": device.attributes.udid.jsonSafe,
            "deviceClass": device.attributes.deviceClass.jsonSafe,
            "status": device.attributes.status.jsonSafe,
            "model": device.attributes.model.jsonSafe,
            "addedDate": device.attributes.addedDate.jsonSafe
        ]
    }

    private func formatCertificate(_ cert: ASCCertificate) -> [String: Any] {
        return [
            "id": cert.id,
            "type": cert.type,
            "name": cert.attributes.name.jsonSafe,
            "certificateType": cert.attributes.certificateType.jsonSafe,
            "displayName": cert.attributes.displayName.jsonSafe,
            "serialNumber": cert.attributes.serialNumber.jsonSafe,
            "platform": cert.attributes.platform.jsonSafe,
            "expirationDate": cert.attributes.expirationDate.jsonSafe
        ]
    }

    private func formatProfile(_ profile: ASCProfile) -> [String: Any] {
        return [
            "id": profile.id,
            "type": profile.type,
            "name": profile.attributes.name.jsonSafe,
            "platform": profile.attributes.platform.jsonSafe,
            "profileType": profile.attributes.profileType.jsonSafe,
            "profileState": profile.attributes.profileState.jsonSafe,
            "uuid": profile.attributes.uuid.jsonSafe,
            "expirationDate": profile.attributes.expirationDate.jsonSafe
        ]
    }

    private func formatCapability(_ capability: ASCBundleIdCapability) -> [String: Any] {
        var result: [String: Any] = [
            "id": capability.id,
            "type": capability.type,
            "capabilityType": capability.attributes.capabilityType.jsonSafe
        ]

        if let settings = capability.attributes.settings, !settings.isEmpty {
            let formattedSettings = settings.map { setting -> [String: Any] in
                var s: [String: Any] = [
                    "key": setting.key.jsonSafe,
                    "name": setting.name.jsonSafe
                ]
                if let desc = setting.description {
                    s["description"] = desc
                }
                if let allowedInstances = setting.allowedInstances {
                    s["allowedInstances"] = allowedInstances
                }
                if let minInstances = setting.minInstances {
                    s["minInstances"] = minInstances
                }
                if let options = setting.options, !options.isEmpty {
                    s["options"] = options.map { option -> [String: Any] in
                        var o: [String: Any] = [
                            "key": option.key.jsonSafe,
                            "name": option.name.jsonSafe
                        ]
                        if let desc = option.description {
                            o["description"] = desc
                        }
                        if let enabled = option.enabled {
                            o["enabled"] = enabled
                        }
                        return o
                    }
                }
                return s
            }
            result["settings"] = formattedSettings
        }

        return result
    }
}
