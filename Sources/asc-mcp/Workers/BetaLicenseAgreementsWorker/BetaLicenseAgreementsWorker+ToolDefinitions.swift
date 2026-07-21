import Foundation
import MCP

// MARK: - Tool Definitions
extension BetaLicenseAgreementsWorker {

    func listBetaLicenseAgreementsTool() -> Tool {
        return Tool(
            name: "beta_license_list",
            description: "List beta license agreements. Each app has one auto-created agreement with the license text shown to TestFlight testers",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "oneOf": .array([
                            .object(["type": .string("string"), "minLength": .int(1)]),
                            .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string"), "minLength": .int(1)]),
                                "minItems": .int(1),
                                "uniqueItems": .bool(true)
                            ])
                        ]),
                        "description": .string("Filter by one or more app IDs")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "minimum": .int(1),
                        "maximum": .int(200),
                        "default": .int(25),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getBetaLicenseAgreementTool() -> Tool {
        return Tool(
            name: "beta_license_get",
            description: "Get a specific beta license agreement by ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_license_agreement_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta license agreement ID")
                    ])
                ]),
                "required": .array([.string("beta_license_agreement_id")])
            ])
        )
    }

    func updateBetaLicenseAgreementTool() -> Tool {
        return Tool(
            name: "beta_license_update",
            description: "Update the license agreement text shown to TestFlight testers",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "beta_license_agreement_id": .object([
                        "type": .string("string"),
                        "description": .string("Beta license agreement ID")
                    ]),
                    "agreement_text": .object([
                        "type": .array([.string("string"), .string("null")]),
                        "description": .string("New license agreement text, or null to clear it")
                    ])
                ]),
                "required": .array([.string("beta_license_agreement_id"), .string("agreement_text")])
            ])
        )
    }
}
