import CryptoKit
import Foundation
import MCP

extension XcodeCloudWorker {
    /// Creates an Xcode Cloud workflow from the complete Apple API 4.4.1 request contract.
    /// - Parameter params: Tool parameters containing required attributes and relationships.
    /// - Returns: A verified commit result or an explicit rejected, unknown, or committed-unverified outcome.
    /// - Throws: Never; failures are represented in the MCP result.
    func createWorkflow(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let request: XcodeCloudWorkflowMutationRequestPlan
        do {
            request = try xcWorkflowMutationRequest(arguments, workflowID: nil, isCreate: true)
        } catch {
            return xcMutationNotAttempted(
                operation: "create_workflow",
                error: error,
                identifiers: xcMutationIdentifiers(arguments, fields: ["product_id", "repository_id"])
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/ciWorkflows", body: request.body)
        } catch {
            return xcMutationFailure(
                operation: "create_workflow",
                error: error,
                phase: .request,
                identifiers: xcRequestRelationshipIdentifiers(request),
                inspection: xcCreateInspection(request)
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Xcode Cloud workflow create"
            )
            let response = try JSONDecoder().decode(XcodeCloudMutationResourceDocument.self, from: receipt.data)
            try xcValidateMutationResponse(
                response,
                expectedID: nil,
                expectedPath: nil,
                request: request,
                context: "workflow create"
            )
            return xcMutationSuccess(
                operation: "create_workflow",
                statusCode: receipt.statusCode,
                resourceField: "workflow",
                resource: response.data,
                selfURL: response.links.`self`,
                included: response.included
            )
        } catch {
            return xcMutationFailure(
                operation: "create_workflow",
                error: error,
                phase: .acceptedResponse,
                identifiers: xcRequestRelationshipIdentifiers(request),
                inspection: xcCreateInspection(request)
            )
        }
    }

    /// Updates selected Xcode Cloud workflow fields while preserving omission and explicit null.
    /// - Parameter params: Tool parameters containing a workflow ID and at least one patch field.
    /// - Returns: A verified commit result or an explicit rejected, unknown, or committed-unverified outcome.
    /// - Throws: Never; failures are represented in the MCP result.
    func updateWorkflow(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let workflowID: String
        let path: String
        let request: XcodeCloudWorkflowMutationRequestPlan
        do {
            workflowID = try xcMutationResourceID("workflow_id", from: arguments)
            path = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))"
            request = try xcWorkflowMutationRequest(arguments, workflowID: workflowID, isCreate: false)
            guard !request.attributes.isEmpty || !request.relationships.isEmpty else {
                throw XcodeCloudMutationArgumentError(
                    "Provide at least one workflow attribute or version relationship to update"
                )
            }
        } catch {
            return xcMutationNotAttempted(
                operation: "update_workflow",
                error: error,
                identifiers: xcMutationIdentifiers(arguments, fields: ["workflow_id"])
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(path, body: request.body)
        } catch {
            return xcMutationFailure(
                operation: "update_workflow",
                error: error,
                phase: .request,
                identifiers: ["workflow_id": .string(workflowID)],
                inspection: xcResourceInspection(tool: "xcode_cloud_workflows_get", idField: "workflow_id", id: workflowID)
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Xcode Cloud workflow update"
            )
            let response = try JSONDecoder().decode(XcodeCloudMutationResourceDocument.self, from: receipt.data)
            try xcValidateMutationResponse(
                response,
                expectedID: workflowID,
                expectedPath: path,
                request: request,
                context: "workflow update"
            )
            return xcMutationSuccess(
                operation: "update_workflow",
                statusCode: receipt.statusCode,
                resourceField: "workflow",
                resource: response.data,
                selfURL: response.links.`self`,
                included: response.included
            )
        } catch {
            return xcMutationFailure(
                operation: "update_workflow",
                error: error,
                phase: .acceptedResponse,
                identifiers: ["workflow_id": .string(workflowID)],
                inspection: xcResourceInspection(tool: "xcode_cloud_workflows_get", idField: "workflow_id", id: workflowID)
            )
        }
    }

    /// Previews or permanently deletes an Xcode Cloud workflow.
    /// - Parameter params: Tool parameters containing the workflow ID and optional exact confirmation values.
    /// - Returns: A fresh preview or an explicit deletion outcome.
    /// - Throws: Never; failures are represented in the MCP result.
    func deleteWorkflow(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let workflowID: String
        let path: String
        do {
            try xcValidateMutationKeys(arguments, allowed: xcWorkflowDeleteFields, context: "arguments")
            workflowID = try xcMutationResourceID("workflow_id", from: arguments)
            path = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))"
        } catch {
            return xcMutationNotAttempted(
                operation: "delete_workflow",
                error: error,
                identifiers: xcMutationIdentifiers(arguments, fields: ["workflow_id"])
            )
        }

        let preview: XcodeCloudDeletionPreview
        do {
            let resource = try await xcFetchDeletionResource(path: path, expectedType: "ciWorkflows", expectedID: workflowID)
            let name = try xcRequiredResourceName(resource, context: "workflow deletion preview")
            let buildRunIDs = try await xcExactCollectionInventory(
                path: "\(path)/buildRuns",
                expectedType: "ciBuildRuns",
                context: "workflow build runs"
            )
            preview = XcodeCloudDeletionPreview(
                resourceType: "ciWorkflows",
                resourceID: workflowID,
                name: name,
                workflowCount: nil,
                buildRunCount: buildRunIDs.count,
                receipt: xcDeletionReceipt(
                    resourceType: "ciWorkflows",
                    resourceID: workflowID,
                    name: name,
                    workflowIDs: nil,
                    buildRunIDs: buildRunIDs
                )
            )
        } catch {
            return xcMutationNotAttempted(
                operation: "delete_workflow",
                error: error,
                identifiers: ["workflow_id": .string(workflowID)]
            )
        }

        guard xcHasAnyDeletionConfirmation(arguments, fields: xcWorkflowDeleteConfirmationFields) else {
            return xcWorkflowDeletionPreviewResult(preview)
        }
        guard xcWorkflowDeletionConfirmationMatches(arguments, preview: preview) else {
            return xcDeletionConfirmationMismatch(operation: "delete_workflow", preview: preview)
        }

        return await xcExecuteDeletion(
            operation: "delete_workflow",
            path: path,
            identifiers: ["workflow_id": .string(workflowID)],
            preview: preview,
            inspection: xcResourceInspection(tool: "xcode_cloud_workflows_get", idField: "workflow_id", id: workflowID)
        )
    }

    /// Previews or permanently deletes an Xcode Cloud product.
    /// - Parameter params: Tool parameters containing the product ID and optional exact confirmation values.
    /// - Returns: A fresh preview or an explicit deletion outcome.
    /// - Throws: Never; failures are represented in the MCP result.
    func deleteProduct(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let productID: String
        let path: String
        do {
            try xcValidateMutationKeys(arguments, allowed: xcProductDeleteFields, context: "arguments")
            productID = try xcMutationResourceID("product_id", from: arguments)
            path = "/v1/ciProducts/\(try ASCPathSegment.encode(productID))"
        } catch {
            return xcMutationNotAttempted(
                operation: "delete_product",
                error: error,
                identifiers: xcMutationIdentifiers(arguments, fields: ["product_id"])
            )
        }

        let preview: XcodeCloudDeletionPreview
        do {
            let resource = try await xcFetchDeletionResource(path: path, expectedType: "ciProducts", expectedID: productID)
            let name = try xcRequiredResourceName(resource, context: "product deletion preview")
            let workflowIDs = try await xcExactCollectionInventory(
                path: "\(path)/workflows",
                expectedType: "ciWorkflows",
                context: "product workflows"
            )
            let buildRunIDs = try await xcExactCollectionInventory(
                path: "\(path)/buildRuns",
                expectedType: "ciBuildRuns",
                context: "product build runs"
            )
            preview = XcodeCloudDeletionPreview(
                resourceType: "ciProducts",
                resourceID: productID,
                name: name,
                workflowCount: workflowIDs.count,
                buildRunCount: buildRunIDs.count,
                receipt: xcDeletionReceipt(
                    resourceType: "ciProducts",
                    resourceID: productID,
                    name: name,
                    workflowIDs: workflowIDs,
                    buildRunIDs: buildRunIDs
                )
            )
        } catch {
            return xcMutationNotAttempted(
                operation: "delete_product",
                error: error,
                identifiers: ["product_id": .string(productID)]
            )
        }

        guard xcHasAnyDeletionConfirmation(arguments, fields: xcProductDeleteConfirmationFields) else {
            return xcProductDeletionPreviewResult(preview)
        }
        guard xcProductDeletionConfirmationMatches(arguments, preview: preview) else {
            return xcDeletionConfirmationMismatch(operation: "delete_product", preview: preview)
        }

        return await xcExecuteDeletion(
            operation: "delete_product",
            path: path,
            identifiers: ["product_id": .string(productID)],
            preview: preview,
            inspection: xcResourceInspection(tool: "xcode_cloud_products_get", idField: "product_id", id: productID)
        )
    }
}

private extension XcodeCloudWorker {
    var xcWorkflowMutationFields: Set<String> {
        [
            "workflow_id", "product_id", "repository_id", "name", "description",
            "branch_start_condition", "tag_start_condition", "pull_request_start_condition",
            "scheduled_start_condition", "manual_branch_start_condition", "manual_tag_start_condition",
            "manual_pull_request_start_condition", "actions", "is_enabled", "is_locked_for_editing",
            "clean", "container_file_path", "xcode_version_id", "macos_version_id"
        ]
    }

    var xcWorkflowDeleteFields: Set<String> {
        xcWorkflowDeleteConfirmationFields.union(["workflow_id"])
    }

    var xcWorkflowDeleteConfirmationFields: Set<String> {
        [
            "confirm_permanent_deletion", "confirmation_receipt",
            "expected_workflow_name", "expected_build_run_count"
        ]
    }

    var xcProductDeleteFields: Set<String> {
        xcProductDeleteConfirmationFields.union(["product_id"])
    }

    var xcProductDeleteConfirmationFields: Set<String> {
        [
            "confirm_permanent_deletion", "confirmation_receipt", "expected_product_name",
            "expected_workflow_count", "expected_build_run_count"
        ]
    }

    func xcWorkflowMutationRequest(
        _ arguments: [String: Value],
        workflowID: String?,
        isCreate: Bool
    ) throws -> XcodeCloudWorkflowMutationRequestPlan {
        let allowed = isCreate
            ? xcWorkflowMutationFields.subtracting(["workflow_id"])
            : xcWorkflowMutationFields.subtracting(["product_id", "repository_id"])
        try xcValidateMutationKeys(arguments, allowed: allowed, context: "arguments")

        var attributes: [String: XcodeCloudMutationPresence] = [:]
        let scalarFields: [(String, String, XcodeCloudMutationScalarKind, Bool, Bool)] = [
            ("name", "name", .string, isCreate, !isCreate),
            ("description", "description", .string, isCreate, !isCreate),
            ("is_enabled", "isEnabled", .boolean, isCreate, !isCreate),
            ("is_locked_for_editing", "isLockedForEditing", .boolean, false, true),
            ("clean", "clean", .boolean, isCreate, !isCreate),
            ("container_file_path", "containerFilePath", .string, isCreate, !isCreate)
        ]
        for (toolField, appleField, kind, required, nullable) in scalarFields {
            let presence = try xcMutationScalar(
                toolField,
                from: arguments,
                kind: kind,
                required: required,
                nullable: nullable
            )
            if case .omitted = presence {
                continue
            }
            attributes[appleField] = presence
        }

        let conditions: [(String, String, XcodeCloudMutationStartConditionKind)] = [
            ("branch_start_condition", "branchStartCondition", .branch),
            ("tag_start_condition", "tagStartCondition", .tag),
            ("pull_request_start_condition", "pullRequestStartCondition", .pullRequest),
            ("scheduled_start_condition", "scheduledStartCondition", .scheduled),
            ("manual_branch_start_condition", "manualBranchStartCondition", .manualBranch),
            ("manual_tag_start_condition", "manualTagStartCondition", .manualTag),
            ("manual_pull_request_start_condition", "manualPullRequestStartCondition", .manualPullRequest)
        ]
        for (toolField, appleField, kind) in conditions {
            guard let value = arguments[toolField] else { continue }
            attributes[appleField] = try xcMutationStartCondition(value, field: toolField, kind: kind)
        }

        if let value = arguments["actions"] {
            attributes["actions"] = try xcMutationActions(value, nullable: !isCreate)
        } else if isCreate {
            throw XcodeCloudMutationArgumentError("actions is required")
        }

        var relationships: [String: XcodeCloudMutationResourceIdentifier] = [:]
        if isCreate {
            relationships["product"] = .init(
                type: "ciProducts",
                id: try xcMutationResourceID("product_id", from: arguments)
            )
            relationships["repository"] = .init(
                type: "scmRepositories",
                id: try xcMutationResourceID("repository_id", from: arguments)
            )
            relationships["xcodeVersion"] = .init(
                type: "ciXcodeVersions",
                id: try xcMutationResourceID("xcode_version_id", from: arguments)
            )
            relationships["macOsVersion"] = .init(
                type: "ciMacOsVersions",
                id: try xcMutationResourceID("macos_version_id", from: arguments)
            )
        } else {
            if arguments["xcode_version_id"] != nil {
                relationships["xcodeVersion"] = .init(
                    type: "ciXcodeVersions",
                    id: try xcMutationResourceID("xcode_version_id", from: arguments)
                )
            }
            if arguments["macos_version_id"] != nil {
                relationships["macOsVersion"] = .init(
                    type: "ciMacOsVersions",
                    id: try xcMutationResourceID("macos_version_id", from: arguments)
                )
            }
        }

        var resource: [String: JSONValue] = ["type": .string("ciWorkflows")]
        if let workflowID {
            resource["id"] = .string(workflowID)
        }
        if isCreate || !attributes.isEmpty {
            resource["attributes"] = .object(attributes.compactMapValues(\.jsonValue))
        }
        if isCreate || !relationships.isEmpty {
            resource["relationships"] = .object(relationships.mapValues { relationship in
                .object([
                    "data": .object([
                        "type": .string(relationship.type),
                        "id": .string(relationship.id)
                    ])
                ])
            })
        }
        let body = try JSONEncoder().encode(JSONValue.object(["data": .object(resource)]))
        return XcodeCloudWorkflowMutationRequestPlan(
            body: body,
            attributes: attributes,
            relationships: relationships
        )
    }
}

private extension XcodeCloudWorker {
    func xcMutationScalar(
        _ field: String,
        from arguments: [String: Value],
        kind: XcodeCloudMutationScalarKind,
        required: Bool,
        nullable: Bool
    ) throws -> XcodeCloudMutationPresence {
        guard let value = arguments[field] else {
            if required {
                throw XcodeCloudMutationArgumentError("\(field) is required")
            }
            return .omitted
        }
        if xcMutationValueIsNull(value) {
            guard nullable else {
                throw XcodeCloudMutationArgumentError("\(field) cannot be null")
            }
            return .null
        }
        switch kind {
        case .string:
            guard let string = value.stringValue else {
                throw XcodeCloudMutationArgumentError("\(field) must be a string\(nullable ? " or null" : "")")
            }
            return .value(.string(string))
        case .boolean:
            guard let boolean = value.boolValue else {
                throw XcodeCloudMutationArgumentError("\(field) must be a boolean\(nullable ? " or null" : "")")
            }
            return .value(.bool(boolean))
        }
    }

    func xcMutationActions(_ value: Value, nullable: Bool) throws -> XcodeCloudMutationPresence {
        if xcMutationValueIsNull(value) {
            guard nullable else {
                throw XcodeCloudMutationArgumentError("actions cannot be null")
            }
            return .null
        }
        guard let values = value.arrayValue else {
            throw XcodeCloudMutationArgumentError("actions must be an array\(nullable ? " or null" : "")")
        }
        let actions = try values.enumerated().map { index, action -> JSONValue in
            let field = "actions[\(index)]"
            let object = try xcMutationObject(
                action,
                field: field,
                allowed: [
                    "name", "action_type", "destination", "build_distribution_audience",
                    "test_configuration", "scheme", "platform", "is_required_to_pass"
                ]
            )
            var result: [String: JSONValue] = [:]
            try xcAppendMutationString(object["name"], field: "\(field).name", appleField: "name", to: &result)
            try xcAppendMutationEnum(
                object["action_type"],
                field: "\(field).action_type",
                appleField: "actionType",
                values: ["BUILD", "ANALYZE", "TEST", "ARCHIVE"],
                to: &result
            )
            try xcAppendMutationEnum(
                object["destination"],
                field: "\(field).destination",
                appleField: "destination",
                values: [
                    "ANY_IOS_DEVICE", "ANY_IOS_SIMULATOR", "ANY_TVOS_DEVICE", "ANY_TVOS_SIMULATOR",
                    "ANY_WATCHOS_DEVICE", "ANY_WATCHOS_SIMULATOR", "ANY_MAC", "ANY_MAC_CATALYST",
                    "ANY_VISIONOS_DEVICE", "ANY_VISIONOS_SIMULATOR"
                ],
                to: &result
            )
            try xcAppendMutationEnum(
                object["build_distribution_audience"],
                field: "\(field).build_distribution_audience",
                appleField: "buildDistributionAudience",
                values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"],
                to: &result
            )
            try xcAppendMutationString(object["scheme"], field: "\(field).scheme", appleField: "scheme", to: &result)
            try xcAppendMutationEnum(
                object["platform"],
                field: "\(field).platform",
                appleField: "platform",
                values: ["MACOS", "IOS", "TVOS", "WATCHOS", "VISIONOS"],
                to: &result
            )
            try xcAppendMutationBool(
                object["is_required_to_pass"],
                field: "\(field).is_required_to_pass",
                appleField: "isRequiredToPass",
                to: &result
            )
            if let configuration = object["test_configuration"] {
                result["testConfiguration"] = try xcMutationTestConfiguration(
                    configuration,
                    field: "\(field).test_configuration"
                )
            }
            return .object(result)
        }
        return .value(.array(actions))
    }

    func xcMutationTestConfiguration(_ value: Value, field: String) throws -> JSONValue {
        let object = try xcMutationObject(
            value,
            field: field,
            allowed: ["kind", "test_plan_name", "test_destinations"]
        )
        var result: [String: JSONValue] = [:]
        try xcAppendMutationEnum(
            object["kind"],
            field: "\(field).kind",
            appleField: "kind",
            values: ["USE_SCHEME_SETTINGS", "SPECIFIC_TEST_PLANS"],
            to: &result
        )
        try xcAppendMutationString(
            object["test_plan_name"],
            field: "\(field).test_plan_name",
            appleField: "testPlanName",
            to: &result
        )
        if let destinations = object["test_destinations"] {
            guard let values = destinations.arrayValue else {
                throw XcodeCloudMutationArgumentError("\(field).test_destinations must be an array")
            }
            result["testDestinations"] = .array(try values.enumerated().map { index, destination in
                let itemField = "\(field).test_destinations[\(index)]"
                let object = try xcMutationObject(
                    destination,
                    field: itemField,
                    allowed: [
                        "device_type_name", "device_type_identifier", "runtime_name",
                        "runtime_identifier", "kind"
                    ]
                )
                var item: [String: JSONValue] = [:]
                try xcAppendMutationString(object["device_type_name"], field: "\(itemField).device_type_name", appleField: "deviceTypeName", to: &item)
                try xcAppendMutationString(object["device_type_identifier"], field: "\(itemField).device_type_identifier", appleField: "deviceTypeIdentifier", to: &item)
                try xcAppendMutationString(object["runtime_name"], field: "\(itemField).runtime_name", appleField: "runtimeName", to: &item)
                try xcAppendMutationString(object["runtime_identifier"], field: "\(itemField).runtime_identifier", appleField: "runtimeIdentifier", to: &item)
                try xcAppendMutationEnum(
                    object["kind"],
                    field: "\(itemField).kind",
                    appleField: "kind",
                    values: ["SIMULATOR", "MAC"],
                    to: &item
                )
                return .object(item)
            })
        }
        return .object(result)
    }

    func xcMutationStartCondition(
        _ value: Value,
        field: String,
        kind: XcodeCloudMutationStartConditionKind
    ) throws -> XcodeCloudMutationPresence {
        if xcMutationValueIsNull(value) {
            return .null
        }
        let allowed: Set<String>
        switch kind {
        case .branch, .tag:
            allowed = ["source", "files_and_folders_rule", "auto_cancel"]
        case .pullRequest:
            allowed = ["source", "destination", "files_and_folders_rule", "auto_cancel"]
        case .scheduled:
            allowed = ["source", "schedule"]
        case .manualBranch, .manualTag:
            allowed = ["source"]
        case .manualPullRequest:
            allowed = ["source", "destination"]
        }
        let object = try xcMutationObject(value, field: field, allowed: allowed)
        var result: [String: JSONValue] = [:]
        if let source = object["source"] {
            result["source"] = try xcMutationPatternGroup(source, field: "\(field).source")
        }
        if let destination = object["destination"] {
            result["destination"] = try xcMutationPatternGroup(destination, field: "\(field).destination")
        }
        if let rule = object["files_and_folders_rule"] {
            result["filesAndFoldersRule"] = try xcMutationFilesAndFoldersRule(
                rule,
                field: "\(field).files_and_folders_rule"
            )
        }
        try xcAppendMutationBool(object["auto_cancel"], field: "\(field).auto_cancel", appleField: "autoCancel", to: &result)
        if let schedule = object["schedule"] {
            result["schedule"] = try xcMutationSchedule(schedule, field: "\(field).schedule")
        }
        return .value(.object(result))
    }

    func xcMutationPatternGroup(_ value: Value, field: String) throws -> JSONValue {
        let object = try xcMutationObject(value, field: field, allowed: ["is_all_match", "patterns"])
        var result: [String: JSONValue] = [:]
        try xcAppendMutationBool(object["is_all_match"], field: "\(field).is_all_match", appleField: "isAllMatch", to: &result)
        if let patterns = object["patterns"] {
            guard let values = patterns.arrayValue else {
                throw XcodeCloudMutationArgumentError("\(field).patterns must be an array")
            }
            result["patterns"] = .array(try values.enumerated().map { index, pattern in
                let itemField = "\(field).patterns[\(index)]"
                let object = try xcMutationObject(pattern, field: itemField, allowed: ["pattern", "is_prefix"])
                var item: [String: JSONValue] = [:]
                try xcAppendMutationString(object["pattern"], field: "\(itemField).pattern", appleField: "pattern", to: &item)
                try xcAppendMutationBool(object["is_prefix"], field: "\(itemField).is_prefix", appleField: "isPrefix", to: &item)
                return .object(item)
            })
        }
        return .object(result)
    }

    func xcMutationFilesAndFoldersRule(_ value: Value, field: String) throws -> JSONValue {
        let object = try xcMutationObject(value, field: field, allowed: ["mode", "matchers"])
        var result: [String: JSONValue] = [:]
        try xcAppendMutationEnum(
            object["mode"],
            field: "\(field).mode",
            appleField: "mode",
            values: ["START_IF_ANY_FILE_MATCHES", "DO_NOT_START_IF_ALL_FILES_MATCH"],
            to: &result
        )
        if let matchers = object["matchers"] {
            guard let values = matchers.arrayValue else {
                throw XcodeCloudMutationArgumentError("\(field).matchers must be an array")
            }
            result["matchers"] = .array(try values.enumerated().map { index, matcher in
                let itemField = "\(field).matchers[\(index)]"
                let object = try xcMutationObject(
                    matcher,
                    field: itemField,
                    allowed: ["directory", "file_extension", "file_name"]
                )
                var item: [String: JSONValue] = [:]
                try xcAppendMutationString(object["directory"], field: "\(itemField).directory", appleField: "directory", to: &item)
                try xcAppendMutationString(object["file_extension"], field: "\(itemField).file_extension", appleField: "fileExtension", to: &item)
                try xcAppendMutationString(object["file_name"], field: "\(itemField).file_name", appleField: "fileName", to: &item)
                return .object(item)
            })
        }
        return .object(result)
    }

    func xcMutationSchedule(_ value: Value, field: String) throws -> JSONValue {
        let object = try xcMutationObject(
            value,
            field: field,
            allowed: ["frequency", "days", "hour", "minute", "timezone"]
        )
        var result: [String: JSONValue] = [:]
        try xcAppendMutationEnum(
            object["frequency"],
            field: "\(field).frequency",
            appleField: "frequency",
            values: ["WEEKLY", "DAILY", "HOURLY"],
            to: &result
        )
        try xcAppendMutationString(object["timezone"], field: "\(field).timezone", appleField: "timezone", to: &result)
        for toolField in ["hour", "minute"] {
            guard let value = object[toolField] else { continue }
            guard let integer = value.intValue else {
                throw XcodeCloudMutationArgumentError("\(field).\(toolField) must be an integer")
            }
            result[toolField] = .int(integer)
        }
        if let days = object["days"] {
            guard let values = days.arrayValue else {
                throw XcodeCloudMutationArgumentError("\(field).days must be an array")
            }
            let allowed = Set([
                "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
                "THURSDAY", "FRIDAY", "SATURDAY"
            ])
            result["days"] = .array(try values.enumerated().map { index, day in
                guard let string = day.stringValue, allowed.contains(string) else {
                    throw XcodeCloudMutationArgumentError("\(field).days[\(index)] is not a supported day")
                }
                return .string(string)
            })
        }
        return .object(result)
    }

    func xcMutationObject(_ value: Value, field: String, allowed: Set<String>) throws -> [String: Value] {
        guard let object = value.objectValue else {
            throw XcodeCloudMutationArgumentError("\(field) must be an object")
        }
        try xcValidateMutationKeys(object, allowed: allowed, context: field)
        return object
    }

    func xcAppendMutationString(
        _ value: Value?,
        field: String,
        appleField: String,
        to result: inout [String: JSONValue]
    ) throws {
        guard let value else { return }
        guard let string = value.stringValue else {
            throw XcodeCloudMutationArgumentError("\(field) must be a string")
        }
        result[appleField] = .string(string)
    }

    func xcAppendMutationBool(
        _ value: Value?,
        field: String,
        appleField: String,
        to result: inout [String: JSONValue]
    ) throws {
        guard let value else { return }
        guard let boolean = value.boolValue else {
            throw XcodeCloudMutationArgumentError("\(field) must be a boolean")
        }
        result[appleField] = .bool(boolean)
    }

    func xcAppendMutationEnum(
        _ value: Value?,
        field: String,
        appleField: String,
        values: Set<String>,
        to result: inout [String: JSONValue]
    ) throws {
        guard let value else { return }
        guard let string = value.stringValue, values.contains(string) else {
            throw XcodeCloudMutationArgumentError("\(field) is not a supported Apple API 4.4.1 value")
        }
        result[appleField] = .string(string)
    }

    func xcValidateMutationKeys(_ object: [String: Value], allowed: Set<String>, context: String) throws {
        if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw XcodeCloudMutationArgumentError("\(context) contains unsupported field '\(key)'")
        }
    }

    func xcMutationResourceID(_ field: String, from arguments: [String: Value]) throws -> String {
        guard let id = arguments[field]?.stringValue else {
            throw XcodeCloudMutationArgumentError("\(field) is required and must be a string")
        }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == id else {
            throw XcodeCloudMutationArgumentError("\(field) must be a non-empty canonical ID")
        }
        let encoded = try ASCPathSegment.encode(id, field: field)
        guard encoded == id else {
            throw XcodeCloudMutationArgumentError("\(field) must already be a canonical URL-path ID")
        }
        return id
    }

    func xcMutationValueIsNull(_ value: Value) -> Bool {
        if case .null = value {
            return true
        }
        return false
    }
}

private extension XcodeCloudWorker {
    func xcValidateMutationResponse(
        _ response: XcodeCloudMutationResourceDocument,
        expectedID: String?,
        expectedPath: String?,
        request: XcodeCloudWorkflowMutationRequestPlan,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: response.data.type,
            id: response.data.id,
            expectedType: "ciWorkflows",
            expectedID: expectedID,
            context: "Apple \(context) response"
        )
        let path: String
        if let expectedPath {
            path = expectedPath
        } else {
            path = "/v1/ciWorkflows/\(try ASCPathSegment.encode(response.data.id))"
        }
        try xcValidateDocumentSelf(response.links.`self`, expectedPath: path, context: context)
        if let resourceSelf = response.data.links?.`self` {
            try xcValidateDocumentSelf(resourceSelf, expectedPath: path, context: "\(context) resource")
        }
        try xcValidateWorkflowResponseAttributes(response.data.attributes, context: context)
        try xcValidateWorkflowResponseRelationships(
            response.data.relationships,
            workflowID: response.data.id,
            context: context
        )
        try xcValidateWorkflowMutationIncluded(response.included, context: context)

        if !request.attributes.isEmpty {
            guard let responseAttributes = response.data.attributes else {
                throw ASCError.parsing("Apple \(context) response omitted every requested workflow attribute")
            }
            for (field, presence) in request.attributes {
                guard let expected = presence.jsonValue,
                      let actual = responseAttributes[field],
                      xcMutationJSONEqual(expected, actual) else {
                    throw ASCError.parsing(
                        "Apple \(context) response did not exactly verify requested attribute '\(field)'"
                    )
                }
            }
        }
        for (field, expected) in request.relationships {
            guard let raw = response.data.relationships?[field] else {
                throw ASCError.parsing(
                    "Apple \(context) response omitted requested relationship '\(field)'"
                )
            }
            guard let actual = try xcMutationRelationshipIdentifier(
                raw,
                field: field,
                expectedType: expected.type,
                context: context,
                requireData: true
            ), actual.type == expected.type, actual.id == expected.id else {
                throw ASCError.parsing(
                    "Apple \(context) response did not exactly verify requested relationship '\(field)'"
                )
            }
        }
    }

    func xcValidateWorkflowResponseAttributes(
        _ attributes: [String: JSONValue]?,
        context: String
    ) throws {
        guard let attributes else { return }
        let stringFields = ["name", "description", "containerFilePath", "lastModifiedDate"]
        for field in stringFields {
            guard let value = attributes[field] else { continue }
            guard case .string = value else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
            }
        }
        let booleanFields = ["isEnabled", "isLockedForEditing", "clean"]
        for field in booleanFields {
            guard let value = attributes[field] else { continue }
            guard case .bool = value else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
            }
        }
        let conditionFields: [(String, XcodeCloudMutationStartConditionKind)] = [
            ("branchStartCondition", .branch),
            ("tagStartCondition", .tag),
            ("pullRequestStartCondition", .pullRequest),
            ("scheduledStartCondition", .scheduled),
            ("manualBranchStartCondition", .manualBranch),
            ("manualTagStartCondition", .manualTag),
            ("manualPullRequestStartCondition", .manualPullRequest)
        ]
        for (field, kind) in conditionFields {
            guard let value = attributes[field] else { continue }
            try xcValidateWorkflowResponseCondition(value, field: field, kind: kind, context: context)
        }
        if let actions = attributes["actions"] {
            try xcValidateWorkflowResponseActions(actions, context: context)
        }
    }

    func xcValidateWorkflowResponseCondition(
        _ value: JSONValue,
        field: String,
        kind: XcodeCloudMutationStartConditionKind,
        context: String
    ) throws {
        guard case .object(let condition) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
        switch kind {
        case .branch, .tag:
            if let source = condition["source"] {
                try xcValidateWorkflowResponsePatternGroup(source, field: "\(field).source", context: context)
            }
            if let rule = condition["filesAndFoldersRule"] {
                try xcValidateWorkflowResponseFilesRule(
                    rule,
                    field: "\(field).filesAndFoldersRule",
                    context: context
                )
            }
            try xcValidateWorkflowResponseBool(
                condition["autoCancel"],
                field: "\(field).autoCancel",
                context: context
            )
        case .pullRequest:
            if let source = condition["source"] {
                try xcValidateWorkflowResponsePatternGroup(source, field: "\(field).source", context: context)
            }
            if let destination = condition["destination"] {
                try xcValidateWorkflowResponsePatternGroup(
                    destination,
                    field: "\(field).destination",
                    context: context
                )
            }
            if let rule = condition["filesAndFoldersRule"] {
                try xcValidateWorkflowResponseFilesRule(
                    rule,
                    field: "\(field).filesAndFoldersRule",
                    context: context
                )
            }
            try xcValidateWorkflowResponseBool(
                condition["autoCancel"],
                field: "\(field).autoCancel",
                context: context
            )
        case .scheduled:
            if let source = condition["source"] {
                try xcValidateWorkflowResponsePatternGroup(source, field: "\(field).source", context: context)
            }
            if let schedule = condition["schedule"] {
                try xcValidateWorkflowResponseSchedule(
                    schedule,
                    field: "\(field).schedule",
                    context: context
                )
            }
        case .manualBranch, .manualTag:
            if let source = condition["source"] {
                try xcValidateWorkflowResponsePatternGroup(source, field: "\(field).source", context: context)
            }
        case .manualPullRequest:
            if let source = condition["source"] {
                try xcValidateWorkflowResponsePatternGroup(source, field: "\(field).source", context: context)
            }
            if let destination = condition["destination"] {
                try xcValidateWorkflowResponsePatternGroup(
                    destination,
                    field: "\(field).destination",
                    context: context
                )
            }
        }
    }

    func xcValidateWorkflowResponsePatternGroup(
        _ value: JSONValue,
        field: String,
        context: String
    ) throws {
        guard case .object(let group) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
        try xcValidateWorkflowResponseBool(group["isAllMatch"], field: "\(field).isAllMatch", context: context)
        if let patterns = group["patterns"] {
            guard case .array(let items) = patterns else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field).patterns'")
            }
            for (index, item) in items.enumerated() {
                let itemField = "\(field).patterns[\(index)]"
                guard case .object(let pattern) = item else {
                    throw ASCError.parsing("Apple \(context) response contains malformed '\(itemField)'")
                }
                try xcValidateWorkflowResponseString(
                    pattern["pattern"],
                    field: "\(itemField).pattern",
                    context: context
                )
                try xcValidateWorkflowResponseBool(
                    pattern["isPrefix"],
                    field: "\(itemField).isPrefix",
                    context: context
                )
            }
        }
    }

    func xcValidateWorkflowResponseFilesRule(
        _ value: JSONValue,
        field: String,
        context: String
    ) throws {
        guard case .object(let rule) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
        try xcValidateWorkflowResponseEnum(
            rule["mode"],
            field: "\(field).mode",
            values: ["START_IF_ANY_FILE_MATCHES", "DO_NOT_START_IF_ALL_FILES_MATCH"],
            context: context
        )
        if let matchers = rule["matchers"] {
            guard case .array(let items) = matchers else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field).matchers'")
            }
            for (index, item) in items.enumerated() {
                let itemField = "\(field).matchers[\(index)]"
                guard case .object(let matcher) = item else {
                    throw ASCError.parsing("Apple \(context) response contains malformed '\(itemField)'")
                }
                for name in ["directory", "fileExtension", "fileName"] {
                    try xcValidateWorkflowResponseString(
                        matcher[name],
                        field: "\(itemField).\(name)",
                        context: context
                    )
                }
            }
        }
    }

    func xcValidateWorkflowResponseSchedule(
        _ value: JSONValue,
        field: String,
        context: String
    ) throws {
        guard case .object(let schedule) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
        try xcValidateWorkflowResponseEnum(
            schedule["frequency"],
            field: "\(field).frequency",
            values: ["WEEKLY", "DAILY", "HOURLY"],
            context: context
        )
        if let days = schedule["days"] {
            guard case .array(let items) = days else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field).days'")
            }
            let allowedDays: Set<String> = [
                "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
                "THURSDAY", "FRIDAY", "SATURDAY"
            ]
            for (index, item) in items.enumerated() {
                guard case .string(let day) = item, allowedDays.contains(day) else {
                    throw ASCError.parsing(
                        "Apple \(context) response contains malformed '\(field).days[\(index)]'"
                    )
                }
            }
        }
        for name in ["hour", "minute"] {
            guard let value = schedule[name] else { continue }
            guard case .int = value else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field).\(name)'")
            }
        }
        try xcValidateWorkflowResponseString(schedule["timezone"], field: "\(field).timezone", context: context)
    }

    func xcValidateWorkflowResponseActions(_ value: JSONValue, context: String) throws {
        guard case .array(let actions) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed 'actions'")
        }
        for (index, value) in actions.enumerated() {
            let field = "actions[\(index)]"
            guard case .object(let action) = value else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
            }
            try xcValidateWorkflowResponseString(action["name"], field: "\(field).name", context: context)
            try xcValidateWorkflowResponseEnum(
                action["actionType"],
                field: "\(field).actionType",
                values: ["BUILD", "ANALYZE", "TEST", "ARCHIVE"],
                context: context
            )
            try xcValidateWorkflowResponseEnum(
                action["destination"],
                field: "\(field).destination",
                values: [
                    "ANY_IOS_DEVICE", "ANY_IOS_SIMULATOR", "ANY_TVOS_DEVICE", "ANY_TVOS_SIMULATOR",
                    "ANY_WATCHOS_DEVICE", "ANY_WATCHOS_SIMULATOR", "ANY_MAC", "ANY_MAC_CATALYST",
                    "ANY_VISIONOS_DEVICE", "ANY_VISIONOS_SIMULATOR"
                ],
                context: context
            )
            try xcValidateWorkflowResponseEnum(
                action["buildDistributionAudience"],
                field: "\(field).buildDistributionAudience",
                values: ["INTERNAL_ONLY", "APP_STORE_ELIGIBLE"],
                context: context
            )
            if let configuration = action["testConfiguration"] {
                try xcValidateWorkflowResponseTestConfiguration(
                    configuration,
                    field: "\(field).testConfiguration",
                    context: context
                )
            }
            try xcValidateWorkflowResponseString(action["scheme"], field: "\(field).scheme", context: context)
            try xcValidateWorkflowResponseEnum(
                action["platform"],
                field: "\(field).platform",
                values: ["MACOS", "IOS", "TVOS", "WATCHOS", "VISIONOS"],
                context: context
            )
            try xcValidateWorkflowResponseBool(
                action["isRequiredToPass"],
                field: "\(field).isRequiredToPass",
                context: context
            )
        }
    }

    func xcValidateWorkflowResponseTestConfiguration(
        _ value: JSONValue,
        field: String,
        context: String
    ) throws {
        guard case .object(let configuration) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
        try xcValidateWorkflowResponseEnum(
            configuration["kind"],
            field: "\(field).kind",
            values: ["USE_SCHEME_SETTINGS", "SPECIFIC_TEST_PLANS"],
            context: context
        )
        try xcValidateWorkflowResponseString(
            configuration["testPlanName"],
            field: "\(field).testPlanName",
            context: context
        )
        if let destinations = configuration["testDestinations"] {
            guard case .array(let items) = destinations else {
                throw ASCError.parsing("Apple \(context) response contains malformed '\(field).testDestinations'")
            }
            for (index, item) in items.enumerated() {
                let itemField = "\(field).testDestinations[\(index)]"
                guard case .object(let destination) = item else {
                    throw ASCError.parsing("Apple \(context) response contains malformed '\(itemField)'")
                }
                for name in ["deviceTypeName", "deviceTypeIdentifier", "runtimeName", "runtimeIdentifier"] {
                    try xcValidateWorkflowResponseString(
                        destination[name],
                        field: "\(itemField).\(name)",
                        context: context
                    )
                }
                try xcValidateWorkflowResponseEnum(
                    destination["kind"],
                    field: "\(itemField).kind",
                    values: ["SIMULATOR", "MAC"],
                    context: context
                )
            }
        }
    }

    func xcValidateWorkflowResponseString(
        _ value: JSONValue?,
        field: String,
        context: String
    ) throws {
        guard let value else { return }
        guard case .string = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
    }

    func xcValidateWorkflowResponseBool(
        _ value: JSONValue?,
        field: String,
        context: String
    ) throws {
        guard let value else { return }
        guard case .bool = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
    }

    func xcValidateWorkflowResponseEnum(
        _ value: JSONValue?,
        field: String,
        values: Set<String>,
        context: String
    ) throws {
        guard let value else { return }
        guard case .string(let rawValue) = value, values.contains(rawValue) else {
            throw ASCError.parsing("Apple \(context) response contains malformed '\(field)'")
        }
    }

    func xcValidateWorkflowResponseRelationships(
        _ relationships: [String: JSONValue]?,
        workflowID: String,
        context: String
    ) throws {
        guard let relationships else { return }
        let expectedTypes = [
            "product": "ciProducts",
            "repository": "scmRepositories",
            "xcodeVersion": "ciXcodeVersions",
            "macOsVersion": "ciMacOsVersions"
        ]
        for (field, expectedType) in expectedTypes {
            guard let value = relationships[field] else { continue }
            guard case .object(let relationship) = value else {
                throw ASCError.parsing("Apple \(context) response contains malformed relationship '\(field)'")
            }
            let allowedKeys: Set<String> = field == "repository" ? ["data", "links"] : ["data"]
            guard Set(relationship.keys).isSubset(of: allowedKeys) else {
                throw ASCError.parsing("Apple \(context) response contains unsupported members in relationship '\(field)'")
            }
            _ = try xcMutationRelationshipIdentifier(
                value,
                field: field,
                expectedType: expectedType,
                context: context,
                requireData: false
            )
            if field == "repository", let links = relationship["links"] {
                try xcValidateWorkflowRelationshipLinks(
                    links,
                    relationship: field,
                    workflowID: workflowID,
                    context: context
                )
            }
        }
        if let buildRuns = relationships["buildRuns"] {
            guard case .object(let relationship) = buildRuns,
                  Set(relationship.keys).isSubset(of: ["links"]) else {
                throw ASCError.parsing("Apple \(context) response contains malformed relationship 'buildRuns'")
            }
            if let links = relationship["links"] {
                try xcValidateWorkflowRelationshipLinks(
                    links,
                    relationship: "buildRuns",
                    workflowID: workflowID,
                    context: context
                )
            }
        }
    }

    func xcValidateWorkflowRelationshipLinks(
        _ value: JSONValue,
        relationship: String,
        workflowID: String,
        context: String
    ) throws {
        guard case .object(let links) = value,
              Set(links.keys).isSubset(of: ["self", "related"]) else {
            throw ASCError.parsing(
                "Apple \(context) response contains malformed links for relationship '\(relationship)'"
            )
        }
        let relationshipPath = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))/relationships/\(try ASCPathSegment.encode(relationship))"
        let relatedPath = "/v1/ciWorkflows/\(try ASCPathSegment.encode(workflowID))/\(try ASCPathSegment.encode(relationship))"
        for (name, path) in [("self", relationshipPath), ("related", relatedPath)] {
            guard let value = links[name] else { continue }
            guard case .string(let link) = value else {
                throw ASCError.parsing(
                    "Apple \(context) response contains malformed \(name) link for relationship '\(relationship)'"
                )
            }
            try xcValidateDocumentSelf(
                link,
                expectedPath: path,
                context: "\(context) relationship '\(relationship)' \(name)"
            )
        }
    }

    func xcValidateWorkflowMutationIncluded(
        _ included: [JSONValue]?,
        context: String
    ) throws {
        guard let included else { return }
        var identities: [String: Set<String>] = [:]
        for value in included {
            guard case .object(let object) = value,
                  case .string(let type)? = object["type"],
                  case .string(let id)? = object["id"] else {
                throw ASCError.parsing("Apple \(context) response contains a malformed included resource")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: type,
                id: id,
                expectedType: type,
                context: "Apple \(context) included resource"
            )
            guard identities[type, default: []].insert(id).inserted else {
                throw ASCError.parsing("Apple \(context) response contains a duplicate included resource")
            }

            let data = try JSONEncoder().encode(value)
            switch type {
            case "ciMacOsVersions":
                try xcValidateWorkflowMutationIncludedResource(
                    data,
                    as: ASCCIMacOSVersion.self,
                    expectedType: type,
                    context: context
                )
            case "ciProducts":
                try xcValidateWorkflowMutationIncludedResource(
                    data,
                    as: ASCCIProduct.self,
                    expectedType: type,
                    context: context
                )
            case "ciXcodeVersions":
                try xcValidateWorkflowMutationIncludedResource(
                    data,
                    as: ASCCIXcodeVersion.self,
                    expectedType: type,
                    context: context
                )
            case "scmRepositories":
                try xcValidateWorkflowMutationIncludedResource(
                    data,
                    as: ASCScmRepository.self,
                    expectedType: type,
                    context: context
                )
            default:
                throw ASCError.parsing("Apple \(context) response contains an unsupported included resource type")
            }
            try xcValidateWorkflowMutationIncludedKnownFields(
                object,
                type: type,
                context: context
            )
        }
    }

    func xcValidateWorkflowMutationIncludedResource<Resource: ASCXcodeCloudResourceContract>(
        _ data: Data,
        as resourceType: Resource.Type,
        expectedType: String,
        context: String
    ) throws {
        let resource = try JSONDecoder().decode(resourceType, from: data)
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: resource.type,
            id: resource.id,
            expectedType: expectedType,
            context: "Apple \(context) included resource"
        )
        try resource.validateXcodeCloudRelationships()
        try validateXcodeCloudRelationshipLinks(for: resource)
        try validateXcodeCloudResourceSelf(
            resource.links?.`self`,
            type: resource.type,
            id: resource.id
        )
    }

    func xcValidateWorkflowMutationIncludedKnownFields(
        _ object: [String: JSONValue],
        type: String,
        context: String
    ) throws {
        if let links = object["links"] {
            guard case .object(let linksObject) = links else {
                throw ASCError.parsing("Apple \(context) included resource contains malformed links")
            }
            try xcValidateWorkflowResponseString(
                linksObject["self"],
                field: "included.links.self",
                context: context
            )
        }

        let attributes: [String: JSONValue]?
        if let value = object["attributes"] {
            guard case .object(let decoded) = value else {
                throw ASCError.parsing("Apple \(context) included resource contains malformed attributes")
            }
            attributes = decoded
        } else {
            attributes = nil
        }
        if let attributes {
            switch type {
            case "ciMacOsVersions":
                try xcValidateIncludedStringFields(
                    ["version", "name"],
                    in: attributes,
                    type: type,
                    context: context
                )
            case "ciProducts":
                try xcValidateIncludedStringFields(
                    ["name", "createdDate"],
                    in: attributes,
                    type: type,
                    context: context
                )
                try xcValidateWorkflowResponseEnum(
                    attributes["productType"],
                    field: "included.\(type).productType",
                    values: ["APP", "FRAMEWORK"],
                    context: context
                )
            case "ciXcodeVersions":
                try xcValidateIncludedStringFields(
                    ["version", "name"],
                    in: attributes,
                    type: type,
                    context: context
                )
                try xcValidateIncludedTestDestinations(attributes["testDestinations"], context: context)
            case "scmRepositories":
                try xcValidateIncludedStringFields(
                    ["lastAccessedDate", "httpCloneUrl", "sshCloneUrl", "ownerName", "repositoryName"],
                    in: attributes,
                    type: type,
                    context: context
                )
            default:
                break
            }
        }

        let relationships: [String: JSONValue]?
        if let value = object["relationships"] {
            guard case .object(let decoded) = value else {
                throw ASCError.parsing("Apple \(context) included resource contains malformed relationships")
            }
            relationships = decoded
        } else {
            relationships = nil
        }
        guard let relationships else { return }
        switch type {
        case "ciMacOsVersions":
            try xcValidateIncludedToManyRelationship(
                relationships["xcodeVersions"],
                expectedType: "ciXcodeVersions",
                context: context
            )
        case "ciProducts":
            try xcValidateIncludedToOneRelationship(
                relationships["app"],
                expectedType: "apps",
                allowsLinks: true,
                context: context
            )
            try xcValidateIncludedToOneRelationship(
                relationships["bundleId"],
                expectedType: "bundleIds",
                allowsLinks: false,
                context: context
            )
            try xcValidateIncludedLinksOnlyRelationship(relationships["workflows"], context: context)
            try xcValidateIncludedToManyRelationship(
                relationships["primaryRepositories"],
                expectedType: "scmRepositories",
                context: context
            )
            try xcValidateIncludedLinksOnlyRelationship(
                relationships["additionalRepositories"],
                context: context
            )
            try xcValidateIncludedLinksOnlyRelationship(relationships["buildRuns"], context: context)
        case "ciXcodeVersions":
            try xcValidateIncludedToManyRelationship(
                relationships["macOsVersions"],
                expectedType: "ciMacOsVersions",
                context: context
            )
        case "scmRepositories":
            try xcValidateIncludedToOneRelationship(
                relationships["scmProvider"],
                expectedType: "scmProviders",
                allowsLinks: false,
                context: context
            )
            try xcValidateIncludedToOneRelationship(
                relationships["defaultBranch"],
                expectedType: "scmGitReferences",
                allowsLinks: false,
                context: context
            )
            try xcValidateIncludedLinksOnlyRelationship(relationships["gitReferences"], context: context)
            try xcValidateIncludedLinksOnlyRelationship(relationships["pullRequests"], context: context)
        default:
            break
        }
    }

    func xcValidateIncludedStringFields(
        _ fields: [String],
        in attributes: [String: JSONValue],
        type: String,
        context: String
    ) throws {
        for field in fields {
            try xcValidateWorkflowResponseString(
                attributes[field],
                field: "included.\(type).\(field)",
                context: context
            )
        }
    }

    func xcValidateIncludedTestDestinations(_ value: JSONValue?, context: String) throws {
        guard let value else { return }
        guard case .array(let destinations) = value else {
            throw ASCError.parsing("Apple \(context) included Xcode version contains malformed testDestinations")
        }
        for (index, value) in destinations.enumerated() {
            guard case .object(let destination) = value else {
                throw ASCError.parsing(
                    "Apple \(context) included Xcode version contains malformed testDestinations[\(index)]"
                )
            }
            for field in ["deviceTypeName", "deviceTypeIdentifier"] {
                try xcValidateWorkflowResponseString(
                    destination[field],
                    field: "included.ciXcodeVersions.testDestinations[\(index)].\(field)",
                    context: context
                )
            }
            try xcValidateWorkflowResponseEnum(
                destination["kind"],
                field: "included.ciXcodeVersions.testDestinations[\(index)].kind",
                values: ["SIMULATOR", "MAC"],
                context: context
            )
            if let runtimes = destination["availableRuntimes"] {
                guard case .array(let values) = runtimes else {
                    throw ASCError.parsing(
                        "Apple \(context) included Xcode version contains malformed availableRuntimes"
                    )
                }
                for (runtimeIndex, value) in values.enumerated() {
                    guard case .object(let runtime) = value else {
                        throw ASCError.parsing(
                            "Apple \(context) included Xcode version contains malformed availableRuntimes[\(runtimeIndex)]"
                        )
                    }
                    for field in ["runtimeName", "runtimeIdentifier"] {
                        try xcValidateWorkflowResponseString(
                            runtime[field],
                            field: "included.ciXcodeVersions.availableRuntimes[\(runtimeIndex)].\(field)",
                            context: context
                        )
                    }
                }
            }
        }
    }

    func xcValidateIncludedToOneRelationship(
        _ value: JSONValue?,
        expectedType: String,
        allowsLinks: Bool,
        context: String
    ) throws {
        guard let value else { return }
        guard case .object(let relationship) = value else {
            throw ASCError.parsing("Apple \(context) included resource contains a malformed relationship")
        }
        if let links = relationship["links"] {
            guard allowsLinks else {
                throw ASCError.parsing("Apple \(context) included resource relationship contains unsupported links")
            }
            try xcValidateIncludedRelationshipLinks(links, context: context)
        }
        if relationship["meta"] != nil {
            throw ASCError.parsing("Apple \(context) included resource relationship contains unsupported meta")
        }
        if let data = relationship["data"] {
            _ = try xcValidateIncludedIdentifier(data, expectedType: expectedType, context: context)
        }
    }

    func xcValidateIncludedToManyRelationship(
        _ value: JSONValue?,
        expectedType: String,
        context: String
    ) throws {
        guard let value else { return }
        guard case .object(let relationship) = value else {
            throw ASCError.parsing("Apple \(context) included resource contains a malformed relationship")
        }
        if let links = relationship["links"] {
            try xcValidateIncludedRelationshipLinks(links, context: context)
        }
        var count: Int?
        if let data = relationship["data"] {
            guard case .array(let identifiers) = data else {
                throw ASCError.parsing("Apple \(context) included resource relationship contains malformed data")
            }
            count = identifiers.count
            var identities: Set<String> = []
            for identifier in identifiers {
                let identity = try xcValidateIncludedIdentifier(
                    identifier,
                    expectedType: expectedType,
                    context: context
                )
                guard identities.insert(identity).inserted else {
                    throw ASCError.parsing(
                        "Apple \(context) included resource relationship contains a duplicate identifier"
                    )
                }
            }
        }
        if let meta = relationship["meta"] {
            try xcValidateIncludedPaging(meta, count: count, context: context)
        }
    }

    func xcValidateIncludedLinksOnlyRelationship(
        _ value: JSONValue?,
        context: String
    ) throws {
        guard let value else { return }
        guard case .object(let relationship) = value else {
            throw ASCError.parsing("Apple \(context) included resource contains a malformed relationship")
        }
        guard relationship["data"] == nil, relationship["meta"] == nil else {
            throw ASCError.parsing("Apple \(context) included links-only relationship contains unsupported data")
        }
        if let links = relationship["links"] {
            try xcValidateIncludedRelationshipLinks(links, context: context)
        }
    }

    func xcValidateIncludedIdentifier(
        _ value: JSONValue,
        expectedType: String,
        context: String
    ) throws -> String {
        guard case .object(let identifier) = value,
              case .string(let type)? = identifier["type"],
              case .string(let id)? = identifier["id"] else {
            throw ASCError.parsing("Apple \(context) included resource contains a malformed relationship identifier")
        }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            context: "Apple \(context) included relationship"
        )
        return "\(type):\(id)"
    }

    func xcValidateIncludedRelationshipLinks(_ value: JSONValue, context: String) throws {
        guard case .object(let links) = value else {
            throw ASCError.parsing("Apple \(context) included resource contains malformed relationship links")
        }
        for name in ["self", "related"] {
            guard let value = links[name] else { continue }
            guard case .string(let link) = value,
                  xcIsValidURIReference(link) else {
                throw ASCError.parsing("Apple \(context) included resource contains a malformed \(name) link")
            }
        }
    }

    func xcValidateIncludedPaging(
        _ value: JSONValue,
        count: Int?,
        context: String
    ) throws {
        guard case .object(let meta) = value,
              case .object(let paging)? = meta["paging"],
              case .int(let limit)? = paging["limit"],
              limit > 0,
              count.map({ $0 <= limit }) ?? true else {
            throw ASCError.parsing("Apple \(context) included relationship contains malformed paging metadata")
        }
        if let totalValue = paging["total"] {
            guard case .int(let total) = totalValue,
                  total >= 0,
                  count.map({ total >= $0 }) ?? true else {
                throw ASCError.parsing("Apple \(context) included relationship contains invalid paging total")
            }
        }
        if let cursor = paging["nextCursor"] {
            guard case .string(let value) = cursor,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ASCError.parsing("Apple \(context) included relationship contains invalid paging cursor")
            }
        }
    }

    func xcIsValidURIReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed == value
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && URLComponents(string: value) != nil
    }

    func xcMutationRelationshipIdentifier(
        _ value: JSONValue,
        field: String,
        expectedType: String,
        context: String,
        requireData: Bool
    ) throws -> XcodeCloudMutationResourceIdentifier? {
        guard case .object(let relationship) = value else {
            throw ASCError.parsing("Apple \(context) response contains malformed relationship '\(field)'")
        }
        guard let rawData = relationship["data"] else {
            if requireData {
                throw ASCError.parsing("Apple \(context) response omitted data for relationship '\(field)'")
            }
            return nil
        }
        guard case .object(let data) = rawData,
              case .string(let type)? = data["type"],
              case .string(let id)? = data["id"],
              Set(data.keys) == ["type", "id"] else {
            throw ASCError.parsing("Apple \(context) response contains malformed relationship '\(field)'")
        }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            context: "Apple \(context) relationship '\(field)'"
        )
        return .init(type: type, id: id)
    }

    func xcValidateDocumentSelf(_ link: String, expectedPath: String, context: String) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                link,
                scope: PaginationScope(
                    path: expectedPath,
                    allowedParameters: Set<String>()
                )
            )
        } catch {
            throw ASCError.parsing("Apple \(context) response contains an invalid links.self")
        }
    }

    func xcMutationJSONEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let lhs), .string(let rhs)):
            lhs == rhs
        case (.int(let lhs), .int(let rhs)):
            lhs == rhs
        case (.double(let lhs), .double(let rhs)):
            lhs == rhs
        case (.int(let lhs), .double(let rhs)):
            Double(lhs) == rhs
        case (.double(let lhs), .int(let rhs)):
            lhs == Double(rhs)
        case (.bool(let lhs), .bool(let rhs)):
            lhs == rhs
        case (.null, .null):
            true
        case (.array(let lhs), .array(let rhs)):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in
                xcMutationJSONEqual(pair.0, pair.1)
            }
        case (.object(let lhs), .object(let rhs)):
            lhs.count == rhs.count && lhs.allSatisfy { key, value in
                rhs[key].map { xcMutationJSONEqual(value, $0) } == true
            }
        default:
            false
        }
    }

    func xcRequestRelationshipIdentifiers(
        _ request: XcodeCloudWorkflowMutationRequestPlan
    ) -> [String: Value] {
        let publicFieldByRelationship = [
            "product": "product_id",
            "repository": "repository_id",
            "xcodeVersion": "xcode_version_id",
            "macOsVersion": "macos_version_id"
        ]
        return Dictionary(uniqueKeysWithValues: request.relationships.compactMap { field, relationship in
            publicFieldByRelationship[field].map { ($0, .string(relationship.id)) }
        })
    }

    func xcCreateInspection(_ request: XcodeCloudWorkflowMutationRequestPlan) -> Value {
        guard let product = request.relationships["product"] else {
            return .object([:])
        }
        return .object([
            "tool": .string("xcode_cloud_product_workflows_list"),
            "arguments": .object(["product_id": .string(product.id)]),
            "instruction": .string(
                "Inspect current workflows before any retry; observed state alone does not attribute an ambiguous write to this invocation."
            )
        ])
    }

    func xcResourceInspection(tool: String, idField: String, id: String) -> Value {
        .object([
            "tool": .string(tool),
            "arguments": .object([idField: .string(id)]),
            "instruction": .string("Inspect the exact resource before any retry.")
        ])
    }

    func xcMutationIdentifiers(_ arguments: [String: Value], fields: [String]) -> [String: Value] {
        Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            arguments[field].map { (field, $0) }
        })
    }

    func xcMutationSuccess(
        operation: String,
        statusCode: Int,
        resourceField: String,
        resource: XcodeCloudMutationResource,
        selfURL: String,
        included: [JSONValue]?
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": true,
            "operation": operation,
            "operationCommitted": true,
            "operationCommitState": "committed",
            "write_outcome": "committed",
            "changeVerified": true,
            "retrySafe": false,
            "statusCode": statusCode,
            "self_url": selfURL,
            resourceField: xcMutationResourcePayload(resource)
        ]
        if let included {
            payload["included"] = included.map(\.asAny)
        }
        return MCPResult.jsonObject(payload)
    }

    func xcMutationResourcePayload(_ resource: XcodeCloudMutationResource) -> [String: Any] {
        var payload: [String: Any] = [
            "type": resource.type,
            "id": resource.id
        ]
        if let attributes = resource.attributes {
            payload["attributes"] = attributes.mapValues(\.asAny)
        }
        if let relationships = resource.relationships {
            payload["relationships"] = relationships.mapValues(\.asAny)
        }
        if let resourceSelf = resource.links?.`self` {
            payload["self"] = resourceSelf
        }
        return payload
    }

    func xcMutationNotAttempted(
        operation: String,
        error: Error,
        identifiers: [String: Value]
    ) -> CallTool.Result {
        MCPResult.json(
            .object([
                "success": .bool(false),
                "operation": .string(operation),
                "operationCommitState": .string("not_attempted"),
                "write_outcome": .string("not_attempted"),
                "mutationAttempted": .bool(false),
                "operationCommitted": .bool(false),
                "retrySafe": .bool(false),
                "identifiers": .object(identifiers),
                "cause": xcMutationCause(error, phase: .request),
                "error": .string(Redactor.redact(error.localizedDescription))
            ]),
            text: "Error: The Xcode Cloud mutation was not attempted because validation or read-only preflight failed.",
            isError: true
        )
    }

    func xcMutationFailure(
        operation: String,
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        identifiers: [String: Value],
        inspection: Value
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: phase)
        var payload: [String: Value] = [
            "success": .bool(false),
            "operation": .string(operation),
            "operationCommitState": .string(disposition.rawValue),
            "write_outcome": .string(disposition.rawValue),
            "mutationAttempted": .bool(true),
            "retrySafe": .bool(false),
            "identifiers": .object(identifiers),
            "cause": xcMutationCause(error, phase: phase),
            "error": .string(Redactor.redact(error.localizedDescription))
        ]
        let text: String
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = .bool(false)
            payload["outcomeUnknown"] = .bool(false)
            text = "Error: Apple definitively rejected the Xcode Cloud mutation; it was not committed."
        case .outcomeUnknown:
            payload["operationCommitted"] = .null
            payload["outcomeUnknown"] = .bool(true)
            payload["inspectionRequired"] = .bool(true)
            payload["inspection"] = inspection
            text = "Error: The Xcode Cloud mutation outcome is unknown. Inspect exact current state before any retry."
        case .committedUnverified:
            payload["operationCommitted"] = .bool(true)
            payload["outcomeUnknown"] = .bool(false)
            payload["inspectionRequired"] = .bool(true)
            payload["inspection"] = inspection
            text = "Error: Apple accepted the Xcode Cloud mutation, but its exact result was not safely verified. Inspect before any retry."
        }
        return MCPResult.json(.object(payload), text: text, isError: true)
    }

    func xcMutationCause(
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
}

private extension XcodeCloudWorker {
    func xcFetchDeletionResource(
        path: String,
        expectedType: String,
        expectedID: String
    ) async throws -> XcodeCloudMutationResource {
        let response: XcodeCloudMutationResourceDocument = try await httpClient.get(
            path,
            as: XcodeCloudMutationResourceDocument.self
        )
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: response.data.type,
            id: response.data.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: "Apple deletion preflight response"
        )
        try xcValidateDocumentSelf(response.links.`self`, expectedPath: path, context: "deletion preflight")
        if let resourceSelf = response.data.links?.`self` {
            try xcValidateDocumentSelf(resourceSelf, expectedPath: path, context: "deletion preflight resource")
        }
        return response.data
    }

    func xcRequiredResourceName(
        _ resource: XcodeCloudMutationResource,
        context: String
    ) throws -> String {
        guard case .string(let name)? = resource.attributes?["name"] else {
            throw ASCError.parsing("Apple \(context) omitted the exact current resource name")
        }
        return name
    }

    func xcExactCollectionInventory(
        path: String,
        expectedType: String,
        context: String
    ) async throws -> [String] {
        let sparseField: (name: String, value: String)
        switch expectedType {
        case "ciBuildRuns":
            sparseField = ("fields[ciBuildRuns]", "number")
        case "ciWorkflows":
            sparseField = ("fields[ciWorkflows]", "name")
        default:
            throw ASCError.parsing("Unsupported Xcode Cloud deletion inventory type")
        }
        let query = ["limit": "200", sparseField.name: sparseField.value]
        let continuationScope = PaginationScope.strict(path: path, query: query)
        var response: XcodeCloudMutationCollectionDocument = try await httpClient.get(
            path,
            parameters: query,
            as: XcodeCloudMutationCollectionDocument.self
        )
        var expectedSelfParameters = query
        var identifiers: Set<String> = []
        var visitedNextLinks: Set<String> = []
        var declaredTotal: Int?

        while true {
            let selfRequest: PaginationRequest
            do {
                selfRequest = try httpClient.validatedScopedLink(
                    response.links.`self`,
                    scope: PaginationScope(
                        path: path,
                        requiredParameters: expectedSelfParameters,
                        allowedParameters: Set(expectedSelfParameters.keys),
                        requiredNonEmptyParameters: expectedSelfParameters["cursor"] == nil ? [] : ["cursor"]
                    )
                )
            } catch {
                throw ASCError.parsing("Apple returned an out-of-scope links.self while counting \(context)")
            }
            guard selfRequest.parameters == expectedSelfParameters else {
                throw ASCError.parsing("Apple returned a links.self that does not identify the requested \(context) page")
            }
            if let first = response.links.first {
                do {
                    let firstRequest = try httpClient.validatedScopedLink(
                        first,
                        scope: PaginationScope(
                            path: path,
                            requiredParameters: query,
                            allowedParameters: Set(query.keys)
                        )
                    )
                    guard firstRequest.parameters == query else {
                        throw ASCError.parsing("Apple returned a links.first containing a cursor while counting \(context)")
                    }
                } catch {
                    throw ASCError.parsing("Apple returned an out-of-scope links.first while counting \(context)")
                }
            }
            guard response.data.count <= 200 else {
                throw ASCError.parsing("Apple returned more than the requested limit while counting \(context)")
            }
            for resource in response.data {
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: resource.type,
                    id: resource.id,
                    expectedType: expectedType,
                    context: "Apple \(context) collection"
                )
                guard identifiers.insert(resource.id).inserted else {
                    throw ASCError.parsing("Apple returned a duplicate resource while counting \(context)")
                }
            }
            if let paging = response.meta?.paging {
                guard paging.limit == 200 else {
                    throw ASCError.parsing("Apple returned an unexpected paging limit while counting \(context)")
                }
                if let total = paging.total {
                    guard total >= 0, identifiers.count <= total else {
                        throw ASCError.parsing("Apple returned an impossible total while counting \(context)")
                    }
                    if let declaredTotal, declaredTotal != total {
                        throw ASCError.parsing("Apple changed the declared total while counting \(context)")
                    }
                    declaredTotal = total
                }
            }

            guard let next = response.links.next else {
                if let paging = response.meta?.paging, paging.nextCursor != nil {
                    throw ASCError.parsing("Apple returned a paging nextCursor without links.next while counting \(context)")
                }
                if let declaredTotal, declaredTotal != identifiers.count {
                    throw ASCError.parsing("Apple returned an incomplete collection while counting \(context)")
                }
                return identifiers.sorted()
            }
            if let declaredTotal, declaredTotal == identifiers.count {
                throw ASCError.parsing("Apple returned another page after the declared \(context) total was collected")
            }
            guard visitedNextLinks.insert(next).inserted else {
                throw ASCError.parsing("Apple returned a repeated pagination link while counting \(context)")
            }
            let nextRequest: PaginationRequest
            do {
                nextRequest = try httpClient.validatedScopedLink(next, scope: continuationScope)
            } catch {
                throw ASCError.parsing("Apple returned an out-of-scope links.next while counting \(context)")
            }
            guard nextRequest.parameters != expectedSelfParameters else {
                throw ASCError.parsing("Apple returned a pagination link that does not advance while counting \(context)")
            }
            if let paging = response.meta?.paging {
                guard let nextCursor = paging.nextCursor,
                      nextRequest.parameters["cursor"] == nextCursor else {
                    throw ASCError.parsing("Apple returned inconsistent links.next and paging.nextCursor while counting \(context)")
                }
            }
            expectedSelfParameters = nextRequest.parameters
            response = try await httpClient.getPage(
                next,
                scope: continuationScope,
                as: XcodeCloudMutationCollectionDocument.self
            )
        }
    }

    func xcDeletionReceipt(
        resourceType: String,
        resourceID: String,
        name: String,
        workflowIDs: [String]?,
        buildRunIDs: [String]
    ) -> String {
        let workflowMaterial = workflowIDs.map(xcDeletionInventoryMaterial) ?? "-"
        let buildRunMaterial = xcDeletionInventoryMaterial(buildRunIDs)
        let material = [
            "xcode-cloud-delete-v1",
            resourceType,
            "\(resourceID.utf8.count):\(resourceID)",
            "\(name.utf8.count):\(name)",
            workflowMaterial,
            buildRunMaterial
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "xcode-cloud-delete-v1:\(digest)"
    }

    func xcDeletionInventoryMaterial(_ identifiers: [String]) -> String {
        identifiers.sorted().map { "\($0.utf8.count):\($0)" }.joined(separator: ",")
    }

    func xcHasAnyDeletionConfirmation(
        _ arguments: [String: Value],
        fields: Set<String>
    ) -> Bool {
        fields.contains { arguments[$0] != nil }
    }

    func xcWorkflowDeletionConfirmationMatches(
        _ arguments: [String: Value],
        preview: XcodeCloudDeletionPreview
    ) -> Bool {
        arguments["confirm_permanent_deletion"]?.boolValue == true
            && arguments["confirmation_receipt"]?.stringValue == preview.receipt
            && arguments["expected_workflow_name"]?.stringValue == preview.name
            && arguments["expected_build_run_count"]?.intValue == preview.buildRunCount
    }

    func xcProductDeletionConfirmationMatches(
        _ arguments: [String: Value],
        preview: XcodeCloudDeletionPreview
    ) -> Bool {
        arguments["confirm_permanent_deletion"]?.boolValue == true
            && arguments["confirmation_receipt"]?.stringValue == preview.receipt
            && arguments["expected_product_name"]?.stringValue == preview.name
            && arguments["expected_workflow_count"]?.intValue == preview.workflowCount
            && arguments["expected_build_run_count"]?.intValue == preview.buildRunCount
    }

    func xcWorkflowDeletionPreviewResult(_ preview: XcodeCloudDeletionPreview) -> CallTool.Result {
        MCPResult.jsonObject([
            "success": true,
            "executed": false,
            "previewOnly": true,
            "requiresConfirmation": true,
            "resourceType": preview.resourceType,
            "workflowId": preview.resourceID,
            "workflowName": preview.name,
            "buildRunCount": preview.buildRunCount,
            "confirmation": [
                "confirmationReceipt": preview.receipt,
                "expectedWorkflowName": preview.name,
                "expectedBuildRunCount": preview.buildRunCount,
                "requiredInputs": [
                    "confirm_permanent_deletion=true",
                    "confirmation_receipt",
                    "expected_workflow_name",
                    "expected_build_run_count"
                ]
            ],
            "impact": [
                "permanent": true,
                "buildHistoryAndArtifactsMayBeRemoved": true,
                "alternative": [
                    "tool": "xcode_cloud_workflows_update",
                    "arguments": ["workflow_id": preview.resourceID, "is_enabled": false]
                ]
            ]
        ])
    }

    func xcProductDeletionPreviewResult(_ preview: XcodeCloudDeletionPreview) -> CallTool.Result {
        MCPResult.jsonObject([
            "success": true,
            "executed": false,
            "previewOnly": true,
            "requiresConfirmation": true,
            "resourceType": preview.resourceType,
            "productId": preview.resourceID,
            "productName": preview.name,
            "workflowCount": preview.workflowCount ?? 0,
            "buildRunCount": preview.buildRunCount,
            "confirmation": [
                "confirmationReceipt": preview.receipt,
                "expectedProductName": preview.name,
                "expectedWorkflowCount": preview.workflowCount ?? 0,
                "expectedBuildRunCount": preview.buildRunCount,
                "requiredInputs": [
                    "confirm_permanent_deletion=true",
                    "confirmation_receipt",
                    "expected_product_name",
                    "expected_workflow_count",
                    "expected_build_run_count"
                ]
            ],
            "impact": [
                "permanent": true,
                "workflowsBuildHistoryAndArtifactsMayBeRemoved": true
            ]
        ])
    }

    func xcDeletionConfirmationMismatch(
        operation: String,
        preview: XcodeCloudDeletionPreview
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "executed": false,
            "operation": operation,
            "operationCommitState": "not_attempted",
            "write_outcome": "not_attempted",
            "mutationAttempted": false,
            "operationCommitted": false,
            "retrySafe": false,
            "error": "Deletion confirmation does not match the latest preflight state"
        ]
        let previewResult = preview.resourceType == "ciProducts"
            ? xcProductDeletionPreviewPayload(preview)
            : xcWorkflowDeletionPreviewPayload(preview)
        payload["latestPreview"] = previewResult
        return MCPResult.jsonObject(
            payload,
            text: "Error: Deletion confirmation does not match the latest preflight state. Review the fresh preview and confirm again.",
            isError: true
        )
    }

    func xcProductDeletionPreviewPayload(_ preview: XcodeCloudDeletionPreview) -> [String: Any] {
        [
            "productId": preview.resourceID,
            "expectedProductName": preview.name,
            "expectedWorkflowCount": preview.workflowCount ?? 0,
            "expectedBuildRunCount": preview.buildRunCount,
            "confirmationReceipt": preview.receipt
        ]
    }

    func xcWorkflowDeletionPreviewPayload(_ preview: XcodeCloudDeletionPreview) -> [String: Any] {
        [
            "workflowId": preview.resourceID,
            "expectedWorkflowName": preview.name,
            "expectedBuildRunCount": preview.buildRunCount,
            "confirmationReceipt": preview.receipt
        ]
    }

    func xcExecuteDeletion(
        operation: String,
        path: String,
        identifiers: [String: Value],
        preview: XcodeCloudDeletionPreview,
        inspection: Value
    ) async -> CallTool.Result {
        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(path)
        } catch {
            return xcMutationFailure(
                operation: operation,
                error: error,
                phase: .request,
                identifiers: identifiers,
                inspection: inspection
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 204,
                context: "Xcode Cloud deletion"
            )
            guard receipt.data.isEmpty else {
                throw ASCError.parsing("Apple returned a non-empty HTTP 204 deletion response")
            }
            var payload: [String: Any] = [
                "success": true,
                "executed": true,
                "deleted": true,
                "operation": operation,
                "operationCommitted": true,
                "operationCommitState": "committed",
                "write_outcome": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "resourceType": preview.resourceType,
                "resourceId": preview.resourceID,
                "resourceNameAtPreview": preview.name,
                "buildRunCountAtPreview": preview.buildRunCount,
                "confirmationReceipt": preview.receipt
            ]
            if let workflowCount = preview.workflowCount {
                payload["workflowCountAtPreview"] = workflowCount
            }
            return MCPResult.jsonObject(payload)
        } catch {
            return xcMutationFailure(
                operation: operation,
                error: error,
                phase: .acceptedResponse,
                identifiers: identifiers,
                inspection: inspection
            )
        }
    }
}

private enum XcodeCloudMutationScalarKind: Sendable {
    case string
    case boolean
}

private enum XcodeCloudMutationStartConditionKind: Sendable {
    case branch
    case tag
    case pullRequest
    case scheduled
    case manualBranch
    case manualTag
    case manualPullRequest
}

private struct XcodeCloudDeletionPreview: Sendable {
    let resourceType: String
    let resourceID: String
    let name: String
    let workflowCount: Int?
    let buildRunCount: Int
    let receipt: String
}

private struct XcodeCloudMutationArgumentError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
