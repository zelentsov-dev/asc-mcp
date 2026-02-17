import Foundation
import MCP

// MARK: - Tool Handlers
extension ProductPageOptimizationWorker {

    /// Lists product page optimization experiments for an app
    /// - Returns: JSON array of experiments with attributes (name, state, trafficProportion, dates)
    /// - Throws: On network or decoding errors
    func listExperiments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCExperimentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCExperimentsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/appStoreVersionExperimentsV2",
                    parameters: queryParams,
                    as: ASCExperimentsResponse.self
                )
            }

            let experiments = response.data.map { formatExperiment($0) }

            var result: [String: Any] = [
                "success": true,
                "experiments": experiments,
                "count": experiments.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list experiments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific experiment
    /// - Returns: JSON with experiment details (name, state, trafficProportion, dates)
    /// - Throws: On network or decoding errors
    func getExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let experimentId = arguments["experiment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCExperimentResponse = try await httpClient.get(
                "/v2/appStoreVersionExperiments/\(experimentId)",
                as: ASCExperimentResponse.self
            )

            let experiment = formatExperiment(response.data)

            let result = [
                "success": true,
                "experiment": experiment
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get experiment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a new product page optimization experiment
    /// - Returns: JSON with created experiment details
    /// - Throws: On network or encoding errors
    func createExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let name = arguments["name"]?.stringValue,
              let trafficProportion = arguments["traffic_proportion"]?.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: app_id, name, traffic_proportion")],
                isError: true
            )
        }

        let platform = arguments["platform"]?.stringValue ?? "IOS"

        do {
            let request = CreateExperimentRequest(
                data: CreateExperimentRequest.CreateData(
                    attributes: CreateExperimentRequest.Attributes(
                        name: name,
                        trafficProportion: trafficProportion,
                        platform: platform
                    ),
                    relationships: CreateExperimentRequest.Relationships(
                        app: CreateExperimentRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCExperimentResponse = try await httpClient.post(
                "/v2/appStoreVersionExperiments",
                body: request,
                as: ASCExperimentResponse.self
            )

            let experiment = formatExperiment(response.data)

            let result = [
                "success": true,
                "experiment": experiment
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create experiment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a product page optimization experiment
    /// - Returns: JSON with updated experiment details
    /// - Throws: On network or encoding errors
    func updateExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let experimentId = arguments["experiment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateExperimentRequest(
                data: UpdateExperimentRequest.UpdateData(
                    id: experimentId,
                    attributes: UpdateExperimentRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        trafficProportion: arguments["traffic_proportion"]?.intValue,
                        state: arguments["state"]?.stringValue
                    )
                )
            )

            let response: ASCExperimentResponse = try await httpClient.patch(
                "/v2/appStoreVersionExperiments/\(experimentId)",
                body: request,
                as: ASCExperimentResponse.self
            )

            let experiment = formatExperiment(response.data)

            let result = [
                "success": true,
                "experiment": experiment
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update experiment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a product page optimization experiment
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deleteExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let experimentId = arguments["experiment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v2/appStoreVersionExperiments/\(experimentId)")

            let result = [
                "success": true,
                "message": "Experiment '\(experimentId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete experiment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists treatments for an experiment
    /// - Returns: JSON array of treatments with attributes (name, appIconName)
    /// - Throws: On network or decoding errors
    func listTreatments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let experimentId = arguments["experiment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTreatmentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCTreatmentsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v2/appStoreVersionExperiments/\(experimentId)/appStoreVersionExperimentTreatments",
                    parameters: queryParams,
                    as: ASCTreatmentsResponse.self
                )
            }

            let treatments = response.data.map { formatTreatment($0) }

            var result: [String: Any] = [
                "success": true,
                "treatments": treatments,
                "count": treatments.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list treatments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a treatment for an experiment
    /// - Returns: JSON with created treatment details
    /// - Throws: On network or encoding errors
    func createTreatment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let experimentId = arguments["experiment_id"]?.stringValue,
              let name = arguments["name"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: experiment_id, name")],
                isError: true
            )
        }

        do {
            let request = CreateTreatmentRequest(
                data: CreateTreatmentRequest.CreateData(
                    attributes: CreateTreatmentRequest.Attributes(
                        name: name
                    ),
                    relationships: CreateTreatmentRequest.Relationships(
                        appStoreVersionExperiment: CreateTreatmentRequest.ExperimentRelationship(
                            data: ASCResourceIdentifier(type: "appStoreVersionExperiments", id: experimentId)
                        )
                    )
                )
            )

            let response: ASCTreatmentResponse = try await httpClient.post(
                "/v1/appStoreVersionExperimentTreatments",
                body: request,
                as: ASCTreatmentResponse.self
            )

            let treatment = formatTreatment(response.data)

            let result = [
                "success": true,
                "treatment": treatment
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create treatment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists localizations for a treatment
    /// - Returns: JSON array of localizations with locale
    /// - Throws: On network or decoding errors
    func listTreatmentLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let treatmentId = arguments["treatment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'treatment_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTreatmentLocalizationsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCTreatmentLocalizationsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appStoreVersionExperimentTreatments/\(treatmentId)/appStoreVersionExperimentTreatmentLocalizations",
                    parameters: queryParams,
                    as: ASCTreatmentLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatTreatmentLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list treatment localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a localization for a treatment
    /// - Returns: JSON with created localization details
    /// - Throws: On network or encoding errors
    func createTreatmentLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let treatmentId = arguments["treatment_id"]?.stringValue,
              let locale = arguments["locale"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: treatment_id, locale")],
                isError: true
            )
        }

        do {
            let request = CreateTreatmentLocalizationRequest(
                data: CreateTreatmentLocalizationRequest.CreateData(
                    attributes: CreateTreatmentLocalizationRequest.Attributes(
                        locale: locale
                    ),
                    relationships: CreateTreatmentLocalizationRequest.Relationships(
                        appStoreVersionExperimentTreatment: CreateTreatmentLocalizationRequest.TreatmentRelationship(
                            data: ASCResourceIdentifier(type: "appStoreVersionExperimentTreatments", id: treatmentId)
                        )
                    )
                )
            )

            let response: ASCTreatmentLocalizationResponse = try await httpClient.post(
                "/v1/appStoreVersionExperimentTreatmentLocalizations",
                body: request,
                as: ASCTreatmentLocalizationResponse.self
            )

            let localization = formatTreatmentLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create treatment localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatExperiment(_ experiment: ASCExperiment) -> [String: Any] {
        return [
            "id": experiment.id,
            "type": experiment.type,
            "name": experiment.attributes?.name.jsonSafe ?? NSNull(),
            "trafficProportion": experiment.attributes?.trafficProportion.jsonSafe ?? NSNull(),
            "state": experiment.attributes?.state.jsonSafe ?? NSNull(),
            "reviewRequired": experiment.attributes?.reviewRequired.jsonSafe ?? NSNull(),
            "startDate": experiment.attributes?.startDate.jsonSafe ?? NSNull(),
            "endDate": experiment.attributes?.endDate.jsonSafe ?? NSNull()
        ]
    }

    private func formatTreatment(_ treatment: ASCTreatment) -> [String: Any] {
        return [
            "id": treatment.id,
            "type": treatment.type,
            "name": treatment.attributes?.name.jsonSafe ?? NSNull(),
            "appIconName": treatment.attributes?.appIconName.jsonSafe ?? NSNull()
        ]
    }

    private func formatTreatmentLocalization(_ localization: ASCTreatmentLocalization) -> [String: Any] {
        return [
            "id": localization.id,
            "type": localization.type,
            "locale": localization.attributes?.locale.jsonSafe ?? NSNull()
        ]
    }
}
