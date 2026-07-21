import Foundation
import MCP

// MARK: - Tool Handlers
extension ProductPageOptimizationWorker {
    func listExperiments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["app_id", "limit", "states", "next_url"])
            let appID = try requiredPPOIdentifier("app_id", from: arguments)
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/appStoreVersionExperimentsV2"
            return try await listExperimentCollection(
                arguments: arguments,
                path: path,
                scopeField: "appId",
                scopeID: appID,
                expectedAppID: appID
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list product page optimization experiments")
        }
    }

    func listVersionExperiments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["version_id", "limit", "states", "next_url"])
            let versionID = try requiredPPOIdentifier("version_id", from: arguments)
            let path = "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/appStoreVersionExperimentsV2"
            return try await listExperimentCollection(
                arguments: arguments,
                path: path,
                scopeField: "versionId",
                scopeID: versionID,
                expectedAppID: nil
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to list version-scoped product page optimization experiments")
        }
    }

    func getExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'experiment_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["experiment_id"])
            let experimentID = try requiredPPOIdentifier("experiment_id", from: arguments)
            let path = "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentID, field: "experiment_id"))"
            let response = try await httpClient.get(path, as: ASCExperimentResponse.self)
            try validateExperiment(response.data, expectedID: experimentID, expectedAppID: nil, context: "experiment get")
            try validatePPODocumentSelf(response.links.`self`, expectedPath: path, context: "experiment get")
            return MCPResult.jsonObject([
                "success": true,
                "experiment": formatExperiment(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get product page optimization experiment")
        }
    }

    func createExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: app_id, name, traffic_proportion")
        }

        let appID: String
        let name: String
        let trafficProportion: Int
        let platform: ASCPPOPlatform
        do {
            try validatePPOArguments(
                arguments,
                allowed: ["app_id", "name", "traffic_proportion", "platform"]
            )
            appID = try requiredPPOIdentifier("app_id", from: arguments)
            name = try requiredPPOString("name", from: arguments)
            trafficProportion = try requiredPPOInteger("traffic_proportion", from: arguments)
            platform = try ppoPlatform(arguments["platform"])
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate experiment creation")
        }

        let request = CreateExperimentRequest(
            data: .init(
                attributes: .init(
                    name: name,
                    trafficProportion: trafficProportion,
                    platform: platform
                ),
                relationships: .init(
                    app: .init(data: ASCResourceIdentifier(type: "apps", id: appID))
                )
            )
        )
        let recovery = PPOMutationRecovery(
            action: "CREATE",
            identifiers: [
                "app_id": .string(appID),
                "name": .string(name),
                "traffic_proportion": .int(trafficProportion),
                "platform": .string(platform.rawValue)
            ],
            requestedValues: [
                "name": .string(name),
                "traffic_proportion": .int(trafficProportion),
                "platform": .string(platform.rawValue)
            ],
            listTool: "ppo_list_experiments",
            listArguments: ["app_id": .string(appID)],
            getTool: "ppo_get_experiment",
            getIDArgument: "experiment_id",
            exactID: nil,
            matchingFields: ["name", "traffic_proportion", "platform"]
        )
        guard let body = encodePPORequest(request, operation: "create_experiment", recovery: recovery) else {
            return ppoEncodingFailure(operation: "create_experiment", recovery: recovery)
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v2/appStoreVersionExperiments", body: body)
        } catch {
            return ppoMutationFailure(
                operation: "create_experiment",
                error: error,
                phase: .request,
                recovery: recovery
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Product page optimization experiment create"
            )
            let response = try JSONDecoder().decode(ASCExperimentResponse.self, from: receipt.data)
            try validateExperiment(response.data, expectedID: nil, expectedAppID: appID, context: "experiment create")
            try validatePPODocumentSelf(
                response.links.`self`,
                expectedPath: "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(response.data.id))",
                context: "experiment create"
            )
            guard response.data.attributes?.name == name,
                  response.data.attributes?.trafficProportion == trafficProportion,
                  response.data.attributes?.platform == platform else {
                throw PPOArgumentError("Apple create response did not preserve the requested experiment attributes")
            }
            return ppoMutationSuccess(
                operation: "create_experiment",
                statusCode: receipt.statusCode,
                resourceField: "experiment",
                resource: formatExperiment(response.data)
            )
        } catch {
            return ppoMutationFailure(
                operation: "create_experiment",
                error: error,
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
    }

    func updateExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'experiment_id' and at least one update field are missing")
        }

        let experimentID: String
        let name: ASCPPONullable<String>?
        let trafficProportion: ASCPPONullable<Int>?
        let started: ASCPPONullable<Bool>?
        let lifecycleAction: String?
        do {
            try validatePPOArguments(
                arguments,
                allowed: ["experiment_id", "name", "traffic_proportion", "state", "confirm_experiment_id"]
            )
            experimentID = try requiredPPOIdentifier("experiment_id", from: arguments)
            name = try nullablePPOString(arguments["name"], field: "name")
            trafficProportion = try nullablePPOInteger(arguments["traffic_proportion"], field: "traffic_proportion")
            (started, lifecycleAction) = try nullablePPOStarted(arguments["state"])
            guard name != nil || trafficProportion != nil || started != nil else {
                throw PPOArgumentError("At least one of name, traffic_proportion, or state must be supplied")
            }
            if arguments["state"] != nil {
                let confirmation = try requiredPPOIdentifier("confirm_experiment_id", from: arguments)
                guard confirmation == experimentID else {
                    throw PPOArgumentError(
                        "Changing experiment lifecycle is consequential. Set confirm_experiment_id to the exact experiment_id to continue."
                    )
                }
            } else if arguments["confirm_experiment_id"] != nil {
                throw PPOArgumentError("confirm_experiment_id is only valid when state is supplied")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate experiment update")
        }

        let request = UpdateExperimentRequest(
            data: .init(
                id: experimentID,
                attributes: .init(
                    name: name,
                    trafficProportion: trafficProportion,
                    started: started
                )
            )
        )
        let requestedValues = ppoRequestedValues(
            arguments,
            fields: ["name", "traffic_proportion", "state"]
        )
        let recovery = PPOMutationRecovery(
            action: lifecycleAction ?? "UPDATE",
            identifiers: ["experiment_id": .string(experimentID)],
            requestedValues: requestedValues,
            listTool: nil,
            listArguments: nil,
            getTool: "ppo_get_experiment",
            getIDArgument: "experiment_id",
            exactID: experimentID,
            matchingFields: requestedValues.keys.sorted()
        )
        guard let body = encodePPORequest(request, operation: "update_experiment", recovery: recovery) else {
            return ppoEncodingFailure(operation: "update_experiment", recovery: recovery)
        }

        let path = "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentID, field: "experiment_id"))"
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(path, body: body)
        } catch {
            return ppoMutationFailure(
                operation: "update_experiment",
                error: error,
                phase: .request,
                recovery: recovery
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Product page optimization experiment update"
            )
            let response = try JSONDecoder().decode(ASCExperimentResponse.self, from: receipt.data)
            try validateExperiment(response.data, expectedID: experimentID, expectedAppID: nil, context: "experiment update")
            try validatePPODocumentSelf(response.links.`self`, expectedPath: path, context: "experiment update")
            try validateExperimentUpdateResponse(response.data, name: name, trafficProportion: trafficProportion)
            if let lifecycleAction {
                guard lifecycleAction == "STOP",
                      response.data.attributes?.hasState == true,
                      response.data.attributes?.state == .stopped else {
                    throw PPOArgumentError(
                        "Apple returned HTTP 200, but its response cannot verify the requested \(lifecycleAction) lifecycle outcome"
                    )
                }
            }
            var result = ppoMutationSuccessObject(
                operation: "update_experiment",
                statusCode: receipt.statusCode,
                resourceField: "experiment",
                resource: formatExperiment(response.data),
                changed: nil
            )
            if let lifecycleAction {
                result["lifecycleAction"] = lifecycleAction
                result["lifecycleConfirmationMatched"] = true
            }
            return MCPResult.jsonObject(result)
        } catch {
            return ppoMutationFailure(
                operation: "update_experiment",
                error: error,
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
    }

    func deleteExperiment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await deletePPOResource(
            params,
            operation: "delete_experiment",
            idField: "experiment_id",
            confirmationField: "confirm_experiment_id",
            resourceName: "experiment",
            pathPrefix: "/v2/appStoreVersionExperiments",
            getTool: "ppo_get_experiment"
        )
    }

    func listTreatments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'experiment_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["experiment_id", "limit", "next_url"])
            let experimentID = try requiredPPOIdentifier("experiment_id", from: arguments)
            let path = "/v2/appStoreVersionExperiments/\(try ASCPathSegment.encode(experimentID, field: "experiment_id"))/appStoreVersionExperimentTreatments"
            let limit = try ppoLimit(arguments["limit"])
            let query = ["limit": String(limit)]
            let paginationScope = PaginationScope.strict(path: path, query: query)
            let response: ASCTreatmentsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCTreatmentsResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCTreatmentsResponse.self)
            }
            try validatePPOCollectionLinks(
                response.links,
                paginationScope: paginationScope,
                context: "treatment list"
            )
            var identities = Set<String>()
            for treatment in response.data {
                try validateTreatment(treatment, expectedID: nil, expectedExperimentID: experimentID, context: "treatment list")
                guard identities.insert(treatment.id).inserted else {
                    throw PPOArgumentError("Apple returned a duplicate treatment identity")
                }
            }
            try validatePPOPaging(response.meta, count: response.data.count, requestedLimit: limit, context: "treatment list")
            var result: [String: Any] = [
                "success": true,
                "experimentId": experimentID,
                "treatments": response.data.map(formatTreatment),
                "count": response.data.count,
                "limit": limit
            ]
            appendPPOPagination(response.links, meta: response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list product page optimization treatments")
        }
    }

    func getTreatment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'treatment_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["treatment_id"])
            let treatmentID = try requiredPPOIdentifier("treatment_id", from: arguments)
            let path = "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(treatmentID, field: "treatment_id"))"
            let response = try await httpClient.get(path, as: ASCTreatmentResponse.self)
            try validateTreatment(response.data, expectedID: treatmentID, expectedExperimentID: nil, context: "treatment get")
            try validatePPODocumentSelf(response.links.`self`, expectedPath: path, context: "treatment get")
            return MCPResult.jsonObject([
                "success": true,
                "treatment": formatTreatment(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get product page optimization treatment")
        }
    }

    func createTreatment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: experiment_id, name")
        }
        let experimentID: String
        let name: String
        let appIconName: ASCPPONullable<String>?
        do {
            try validatePPOArguments(arguments, allowed: ["experiment_id", "name", "app_icon_name"])
            experimentID = try requiredPPOIdentifier("experiment_id", from: arguments)
            name = try requiredPPOString("name", from: arguments)
            appIconName = try nullablePPOString(arguments["app_icon_name"], field: "app_icon_name")
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate treatment creation")
        }

        let request = CreateTreatmentRequest(
            data: .init(
                attributes: .init(name: name, appIconName: appIconName),
                relationships: .init(
                    appStoreVersionExperimentV2: .init(
                        data: ASCResourceIdentifier(type: "appStoreVersionExperiments", id: experimentID)
                    )
                )
            )
        )
        var identifiers: [String: Value] = [
            "experiment_id": .string(experimentID),
            "name": .string(name)
        ]
        identifiers["app_icon_name"] = ppoNullableValue(appIconName)
        let recovery = PPOMutationRecovery(
            action: "CREATE",
            identifiers: identifiers,
            requestedValues: ppoRequestedValues(arguments, fields: ["name", "app_icon_name"]),
            listTool: "ppo_list_treatments",
            listArguments: ["experiment_id": .string(experimentID)],
            getTool: "ppo_get_treatment",
            getIDArgument: "treatment_id",
            exactID: nil,
            matchingFields: ["name", "app_icon_name"]
        )
        guard let body = encodePPORequest(request, operation: "create_treatment", recovery: recovery) else {
            return ppoEncodingFailure(operation: "create_treatment", recovery: recovery)
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appStoreVersionExperimentTreatments", body: body)
        } catch {
            return ppoMutationFailure(operation: "create_treatment", error: error, phase: .request, recovery: recovery)
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Product page optimization treatment create"
            )
            let response = try JSONDecoder().decode(ASCTreatmentResponse.self, from: receipt.data)
            try validateTreatment(response.data, expectedID: nil, expectedExperimentID: experimentID, context: "treatment create")
            try validatePPODocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(response.data.id))",
                context: "treatment create"
            )
            guard response.data.attributes?.name == name else {
                throw PPOArgumentError("Apple create response did not preserve the requested treatment name")
            }
            try validateTreatmentAttribute(
                response.data.attributes,
                update: appIconName,
                keyPath: \.appIconName,
                presenceKeyPath: \.hasAppIconName,
                field: "app_icon_name"
            )
            return ppoMutationSuccess(
                operation: "create_treatment",
                statusCode: receipt.statusCode,
                resourceField: "treatment",
                resource: formatTreatment(response.data)
            )
        } catch {
            return ppoMutationFailure(
                operation: "create_treatment",
                error: error,
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
    }

    func updateTreatment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'treatment_id' and at least one update field are missing")
        }
        let treatmentID: String
        let name: ASCPPONullable<String>?
        let appIconName: ASCPPONullable<String>?
        do {
            try validatePPOArguments(arguments, allowed: ["treatment_id", "name", "app_icon_name"])
            treatmentID = try requiredPPOIdentifier("treatment_id", from: arguments)
            name = try nullablePPOString(arguments["name"], field: "name")
            appIconName = try nullablePPOString(arguments["app_icon_name"], field: "app_icon_name")
            guard name != nil || appIconName != nil else {
                throw PPOArgumentError("At least one of name or app_icon_name must be supplied")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate treatment update")
        }

        let request = UpdateTreatmentRequest(
            data: .init(id: treatmentID, attributes: .init(name: name, appIconName: appIconName))
        )
        let requestedValues = ppoRequestedValues(arguments, fields: ["name", "app_icon_name"])
        let recovery = PPOMutationRecovery(
            action: "UPDATE",
            identifiers: ["treatment_id": .string(treatmentID)],
            requestedValues: requestedValues,
            listTool: nil,
            listArguments: nil,
            getTool: "ppo_get_treatment",
            getIDArgument: "treatment_id",
            exactID: treatmentID,
            matchingFields: requestedValues.keys.sorted()
        )
        guard let body = encodePPORequest(request, operation: "update_treatment", recovery: recovery) else {
            return ppoEncodingFailure(operation: "update_treatment", recovery: recovery)
        }
        let path = "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(treatmentID, field: "treatment_id"))"
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(path, body: body)
        } catch {
            return ppoMutationFailure(operation: "update_treatment", error: error, phase: .request, recovery: recovery)
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Product page optimization treatment update"
            )
            let response = try JSONDecoder().decode(ASCTreatmentResponse.self, from: receipt.data)
            try validateTreatment(response.data, expectedID: treatmentID, expectedExperimentID: nil, context: "treatment update")
            try validatePPODocumentSelf(response.links.`self`, expectedPath: path, context: "treatment update")
            try validateTreatmentAttribute(
                response.data.attributes,
                update: name,
                keyPath: \.name,
                presenceKeyPath: \.hasName,
                field: "name"
            )
            try validateTreatmentAttribute(
                response.data.attributes,
                update: appIconName,
                keyPath: \.appIconName,
                presenceKeyPath: \.hasAppIconName,
                field: "app_icon_name"
            )
            return ppoMutationSuccess(
                operation: "update_treatment",
                statusCode: receipt.statusCode,
                resourceField: "treatment",
                resource: formatTreatment(response.data),
                changed: nil
            )
        } catch {
            return ppoMutationFailure(
                operation: "update_treatment",
                error: error,
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
    }

    func deleteTreatment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await deletePPOResource(
            params,
            operation: "delete_treatment",
            idField: "treatment_id",
            confirmationField: "confirm_treatment_id",
            resourceName: "treatment",
            pathPrefix: "/v1/appStoreVersionExperimentTreatments",
            getTool: "ppo_get_treatment"
        )
    }

    func listTreatmentLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'treatment_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["treatment_id", "limit", "locale", "next_url"])
            let treatmentID = try requiredPPOIdentifier("treatment_id", from: arguments)
            let locales = try ppoStringList(arguments["locale"], field: "locale", allowedValues: nil)
            let path = "/v1/appStoreVersionExperimentTreatments/\(try ASCPathSegment.encode(treatmentID, field: "treatment_id"))/appStoreVersionExperimentTreatmentLocalizations"
            let limit = try ppoLimit(arguments["limit"])
            var query = ["limit": String(limit)]
            if let locales {
                query["filter[locale]"] = locales.joined(separator: ",")
            }
            let paginationScope = PaginationScope.strict(path: path, query: query)
            let response: ASCTreatmentLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCTreatmentLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCTreatmentLocalizationsResponse.self)
            }
            try validatePPOCollectionLinks(
                response.links,
                paginationScope: paginationScope,
                context: "treatment localization list"
            )
            var identities = Set<String>()
            for localization in response.data {
                try validateTreatmentLocalization(
                    localization,
                    expectedID: nil,
                    expectedTreatmentID: treatmentID,
                    context: "treatment localization list"
                )
                guard identities.insert(localization.id).inserted else {
                    throw PPOArgumentError("Apple returned a duplicate treatment-localization identity")
                }
            }
            try validatePPOPaging(
                response.meta,
                count: response.data.count,
                requestedLimit: limit,
                context: "treatment localization list"
            )
            var result: [String: Any] = [
                "success": true,
                "treatmentId": treatmentID,
                "localizations": response.data.map(formatTreatmentLocalization),
                "count": response.data.count,
                "limit": limit
            ]
            appendPPOPagination(response.links, meta: response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list treatment localizations")
        }
    }

    func getTreatmentLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }
        do {
            try validatePPOArguments(arguments, allowed: ["localization_id"])
            let localizationID = try requiredPPOIdentifier("localization_id", from: arguments)
            let path = "/v1/appStoreVersionExperimentTreatmentLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let response = try await httpClient.get(path, as: ASCTreatmentLocalizationResponse.self)
            try validateTreatmentLocalization(
                response.data,
                expectedID: localizationID,
                expectedTreatmentID: nil,
                context: "treatment localization get"
            )
            try validatePPODocumentSelf(response.links.`self`, expectedPath: path, context: "treatment localization get")
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatTreatmentLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get treatment localization")
        }
    }

    func createTreatmentLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: treatment_id, locale")
        }
        let treatmentID: String
        let locale: String
        do {
            try validatePPOArguments(arguments, allowed: ["treatment_id", "locale"])
            treatmentID = try requiredPPOIdentifier("treatment_id", from: arguments)
            locale = try requiredPPOString("locale", from: arguments)
            guard !locale.contains(",") else {
                throw PPOArgumentError("locale must not contain a comma")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate treatment localization creation")
        }
        let request = CreateTreatmentLocalizationRequest(
            data: .init(
                attributes: .init(locale: locale),
                relationships: .init(
                    appStoreVersionExperimentTreatment: .init(
                        data: ASCResourceIdentifier(type: "appStoreVersionExperimentTreatments", id: treatmentID)
                    )
                )
            )
        )
        let recovery = PPOMutationRecovery(
            action: "CREATE",
            identifiers: ["treatment_id": .string(treatmentID), "locale": .string(locale)],
            requestedValues: ppoRequestedValues(arguments, fields: ["locale"]),
            listTool: "ppo_list_treatment_localizations",
            listArguments: ["treatment_id": .string(treatmentID), "locale": .string(locale)],
            getTool: "ppo_get_treatment_localization",
            getIDArgument: "localization_id",
            exactID: nil,
            matchingFields: ["locale"]
        )
        guard let body = encodePPORequest(request, operation: "create_treatment_localization", recovery: recovery) else {
            return ppoEncodingFailure(operation: "create_treatment_localization", recovery: recovery)
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appStoreVersionExperimentTreatmentLocalizations", body: body)
        } catch {
            return ppoMutationFailure(
                operation: "create_treatment_localization",
                error: error,
                phase: .request,
                recovery: recovery
            )
        }
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Product page optimization treatment localization create"
            )
            let response = try JSONDecoder().decode(ASCTreatmentLocalizationResponse.self, from: receipt.data)
            try validateTreatmentLocalization(
                response.data,
                expectedID: nil,
                expectedTreatmentID: treatmentID,
                context: "treatment localization create"
            )
            try validatePPODocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/appStoreVersionExperimentTreatmentLocalizations/\(try ASCPathSegment.encode(response.data.id))",
                context: "treatment localization create"
            )
            guard response.data.attributes?.locale == locale else {
                throw PPOArgumentError("Apple create response did not preserve the requested locale")
            }
            return ppoMutationSuccess(
                operation: "create_treatment_localization",
                statusCode: receipt.statusCode,
                resourceField: "localization",
                resource: formatTreatmentLocalization(response.data)
            )
        } catch {
            return ppoMutationFailure(
                operation: "create_treatment_localization",
                error: error,
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
    }

    func deleteTreatmentLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await deletePPOResource(
            params,
            operation: "delete_treatment_localization",
            idField: "localization_id",
            confirmationField: "confirm_localization_id",
            resourceName: "localization",
            pathPrefix: "/v1/appStoreVersionExperimentTreatmentLocalizations",
            getTool: "ppo_get_treatment_localization"
        )
    }
}

// MARK: - Validation and Recovery
private extension ProductPageOptimizationWorker {
    struct PPOMutationRecovery {
        let action: String
        let identifiers: [String: Value]
        let requestedValues: [String: Value]
        let listTool: String?
        let listArguments: [String: Value]?
        let getTool: String
        let getIDArgument: String
        let exactID: String?
        let matchingFields: [String]
    }

    func listExperimentCollection(
        arguments: [String: Value],
        path: String,
        scopeField: String,
        scopeID: String,
        expectedAppID: String?
    ) async throws -> CallTool.Result {
        let states = try ppoStringList(
            arguments["states"],
            field: "states",
            allowedValues: Set(Self.supportedExperimentStates)
        )
        let limit = try ppoLimit(arguments["limit"])
        var query = ["limit": String(limit)]
        if let states {
            query["filter[state]"] = states.joined(separator: ",")
        }
        let paginationScope = PaginationScope.strict(path: path, query: query)
        let response: ASCExperimentsResponse
        if let nextURL = try paginationURL(from: arguments["next_url"]) {
            response = try await httpClient.getPage(
                nextURL,
                scope: paginationScope,
                as: ASCExperimentsResponse.self
            )
        } else {
            response = try await httpClient.get(path, parameters: query, as: ASCExperimentsResponse.self)
        }
        try validatePPOCollectionLinks(
            response.links,
            paginationScope: paginationScope,
            context: "experiment collection"
        )
        var identities = Set<String>()
        for experiment in response.data {
            try validateExperiment(
                experiment,
                expectedID: nil,
                expectedAppID: expectedAppID,
                context: "experiment collection"
            )
            guard identities.insert(experiment.id).inserted else {
                throw PPOArgumentError("Apple returned a duplicate experiment identity")
            }
        }
        try validatePPOPaging(response.meta, count: response.data.count, requestedLimit: limit, context: "experiment collection")
        var result: [String: Any] = [
            "success": true,
            scopeField: scopeID,
            "experiments": response.data.map(formatExperiment),
            "count": response.data.count,
            "limit": limit
        ]
        appendPPOPagination(response.links, meta: response.meta, to: &result)
        return MCPResult.jsonObject(result)
    }

    func deletePPOResource(
        _ params: CallTool.Parameters,
        operation: String,
        idField: String,
        confirmationField: String,
        resourceName: String,
        pathPrefix: String,
        getTool: String
    ) async -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: \(idField), \(confirmationField)")
        }
        let resourceID: String
        do {
            try validatePPOArguments(arguments, allowed: [idField, confirmationField])
            resourceID = try requiredPPOIdentifier(idField, from: arguments)
            let confirmationID = try requiredPPOIdentifier(confirmationField, from: arguments)
            guard resourceID == confirmationID else {
                throw PPOArgumentError(
                    "Deleting this \(resourceName) is irreversible. Set \(confirmationField) to the exact \(idField) to continue."
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate \(resourceName) deletion")
        }
        let recovery = PPOMutationRecovery(
            action: "DELETE",
            identifiers: [idField: .string(resourceID)],
            requestedValues: [idField: .string(resourceID)],
            listTool: nil,
            listArguments: nil,
            getTool: getTool,
            getIDArgument: idField,
            exactID: resourceID,
            matchingFields: [idField]
        )
        let path: String
        do {
            path = "\(pathPrefix)/\(try ASCPathSegment.encode(resourceID, field: idField))"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate \(resourceName) deletion")
        }
        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(path)
        } catch {
            return ppoMutationFailure(operation: operation, error: error, phase: .request, recovery: recovery)
        }
        guard receipt.statusCode == 204 else {
            return ppoMutationFailure(
                operation: operation,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode),
                phase: .acceptedResponse,
                recovery: recovery
            )
        }
        return MCPResult.jsonObject([
            "success": true,
            "operation": operation,
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changed": true,
            "retrySafe": false,
            idField: resourceID,
            "confirmationMatched": true,
            "statusCode": receipt.statusCode,
            "message": "Product page optimization \(resourceName) deleted"
        ])
    }

    func validatePPOArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw PPOArgumentError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    func requiredPPOIdentifier(_ field: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[field]?.stringValue else {
            throw PPOArgumentError("Required parameter '\(field)' must be a string")
        }
        let encoded = try ASCPathSegment.encode(value, field: field)
        guard encoded == value else {
            throw PPOArgumentError("'\(field)' must be a canonical App Store Connect resource ID")
        }
        return value
    }

    func requiredPPOString(_ field: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[field]?.stringValue else {
            throw PPOArgumentError("Required parameter '\(field)' must be a string")
        }
        return try validatedPPOString(value, field: field)
    }

    func requiredPPOInteger(_ field: String, from arguments: [String: Value]) throws -> Int {
        guard let value = arguments[field]?.intValue else {
            throw PPOArgumentError("Required parameter '\(field)' must be an integer")
        }
        return value
    }

    func validatedPPOString(_ value: String, field: String) throws -> String {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PPOArgumentError("'\(field)' must be non-empty, have no surrounding whitespace, and contain no control characters")
        }
        return value
    }

    func ppoPlatform(_ value: Value?) throws -> ASCPPOPlatform {
        guard let value else { return .iOS }
        guard let rawValue = value.stringValue,
              let platform = ASCPPOPlatform(rawValue: rawValue) else {
            throw PPOArgumentError("platform must be one of: \(Self.supportedPlatforms.joined(separator: ", "))")
        }
        return platform
    }

    func nullablePPOString(_ value: Value?, field: String) throws -> ASCPPONullable<String>? {
        guard let value else { return nil }
        if value.isNull { return .null }
        guard let string = value.stringValue else {
            throw PPOArgumentError("'\(field)' must be a string or null")
        }
        return .value(try validatedPPOString(string, field: field))
    }

    func nullablePPOInteger(_ value: Value?, field: String) throws -> ASCPPONullable<Int>? {
        guard let value else { return nil }
        if value.isNull { return .null }
        guard let integer = value.intValue else {
            throw PPOArgumentError("'\(field)' must be an integer or null")
        }
        return .value(integer)
    }

    func nullablePPOStarted(_ value: Value?) throws -> (ASCPPONullable<Bool>?, String?) {
        guard let value else { return (nil, nil) }
        if value.isNull { return (.null, "CLEAR") }
        guard let state = value.stringValue else {
            throw PPOArgumentError("state must be START, STOP, or null")
        }
        switch state {
        case "START":
            return (.value(true), "START")
        case "STOP":
            return (.value(false), "STOP")
        default:
            throw PPOArgumentError("state must be START, STOP, or null")
        }
    }

    func ppoLimit(_ value: Value?) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw PPOArgumentError("limit must be an integer between 1 and 200")
        }
        return limit
    }

    func ppoStringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>?
    ) throws -> [String]? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue, !array.isEmpty {
            guard array.allSatisfy({ $0.stringValue != nil }) else {
                throw PPOArgumentError("'\(field)' must contain only strings")
            }
            values = array.compactMap(\.stringValue)
        } else {
            throw PPOArgumentError("'\(field)' must be a non-empty string or array of strings")
        }
        for value in values {
            _ = try validatedPPOString(value, field: field)
            guard !value.contains(",") else {
                throw PPOArgumentError("'\(field)' values must not contain commas")
            }
            if let allowedValues, !allowedValues.contains(value) {
                throw PPOArgumentError(
                    "Unsupported \(field) value '\(value)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
                )
            }
        }
        guard Set(values).count == values.count else {
            throw PPOArgumentError("'\(field)' must not contain duplicate values")
        }
        return values
    }

    func validateExperiment(
        _ experiment: ASCExperiment,
        expectedID: String?,
        expectedAppID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: experiment.type.rawValue,
            id: experiment.id,
            expectedType: ASCPPOExperimentResourceType.experiment.rawValue,
            expectedID: expectedID,
            context: context
        )
        if let app = experiment.relationships?.app?.data {
            try validatePPORelationship(
                app,
                expectedType: "apps",
                expectedID: expectedAppID,
                context: "\(context) app relationship"
            )
        }
    }

    func validateTreatment(
        _ treatment: ASCTreatment,
        expectedID: String?,
        expectedExperimentID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: treatment.type.rawValue,
            id: treatment.id,
            expectedType: ASCPPOTreatmentResourceType.treatment.rawValue,
            expectedID: expectedID,
            context: context
        )
        if let parent = treatment.relationships?.appStoreVersionExperimentV2?.data {
            try validatePPORelationship(
                parent,
                expectedType: ASCPPOExperimentResourceType.experiment.rawValue,
                expectedID: expectedExperimentID,
                context: "\(context) V2 experiment relationship"
            )
        } else if treatment.relationships?.appStoreVersionExperiment?.data != nil {
            throw PPOArgumentError("Apple returned only the deprecated V1 experiment relationship in \(context)")
        }
    }

    func validateTreatmentLocalization(
        _ localization: ASCTreatmentLocalization,
        expectedID: String?,
        expectedTreatmentID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: localization.type.rawValue,
            id: localization.id,
            expectedType: ASCPPOLocalizationResourceType.localization.rawValue,
            expectedID: expectedID,
            context: context
        )
        if let parent = localization.relationships?.appStoreVersionExperimentTreatment?.data {
            try validatePPORelationship(
                parent,
                expectedType: ASCPPOTreatmentResourceType.treatment.rawValue,
                expectedID: expectedTreatmentID,
                context: "\(context) treatment relationship"
            )
        }
    }

    func validatePPORelationship(
        _ identifier: ASCResourceIdentifier,
        expectedType: String,
        expectedID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validateExperimentUpdateResponse(
        _ experiment: ASCExperiment,
        name: ASCPPONullable<String>?,
        trafficProportion: ASCPPONullable<Int>?
    ) throws {
        if let name {
            switch name {
            case .value(let expected):
                guard experiment.attributes?.hasName == true,
                      experiment.attributes?.name == expected else {
                    throw PPOArgumentError("Apple update response did not preserve the requested experiment name")
                }
            case .null:
                guard experiment.attributes?.hasName == true,
                      experiment.attributes?.name == nil else {
                    throw PPOArgumentError("Apple update response did not preserve explicit null for experiment name")
                }
            }
        }
        if let trafficProportion {
            switch trafficProportion {
            case .value(let expected):
                guard experiment.attributes?.hasTrafficProportion == true,
                      experiment.attributes?.trafficProportion == expected else {
                    throw PPOArgumentError("Apple update response did not preserve the requested traffic proportion")
                }
            case .null:
                guard experiment.attributes?.hasTrafficProportion == true,
                      experiment.attributes?.trafficProportion == nil else {
                    throw PPOArgumentError("Apple update response did not preserve explicit null for traffic proportion")
                }
            }
        }
    }

    func validateTreatmentAttribute(
        _ attributes: TreatmentAttributes?,
        update: ASCPPONullable<String>?,
        keyPath: KeyPath<TreatmentAttributes, String?>,
        presenceKeyPath: KeyPath<TreatmentAttributes, Bool>,
        field: String
    ) throws {
        guard let update else { return }
        switch update {
        case .value(let expected):
            guard let attributes,
                  attributes[keyPath: presenceKeyPath],
                  attributes[keyPath: keyPath] == expected else {
                throw PPOArgumentError("Apple response did not preserve the requested \(field)")
            }
        case .null:
            guard let attributes,
                  attributes[keyPath: presenceKeyPath],
                  attributes[keyPath: keyPath] == nil else {
                throw PPOArgumentError("Apple response did not preserve explicit null for \(field)")
            }
        }
    }

    func validatePPODocumentSelf(_ value: String, expectedPath: String, context: String) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(path: expectedPath, allowedParameters: [])
            )
        } catch {
            throw ASCError.parsing("Apple returned an out-of-scope required links.self in \(context)")
        }
    }

    func validatePPOCollectionLinks(
        _ links: ASCPagedDocumentLinks,
        paginationScope: PaginationScope,
        context: String
    ) throws {
        let selfScope = PaginationScope(
            path: paginationScope.path,
            requiredParameters: paginationScope.requiredParameters,
            allowedParameters: paginationScope.allowedParameters
        )
        do {
            _ = try httpClient.validatedScopedLink(links.`self`, scope: selfScope)
        } catch {
            throw ASCError.parsing("Apple returned an out-of-scope required links.self in \(context)")
        }
        if let next = links.next {
            do {
                _ = try httpClient.validatedScopedLink(next, scope: paginationScope)
            } catch {
                throw ASCError.parsing("Apple returned an out-of-scope links.next in \(context)")
            }
        }
    }

    func validatePPOPaging(
        _ meta: ASCPagingInformation?,
        count: Int,
        requestedLimit: Int,
        context: String
    ) throws {
        guard let meta else {
            guard count <= requestedLimit else {
                throw PPOArgumentError("Apple returned more \(context) resources than the requested limit")
            }
            return
        }
        guard let paging = meta.paging, let limit = paging.limit else {
            throw PPOArgumentError("Apple returned incomplete paging metadata for \(context)")
        }
        guard limit == requestedLimit, count <= limit else {
            throw PPOArgumentError("Apple returned paging metadata outside the requested \(context) scope")
        }
        if let total = paging.total, total < count {
            throw PPOArgumentError("Apple returned an impossible paging total for \(context)")
        }
    }

    func appendPPOPagination(
        _ links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        to result: inout [String: Any]
    ) {
        if let next = links.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    func encodePPORequest<T: Encodable>(
        _ request: T,
        operation: String,
        recovery: PPOMutationRecovery
    ) -> Data? {
        try? JSONEncoder().encode(request)
    }

    func ppoEncodingFailure(operation: String, recovery: PPOMutationRecovery) -> CallTool.Result {
        var payload: [String: Value] = [
            "success": .bool(false),
            "error": .string("Failed to encode the product page optimization request"),
            "operation": .string(operation),
            "action": .string(recovery.action),
            "operationCommitState": .string("not_attempted"),
            "write_outcome": .string("not_attempted"),
            "mutationAttempted": .bool(false),
            "operationCommitted": .bool(false),
            "retrySafe": .bool(true),
            "identifiers": .object(recovery.identifiers),
            "requestedValues": .object(recovery.requestedValues)
        ]
        payload["recovery"] = ppoRecoveryValue(recovery)
        return MCPResult.json(.object(payload), isError: true)
    }

    func ppoMutationFailure(
        operation: String,
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        recovery: PPOMutationRecovery
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: phase)
        var payload: [String: Value] = [
            "success": .bool(false),
            "error": .string(Redactor.redact(error.localizedDescription)),
            "operation": .string(operation),
            "action": .string(recovery.action),
            "operationCommitState": .string(disposition.rawValue),
            "write_outcome": .string(disposition.rawValue),
            "mutationAttempted": .bool(true),
            "retrySafe": .bool(disposition == .rejected),
            "identifiers": .object(recovery.identifiers),
            "requestedValues": .object(recovery.requestedValues),
            "cause": ppoCauseValue(error, phase: phase)
        ]
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = .bool(false)
            payload["outcomeUnknown"] = .bool(false)
        case .outcomeUnknown:
            payload["operationCommitted"] = .null
            payload["outcomeUnknown"] = .bool(true)
            payload["inspectionRequired"] = .bool(true)
            payload["recovery"] = ppoRecoveryValue(recovery)
        case .committedUnverified:
            payload["operationCommitted"] = .bool(true)
            payload["outcomeUnknown"] = .bool(false)
            payload["inspectionRequired"] = .bool(true)
            payload["recovery"] = ppoRecoveryValue(recovery)
        }
        let text: String
        switch disposition {
        case .rejected:
            text = "Error: Apple definitively rejected the PPO mutation; it was not committed."
        case .outcomeUnknown:
            text = "Error: The PPO mutation outcome is unknown. Inspect the exact resource state before retrying."
        case .committedUnverified:
            text = "Error: Apple accepted the PPO mutation, but the exact result was not safely verified. Inspect before retrying."
        }
        return MCPResult.json(.object(payload), text: text, isError: true)
    }

    func ppoCauseValue(
        _ error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> Value {
        if let ascError = error as? ASCError {
            return ascError.structuredValue
        }
        if error is CancellationError {
            return .object([
                "type": .string("cancellation"),
                "message": .string("The request was cancelled before its outcome was confirmed")
            ])
        }
        return .object([
            "type": .string(phase == .request ? "request" : "response_validation"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    func ppoRecoveryValue(_ recovery: PPOMutationRecovery) -> Value {
        var object: [String: Value] = [
            "action": .string(recovery.action),
            "requested_values": .object(recovery.requestedValues),
            "match_requested": .object([
                "fields": .array(recovery.matchingFields.map(Value.string)),
                "identifiers": .object(recovery.identifiers),
                "requested_values": .object(recovery.requestedValues)
            ])
        ]
        if let listTool = recovery.listTool, let listArguments = recovery.listArguments {
            object["list_candidates"] = .object([
                "tool": .string(listTool),
                "arguments": .object(listArguments),
                "continue_with_next_url": .bool(true)
            ])
        }
        var getArguments: [String: Value] = [:]
        if let exactID = recovery.exactID {
            getArguments[recovery.getIDArgument] = .string(exactID)
        }
        object["get_candidate"] = .object([
            "tool": .string(recovery.getTool),
            "arguments": .object(getArguments),
            "id_argument": .string(recovery.getIDArgument),
            "id_source": .string(recovery.exactID == nil ? "list_candidates result" : "exact input ID"),
            "instruction": .string("Inspect the exact resource before any retry; observed state alone does not attribute an ambiguous write to this invocation.")
        ])
        return .object(object)
    }

    func ppoMutationSuccess(
        operation: String,
        statusCode: Int,
        resourceField: String,
        resource: [String: Any],
        changed: Bool? = true
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            ppoMutationSuccessObject(
                operation: operation,
                statusCode: statusCode,
                resourceField: resourceField,
                resource: resource,
                changed: changed
            )
        )
    }

    func ppoMutationSuccessObject(
        operation: String,
        statusCode: Int,
        resourceField: String,
        resource: [String: Any],
        changed: Bool? = true
    ) -> [String: Any] {
        var result: [String: Any] = [
            "success": true,
            "operation": operation,
            "operationCommitted": true,
            "operationCommitState": "committed",
            "changeVerified": changed != nil,
            "retrySafe": false,
            "statusCode": statusCode,
            resourceField: resource
        ]
        if let changed {
            result["changed"] = changed
        } else {
            result["changed"] = NSNull()
        }
        return result
    }

    func ppoRequestedValues(_ arguments: [String: Value], fields: [String]) -> [String: Value] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            arguments[field].map { (field, $0) }
        })
    }

    func ppoNullableValue(_ value: ASCPPONullable<String>?) -> Value {
        guard let value else { return .string("omitted") }
        switch value {
        case .value(let string):
            return .string(string)
        case .null:
            return .null
        }
    }

    func formatExperiment(_ experiment: ASCExperiment) -> [String: Any] {
        var result: [String: Any] = [
            "id": experiment.id,
            "type": experiment.type.rawValue,
            "name": (experiment.attributes?.name).jsonSafe,
            "platform": (experiment.attributes?.platform?.rawValue).jsonSafe,
            "trafficProportion": (experiment.attributes?.trafficProportion).jsonSafe,
            "state": (experiment.attributes?.state?.rawValue).jsonSafe,
            "reviewRequired": (experiment.attributes?.reviewRequired).jsonSafe,
            "startDate": (experiment.attributes?.startDate).jsonSafe,
            "endDate": (experiment.attributes?.endDate).jsonSafe
        ]
        if let app = experiment.relationships?.app?.data {
            result["appId"] = app.id
        }
        if let latestControlVersion = experiment.relationships?.latestControlVersion?.data {
            result["latestControlVersionId"] = latestControlVersion.id
        }
        if let controlVersions = experiment.relationships?.controlVersions?.data {
            result["controlVersionIds"] = controlVersions.map(\.id)
        }
        return result
    }

    func formatTreatment(_ treatment: ASCTreatment) -> [String: Any] {
        var result: [String: Any] = [
            "id": treatment.id,
            "type": treatment.type.rawValue,
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
        if let experiment = treatment.relationships?.appStoreVersionExperimentV2?.data {
            result["experimentV2Id"] = experiment.id
        }
        return result
    }

    func formatTreatmentLocalization(_ localization: ASCTreatmentLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": localization.id,
            "type": localization.type.rawValue,
            "locale": (localization.attributes?.locale).jsonSafe
        ]
        if let treatment = localization.relationships?.appStoreVersionExperimentTreatment?.data {
            result["treatmentId"] = treatment.id
        }
        return result
    }
}

private struct PPOArgumentError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
