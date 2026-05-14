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
                publish: true,
                supports: .init(
                    supportsAudioDescriptions: true,
                    supportsVoiceControl: false
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
