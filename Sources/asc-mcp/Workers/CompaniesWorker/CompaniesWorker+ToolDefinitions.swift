import Foundation
import MCP

// MARK: - Tool Definitions
extension CompaniesWorker {

    func listCompaniesTool() -> Tool {
        return Tool(
            name: "company_list",
            description: "List all configured companies and show which one is active",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }

    func switchCompanyTool() -> Tool {
        return Tool(
            name: "company_switch",
            description: "Switch to a different company for API operations",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "company": .object([
                        "type": .string("string"),
                        "description": .string("Company ID or name (partial match supported)")
                    ])
                ]),
                "required": .array([.string("company")])
            ])
        )
    }

    func currentCompanyTool() -> Tool {
        return Tool(
            name: "company_current",
            description: "Get information about the currently active company",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }
}
