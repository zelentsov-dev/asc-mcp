import Foundation
import MCP

extension BetaGroupsWorker {
    func getRecruitmentCriteriaTool() -> Tool {
        Tool(
            name: "beta_groups_get_recruitment_criteria",
            description: "Get the public-link recruitment criteria attached to a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "group_id": recruitmentIdentifierSchema("Beta group ID")
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    func createRecruitmentCriteriaTool() -> Tool {
        Tool(
            name: "beta_groups_create_recruitment_criteria",
            description: "Create public-link device-family and OS-version recruitment criteria for a TestFlight beta group",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "group_id": recruitmentIdentifierSchema("Beta group ID"),
                    "device_filters": recruitmentDeviceFiltersSchema(nullable: false)
                ]),
                "required": .array([.string("group_id"), .string("device_filters")])
            ])
        )
    }

    func updateRecruitmentCriteriaTool() -> Tool {
        Tool(
            name: "beta_groups_update_recruitment_criteria",
            description: "Replace or explicitly clear the device-family and OS-version filters for TestFlight public-link recruitment criteria",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "group_id": recruitmentIdentifierSchema("Beta group ID used to verify criterion ownership"),
                    "criterion_id": recruitmentIdentifierSchema("Beta recruitment criterion ID"),
                    "device_filters": recruitmentDeviceFiltersSchema(nullable: true)
                ]),
                "required": .array([.string("group_id"), .string("criterion_id"), .string("device_filters")])
            ])
        )
    }

    func deleteRecruitmentCriteriaTool() -> Tool {
        Tool(
            name: "beta_groups_delete_recruitment_criteria",
            description: "Delete the public-link recruitment criteria attached to a TestFlight beta group after exact criterion-ID confirmation",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "group_id": recruitmentIdentifierSchema("Beta group ID used to verify criterion ownership"),
                    "criterion_id": recruitmentIdentifierSchema("Beta recruitment criterion ID"),
                    "confirm_criterion_id": recruitmentIdentifierSchema("Exact criterion ID required to confirm irreversible deletion")
                ]),
                "required": .array([
                    .string("group_id"),
                    .string("criterion_id"),
                    .string("confirm_criterion_id")
                ])
            ])
        )
    }

    func listRecruitmentOptionsTool() -> Tool {
        Tool(
            name: "beta_groups_list_recruitment_options",
            description: "List the device families and OS versions Apple currently permits in TestFlight public-link recruitment criteria",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum options per page"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25)
                    ]),
                    "next_url": recruitmentContinuationSchema()
                ])
            ])
        )
    }

    func checkRecruitmentCompatibilityTool() -> Tool {
        Tool(
            name: "beta_groups_check_recruitment_compatibility",
            description: "Check whether a TestFlight beta group has a build compatible with its public-link recruitment criteria",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "group_id": recruitmentIdentifierSchema("Beta group ID")
                ]),
                "required": .array([.string("group_id")])
            ])
        )
    }

    private func recruitmentIdentifierSchema(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "minLength": .int(1)
        ])
    }

    private func recruitmentDeviceFiltersSchema(nullable: Bool) -> Value {
        .object([
            "type": nullable
                ? .array([.string("array"), .string("null")])
                : .string("array"),
            "description": .string(nullable
                ? "Complete replacement array, an empty array, or null to clear Apple's nullable filter attribute"
                : "Device-family and optional inclusive OS-version ranges; Apple permits an empty array"),
            "items": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "device_family": .object([
                        "type": .string("string"),
                        "enum": .array(["IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION"].map(Value.string))
                    ]),
                    "minimum_os_inclusive": .object(["type": .string("string")]),
                    "maximum_os_inclusive": .object(["type": .string("string")])
                ])
            ])
        ])
    }

    private func recruitmentContinuationSchema() -> Value {
        .object([
            "type": .string("string"),
            "format": .string("uri-reference"),
            "minLength": .int(1),
            "description": .string("Apple continuation URL from the previous response. Repeat the effective limit; the exact query, origin, path, and a non-empty cursor are validated.")
        ])
    }
}
