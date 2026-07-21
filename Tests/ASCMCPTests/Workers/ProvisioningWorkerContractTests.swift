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
                "filter_id": .string("bundle-1,bundle-2"),
                "sort": .array([.string("name"), .string("-id")])
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_devices",
            arguments: [
                "filter_name": .string("Phone One,Phone Two"),
                "filter_platform": .string("IOS,UNIVERSAL"),
                "filter_udid": .string("UDID1,UDID2"),
                "filter_status": .string("ENABLED,DISABLED"),
                "filter_id": .string("device-1,device-2"),
                "sort": .array([.string("udid"), .string("-status")])
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_certificates",
            arguments: [
                "filter_display_name": .string("Distribution One,Distribution Two"),
                "filter_type": .string("IOS_DISTRIBUTION,DISTRIBUTION"),
                "filter_serial_number": .string("SERIAL1,SERIAL2"),
                "filter_id": .string("certificate-1,certificate-2"),
                "sort": .array([.string("displayName"), .string("-id")])
            ]
        ))
        _ = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_list_profiles",
            arguments: [
                "filter_name": .string("Profile One,Profile Two"),
                "filter_profile_type": .string("IOS_APP_STORE,MAC_APP_STORE"),
                "filter_profile_state": .string("ACTIVE,INVALID"),
                "filter_id": .string("profile-1,profile-2"),
                "sort": .array([.string("profileType"), .string("-profileState")])
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
        #expect(bundleQuery["sort"] == "name,-id")

        let deviceQuery = provisioningQueryItems(try #require(requests[safe: 1]))
        #expect(deviceQuery["filter[name]"] == "Phone One,Phone Two")
        #expect(deviceQuery["filter[platform]"] == "IOS,UNIVERSAL")
        #expect(deviceQuery["filter[udid]"] == "UDID1,UDID2")
        #expect(deviceQuery["filter[status]"] == "ENABLED,DISABLED")
        #expect(deviceQuery["filter[id]"] == "device-1,device-2")
        #expect(deviceQuery["sort"] == "udid,-status")

        let certificateQuery = provisioningQueryItems(try #require(requests[safe: 2]))
        #expect(certificateQuery["filter[displayName]"] == "Distribution One,Distribution Two")
        #expect(certificateQuery["filter[certificateType]"] == "IOS_DISTRIBUTION,DISTRIBUTION")
        #expect(certificateQuery["filter[serialNumber]"] == "SERIAL1,SERIAL2")
        #expect(certificateQuery["filter[id]"] == "certificate-1,certificate-2")
        #expect(certificateQuery["sort"] == "displayName,-id")

        let profileQuery = provisioningQueryItems(try #require(requests[safe: 3]))
        #expect(profileQuery["filter[name]"] == "Profile One,Profile Two")
        #expect(profileQuery["filter[profileType]"] == "IOS_APP_STORE,MAC_APP_STORE")
        #expect(profileQuery["filter[profileState]"] == "ACTIVE,INVALID")
        #expect(profileQuery["filter[id]"] == "profile-1,profile-2")
        #expect(profileQuery["sort"] == "profileType,-profileState")
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
        #expect(certificates?.allSatisfy { $0["type"] as? String == "certificates" } == true)
        #expect(devices?.allSatisfy { $0["type"] as? String == "devices" } == true)

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

    @Test("nullable provisioning writes preserve explicit null and accept sparse responses")
    func nullableWritesAndSparseResponses() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"bundleIds","id":"bundle-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"devices","id":"device-1"}}"#)
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        let bundleResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_create_bundle_id",
            arguments: [
                "name": .string("Example"),
                "identifier": .string("com.example.app"),
                "platform": .string("IOS"),
                "seed_id": .null
            ]
        ))
        let deviceResult = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_update_device",
            arguments: [
                "device_id": .string("device-1"),
                "name": .null,
                "status": .null
            ]
        ))

        #expect(bundleResult.isError != true)
        #expect(deviceResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)

        let bundleBody = try provisioningJSONBody(try #require(requests[safe: 0]))
        let bundleData = try provisioningDictionary(bundleBody["data"])
        let bundleAttributes = try provisioningDictionary(bundleData["attributes"])
        #expect(bundleAttributes["seedId"] is NSNull)

        let deviceBody = try provisioningJSONBody(try #require(requests[safe: 1]))
        let deviceData = try provisioningDictionary(deviceBody["data"])
        let deviceAttributes = try provisioningDictionary(deviceData["attributes"])
        #expect(deviceAttributes["name"] is NSNull)
        #expect(deviceAttributes["status"] is NSNull)
    }

    @Test("provisioning POST preserves an unknown mutation outcome")
    func postPreservesUnknownMutationOutcome() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_create_bundle_id",
            arguments: [
                "name": .string("Example"),
                "identifier": .string("com.example.app"),
                "platform": .string("IOS")
            ]
        ))

        #expect(result.isError == true)
        let root = try provisioningObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("unknown"))
        #expect(root["outcomeUnknown"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        #expect(root["inspectionRequired"] == .bool(true))
        let details = try provisioningObject(root["details"])
        #expect(details["type"] == .string("mutation_unknown"))
        #expect(details["method"] == .string("POST"))
        #expect(await transport.requestCount() == 1)
    }

    @Test("provisioning DELETE preserves a committed-unverified outcome")
    func deletePreservesCommittedUnverifiedOutcome() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 202, body: "")
        ])
        let worker = try await makeProvisioningWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_delete_bundle_id",
            arguments: ["bundle_id_resource_id": .string("bundle-1")]
        ))

        #expect(result.isError == true)
        let root = try provisioningObject(result.structuredContent)
        #expect(root["operationCommitState"] == .string("committed_unverified"))
        #expect(root["operationCommitted"] == .bool(true))
        #expect(root["retrySafe"] == .bool(false))
        let details = try provisioningObject(root["details"])
        #expect(details["type"] == .string("delete_unverified"))
        #expect(details["statusCode"] == .int(202))
        #expect(await transport.requestCount() == 1)
    }

    @Test("provisioning mutations reject values outside Apple enums before network")
    func mutationEnumsAreValidated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)
        let calls = [
            CallTool.Parameters(
                name: "provisioning_create_bundle_id",
                arguments: [
                    "name": .string("App"),
                    "identifier": .string("com.example.app"),
                    "platform": .string("TV_OS")
                ]
            ),
            CallTool.Parameters(
                name: "provisioning_register_device",
                arguments: [
                    "name": .string("Phone"),
                    "udid": .string("UDID"),
                    "platform": .string("TV_OS")
                ]
            ),
            CallTool.Parameters(
                name: "provisioning_update_device",
                arguments: [
                    "device_id": .string("device-1"),
                    "status": .string("UNKNOWN")
                ]
            ),
            CallTool.Parameters(
                name: "provisioning_create_profile",
                arguments: [
                    "name": .string("Profile"),
                    "profile_type": .string("UNKNOWN"),
                    "bundle_id_resource_id": .string("bundle-1"),
                    "certificate_ids": .array([.string("certificate-1")])
                ]
            ),
            CallTool.Parameters(
                name: "provisioning_enable_capability",
                arguments: [
                    "bundle_id_resource_id": .string("bundle-1"),
                    "capability_type": .string("UNKNOWN")
                ]
            )
        ]

        for call in calls {
            let result = try await worker.handleTool(call)
            #expect(result.isError == true)
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("provisioning collection limits reject wrong types and out-of-range values before network")
    func collectionLimitsAreStrictlyValidated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)
        let calls: [(String, [String: Value])] = [
            ("provisioning_list_bundle_ids", [:]),
            ("provisioning_list_devices", [:]),
            ("provisioning_list_certificates", [:]),
            ("provisioning_list_profiles", [:]),
            ("provisioning_list_capabilities", ["bundle_id_resource_id": .string("bundle-1")])
        ]
        let invalidLimits: [Value] = [.null, .string("25"), .bool(true), .int(0), .int(201)]

        for (tool, baseArguments) in calls {
            for limit in invalidLimits {
                var arguments = baseArguments
                arguments["limit"] = limit
                let result = try await worker.handleTool(CallTool.Parameters(
                    name: tool,
                    arguments: arguments
                ))
                #expect(result.isError == true)
            }
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("provisioning collection enums reject unsupported values before network")
    func collectionEnumsAreStrictlyValidated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)
        let cases: [(String, String)] = [
            ("provisioning_list_bundle_ids", "filter_platform"),
            ("provisioning_list_bundle_ids", "sort"),
            ("provisioning_list_devices", "filter_platform"),
            ("provisioning_list_devices", "filter_status"),
            ("provisioning_list_devices", "sort"),
            ("provisioning_list_certificates", "filter_type"),
            ("provisioning_list_certificates", "sort"),
            ("provisioning_list_profiles", "filter_profile_type"),
            ("provisioning_list_profiles", "filter_profile_state"),
            ("provisioning_list_profiles", "sort")
        ]

        for (tool, field) in cases {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: tool,
                arguments: [field: .string("UNKNOWN")]
            ))
            #expect(result.isError == true)
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("provisioning collections expose paging totals and use the default limit")
    func collectionPagingTotalsArePreserved() async throws {
        let responses = (1...5).map { total in
            TestHTTPTransport.Response(
                statusCode: 200,
                body: #"{"data":[],"meta":{"paging":{"total":\#(total),"limit":25}}}"#
            )
        }
        let transport = TestHTTPTransport(responses: responses)
        let worker = try await makeProvisioningWorker(transport: transport)
        let calls: [(String, [String: Value])] = [
            ("provisioning_list_bundle_ids", [:]),
            ("provisioning_list_devices", [:]),
            ("provisioning_list_certificates", [:]),
            ("provisioning_list_profiles", [:]),
            ("provisioning_list_capabilities", ["bundle_id_resource_id": .string("bundle-1")])
        ]

        for (index, call) in calls.enumerated() {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: call.0,
                arguments: call.1
            ))
            #expect(result.isError != true)
            let payload = try provisioningObject(result.structuredContent)
            #expect(payload["total"] == .int(index + 1))
        }

        let requests = await transport.recordedRequests()
        #expect(requests.count == 5)
        for request in requests {
            #expect(provisioningQueryItems(request)["limit"] == "25")
        }
    }

    @Test("capability settings preserve omission, null, empty values, and empty response arrays")
    func capabilitySettingsTriStateIsPreserved() async throws {
        let response = #"{"data":{"type":"bundleIdCapabilities","id":"capability-1","attributes":{"capabilityType":"ICLOUD","settings":[]}}}"#
        let transport = TestHTTPTransport(responses: Array(
            repeating: .init(statusCode: 201, body: response),
            count: 3
        ))
        let worker = try await makeProvisioningWorker(transport: transport)
        let baseArguments: [String: Value] = [
            "bundle_id_resource_id": .string("bundle-1"),
            "capability_type": .string("ICLOUD")
        ]

        let omitted = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_enable_capability",
            arguments: baseArguments
        ))
        var nullArguments = baseArguments
        nullArguments["settings"] = .null
        let explicitNull = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_enable_capability",
            arguments: nullArguments
        ))
        var emptyArguments = baseArguments
        emptyArguments["settings"] = .array([])
        let empty = try await worker.handleTool(CallTool.Parameters(
            name: "provisioning_enable_capability",
            arguments: emptyArguments
        ))

        #expect(omitted.isError != true)
        #expect(explicitNull.isError != true)
        #expect(empty.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.count == 3)

        let omittedAttributes = try provisioningDictionary(
            try provisioningDictionary(
                try provisioningJSONBody(try #require(requests[safe: 0]))["data"]
            )["attributes"]
        )
        #expect(omittedAttributes.keys.contains("settings") == false)

        let nullAttributes = try provisioningDictionary(
            try provisioningDictionary(
                try provisioningJSONBody(try #require(requests[safe: 1]))["data"]
            )["attributes"]
        )
        #expect(nullAttributes["settings"] is NSNull)

        let emptyAttributes = try provisioningDictionary(
            try provisioningDictionary(
                try provisioningJSONBody(try #require(requests[safe: 2]))["data"]
            )["attributes"]
        )
        #expect((emptyAttributes["settings"] as? [Any])?.isEmpty == true)

        let payload = try provisioningObject(empty.structuredContent)
        let capability = try provisioningObject(payload["capability"])
        #expect(try provisioningArray(capability["settings"]).isEmpty)
    }

    @Test("capability settings reject malformed nested values before network")
    func capabilitySettingsAreStrictlyValidated() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeProvisioningWorker(transport: transport)
        let invalidSettings: [Value] = [
            .string("[]"),
            .array([.object(["unknown": .bool(true)])]),
            .array([.object(["key": .string("UNKNOWN")])]),
            .array([.object(["allowedInstances": .string("UNKNOWN")])]),
            .array([.object(["name": .int(1)])]),
            .array([.object(["options": .array([.object(["unknown": .bool(true)])])])]),
            .array([.object(["options": .array([.object(["key": .string("UNKNOWN")])])])]),
            .array([.object(["options": .array([.object(["enabled": .string("yes")])])])])
        ]

        for settings in invalidSettings {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "provisioning_enable_capability",
                arguments: [
                    "bundle_id_resource_id": .string("bundle-1"),
                    "capability_type": .string("ICLOUD"),
                    "settings": settings
                ]
            ))
            #expect(result.isError == true)
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("public schemas include the current Apple collection filters")
    func schemasExposeCurrentFilters() async throws {
        let worker = try await makeProvisioningWorker(transport: TestHTTPTransport(responses: []))
        let tools = await worker.getTools()

        func property(_ toolName: String, _ field: String) throws -> [String: Value] {
            let tool = try #require(tools.first { $0.name == toolName })
            guard case .object(let root) = tool.inputSchema,
                  case .object(let properties)? = root["properties"],
                  case .object(let property)? = properties[field] else {
                throw ProvisioningContractTestFailure.expectedObject
            }
            return property
        }

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

        let createPlatform = try property("provisioning_create_bundle_id", "platform")
        let registerPlatform = try property("provisioning_register_device", "platform")
        let updateStatus = try property("provisioning_update_device", "status")
        let profileType = try property("provisioning_create_profile", "profile_type")
        let capabilityType = try property("provisioning_enable_capability", "capability_type")
        #expect(createPlatform["enum"] == .array(ProvisioningWorker.bundleIdPlatforms.map(Value.string)))
        #expect(registerPlatform["enum"] == .array(ProvisioningWorker.bundleIdPlatforms.map(Value.string)))
        #expect(updateStatus["enum"] == .array(ProvisioningWorker.deviceStatuses.map(Value.string) + [.null]))
        #expect(profileType["enum"] == .array(ProvisioningWorker.profileTypes.map(Value.string)))
        #expect(capabilityType["enum"] == .array(ProvisioningWorker.capabilityTypes.map(Value.string)))

        let enumLists: [(String, String, [String])] = [
            ("provisioning_list_bundle_ids", "filter_platform", ProvisioningWorker.bundleIdPlatforms),
            ("provisioning_list_bundle_ids", "sort", ProvisioningWorker.bundleIdSortValues),
            ("provisioning_list_devices", "filter_platform", ProvisioningWorker.bundleIdPlatforms),
            ("provisioning_list_devices", "filter_status", ProvisioningWorker.deviceStatuses),
            ("provisioning_list_devices", "sort", ProvisioningWorker.deviceSortValues),
            ("provisioning_list_certificates", "filter_type", ProvisioningWorker.certificateTypes),
            ("provisioning_list_certificates", "sort", ProvisioningWorker.certificateSortValues),
            ("provisioning_list_profiles", "filter_profile_type", ProvisioningWorker.profileTypes),
            ("provisioning_list_profiles", "filter_profile_state", ProvisioningWorker.profileStates),
            ("provisioning_list_profiles", "sort", ProvisioningWorker.profileSortValues)
        ]
        for (toolName, field, values) in enumLists {
            let schema = try property(toolName, field)
            guard case .array(let alternatives)? = schema["oneOf"],
                  case .object(let scalar)? = alternatives.first,
                  case .array(let scalarValues)? = scalar["enum"],
                  case .object(let array)? = alternatives.last,
                  case .object(let items)? = array["items"],
                  case .array(let itemValues)? = items["enum"] else {
                throw ProvisioningContractTestFailure.expectedArray
            }
            #expect(scalarValues == values.map(Value.string))
            #expect(itemValues == values.map(Value.string))
        }

        let settings = try property("provisioning_enable_capability", "settings")
        guard case .array(let settingsTypes)? = settings["type"],
              case .object(let settingSchema)? = settings["items"],
              case .object(let settingProperties)? = settingSchema["properties"],
              case .object(let settingKey)? = settingProperties["key"],
              case .object(let allowedInstances)? = settingProperties["allowedInstances"],
              case .object(let options)? = settingProperties["options"],
              case .object(let optionSchema)? = options["items"],
              case .object(let optionProperties)? = optionSchema["properties"],
              case .object(let optionKey)? = optionProperties["key"] else {
            throw ProvisioningContractTestFailure.expectedObject
        }
        #expect(Set(settingsTypes.compactMap(\.stringValue)) == ["array", "null"])
        #expect(settingSchema["additionalProperties"] == .bool(false))
        #expect(settingKey["enum"] == .array(ProvisioningWorker.capabilitySettingKeys.map(Value.string)))
        #expect(allowedInstances["enum"] == .array(ProvisioningWorker.capabilityAllowedInstances.map(Value.string)))
        #expect(optionSchema["additionalProperties"] == .bool(false))
        #expect(optionKey["enum"] == .array(ProvisioningWorker.capabilityOptionKeys.map(Value.string)))

        let seedID = try property("provisioning_create_bundle_id", "seed_id")
        let updateName = try property("provisioning_update_device", "name")
        guard case .array(let seedTypes)? = seedID["type"],
              case .array(let nameTypes)? = updateName["type"],
              case .array(let statusTypes)? = updateStatus["type"] else {
            throw ProvisioningContractTestFailure.expectedArray
        }
        #expect(Set(seedTypes.compactMap(\.stringValue)) == ["string", "null"])
        #expect(Set(nameTypes.compactMap(\.stringValue)) == ["string", "null"])
        #expect(Set(statusTypes.compactMap(\.stringValue)) == ["string", "null"])
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
