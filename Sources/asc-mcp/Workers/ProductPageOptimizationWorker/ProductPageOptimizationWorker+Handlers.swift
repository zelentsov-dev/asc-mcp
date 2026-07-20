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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let states = try stringList(
                arguments["states"],
                field: "states",
                allowedValues: Set(Self.supportedExperimentStates)
            )
            let response: ASCExperimentsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersionExperimentsV2"),
                    as: ASCExperimentsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }
                if let states {
                    queryParams["filter[state]"] = states.joined(separator: ",")
                }

                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersionExperimentsV2",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list experiments: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCExperimentResponse = try await httpClient.get(
                "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentId))",
                as: ASCExperimentResponse.self
            )

            let experiment = formatExperiment(response.data)

            let result = [
                "success": true,
                "experiment": experiment
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get experiment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: app_id, name, traffic_proportion")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create experiment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        let started: Bool?
        if let state = arguments["state"]?.stringValue {
            switch state.uppercased() {
            case "START":
                started = true
            case "STOP":
                started = false
            default:
                return CallTool.Result(
                    content: [MCPContent.text("Error: Parameter 'state' must be START or STOP")],
                    isError: true
                )
            }
        } else {
            started = nil
        }

        do {
            let request = UpdateExperimentRequest(
                data: UpdateExperimentRequest.UpdateData(
                    id: experimentId,
                    attributes: UpdateExperimentRequest.Attributes(
                        name: arguments["name"]?.stringValue,
                        trafficProportion: arguments["traffic_proportion"]?.intValue,
                        started: started
                    )
                )
            )

            let response: ASCExperimentResponse = try await httpClient.patch(
                "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentId))",
                body: request,
                as: ASCExperimentResponse.self
            )

            let experiment = formatExperiment(response.data)

            let result = [
                "success": true,
                "experiment": experiment
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update experiment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentId))")

            let result = [
                "success": true,
                "message": "Experiment '\(experimentId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete experiment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'experiment_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCTreatmentsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentId))/appStoreVersionExperimentTreatments"),
                    as: ASCTreatmentsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentId))/appStoreVersionExperimentTreatments",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list treatments: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: experiment_id, name")],
                isError: true
            )
        }

        do {
            let request = CreateTreatmentRequest(
                data: CreateTreatmentRequest.CreateData(
                    attributes: CreateTreatmentRequest.Attributes(
                        name: name,
                        appIconName: arguments["app_icon_name"]?.stringValue
                    ),
                    relationships: CreateTreatmentRequest.Relationships(
                        appStoreVersionExperimentV2: CreateTreatmentRequest.ExperimentRelationship(
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create treatment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'treatment_id' is missing")],
                isError: true
            )
        }

        do {
            let locales = try stringList(arguments["locale"], field: "locale")
            let response: ASCTreatmentLocalizationsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(treatmentId))/appStoreVersionExperimentTreatmentLocalizations"),
                    as: ASCTreatmentLocalizationsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }
                if let locales {
                    queryParams["filter[locale]"] = locales.joined(separator: ",")
                }

                response = try await httpClient.get(
                    "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(treatmentId))/appStoreVersionExperimentTreatmentLocalizations",
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list treatment localizations: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameters: treatment_id, locale")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create treatment localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func stringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            values = array.compactMap(\.stringValue)
        } else {
            throw PPOArgumentError("\(field) must be a non-empty string or array of strings")
        }

        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw PPOArgumentError("\(field) must contain non-empty strings without surrounding whitespace")
        }
        guard Set(values).count == values.count,
              values.allSatisfy({ !$0.contains(",") }) else {
            throw PPOArgumentError("\(field) must contain unique values without commas")
        }
        if let allowedValues,
           let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw PPOArgumentError(
                "Unsupported \(field) value '\(invalid)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return values
    }

    private func formatExperiment(_ experiment: ASCExperiment) -> [String: Any] {
        return [
            "id": experiment.id,
            "type": experiment.type,
            "name": (experiment.attributes?.name).jsonSafe,
            "platform": (experiment.attributes?.platform).jsonSafe,
            "trafficProportion": (experiment.attributes?.trafficProportion).jsonSafe,
            "state": (experiment.attributes?.state).jsonSafe,
            "reviewRequired": (experiment.attributes?.reviewRequired).jsonSafe,
            "startDate": (experiment.attributes?.startDate).jsonSafe,
            "endDate": (experiment.attributes?.endDate).jsonSafe
        ]
    }

    private func formatTreatment(_ treatment: ASCTreatment) -> [String: Any] {
        var result: [String: Any] = [
            "id": treatment.id,
            "type": treatment.type,
            "name": (treatment.attributes?.name).jsonSafe,
            "appIconName": (treatment.attributes?.appIconName).jsonSafe,
            "promotedDate": (treatment.attributes?.promotedDate).jsonSafe
        ]

        if let appIcon = treatment.attributes?.appIcon {
            result["appIcon"] = [
                "templateUrl": appIcon.templateUrl.jsonSafe,
                "width": appIcon.width.jsonSafe,
                "height": appIcon.height.jsonSafe
            ]
        }

        return result
    }

    private func formatTreatmentLocalization(_ localization: ASCTreatmentLocalization) -> [String: Any] {
        return [
            "id": localization.id,
            "type": localization.type,
            "locale": (localization.attributes?.locale).jsonSafe
        ]
    }
}

private struct PPOArgumentError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
