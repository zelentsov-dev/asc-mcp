import Foundation
import MCP

extension AccessibilityWorker {
    /// Lists App Store accessibility declarations for an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional filters/pagination.
    /// - Returns: JSON object containing declarations, count, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listDeclarations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        for field in ["device_family", "state", "fields"] {
            if let error = stringListValidationError(arguments[field], field: field) {
                return MCPResult.error(error)
            }
        }
        if let invalid = firstInvalidDeviceFamily(arguments["device_family"]) {
            return MCPResult.error("Unsupported device_family '\(invalid)'. Valid values: \(ASCAccessibilityDeviceFamily.validRawValues.joined(separator: ", "))")
        }
        if let invalid = firstInvalidState(arguments["state"]) {
            return MCPResult.error("Unsupported state '\(invalid)'. Valid values: \(ASCAccessibilityDeclarationState.validRawValues.joined(separator: ", "))")
        }
        if let invalid = firstInvalidField(arguments["fields"]) {
            return MCPResult.error("Unsupported field '\(invalid)'. Valid values: \(ASCAccessibilityDeclarationFields.all.joined(separator: ", "))")
        }

        do {
            let response: ASCAccessibilityDeclarationsResponse
            let path = "/v1/apps/\(try ASCPathSegment.encode(appID))/accessibilityDeclarations"
            var query = defaultListQuery(arguments: arguments)
            if let deviceFamilies = parseStringList(arguments["device_family"]) {
                query["filter[deviceFamily]"] = deviceFamilies.joined(separator: ",")
            }
            if let states = parseStringList(arguments["state"]) {
                query["filter[state]"] = states.joined(separator: ",")
            }
            if let fields = parseStringList(arguments["fields"]) {
                query["fields[accessibilityDeclarations]"] = fields.joined(separator: ",")
            }
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCAccessibilityDeclarationsResponse.self
                )
            } else {
                response = try await httpClient.get(path, parameters: query, as: ASCAccessibilityDeclarationsResponse.self)
            }

            var result: [String: Any] = [
                "success": true,
                "accessibility_declarations": response.data.map(formatDeclaration),
                "count": response.data.count
            ]
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list accessibility declarations: \(error.localizedDescription)")
        }
    }

    /// Gets one App Store accessibility declaration.
    /// - Parameter params: Tool parameters containing `declaration_id`.
    /// - Returns: JSON object containing the declaration resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let declarationID = arguments["declaration_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'declaration_id' is missing")
        }
        if let error = stringListValidationError(arguments["fields"], field: "fields") {
            return MCPResult.error(error)
        }
        if let invalid = firstInvalidField(arguments["fields"]) {
            return MCPResult.error("Unsupported field '\(invalid)'. Valid values: \(ASCAccessibilityDeclarationFields.all.joined(separator: ", "))")
        }

        do {
            var query: [String: String] = [:]
            if let fields = parseStringList(arguments["fields"]) {
                query["fields[accessibilityDeclarations]"] = fields.joined(separator: ",")
            }
            let response = try await httpClient.get("/v1/accessibilityDeclarations/\(try ASCPathSegment.encode(declarationID))", parameters: query, as: ASCAccessibilityDeclarationResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "accessibility_declaration": formatDeclaration(response.data)
            ])
        } catch {
            return MCPResult.error("Failed to get accessibility declaration: \(error.localizedDescription)")
        }
    }

    /// Creates an App Store accessibility declaration.
    /// - Parameter params: Tool parameters containing `app_id`, `device_family`, and optional support flags.
    /// - Returns: JSON object containing the created declaration resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func createDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue,
              let deviceFamilyValue = arguments["device_family"]?.stringValue else {
            return MCPResult.error("Required parameters: app_id, device_family")
        }
        guard let deviceFamily = ASCAccessibilityDeviceFamily(rawValue: deviceFamilyValue) else {
            return MCPResult.error("Unsupported device_family '\(deviceFamilyValue)'. Valid values: \(ASCAccessibilityDeviceFamily.validRawValues.joined(separator: ", "))")
        }

        do {
            let request = ASCAccessibilityDeclarationCreateRequest(
                appID: appID,
                deviceFamily: deviceFamily,
                supports: supportAttributes(from: arguments)
            )
            let response = try await httpClient.post("/v1/accessibilityDeclarations", body: request, as: ASCAccessibilityDeclarationResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "accessibility_declaration": formatDeclaration(response.data)
            ])
        } catch {
            return MCPResult.error("Failed to create accessibility declaration: \(error.localizedDescription)")
        }
    }

    /// Updates an App Store accessibility declaration.
    /// - Parameter params: Tool parameters containing `declaration_id` and at least one update field.
    /// - Returns: JSON object containing the updated declaration resource.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func updateDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let declarationID = arguments["declaration_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'declaration_id' is missing")
        }

        do {
            let attributes = ASCAccessibilityDeclarationUpdateRequest.Attributes(
                publish: try nullableBooleanValue(arguments["publish"], field: "publish"),
                supports: try updateSupportAttributes(from: arguments)
            )
            guard attributes.hasChanges else {
                return MCPResult.error("At least one update field is required: publish or one supports_* flag")
            }

            let request = ASCAccessibilityDeclarationUpdateRequest(declarationID: declarationID, attributes: attributes)
            let response = try await httpClient.patch("/v1/accessibilityDeclarations/\(try ASCPathSegment.encode(declarationID))", body: request, as: ASCAccessibilityDeclarationResponse.self)
            return MCPResult.jsonObject([
                "success": true,
                "accessibility_declaration": formatDeclaration(response.data)
            ])
        } catch {
            return MCPResult.error("Failed to update accessibility declaration: \(error.localizedDescription)")
        }
    }

    /// Deletes an App Store accessibility declaration.
    /// - Parameter params: Tool parameters containing `declaration_id`.
    /// - Returns: JSON confirmation.
    /// - Throws: Networking or API errors from App Store Connect.
    func deleteDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let declarationID = arguments["declaration_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'declaration_id' is missing")
        }

        do {
            _ = try await httpClient.delete("/v1/accessibilityDeclarations/\(try ASCPathSegment.encode(declarationID))")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Accessibility declaration '\(declarationID)' deleted"
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete accessibility declaration")
        }
    }

    /// Lists accessibility declaration relationship identifiers for an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional pagination.
    /// - Returns: JSON object containing relationship resource identifiers.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listDeclarationRelationships(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appID))/relationships/accessibilityDeclarations"
            let query = defaultListQuery(arguments: arguments)
            let response: ASCAccessibilityDeclarationLinkagesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: endpoint, query: query),
                    as: ASCAccessibilityDeclarationLinkagesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCAccessibilityDeclarationLinkagesResponse.self
                )
            }

            var result: [String: Any] = [
                "success": true,
                "relationships": response.data.map(formatResourceIdentifier),
                "declaration_ids": response.data.map(\.id),
                "count": response.data.count
            ]
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list accessibility declaration relationships: \(error.localizedDescription)")
        }
    }

    private func defaultListQuery(arguments: [String: Value]) -> [String: String] {
        let limit = arguments["limit"]?.intValue ?? 25
        return ["limit": String(min(max(limit, 1), 200))]
    }

    private func supportAttributes(from arguments: [String: Value]) -> ASCAccessibilityDeclarationSupportAttributes {
        ASCAccessibilityDeclarationSupportAttributes(
            supportsAudioDescriptions: arguments["supports_audio_descriptions"]?.boolValue,
            supportsCaptions: arguments["supports_captions"]?.boolValue,
            supportsDarkInterface: arguments["supports_dark_interface"]?.boolValue,
            supportsDifferentiateWithoutColorAlone: arguments["supports_differentiate_without_color_alone"]?.boolValue,
            supportsLargerText: arguments["supports_larger_text"]?.boolValue,
            supportsReducedMotion: arguments["supports_reduced_motion"]?.boolValue,
            supportsSufficientContrast: arguments["supports_sufficient_contrast"]?.boolValue,
            supportsVoiceControl: arguments["supports_voice_control"]?.boolValue,
            supportsVoiceover: arguments["supports_voiceover"]?.boolValue
        )
    }

    private func updateSupportAttributes(
        from arguments: [String: Value]
    ) throws -> ASCAccessibilityDeclarationUpdateSupportAttributes {
        ASCAccessibilityDeclarationUpdateSupportAttributes(
            supportsAudioDescriptions: try nullableBooleanValue(
                arguments["supports_audio_descriptions"],
                field: "supports_audio_descriptions"
            ),
            supportsCaptions: try nullableBooleanValue(arguments["supports_captions"], field: "supports_captions"),
            supportsDarkInterface: try nullableBooleanValue(
                arguments["supports_dark_interface"],
                field: "supports_dark_interface"
            ),
            supportsDifferentiateWithoutColorAlone: try nullableBooleanValue(
                arguments["supports_differentiate_without_color_alone"],
                field: "supports_differentiate_without_color_alone"
            ),
            supportsLargerText: try nullableBooleanValue(arguments["supports_larger_text"], field: "supports_larger_text"),
            supportsReducedMotion: try nullableBooleanValue(
                arguments["supports_reduced_motion"],
                field: "supports_reduced_motion"
            ),
            supportsSufficientContrast: try nullableBooleanValue(
                arguments["supports_sufficient_contrast"],
                field: "supports_sufficient_contrast"
            ),
            supportsVoiceControl: try nullableBooleanValue(
                arguments["supports_voice_control"],
                field: "supports_voice_control"
            ),
            supportsVoiceover: try nullableBooleanValue(arguments["supports_voiceover"], field: "supports_voiceover")
        )
    }

    private func nullableBooleanValue(
        _ value: Value?,
        field: String
    ) throws -> ASCAccessibilityNullableBool? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let boolean = value.boolValue else {
            throw AccessibilityArgumentError("'\(field)' must be a boolean or null")
        }
        return .value(boolean)
    }

    private func parseStringList(_ value: Value?) -> [String]? {
        if let string = value?.stringValue {
            return string
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return value?.arrayValue?
            .compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func stringListValidationError(_ value: Value?, field: String) -> String? {
        guard let value else { return nil }
        let values: [String]
        if let string = value.stringValue {
            values = string
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else if let array = value.arrayValue {
            let parsed = array.compactMap(\.stringValue)
            guard parsed.count == array.count else {
                return "'\(field)' must contain only strings"
            }
            values = parsed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            return "'\(field)' must be a string or array of strings"
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            return "'\(field)' must contain at least one non-empty value"
        }
        guard Set(values).count == values.count else {
            return "'\(field)' must not contain duplicate values"
        }
        return nil
    }

    private func firstInvalidDeviceFamily(_ value: Value?) -> String? {
        parseStringList(value)?.first { ASCAccessibilityDeviceFamily(rawValue: $0) == nil }
    }

    private func firstInvalidState(_ value: Value?) -> String? {
        parseStringList(value)?.first { ASCAccessibilityDeclarationState(rawValue: $0) == nil }
    }

    private func firstInvalidField(_ value: Value?) -> String? {
        parseStringList(value)?.first { !ASCAccessibilityDeclarationFields.all.contains($0) }
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    private func formatDeclaration(_ declaration: ASCAccessibilityDeclaration) -> [String: Any] {
        let attributes = declaration.attributes
        return [
            "id": declaration.id,
            "type": declaration.type,
            "deviceFamily": (attributes?.deviceFamily?.rawValue).jsonSafe,
            "state": (attributes?.state?.rawValue).jsonSafe,
            "supports": formatSupportAttributes(attributes),
            "selfUrl": (declaration.links?.`self`).jsonSafe
        ]
    }

    private func formatSupportAttributes(_ attributes: ASCAccessibilityDeclaration.Attributes?) -> [String: Any] {
        [
            "audioDescriptions": (attributes?.supportsAudioDescriptions).jsonSafe,
            "captions": (attributes?.supportsCaptions).jsonSafe,
            "darkInterface": (attributes?.supportsDarkInterface).jsonSafe,
            "differentiateWithoutColorAlone": (attributes?.supportsDifferentiateWithoutColorAlone).jsonSafe,
            "largerText": (attributes?.supportsLargerText).jsonSafe,
            "reducedMotion": (attributes?.supportsReducedMotion).jsonSafe,
            "sufficientContrast": (attributes?.supportsSufficientContrast).jsonSafe,
            "voiceControl": (attributes?.supportsVoiceControl).jsonSafe,
            "voiceover": (attributes?.supportsVoiceover).jsonSafe
        ]
    }

    private func formatResourceIdentifier(_ identifier: ASCResourceIdentifier) -> [String: Any] {
        [
            "id": identifier.id,
            "type": identifier.type
        ]
    }
}

private struct AccessibilityArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
