import Foundation
import MCP

extension BetaFeedbackWorker {
    func listCrashesTool() -> Tool {
        Tool(
            name: "beta_feedback_list_crashes",
            description: "List TestFlight beta feedback crash submissions for an app. Returns device/build metadata and optional tester PII.",
            inputSchema: listSchema(kindDescription: "crash")
        )
    }

    func getCrashTool() -> Tool {
        Tool(
            name: "beta_feedback_get_crash",
            description: "Get one TestFlight beta feedback crash submission by ID.",
            inputSchema: baseSchema(
                properties: [
                    "submission_id": stringSchema("Beta feedback crash submission ID"),
                    "include": includeSchema(),
                    "include_related": boolSchema(
                        "Compatibility alias: include both build and tester when include is omitted",
                        defaultValue: false
                    ),
                    "include_pii": boolSchema(
                        "Include tester identity fields and free-form feedback PII",
                        defaultValue: true
                    )
                ],
                required: ["submission_id"]
            )
        )
    }

    func getCrashLogTool() -> Tool {
        Tool(
            name: "beta_feedback_get_crash_log",
            description: "Read crash log text for a beta feedback crash submission.",
            inputSchema: crashLogSchema(idName: "submission_id", description: "Beta feedback crash submission ID")
        )
    }

    func getCrashLogByIDTool() -> Tool {
        Tool(
            name: "beta_feedback_get_crash_log_by_id",
            description: "Read crash log text directly by beta crash log ID.",
            inputSchema: crashLogSchema(idName: "crash_log_id", description: "Beta crash log ID")
        )
    }

    func deleteCrashTool() -> Tool {
        Tool(
            name: "beta_feedback_delete_crash",
            description: "Delete a TestFlight beta feedback crash submission.",
            inputSchema: baseSchema(
                properties: [
                    "submission_id": stringSchema("Beta feedback crash submission ID to delete")
                ],
                required: ["submission_id"]
            )
        )
    }

    func listScreenshotsTool() -> Tool {
        Tool(
            name: "beta_feedback_list_screenshots",
            description: "List TestFlight beta feedback screenshot submissions for an app. Returns screenshot asset URLs, device/build metadata, and optional tester PII.",
            inputSchema: listSchema(kindDescription: "screenshot")
        )
    }

    func getScreenshotTool() -> Tool {
        Tool(
            name: "beta_feedback_get_screenshot",
            description: "Get one TestFlight beta feedback screenshot submission by ID.",
            inputSchema: baseSchema(
                properties: [
                    "submission_id": stringSchema("Beta feedback screenshot submission ID"),
                    "include": includeSchema(),
                    "include_related": boolSchema(
                        "Compatibility alias: include both build and tester when include is omitted",
                        defaultValue: false
                    ),
                    "include_pii": boolSchema(
                        "Include tester identity fields and free-form feedback PII",
                        defaultValue: true
                    )
                ],
                required: ["submission_id"]
            )
        )
    }

    func deleteScreenshotTool() -> Tool {
        Tool(
            name: "beta_feedback_delete_screenshot",
            description: "Delete a TestFlight beta feedback screenshot submission.",
            inputSchema: baseSchema(
                properties: [
                    "submission_id": stringSchema("Beta feedback screenshot submission ID to delete")
                ],
                required: ["submission_id"]
            )
        )
    }

    private func listSchema(kindDescription: String) -> Value {
        baseSchema(
            properties: [
                "app_id": stringSchema("App ID whose beta feedback \(kindDescription) submissions should be listed"),
                "build_id": stringListSchema("Filter by one or more related build IDs"),
                "pre_release_version_id": stringListSchema("Filter by one or more related build pre-release version IDs"),
                "tester_id": stringListSchema("Filter by one or more related beta tester IDs"),
                "device_model": stringListSchema("Filter by one or more device models"),
                "os_version": stringListSchema("Filter by one or more OS versions"),
                "app_platform": platformSchema("Filter by one or more app platforms"),
                "device_platform": platformSchema("Filter by one or more device platforms"),
                "sort": enumListSchema(
                    "Sort by creation date; accepts one value or an ordered array",
                    values: ["createdDate", "-createdDate"],
                    defaultValue: "-createdDate"
                ),
                "include": includeSchema(),
                "include_related": boolSchema(
                    "Compatibility alias: include both build and tester when include is omitted",
                    defaultValue: false
                ),
                "include_pii": boolSchema(
                    "Include tester identity fields and free-form feedback PII",
                    defaultValue: false
                ),
                "limit": integerSchema("Max results per page", minimum: 1, maximum: 200, defaultValue: 25),
                "next_url": stringSchema("Pagination URL from a previous response")
            ],
            required: ["app_id"]
        )
    }

    private func crashLogSchema(idName: String, description: String) -> Value {
        baseSchema(
            properties: [
                idName: stringSchema(description),
                "max_log_chars": integerSchema(
                    "Maximum crash log characters to return",
                    minimum: 1,
                    maximum: 500_000,
                    defaultValue: 100_000
                )
            ],
            required: [idName]
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
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    private func integerSchema(_ description: String, minimum: Int, maximum: Int, defaultValue: Int) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(minimum),
            "maximum": .int(maximum),
            "default": .int(defaultValue)
        ])
    }

    private func boolSchema(_ description: String, defaultValue: Bool) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
            "default": .bool(defaultValue)
        ])
    }

    private func stringListSchema(_ description: String) -> Value {
        .object([
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "minLength": .int(1)
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "minLength": .int(1)
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }

    private func enumListSchema(_ description: String, values: [String], defaultValue: String? = nil) -> Value {
        var schema: [String: Value] = [
            "description": .string(description),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(values.map(Value.string))
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(values.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ]
        if let defaultValue {
            schema["default"] = .string(defaultValue)
        }
        return .object(schema)
    }

    private func platformSchema(_ description: String) -> Value {
        enumListSchema(description, values: BetaFeedbackPlatformValues.all)
    }

    private func includeSchema() -> Value {
        enumListSchema(
            "Related resources to include; accepts one relationship or an ordered array",
            values: BetaFeedbackIncludeValues.all
        )
    }
}
