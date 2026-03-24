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
                        "type": .string("string"),
                        "description": .string("Filter by app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max results (default: 25, max: 200)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Pagination URL from previous response to fetch next page")
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
                        "type": .string("string"),
                        "description": .string("New license agreement text for TestFlight testers")
                    ])
                ]),
                "required": .array([.string("beta_license_agreement_id")])
            ])
        )
    }
}
