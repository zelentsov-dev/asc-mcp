import Foundation
import MCP

/// ProductPageOptimizationWorker manages A/B testing experiments for App Store product pages
public final class ProductPageOptimizationWorker: Sendable {
    static let supportedExperimentStates = ASCPPOExperimentState.allCases.map(\.rawValue)
    static let supportedPlatforms = ASCPPOPlatform.allCases.map(\.rawValue)

    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    /// - Returns: Array of 15 PPO tools for experiments, treatments, and localizations
    public func getTools() async -> [Tool] {
        return [
            listExperimentsTool(),
            listVersionExperimentsTool(),
            getExperimentTool(),
            createExperimentTool(),
            updateExperimentTool(),
            deleteExperimentTool(),
            listTreatmentsTool(),
            getTreatmentTool(),
            createTreatmentTool(),
            updateTreatmentTool(),
            deleteTreatmentTool(),
            listTreatmentLocalizationsTool(),
            getTreatmentLocalizationTool(),
            createTreatmentLocalizationTool(),
            deleteTreatmentLocalizationTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    /// - Returns: CallTool.Result with JSON response
    /// - Throws: MCPError if tool name is unknown
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "ppo_list_experiments":
            return try await listExperiments(params)
        case "ppo_list_version_experiments":
            return try await listVersionExperiments(params)
        case "ppo_get_experiment":
            return try await getExperiment(params)
        case "ppo_create_experiment":
            return try await createExperiment(params)
        case "ppo_update_experiment":
            return try await updateExperiment(params)
        case "ppo_delete_experiment":
            return try await deleteExperiment(params)
        case "ppo_list_treatments":
            return try await listTreatments(params)
        case "ppo_get_treatment":
            return try await getTreatment(params)
        case "ppo_create_treatment":
            return try await createTreatment(params)
        case "ppo_update_treatment":
            return try await updateTreatment(params)
        case "ppo_delete_treatment":
            return try await deleteTreatment(params)
        case "ppo_list_treatment_localizations":
            return try await listTreatmentLocalizations(params)
        case "ppo_get_treatment_localization":
            return try await getTreatmentLocalization(params)
        case "ppo_create_treatment_localization":
            return try await createTreatmentLocalization(params)
        case "ppo_delete_treatment_localization":
            return try await deleteTreatmentLocalization(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
