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
            var queryParams: [String: String] = [:]

            queryParams["limit"] = String(try provisioningLimit(arguments?["limit"]))
            queryParams["filter[platform]"] = try provisioningEnumList(
                arguments?["filter_platform"],
                name: "filter_platform",
                allowedValues: Set(ProvisioningWorker.bundleIdPlatforms)
            )

            if let identifierValue = arguments?["filter_identifier"],
               let identifier = identifierValue.stringValue {
                queryParams["filter[identifier]"] = identifier
            }

            if let nameValue = arguments?["filter_name"],
               let name = nameValue.stringValue {
                queryParams["filter[name]"] = name
            }

            if let seedIdValue = arguments?["filter_seed_id"],
               let seedId = seedIdValue.stringValue {
                queryParams["filter[seedId]"] = seedId
            }

            if let idValue = arguments?["filter_id"],
               let id = idValue.stringValue {
                queryParams["filter[id]"] = id
            }

            queryParams["sort"] = try provisioningEnumList(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(ProvisioningWorker.bundleIdSortValues)
            )

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/bundleIds",
                        query: queryParams
                    ),
                    as: ASCBundleIdsResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list bundle IDs: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBundleIdResponse = try await httpClient.get(
                "/v1/bundleIds/\(try ASCPathSegment.encode(resourceId))",
                as: ASCBundleIdResponse.self
            )

            let bundleId = formatBundleId(response.data)

            let result = [
                "success": true,
                "bundle_id": bundleId
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get bundle ID: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: name, identifier, platform")],
                isError: true
            )
        }
        guard ProvisioningWorker.bundleIdPlatforms.contains(platform) else {
            return MCPResult.error("'platform' must be one of: \(ProvisioningWorker.bundleIdPlatforms.joined(separator: ", "))")
        }

        let seedId: ASCNullable<String>?
        if let value = arguments["seed_id"] {
            if value.isNull {
                seedId = .null
            } else if let string = value.stringValue {
                seedId = .value(string)
            } else {
                return MCPResult.error("'seed_id' must be a string or null")
            }
        } else {
            seedId = nil
        }

        do {
            let request = CreateBundleIdRequest(
                data: CreateBundleIdRequest.CreateBundleIdData(
                    attributes: CreateBundleIdRequest.CreateBundleIdAttributes(
                        name: name,
                        identifier: identifier,
                        platform: platform,
                        nullableSeedId: seedId
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create bundle ID")
        }
    }

    /// Deletes a bundle identifier
    /// - Returns: JSON confirmation
    func deleteBundleId(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["bundle_id_resource_id"],
              let resourceId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/bundleIds/\(try ASCPathSegment.encode(resourceId))")

            let result = [
                "success": true,
                "message": "Bundle ID '\(resourceId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete bundle ID")
        }
    }

    /// Lists registered devices
    /// - Returns: JSON array of devices
    func listDevices(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCDevicesResponse
            var queryParams: [String: String] = [:]

            queryParams["limit"] = String(try provisioningLimit(arguments?["limit"]))
            queryParams["filter[platform]"] = try provisioningEnumList(
                arguments?["filter_platform"],
                name: "filter_platform",
                allowedValues: Set(ProvisioningWorker.bundleIdPlatforms)
            )
            queryParams["filter[status]"] = try provisioningEnumList(
                arguments?["filter_status"],
                name: "filter_status",
                allowedValues: Set(ProvisioningWorker.deviceStatuses)
            )

            if let nameValue = arguments?["filter_name"],
               let name = nameValue.stringValue {
                queryParams["filter[name]"] = name
            }

            if let udidValue = arguments?["filter_udid"],
               let udid = udidValue.stringValue {
                queryParams["filter[udid]"] = udid
            }

            if let idValue = arguments?["filter_id"],
               let id = idValue.stringValue {
                queryParams["filter[id]"] = id
            }

            queryParams["sort"] = try provisioningEnumList(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(ProvisioningWorker.deviceSortValues)
            )

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/devices",
                        query: queryParams
                    ),
                    as: ASCDevicesResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list devices: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: name, udid, platform")],
                isError: true
            )
        }
        guard ProvisioningWorker.bundleIdPlatforms.contains(platform) else {
            return MCPResult.error("'platform' must be one of: \(ProvisioningWorker.bundleIdPlatforms.joined(separator: ", "))")
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to register device")
        }
    }

    /// Updates a device's name or status
    /// - Returns: JSON with updated device details
    func updateDevice(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let deviceIdValue = arguments["device_id"],
              let deviceId = deviceIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'device_id' is missing")],
                isError: true
            )
        }

        let name: ASCNullable<String>?
        if let value = arguments["name"] {
            if value.isNull {
                name = .null
            } else if let string = value.stringValue {
                name = .value(string)
            } else {
                return MCPResult.error("'name' must be a string or null")
            }
        } else {
            name = nil
        }

        let status: ASCNullable<String>?
        if let value = arguments["status"] {
            if value.isNull {
                status = .null
            } else if let string = value.stringValue,
                      ProvisioningWorker.deviceStatuses.contains(string) {
                status = .value(string)
            } else {
                return MCPResult.error("'status' must be null or one of: \(ProvisioningWorker.deviceStatuses.joined(separator: ", "))")
            }
        } else {
            status = nil
        }

        guard name != nil || status != nil else {
            return MCPResult.error("Provide at least one update field: name or status")
        }

        do {
            let request = UpdateDeviceRequest(
                data: UpdateDeviceRequest.UpdateDeviceData(
                    id: deviceId,
                    attributes: UpdateDeviceRequest.UpdateDeviceAttributes(
                        nullableName: name,
                        nullableStatus: status
                    )
                )
            )

            let response: ASCDeviceResponse = try await httpClient.patch(
                "/v1/devices/\(try ASCPathSegment.encode(deviceId))",
                body: request,
                as: ASCDeviceResponse.self
            )

            let device = formatDevice(response.data)

            let result = [
                "success": true,
                "device": device
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to update device")
        }
    }

    /// Lists signing certificates
    /// - Returns: JSON array of certificates (without private content)
    func listCertificates(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCCertificatesResponse
            var queryParams: [String: String] = [:]

            queryParams["limit"] = String(try provisioningLimit(arguments?["limit"]))
            queryParams["filter[certificateType]"] = try provisioningEnumList(
                arguments?["filter_type"],
                name: "filter_type",
                allowedValues: Set(ProvisioningWorker.certificateTypes)
            )

            if let displayNameValue = arguments?["filter_display_name"],
               let displayName = displayNameValue.stringValue {
                queryParams["filter[displayName]"] = displayName
            }

            if let serialNumberValue = arguments?["filter_serial_number"],
               let serialNumber = serialNumberValue.stringValue {
                queryParams["filter[serialNumber]"] = serialNumber
            }

            if let idValue = arguments?["filter_id"],
               let id = idValue.stringValue {
                queryParams["filter[id]"] = id
            }

            queryParams["sort"] = try provisioningEnumList(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(ProvisioningWorker.certificateSortValues)
            )

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/certificates",
                        query: queryParams
                    ),
                    as: ASCCertificatesResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list certificates: \(error.localizedDescription)")],
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
            var queryParams: [String: String] = [:]

            queryParams["limit"] = String(try provisioningLimit(arguments?["limit"]))
            queryParams["filter[profileType]"] = try provisioningEnumList(
                arguments?["filter_profile_type"],
                name: "filter_profile_type",
                allowedValues: Set(ProvisioningWorker.profileTypes)
            )
            queryParams["filter[profileState]"] = try provisioningEnumList(
                arguments?["filter_profile_state"],
                name: "filter_profile_state",
                allowedValues: Set(ProvisioningWorker.profileStates)
            )

            if let nameValue = arguments?["filter_name"],
               let name = nameValue.stringValue {
                queryParams["filter[name]"] = name
            }

            if let idValue = arguments?["filter_id"],
               let id = idValue.stringValue {
                queryParams["filter[id]"] = id
            }

            queryParams["sort"] = try provisioningEnumList(
                arguments?["sort"],
                name: "sort",
                allowedValues: Set(ProvisioningWorker.profileSortValues)
            )

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/profiles",
                        query: queryParams
                    ),
                    as: ASCProfilesResponse.self
                )
            } else {
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list profiles: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'certificate_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCCertificateResponse = try await httpClient.get(
                "/v1/certificates/\(try ASCPathSegment.encode(certificateId))",
                as: ASCCertificateResponse.self
            )

            let certificate = formatCertificate(response.data, includeContent: true)

            let result = [
                "success": true,
                "certificate": certificate
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get certificate: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'certificate_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/certificates/\(try ASCPathSegment.encode(certificateId))")

            let result = [
                "success": true,
                "message": "Certificate '\(certificateId)' revoked"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to revoke certificate")
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
                content: [MCPContent.text("Error: Required parameter 'profile_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCProfileResponse = try await httpClient.get(
                "/v1/profiles/\(try ASCPathSegment.encode(profileId))",
                as: ASCProfileResponse.self
            )

            let profile = formatProfile(response.data, includeContent: true)

            let result = [
                "success": true,
                "profile": profile
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get profile: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'profile_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/profiles/\(try ASCPathSegment.encode(profileId))")

            let result = [
                "success": true,
                "message": "Profile '\(profileId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete profile")
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
                content: [MCPContent.text("Error: Required parameters: name, profile_type, bundle_id_resource_id, certificate_ids")],
                isError: true
            )
        }
        guard ProvisioningWorker.profileTypes.contains(profileType) else {
            return MCPResult.error("'profile_type' must be one of: \(ProvisioningWorker.profileTypes.joined(separator: ", "))")
        }

        let certificateIds = certIdsArray.compactMap(\.stringValue)
        guard certificateIds.count == certIdsArray.count,
              !certificateIds.isEmpty,
              certificateIds.allSatisfy({ !$0.isEmpty }) else {
            return MCPResult.error("'certificate_ids' must contain only non-empty string IDs")
        }
        guard Set(certificateIds).count == certificateIds.count else {
            return MCPResult.error("'certificate_ids' must not contain duplicate values")
        }

        let deviceIds: [String]?
        if let deviceIdsValue = arguments["device_ids"] {
            guard let deviceIdsArray = deviceIdsValue.arrayValue else {
                return MCPResult.error("'device_ids' must be an array of strings")
            }
            let parsedDeviceIds = deviceIdsArray.compactMap(\.stringValue)
            guard parsedDeviceIds.count == deviceIdsArray.count,
                  !parsedDeviceIds.isEmpty,
                  parsedDeviceIds.allSatisfy({ !$0.isEmpty }) else {
                return MCPResult.error("'device_ids' must contain only non-empty string IDs")
            }
            guard Set(parsedDeviceIds).count == parsedDeviceIds.count else {
                return MCPResult.error("'device_ids' must not contain duplicate values")
            }
            deviceIds = parsedDeviceIds
        } else {
            deviceIds = nil
        }

        do {
            let certificateItems = certificateIds.map {
                CreateProfileRequest.RelationshipItem(type: "certificates", id: $0)
            }

            let deviceItems = deviceIds?.map {
                CreateProfileRequest.RelationshipItem(type: "devices", id: $0)
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

            let profile = formatProfile(response.data, includeContent: true)

            let result = [
                "success": true,
                "profile": profile
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to create profile")
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
                content: [MCPContent.text("Error: Required parameter 'bundle_id_resource_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBundleIdCapabilitiesResponse
            var queryParams: [String: String] = [:]

            queryParams["limit"] = String(try provisioningLimit(arguments["limit"]))

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/bundleIds/\(try ASCPathSegment.encode(bundleIdResourceId))/bundleIdCapabilities",
                        query: queryParams
                    ),
                    as: ASCBundleIdCapabilitiesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/bundleIds/\(try ASCPathSegment.encode(bundleIdResourceId))/bundleIdCapabilities",
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list capabilities: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: bundle_id_resource_id, capability_type")],
                isError: true
            )
        }
        guard ProvisioningWorker.capabilityTypes.contains(capabilityType) else {
            return MCPResult.error("'capability_type' must be one of: \(ProvisioningWorker.capabilityTypes.joined(separator: ", "))")
        }

        let settings: ASCNullable<[CapabilitySetting]>?
        do {
            settings = try capabilitySettings(arguments["settings"])
        } catch {
            return MCPResult.error(error, prefix: "Invalid capability settings")
        }

        do {
            let request = EnableCapabilityRequest(
                data: EnableCapabilityRequest.EnableCapabilityData(
                    attributes: EnableCapabilityRequest.EnableCapabilityAttributes(
                        capabilityType: capabilityType,
                        nullableSettings: settings
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

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to enable capability")
        }
    }

    /// Disables a capability on a bundle ID
    /// - Returns: JSON confirmation
    func disableCapability(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let idValue = arguments["capability_id"],
              let capabilityId = idValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'capability_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/bundleIdCapabilities/\(try ASCPathSegment.encode(capabilityId))")

            let result = [
                "success": true,
                "message": "Capability '\(capabilityId)' disabled"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to disable capability")
        }
    }

    // MARK: - Formatting

    private func formatBundleId(_ bundleId: ASCBundleId) -> [String: Any] {
        return [
            "id": bundleId.id,
            "type": bundleId.type,
            "name": (bundleId.attributes?.name).jsonSafe,
            "identifier": (bundleId.attributes?.identifier).jsonSafe,
            "platform": (bundleId.attributes?.platform).jsonSafe,
            "seedId": (bundleId.attributes?.seedId).jsonSafe
        ]
    }

    private func formatDevice(_ device: ASCDevice) -> [String: Any] {
        return [
            "id": device.id,
            "type": device.type,
            "name": (device.attributes?.name).jsonSafe,
            "platform": (device.attributes?.platform).jsonSafe,
            "udid": (device.attributes?.udid).jsonSafe,
            "deviceClass": (device.attributes?.deviceClass).jsonSafe,
            "status": (device.attributes?.status).jsonSafe,
            "model": (device.attributes?.model).jsonSafe,
            "addedDate": (device.attributes?.addedDate).jsonSafe
        ]
    }

    private func formatCertificate(_ cert: ASCCertificate, includeContent: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "id": cert.id,
            "type": cert.type,
            "name": (cert.attributes?.name).jsonSafe,
            "certificateType": (cert.attributes?.certificateType).jsonSafe,
            "displayName": (cert.attributes?.displayName).jsonSafe,
            "serialNumber": (cert.attributes?.serialNumber).jsonSafe,
            "platform": (cert.attributes?.platform).jsonSafe,
            "expirationDate": (cert.attributes?.expirationDate).jsonSafe,
            "activated": (cert.attributes?.activated).jsonSafe
        ]
        if includeContent {
            result["certificateContent"] = (cert.attributes?.certificateContent).jsonSafe
        }
        return result
    }

    private func formatProfile(_ profile: ASCProfile, includeContent: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "id": profile.id,
            "type": profile.type,
            "name": (profile.attributes?.name).jsonSafe,
            "platform": (profile.attributes?.platform).jsonSafe,
            "profileType": (profile.attributes?.profileType).jsonSafe,
            "profileState": (profile.attributes?.profileState).jsonSafe,
            "uuid": (profile.attributes?.uuid).jsonSafe,
            "createdDate": (profile.attributes?.createdDate).jsonSafe,
            "expirationDate": (profile.attributes?.expirationDate).jsonSafe
        ]
        if includeContent {
            result["profileContent"] = (profile.attributes?.profileContent).jsonSafe
        }
        return result
    }

    private func formatCapability(_ capability: ASCBundleIdCapability) -> [String: Any] {
        var result: [String: Any] = [
            "id": capability.id,
            "type": capability.type,
            "capabilityType": (capability.attributes?.capabilityType).jsonSafe
        ]

        if let settings = capability.attributes?.settings {
            let formattedSettings = settings.map { setting -> [String: Any] in
                var s: [String: Any] = [
                    "key": setting.key.jsonSafe,
                    "name": setting.name.jsonSafe
                ]
                if let desc = setting.description {
                    s["description"] = desc
                }
                if let enabledByDefault = setting.enabledByDefault {
                    s["enabledByDefault"] = enabledByDefault
                }
                if let visible = setting.visible {
                    s["visible"] = visible
                }
                if let allowedInstances = setting.allowedInstances {
                    s["allowedInstances"] = allowedInstances
                }
                if let minInstances = setting.minInstances {
                    s["minInstances"] = minInstances
                }
                if let options = setting.options {
                    s["options"] = options.map { option -> [String: Any] in
                        var o: [String: Any] = [
                            "key": option.key.jsonSafe,
                            "name": option.name.jsonSafe
                        ]
                        if let desc = option.description {
                            o["description"] = desc
                        }
                        if let enabledByDefault = option.enabledByDefault {
                            o["enabledByDefault"] = enabledByDefault
                        }
                        if let enabled = option.enabled {
                            o["enabled"] = enabled
                        }
                        if let supportsWildcard = option.supportsWildcard {
                            o["supportsWildcard"] = supportsWildcard
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

    private func provisioningLimit(_ value: Value?) throws -> Int {
        guard let value else {
            return 25
        }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw ProvisioningInputValidationError("'limit' must be an integer from 1 through 200")
        }
        return limit
    }

    private func provisioningEnumList(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>
    ) throws -> String? {
        guard let value else {
            return nil
        }

        let values: [String]
        if let string = value.stringValue {
            values = string.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw ProvisioningInputValidationError("'\(name)' must be a string or an array of strings")
            }
            values = strings
        } else {
            throw ProvisioningInputValidationError("'\(name)' must be a string or an array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw ProvisioningInputValidationError("'\(name)' must contain at least one value")
        }
        let unsupported = values.filter { !allowedValues.contains($0) }
        guard unsupported.isEmpty else {
            throw ProvisioningInputValidationError(
                "Unsupported value(s) for '\(name)': \(unsupported.joined(separator: ", "))"
            )
        }
        return values.joined(separator: ",")
    }

    private func capabilitySettings(_ value: Value?) throws -> ASCNullable<[CapabilitySetting]>? {
        guard let value else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let values = value.arrayValue else {
            throw ProvisioningInputValidationError("'settings' must be an array or null")
        }
        return .value(try values.enumerated().map { index, value in
            try capabilitySetting(value, path: "settings[\(index)]")
        })
    }

    private func capabilitySetting(_ value: Value, path: String) throws -> CapabilitySetting {
        guard let object = value.objectValue else {
            throw ProvisioningInputValidationError("'\(path)' must be an object")
        }
        let allowedKeys: Set<String> = [
            "key", "name", "description", "enabledByDefault", "visible",
            "allowedInstances", "minInstances", "options"
        ]
        if let unknown = object.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw ProvisioningInputValidationError("Unknown field '\(path).\(unknown)'")
        }
        return CapabilitySetting(
            key: try capabilityString(
                object["key"],
                path: "\(path).key",
                allowedValues: Set(ProvisioningWorker.capabilitySettingKeys)
            ),
            name: try capabilityString(object["name"], path: "\(path).name"),
            description: try capabilityString(object["description"], path: "\(path).description"),
            enabledByDefault: try capabilityBool(object["enabledByDefault"], path: "\(path).enabledByDefault"),
            visible: try capabilityBool(object["visible"], path: "\(path).visible"),
            allowedInstances: try capabilityString(
                object["allowedInstances"],
                path: "\(path).allowedInstances",
                allowedValues: Set(ProvisioningWorker.capabilityAllowedInstances)
            ),
            minInstances: try capabilityInt(object["minInstances"], path: "\(path).minInstances"),
            options: try capabilityOptions(object["options"], path: "\(path).options")
        )
    }

    private func capabilityOptions(_ value: Value?, path: String) throws -> [CapabilityOption]? {
        guard let value else {
            return nil
        }
        guard let values = value.arrayValue else {
            throw ProvisioningInputValidationError("'\(path)' must be an array")
        }
        return try values.enumerated().map { index, value in
            try capabilityOption(value, path: "\(path)[\(index)]")
        }
    }

    private func capabilityOption(_ value: Value, path: String) throws -> CapabilityOption {
        guard let object = value.objectValue else {
            throw ProvisioningInputValidationError("'\(path)' must be an object")
        }
        let allowedKeys: Set<String> = [
            "key", "name", "description", "enabledByDefault", "enabled", "supportsWildcard"
        ]
        if let unknown = object.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw ProvisioningInputValidationError("Unknown field '\(path).\(unknown)'")
        }
        return CapabilityOption(
            key: try capabilityString(
                object["key"],
                path: "\(path).key",
                allowedValues: Set(ProvisioningWorker.capabilityOptionKeys)
            ),
            name: try capabilityString(object["name"], path: "\(path).name"),
            description: try capabilityString(object["description"], path: "\(path).description"),
            enabledByDefault: try capabilityBool(object["enabledByDefault"], path: "\(path).enabledByDefault"),
            enabled: try capabilityBool(object["enabled"], path: "\(path).enabled"),
            supportsWildcard: try capabilityBool(object["supportsWildcard"], path: "\(path).supportsWildcard")
        )
    }

    private func capabilityString(
        _ value: Value?,
        path: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else {
            return nil
        }
        guard let string = value.stringValue else {
            throw ProvisioningInputValidationError("'\(path)' must be a string")
        }
        if let allowedValues, !allowedValues.contains(string) {
            throw ProvisioningInputValidationError("Unsupported value for '\(path)': \(string)")
        }
        return string
    }

    private func capabilityBool(_ value: Value?, path: String) throws -> Bool? {
        guard let value else {
            return nil
        }
        guard let boolean = value.boolValue else {
            throw ProvisioningInputValidationError("'\(path)' must be a boolean")
        }
        return boolean
    }

    private func capabilityInt(_ value: Value?, path: String) throws -> Int? {
        guard let value else {
            return nil
        }
        guard let integer = value.intValue else {
            throw ProvisioningInputValidationError("'\(path)' must be an integer")
        }
        return integer
    }
}

private struct ProvisioningInputValidationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
