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
                    "device_family": enumListSchema("Optional device family filter", values: ASCAccessibilityDeviceFamily.validRawValues),
                    "state": enumListSchema("Optional declaration state filter", values: ASCAccessibilityDeclarationState.validRawValues),
                    "fields": fieldsSchema(),
                    "limit": integerSchema("Max results (default: 25, max: 200)"),
                    "next_url": stringSchema("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
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
            description: "Update an App Store accessibility declaration. Boolean values set attributes; explicit null clears nullable Apple attributes.",
            inputSchema: baseSchema(
                properties: accessibilitySupportProperties(nullable: true).merging([
                    "declaration_id": stringSchema("Accessibility declaration ID to update"),
                    "publish": nullableBoolSchema("Whether Apple should publish the declaration; null clears the attribute")
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
                    "next_url": stringSchema("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
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
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(200)
        ])
    }

    private func boolSchema(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private func nullableBoolSchema(_ description: String) -> Value {
        .object([
            "type": .array([.string("boolean"), .string("null")]),
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

    private func enumListSchema(_ description: String, values: [String]) -> Value {
        let enumValues = Value.array(values.map(Value.string))
        return .object([
            "description": .string(description + ": " + values.joined(separator: ", ")),
            "oneOf": .array([
                .object([
                    "type": .string("string")
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": enumValues
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func fieldsSchema() -> Value {
        .object([
            "type": .string("array"),
            "description": .string("Accessibility declaration fields to request from Apple"),
            "items": .object([
                "type": .string("string"),
                "enum": .array(ASCAccessibilityDeclarationFields.all.map(Value.string))
            ]),
            "minItems": .int(1),
            "uniqueItems": .bool(true)
        ])
    }

    private func accessibilitySupportProperties(nullable: Bool = false) -> [String: Value] {
        let schema: (String) -> Value = nullable
            ? { self.nullableBoolSchema($0) }
            : { self.boolSchema($0) }
        return [
            "supports_audio_descriptions": schema("Whether the app supports audio descriptions"),
            "supports_captions": schema("Whether the app supports captions"),
            "supports_dark_interface": schema("Whether the app supports a dark interface"),
            "supports_differentiate_without_color_alone": schema("Whether the app can differentiate without relying on color alone"),
            "supports_larger_text": schema("Whether the app supports larger text"),
            "supports_reduced_motion": schema("Whether the app supports reduced motion"),
            "supports_sufficient_contrast": schema("Whether the app supports sufficient contrast"),
            "supports_voice_control": schema("Whether the app supports Voice Control"),
            "supports_voiceover": schema("Whether the app supports VoiceOver")
        ]
    }
}
