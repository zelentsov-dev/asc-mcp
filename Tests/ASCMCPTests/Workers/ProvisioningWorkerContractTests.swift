import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Provisioning Worker Contract Tests")
struct ProvisioningWorkerContractTests {
    @Test("bundle ID creation forwards optional seed ID without changing existing calls")
    func bundleIDSeedIDIsOptionalAndForwarded() async throws {
        let response = #"{"data":{"type":"bundleIds","id":"bundle-1","attributes":{"name":"Example","identifier":"com.example.app","platform":"IOS","seedId":"SEED123"}}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: response),
            .init(statusCode: 201, body: response)
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_create_bundle_id",
            arguments: [
                "name": .string("Example"),
                "identifier": .string("com.example.app"),
                "platform": .string("IOS"),
                "seed_id": .string("SEED123")
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_create_bundle_id",
            arguments: [
                "name": .string("Example"),
                "identifier": .string("com.example.app"),
                "platform": .string("IOS")
            ]
        ))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let firstBody = try provisioningJSONBody(try #require(requests[safe: 0]))
        let firstData = try provisioningDictionary(firstBody["data"])
        let firstAttributes = try provisioningDictionary(firstData["attributes"])
        #expect(firstAttributes["seedId"] as? String == "SEED123")

        let secondBody = try provisioningJSONBody(try #require(requests[safe: 1]))
        let secondData = try provisioningDictionary(secondBody["data"])
        let secondAttributes = try provisioningDictionary(secondData["attributes"])
        #expect(secondAttributes["seedId"] == nil)
    }

    @Test("collection tools expose and forward every supported filter")
    func collectionFiltersAreForwarded() async throws {
        let transport = TestHTTPTransport(responses: Array(repeating: .init(statusCode: 200, body: #"{"data":[]}"#), count: 4))
        let worker = try await makeProvisioningWorker(transport: transport)

        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_bundle_ids",
            arguments: [
                "filter_name": .string("One,Two"),
                "filter_platform": .string("IOS,UNIVERSAL"),
                "filter_identifier": .string("com.example.one,com.example.two"),
                "filter_seed_id": .string("SEED1,SEED2"),
                "filter_id": .string("bundle-1,bundle-2")
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_devices",
            arguments: [
                "filter_name": .string("Phone One,Phone Two"),
                "filter_platform": .string("IOS,UNIVERSAL"),
                "filter_udid": .string("UDID1,UDID2"),
                "filter_status": .string("ENABLED,DISABLED"),
                "filter_id": .string("device-1,device-2")
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_certificates",
            arguments: [
                "filter_display_name": .string("Distribution One,Distribution Two"),
                "filter_type": .string("IOS_DISTRIBUTION,DISTRIBUTION"),
                "filter_serial_number": .string("SERIAL1,SERIAL2"),
                "filter_id": .string("certificate-1,certificate-2")
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_profiles",
            arguments: [
                "filter_name": .string("Profile One,Profile Two"),
                "filter_profile_type": .string("IOS_APP_STORE,MAC_APP_STORE"),
                "filter_profile_state": .string("ACTIVE,INVALID"),
                "filter_id": .string("profile-1,profile-2")
            ]
        ))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)

        let bundleQuery = provisioningQueryItems(try #require(requests[safe: 0]))
        #expect(bundleQuery["filter[name]"] == "One,Two")
        #expect(bundleQuery["filter[platform]"] == "IOS,UNIVERSAL")
        #expect(bundleQuery["filter[identifier]"] == "com.example.one,com.example.two")
        #expect(bundleQuery["filter[seedId]"] == "SEED1,SEED2")
        #expect(bundleQuery["filter[id]"] == "bundle-1,bundle-2")

        let deviceQuery = provisioningQueryItems(try #require(requests[safe: 1]))
        #expect(deviceQuery["filter[name]"] == "Phone One,Phone Two")
        #expect(deviceQuery["filter[platform]"] == "IOS,UNIVERSAL")
        #expect(deviceQuery["filter[udid]"] == "UDID1,UDID2")
        #expect(deviceQuery["filter[status]"] == "ENABLED,DISABLED")
        #expect(deviceQuery["filter[id]"] == "device-1,device-2")

        let certificateQuery = provisioningQueryItems(try #require(requests[safe: 2]))
        #expect(certificateQuery["filter[displayName]"] == "Distribution One,Distribution Two")
        #expect(certificateQuery["filter[certificateType]"] == "IOS_DISTRIBUTION,DISTRIBUTION")
        #expect(certificateQuery["filter[serialNumber]"] == "SERIAL1,SERIAL2")
        #expect(certificateQuery["filter[id]"] == "certificate-1,certificate-2")

        let profileQuery = provisioningQueryItems(try #require(requests[safe: 3]))
        #expect(profileQuery["filter[name]"] == "Profile One,Profile Two")
        #expect(profileQuery["filter[profileType]"] == "IOS_APP_STORE,MAC_APP_STORE")
        #expect(profileQuery["filter[profileState]"] == "ACTIVE,INVALID")
        #expect(profileQuery["filter[id]"] == "profile-1,profile-2")
    }

    @Test("capability limit reaches Apple and current setting flags reach MCP output")
    func capabilityLimitAndFlagsArePreserved() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "bundleIdCapabilities",
                "id": "capability-1",
                "attributes": {
                  "capabilityType": "ICLOUD",
                  "settings": [{
                    "key": "ICLOUD_VERSION",
                    "name": "iCloud",
                    "enabledByDefault": true,
                    "visible": false,
                    "options": [{
                      "key": "XCODE_6",
                      "name": "CloudKit",
                      "enabledByDefault": false,
                      "enabled": true,
                      "supportsWildcard": true
                    }]
                  }]
                }
              }]
            }
            """)
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_capabilities",
            arguments: [
                "bundle_id_resource_id": .string("bundle-1"),
                "limit": .int(137)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/bundleIds/bundle-1/bundleIdCapabilities")
        #expect(provisioningQueryItems(request)["limit"] == "137")

        let payload = try provisioningObject(result.structuredContent)
        let capability = try provisioningObject(try provisioningArray(payload["capabilities"]).first)
        let setting = try provisioningObject(try provisioningArray(capability["settings"]).first)
        #expect(setting["enabledByDefault"] == .bool(true))
        #expect(setting["visible"] == .bool(false))
        let option = try provisioningObject(try provisioningArray(setting["options"]).first)
        #expect(option["enabledByDefault"] == .bool(false))
        #expect(option["enabled"] == .bool(true))
        #expect(option["supportsWildcard"] == .bool(true))
    }

    @Test("large signing content is omitted from lists and returned by detail tools")
    func contentProjectionMatchesOperationPurpose() async throws {
        let certificate = #"{"type":"certificates","id":"certificate-1","attributes":{"displayName":"Distribution","certificateContent":"Q0VSVA==","activated":true}}"#
        let profile = #"{"type":"profiles","id":"profile-1","attributes":{"name":"Distribution","profileContent":"UFJPRklMRQ==","createdDate":"2026-07-20T00:00:00Z"}}"#
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "{\"data\":[\(certificate)]}"),
            .init(statusCode: 200, body: "{\"data\":\(certificate)}"),
            .init(statusCode: 200, body: "{\"data\":[\(profile)]}"),
            .init(statusCode: 200, body: "{\"data\":\(profile)}")
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        let certificatesResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_certificates",
            arguments: [:]
        ))
        let certificateResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_get_certificate",
            arguments: ["certificate_id": .string("certificate-1")]
        ))
        let profilesResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_profiles",
            arguments: [:]
        ))
        let profileResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_get_profile",
            arguments: ["profile_id": .string("profile-1")]
        ))

        let certificatesPayload = try provisioningObject(certificatesResult.structuredContent)
        let listedCertificate = try provisioningObject(try provisioningArray(certificatesPayload["certificates"]).first)
        #expect(listedCertificate["certificateContent"] == nil)
        #expect(listedCertificate["activated"] == .bool(true))

        let certificatePayload = try provisioningObject(certificateResult.structuredContent)
        let detailedCertificate = try provisioningObject(certificatePayload["certificate"])
        #expect(detailedCertificate["certificateContent"] == .string("Q0VSVA=="))
        #expect(detailedCertificate["activated"] == .bool(true))

        let profilesPayload = try provisioningObject(profilesResult.structuredContent)
        let listedProfile = try provisioningObject(try provisioningArray(profilesPayload["profiles"]).first)
        #expect(listedProfile["profileContent"] == nil)
        #expect(listedProfile["createdDate"] == .string("2026-07-20T00:00:00Z"))

        let profilePayload = try provisioningObject(profileResult.structuredContent)
        let detailedProfile = try provisioningObject(profilePayload["profile"])
        #expect(detailedProfile["profileContent"] == .string("UFJPRklMRQ=="))
        #expect(detailedProfile["createdDate"] == .string("2026-07-20T00:00:00Z"))
    }

    @Test("profile creation validates all relationship IDs before network")
    func invalidRelationshipIDsAreRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)
        let cases: [(certificateIDs: [Value], deviceIDs: [Value]?)] = [
            ([], nil),
            ([.string("")], nil),
            ([.string("certificate-1"), .int(2)], nil),
            ([.string("certificate-1"), .string("certificate-1")], nil),
            ([.string("certificate-1")], []),
            ([.string("certificate-1")], [.string("")]),
            ([.string("certificate-1")], [.string("device-1"), .int(2)]),
            ([.string("certificate-1")], [.string("device-1"), .string("device-1")])
        ]

        for item in cases {
            var arguments: [String: Value] = [
                "name": .string("Profile"),
                "profile_type": .string("IOS_APP_DEVELOPMENT"),
                "bundle_id_resource_id": .string("bundle-1"),
                "certificate_ids": .array(item.certificateIDs)
            ]
            if let deviceIDs = item.deviceIDs {
                arguments["device_ids"] = .array(deviceIDs)
            }

            let result = try await worker.handleTool(CallTool.Parameters(
                name: "provisioning_create_profile",
                arguments: arguments
            ))
            #expect(result.isError == true)
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("profile creation preserves validated relationships and returns content")
    func validProfileCreationPreservesRelationships() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"profiles","id":"profile-1","attributes":{"name":"Profile","profileContent":"UFJPRklMRQ==","createdDate":"2026-07-20T00:00:00Z"}}}"#)
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_create_profile",
            arguments: [
                "name": .string("Profile"),
                "profile_type": .string("IOS_APP_DEVELOPMENT"),
                "bundle_id_resource_id": .string("bundle-1"),
                "certificate_ids": .array([.string("certificate-1"), .string("certificate-2")]),
                "device_ids": .array([.string("device-1"), .string("device-2")])
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let body = try provisioningJSONBody(request)
        let data = try provisioningDictionary(body["data"])
        let relationships = try provisioningDictionary(data["relationships"])
        let certificates = try provisioningDictionary(relationships["certificates"])["data"] as? [[String: Any]]
        let devices = try provisioningDictionary(relationships["devices"])["data"] as? [[String: Any]]
        #expect(certificates?.compactMap { $0["id"] as? String } == ["certificate-1", "certificate-2"])
        #expect(devices?.compactMap { $0["id"] as? String } == ["device-1", "device-2"])

        let payload = try provisioningObject(result.structuredContent)
        let profile = try provisioningObject(payload["profile"])
        #expect(profile["profileContent"] == .string("UFJPRklMRQ=="))
    }

    @Test("device update rejects an empty patch before network")
    func emptyDevicePatchIsRejected() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_update_device",
            arguments: ["device_id": .string("device-1")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("capability creation rejects settings of the wrong MCP type before network")
    func capabilitySettingsTypeIsValidated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_enable_capability",
            arguments: [
                "bundle_id_resource_id": .string("bundle-1"),
                "capability_type": .string("ICLOUD"),
                "settings": .array([])
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("public schemas include the current Apple collection filters")
    func schemasExposeCurrentFilters() async throws {
        let worker = try await makeProvisioningWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        let expected: [String: Set<String>] = [
            "provisioning_list_bundle_ids": ["filter_name", "filter_platform", "filter_identifier", "filter_seed_id", "filter_id", "limit", "sort", "next_url"],
            "provisioning_list_devices": ["filter_name", "filter_platform", "filter_udid", "filter_status", "filter_id", "limit", "sort", "next_url"],
            "provisioning_list_certificates": ["filter_display_name", "filter_type", "filter_serial_number", "filter_id", "limit", "sort", "next_url"],
            "provisioning_list_profiles": ["filter_name", "filter_profile_type", "filter_profile_state", "filter_id", "limit", "sort", "next_url"]
        ]

        for (toolName, expectedFields) in expected {
            let tool = try #require(tools.first { $0.name == toolName })
            guard case .object(let root) = tool.inputSchema,
                  case .object(let properties)? = root["properties"] else {
                throw ProvisioningContractTestFailure.expectedObject
            }
            #expect(Set(properties.keys) == expectedFields)
        }

        let createProfile = try #require(tools.first { $0.name == "provisioning_create_profile" })
        guard case .object(let createRoot) = createProfile.inputSchema,
              case .object(let createProperties)? = createRoot["properties"],
              case .object(let certificateIDs)? = createProperties["certificate_ids"],
              case .object(let deviceIDs)? = createProperties["device_ids"] else {
            throw ProvisioningContractTestFailure.expectedObject
        }
        #expect(certificateIDs["minItems"] == .int(1))
        #expect(certificateIDs["uniqueItems"] == .bool(true))
        #expect(deviceIDs["minItems"] == .int(1))
        #expect(deviceIDs["uniqueItems"] == .bool(true))

        let createBundleID = try #require(tools.first { $0.name == "provisioning_create_bundle_id" })
        guard case .object(let bundleRoot) = createBundleID.inputSchema,
              case .object(let bundleProperties)? = bundleRoot["properties"],
              case .array(let bundleRequired)? = bundleRoot["required"] else {
            throw ProvisioningContractTestFailure.expectedObject
        }
        #expect(bundleProperties["seed_id"] != nil)
        #expect(!bundleRequired.contains(.string("seed_id")))
    }
}

private func makeProvisioningWorker(transport: TestHTTPTransport) async throws -> ProvisioningWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return ProvisioningWorker(httpClient: client)
}

private func provisioningQueryItems(_ request: URLRequest) -> [String: String] {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}

private func provisioningJSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw ProvisioningContractTestFailure.expectedObject
    }
    return object
}

private func provisioningDictionary(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw ProvisioningContractTestFailure.expectedObject
    }
    return object
}

private func provisioningObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw ProvisioningContractTestFailure.expectedObject
    }
    return object
}

private func provisioningArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw ProvisioningContractTestFailure.expectedArray
    }
    return array
}

private enum ProvisioningContractTestFailure: Error {
    case expectedObject
    case expectedArray
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
