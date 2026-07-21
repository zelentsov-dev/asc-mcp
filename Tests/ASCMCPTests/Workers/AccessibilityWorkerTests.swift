import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Accessibility Worker Tests")
struct AccessibilityWorkerTests {
    @Test("missing required parameters return isError")
    func missingRequiredParametersReturnErrors() async throws {
        let worker = AccessibilityWorker(httpClient: try await TestFactory.makeHTTPClient())

        let list = try await worker.handleTool(CallTool.Parameters(name: "accessibility_list", arguments: nil))
        let get = try await worker.handleTool(CallTool.Parameters(name: "accessibility_get", arguments: nil))
        let create = try await worker.handleTool(CallTool.Parameters(name: "accessibility_create", arguments: nil))
        let update = try await worker.handleTool(CallTool.Parameters(name: "accessibility_update", arguments: nil))
        let delete = try await worker.handleTool(CallTool.Parameters(name: "accessibility_delete", arguments: nil))
        let relationships = try await worker.handleTool(CallTool.Parameters(name: "accessibility_list_relationships", arguments: nil))

        #expect(list.isError == true)
        #expect(get.isError == true)
        #expect(create.isError == true)
        #expect(update.isError == true)
        #expect(delete.isError == true)
        #expect(relationships.isError == true)
    }

    @Test("validates device family, state, and update fields before network calls")
    func validatesInputsBeforeNetworkCalls() async throws {
        let worker = AccessibilityWorker(httpClient: try await TestFactory.makeHTTPClient())

        let invalidFamily = try await worker.handleTool(
            CallTool.Parameters(
                name: "accessibility_create",
                arguments: [
                    "app_id": .string("app-1"),
                    "device_family": .string("ANDROID")
                ]
            )
        )
        #expect(invalidFamily.isError == true)

        let invalidState = try await worker.handleTool(
            CallTool.Parameters(
                name: "accessibility_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "state": .string("LIVE")
                ]
            )
        )
        #expect(invalidState.isError == true)

        let malformedFilter = try await worker.handleTool(
            CallTool.Parameters(
                name: "accessibility_list",
                arguments: [
                    "app_id": .string("app-1"),
                    "device_family": .array([.string("IPHONE"), .int(1)])
                ]
            )
        )
        #expect(malformedFilter.isError == true)

        let emptyUpdate = try await worker.handleTool(
            CallTool.Parameters(
                name: "accessibility_update",
                arguments: [
                    "declaration_id": .string("decl-1")
                ]
            )
        )
        #expect(emptyUpdate.isError == true)
    }

    @Test("ambiguous DELETE exposes typed retry safety")
    func ambiguousDeleteExposesTypedRetrySafety() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 503,
                body: #"{"errors":[{"status":"503","code":"SERVICE_UNAVAILABLE","detail":"Try later"}]}"#
            )
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 3
        )
        let worker = AccessibilityWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "accessibility_delete",
            arguments: ["declaration_id": .string("decl-1")]
        ))

        guard case .object(let payload)? = result.structuredContent,
              case .object(let details)? = payload["details"],
              case .object(let cause)? = details["cause"] else {
            Issue.record("Expected a typed unknown DELETE result")
            return
        }
        #expect(result.isError == true)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(details["type"] == .string("delete_unknown"))
        #expect(details["method"] == .string("DELETE"))
        #expect(cause["type"] == .string("api"))
        #expect(cause["statusCode"] == .int(503))
        #expect(await transport.requestCount() == 1)
    }

    @Test("present invalid limits fail before network")
    func invalidLimitsFailBeforeNetwork() async throws {
        let cases: [(String, [String: Value])] = [
            ("accessibility_list", ["app_id": .string("app-1"), "limit": .int(0)]),
            ("accessibility_list", ["app_id": .string("app-1"), "limit": .string("25")]),
            ("accessibility_list_relationships", ["app_id": .string("app-1"), "limit": .int(201)])
        ]

        for (tool, arguments) in cases {
            let transport = TestHTTPTransport(responses: [])
            let client = await HTTPClient(
                jwtService: try TestFactory.makeJWTService(),
                baseURL: "https://api.example.test",
                transport: transport,
                maxRetries: 1
            )
            let worker = AccessibilityWorker(httpClient: client)

            let result = try await worker.handleTool(.init(name: tool, arguments: arguments))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("accepted create and update identity failures are committed unverified")
    func mutationIdentityFailuresPreserveCommitState() async throws {
        let createTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: #"{"data":{"type":"apps","id":"decl-1"}}"#)
        ])
        let createClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: createTransport,
            maxRetries: 1
        )
        let create = try await AccessibilityWorker(httpClient: createClient).handleTool(.init(
            name: "accessibility_create",
            arguments: ["app_id": .string("app-1"), "device_family": .string("IPHONE")]
        ))

        let updateTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"accessibilityDeclarations","id":"decl-other"}}"#)
        ])
        let updateClient = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: updateTransport,
            maxRetries: 1
        )
        let update = try await AccessibilityWorker(httpClient: updateClient).handleTool(.init(
            name: "accessibility_update",
            arguments: ["declaration_id": .string("decl-1"), "publish": .bool(true)]
        ))

        for result in [create, update] {
            guard case .object(let payload)? = result.structuredContent else {
                Issue.record("Expected structured mutation failure")
                continue
            }
            #expect(result.isError == true)
            #expect(payload["operationCommitState"] == .string("committed_unverified"))
            #expect(payload["retrySafe"] == .bool(false))
        }
    }

    @Test("request models encode Apple OpenAPI JSON API shape")
    func requestModelsEncodeAppleShape() throws {
        let create = ASCAccessibilityDeclarationCreateRequest(
            appID: "app-1",
            deviceFamily: .iPhone,
            supports: .init(
                supportsCaptions: true,
                supportsLargerText: false,
                supportsVoiceover: true
            )
        )

        let createJSON = try jsonObject(create)
        guard let createData = createJSON["data"] as? [String: Any],
              let createAttributes = createData["attributes"] as? [String: Any],
              let createRelationships = createData["relationships"] as? [String: Any],
              let appRelationship = createRelationships["app"] as? [String: Any],
              let appData = appRelationship["data"] as? [String: Any] else {
            Issue.record("Expected create request JSON API shape")
            return
        }

        #expect(createData["type"] as? String == "accessibilityDeclarations")
        #expect(createAttributes["deviceFamily"] as? String == "IPHONE")
        #expect(createAttributes["supportsCaptions"] as? Bool == true)
        #expect(createAttributes["supportsLargerText"] as? Bool == false)
        #expect(createAttributes["supportsVoiceover"] as? Bool == true)
        #expect(createAttributes["supportsReducedMotion"] == nil)
        #expect(appData["type"] as? String == "apps")
        #expect(appData["id"] as? String == "app-1")

        let update = ASCAccessibilityDeclarationUpdateRequest(
            declarationID: "decl-1",
            attributes: .init(
                publish: .value(true),
                supports: .init(
                    supportsAudioDescriptions: .value(true),
                    supportsVoiceControl: .value(false)
                )
            )
        )
        let updateJSON = try jsonObject(update)
        guard let updateData = updateJSON["data"] as? [String: Any],
              let updateAttributes = updateData["attributes"] as? [String: Any] else {
            Issue.record("Expected update request JSON API shape")
            return
        }

        #expect(updateData["id"] as? String == "decl-1")
        #expect(updateData["type"] as? String == "accessibilityDeclarations")
        #expect(updateAttributes["publish"] as? Bool == true)
        #expect(updateAttributes["supportsAudioDescriptions"] as? Bool == true)
        #expect(updateAttributes["supportsVoiceControl"] as? Bool == false)
        #expect(updateAttributes["supportsCaptions"] == nil)

        let clear = ASCAccessibilityDeclarationUpdateRequest(
            declarationID: "decl-1",
            attributes: .init(
                publish: .null,
                supports: .init(
                    supportsAudioDescriptions: .null,
                    supportsCaptions: .null,
                    supportsDarkInterface: .null,
                    supportsDifferentiateWithoutColorAlone: .null,
                    supportsLargerText: .null,
                    supportsReducedMotion: .null,
                    supportsSufficientContrast: .null,
                    supportsVoiceControl: .null,
                    supportsVoiceover: .null
                )
            )
        )
        let clearJSON = try jsonObject(clear)
        let clearData = try #require(clearJSON["data"] as? [String: Any])
        let clearAttributes = try #require(clearData["attributes"] as? [String: Any])
        for field in [
            "publish",
            "supportsAudioDescriptions",
            "supportsCaptions",
            "supportsDarkInterface",
            "supportsDifferentiateWithoutColorAlone",
            "supportsLargerText",
            "supportsReducedMotion",
            "supportsSufficientContrast",
            "supportsVoiceControl",
            "supportsVoiceover"
        ] {
            #expect(clearAttributes[field] is NSNull)
        }
    }

    @Test("update schema exposes nullable booleans while create remains boolean-only")
    func updateSchemaExposesNullableBooleans() async throws {
        let worker = AccessibilityWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tools = await worker.getTools()
        let create = try #require(tools.first { $0.name == "accessibility_create" })
        let update = try #require(tools.first { $0.name == "accessibility_update" })
        let createProperties = try accessibilityProperties(create)
        let updateProperties = try accessibilityProperties(update)

        let supportFields = [
            "supports_audio_descriptions",
            "supports_captions",
            "supports_dark_interface",
            "supports_differentiate_without_color_alone",
            "supports_larger_text",
            "supports_reduced_motion",
            "supports_sufficient_contrast",
            "supports_voice_control",
            "supports_voiceover"
        ]
        for field in supportFields {
            #expect(createProperties[field]?.objectValue?["type"]?.stringValue == "boolean")
            #expect(try accessibilityStrings(updateProperties[field]?.objectValue?["type"]) == ["boolean", "null"])
        }
        #expect(try accessibilityStrings(updateProperties["publish"]?.objectValue?["type"]) == ["boolean", "null"])
    }

    @Test("null-only update preserves every nullable Apple attribute")
    func nullOnlyUpdatePreservesNullableAttributes() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"accessibilityDeclarations","id":"decl-1","attributes":{"deviceFamily":"IPHONE","state":"DRAFT"}}}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = AccessibilityWorker(httpClient: client)
        let nullableFields = [
            "publish",
            "supports_audio_descriptions",
            "supports_captions",
            "supports_dark_interface",
            "supports_differentiate_without_color_alone",
            "supports_larger_text",
            "supports_reduced_motion",
            "supports_sufficient_contrast",
            "supports_voice_control",
            "supports_voiceover"
        ]
        var arguments = Dictionary(uniqueKeysWithValues: nullableFields.map { ($0, Value.null) })
        arguments["declaration_id"] = .string("decl-1")

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "accessibility_update",
            arguments: arguments
        ))

        #expect(result.isError != true)
        #expect(await transport.requestCount() == 1)
        let request = try #require(await transport.recordedRequests().first)
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(object["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        for field in [
            "publish",
            "supportsAudioDescriptions",
            "supportsCaptions",
            "supportsDarkInterface",
            "supportsDifferentiateWithoutColorAlone",
            "supportsLargerText",
            "supportsReducedMotion",
            "supportsSufficientContrast",
            "supportsVoiceControl",
            "supportsVoiceover"
        ] {
            #expect(attributes[field] is NSNull)
        }
    }

    @Test("list schema accepts multi-value filters and bounds Apple limit")
    func listSchemaSupportsMultiValueFilters() async throws {
        let worker = AccessibilityWorker(httpClient: try await TestFactory.makeHTTPClient())
        let tool = try #require(await worker.getTools().first { $0.name == "accessibility_list" })
        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let deviceFamily)? = properties["device_family"],
              case .array(let deviceFamilyAlternatives)? = deviceFamily["oneOf"],
              case .object(let state)? = properties["state"],
              case .array(let stateAlternatives)? = state["oneOf"],
              case .object(let limit)? = properties["limit"] else {
            Issue.record("Expected accessibility_list contract schema")
            return
        }

        #expect(deviceFamilyAlternatives.count == 2)
        #expect(stateAlternatives.count == 2)
        #expect(deviceFamilyAlternatives.first?.objectValue?["pattern"]?.stringValue != nil)
        #expect(stateAlternatives.first?.objectValue?["pattern"]?.stringValue != nil)
        #expect(limit["minimum"]?.intValue == 1)
        #expect(limit["maximum"]?.intValue == 200)
    }

    @Test("list manifests declare page count and optional Apple total")
    func listManifestOutputParity() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        for toolName in ["accessibility_list", "accessibility_list_relationships"] {
            let mapping = try #require(manifest.mapping(for: toolName))
            let fields = Set(mapping.response.fields.map(\.outputField))
            #expect(fields.contains("count"))
            #expect(fields.contains("total"))
        }
    }

    @Test("list sends multi-value filters and sparse fields using Apple query names")
    func listSendsMultiValueFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = AccessibilityWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "accessibility_list",
            arguments: [
                "app_id": .string("app-1"),
                "device_family": .array([.string("IPHONE"), .string("IPAD")]),
                "state": .array([.string("DRAFT"), .string("PUBLISHED")]),
                "fields": .array([.string("deviceFamily"), .string("state")]),
                "limit": .int(200)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["filter[deviceFamily]"] == "IPHONE,IPAD")
        #expect(query["filter[state]"] == "DRAFT,PUBLISHED")
        #expect(query["fields[accessibilityDeclarations]"] == "deviceFamily,state")
        #expect(query["limit"] == "200")
    }

    @Test("pagination continuation preserves sparse fieldsets")
    func paginationPreservesFields() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = AccessibilityWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "accessibility_list",
            arguments: [
                "app_id": .string("app-1"),
                "fields": .array([.string("deviceFamily"), .string("state")]),
                "next_url": .string("https://api.example.test/v1/apps/app-1/accessibilityDeclarations?cursor=next&limit=25")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("response models decode Apple accessibility declarations")
    func responseModelsDecodeAppleShape() throws {
        let data = """
        {
          "data": {
            "type": "accessibilityDeclarations",
            "id": "decl-1",
            "attributes": {
              "deviceFamily": "IPHONE",
              "state": "DRAFT",
              "supportsCaptions": false,
              "supportsVoiceover": true
            },
            "links": {
              "self": "https://api.appstoreconnect.apple.com/v1/accessibilityDeclarations/decl-1"
            }
          },
          "links": {
            "self": "https://api.appstoreconnect.apple.com/v1/accessibilityDeclarations/decl-1"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ASCAccessibilityDeclarationResponse.self, from: data)

        #expect(response.data.id == "decl-1")
        #expect(response.data.type == "accessibilityDeclarations")
        #expect(response.data.attributes?.deviceFamily == .iPhone)
        #expect(response.data.attributes?.state == .draft)
        #expect(response.data.attributes?.supportsCaptions == false)
        #expect(response.data.attributes?.supportsVoiceover == true)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private func accessibilityProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AccessibilityWorkerTestError.expectedObject
    }
    return properties
}

private func accessibilityStrings(_ value: Value?) throws -> [String] {
    guard case .array(let values) = value else {
        throw AccessibilityWorkerTestError.expectedArray
    }
    return values.compactMap(\.stringValue)
}

private enum AccessibilityWorkerTestError: Error {
    case expectedObject
    case expectedArray
}
