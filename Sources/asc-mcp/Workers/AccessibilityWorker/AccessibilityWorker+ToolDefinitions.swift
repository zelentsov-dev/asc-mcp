import Foundation
import MCP

extension AccessibilityWorker {
    func listDeclarationsTool() -> Tool {
        Tool(
            name: "accessibility_list",
            description: "List App Store accessibility declarations for an app. Returns declaration IDs, device family, publication state, support flags, and pagination info.",
            inputSchema: baseSchema(
                properties: [
                    "app_id": stringSchema("App ID whose accessibility declarations should be listed"),
                    "device_family": enumSchema("Optional device family filter", values: ASCAccessibilityDeviceFamily.validRawValues),
                    "state": enumSchema("Optional declaration state filter", values: ASCAccessibilityDeclarationState.validRawValues),
                    "fields": fieldsSchema(),
                    "limit": integerSchema("Max results (default: 25, max: 200)"),
                    "next_url": stringSchema("Pagination URL from a previous response")
                ],
                required: ["app_id"]
            )
        )
    }

    func getDeclarationTool() -> Tool {
        Tool(
            name: "accessibility_get",
            description: "Get one App Store accessibility declaration by ID.",
            inputSchema: baseSchema(
                properties: [
                    "declaration_id": stringSchema("Accessibility declaration ID"),
                    "fields": fieldsSchema()
                ],
                required: ["declaration_id"]
            )
        )
    }

    func createDeclarationTool() -> Tool {
        Tool(
            name: "accessibility_create",
            description: "Create an App Store accessibility declaration for an app and device family. Optional support flags describe the app's accessibility capabilities.",
            inputSchema: baseSchema(
                properties: accessibilitySupportProperties().merging([
                    "app_id": stringSchema("App ID that owns the declaration"),
                    "device_family": enumSchema("Device family for the declaration", values: ASCAccessibilityDeviceFamily.validRawValues)
                ]) { current, _ in current },
                required: ["app_id", "device_family"]
            )
        )
    }

    func updateDeclarationTool() -> Tool {
        Tool(
            name: "accessibility_update",
            description: "Update an App Store accessibility declaration. Set publish to true when the declaration should be published.",
            inputSchema: baseSchema(
                properties: accessibilitySupportProperties().merging([
                    "declaration_id": stringSchema("Accessibility declaration ID to update"),
                    "publish": boolSchema("Whether Apple should publish the declaration")
                ]) { current, _ in current },
                required: ["declaration_id"]
            )
        )
    }

    func deleteDeclarationTool() -> Tool {
        Tool(
            name: "accessibility_delete",
            description: "Delete an App Store accessibility declaration.",
            inputSchema: baseSchema(
                properties: [
                    "declaration_id": stringSchema("Accessibility declaration ID to delete")
                ],
                required: ["declaration_id"]
            )
        )
    }

    func listDeclarationRelationshipsTool() -> Tool {
        Tool(
            name: "accessibility_list_relationships",
            description: "List accessibility declaration relationship identifiers for an app without fetching full declaration resources.",
            inputSchema: baseSchema(
                properties: [
                    "app_id": stringSchema("App ID whose accessibility declaration relationships should be listed"),
                    "limit": integerSchema("Max results (default: 25, max: 200)"),
                    "next_url": stringSchema("Pagination URL from a previous response")
                ],
                required: ["app_id"]
            )
        )
    }

    private func baseSchema(properties: [String: Value], required: [String]) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(Value.string))
        ])
    }

    private func stringSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private func integerSchema(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description)
        ])
    }

    private func boolSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private func enumSchema(_ description: String, values: [String]) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "enum": .array(values.map(Value.string))
        ])
    }

    private func fieldsSchema() -> Value {
        .object([
            "type": .string("array"),
            "description": .string("Accessibility declaration fields to request from Apple"),
            "items": .object([
                "type": .string("string"),
                "enum": .array(ASCAccessibilityDeclarationFields.all.map(Value.string))
            ])
        ])
    }

    private func accessibilitySupportProperties() -> [String: Value] {
        [
            "supports_audio_descriptions": boolSchema("Whether the app supports audio descriptions"),
            "supports_captions": boolSchema("Whether the app supports captions"),
            "supports_dark_interface": boolSchema("Whether the app supports a dark interface"),
            "supports_differentiate_without_color_alone": boolSchema("Whether the app can differentiate without relying on color alone"),
            "supports_larger_text": boolSchema("Whether the app supports larger text"),
            "supports_reduced_motion": boolSchema("Whether the app supports reduced motion"),
            "supports_sufficient_contrast": boolSchema("Whether the app supports sufficient contrast"),
            "supports_voice_control": boolSchema("Whether the app supports Voice Control"),
            "supports_voiceover": boolSchema("Whether the app supports VoiceOver")
        ]
    }
}
