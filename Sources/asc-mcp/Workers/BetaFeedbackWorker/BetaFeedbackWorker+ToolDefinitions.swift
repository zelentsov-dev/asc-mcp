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
                    "include_related": boolSchema("Include related build and tester resources when Apple returns them"),
                    "include_pii": boolSchema("Include tester email and free-form comment (default: true for single-resource reads)")
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
                    "include_related": boolSchema("Include related build and tester resources when Apple returns them"),
                    "include_pii": boolSchema("Include tester email and free-form comment (default: true for single-resource reads)")
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
                "build_id": stringSchema("Filter by related build ID"),
                "pre_release_version_id": stringSchema("Filter by related build pre-release version ID"),
                "tester_id": stringSchema("Filter by related beta tester ID"),
                "device_model": stringSchema("Filter by device model"),
                "os_version": stringSchema("Filter by OS version"),
                "app_platform": platformSchema("Filter by app platform"),
                "device_platform": platformSchema("Filter by device platform"),
                "sort": enumSchema("Sort order (default: -createdDate)", values: ["createdDate", "-createdDate"]),
                "include_related": boolSchema("Include related build and tester resources when Apple returns them"),
                "include_pii": boolSchema("Include tester email and free-form comment (default: false for list reads)"),
                "limit": integerSchema("Max results (default: 25, max: 200)"),
                "next_url": stringSchema("Pagination URL from a previous response")
            ],
            required: ["app_id"]
        )
    }

    private func crashLogSchema(idName: String, description: String) -> Value {
        baseSchema(
            properties: [
                idName: stringSchema(description),
                "max_log_chars": integerSchema("Maximum crash log characters to return (default: 100000, max: 500000)")
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

    private func platformSchema(_ description: String) -> Value {
        enumSchema(description, values: BetaFeedbackPlatformValues.all)
    }
}
