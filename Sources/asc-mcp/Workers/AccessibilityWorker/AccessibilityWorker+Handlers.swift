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
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                var requiredParameters: [String: String] = [:]
                if let deviceFamilies = parseStringList(arguments["device_family"]) {
                    requiredParameters["filter[deviceFamily]"] = deviceFamilies.joined(separator: ",")
                }
                if let states = parseStringList(arguments["state"]) {
                    requiredParameters["filter[state]"] = states.joined(separator: ",")
                }
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appID))/accessibilityDeclarations",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCAccessibilityDeclarationsResponse.self
                )
            } else {
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
                response = try await httpClient.get("/v1/apps/\(try ASCPathSegment.encode(appID))/accessibilityDeclarations", parameters: query, as: ASCAccessibilityDeclarationsResponse.self)
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

        let attributes = ASCAccessibilityDeclarationUpdateRequest.Attributes(
            publish: arguments["publish"]?.boolValue,
            supports: supportAttributes(from: arguments)
        )
        guard attributes.hasChanges else {
            return MCPResult.error("At least one update field is required: publish or one supports_* flag")
        }

        do {
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
            return MCPResult.error("Failed to delete accessibility declaration: \(error.localizedDescription)")
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
            let response: ASCAccessibilityDeclarationLinkagesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(path: "/v1/apps/\(try ASCPathSegment.encode(appID))/relationships/accessibilityDeclarations"),
                    as: ASCAccessibilityDeclarationLinkagesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appID))/relationships/accessibilityDeclarations",
                    parameters: defaultListQuery(arguments: arguments),
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
