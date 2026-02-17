import Foundation
import MCP

// MARK: - Tool Handlers
extension BuildProcessingWorker {
    
    /// Gets the current processing state of a build
    /// - Returns: JSON with processing state (PROCESSING, FAILED, INVALID, VALID) and timestamps
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getProcessingState(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }
        
        do {
            let queryParams: [String: String] = [
                "fields[builds]": "processingState,uploadedDate,expirationDate,expired,version,minOsVersion"
            ]
            
            let response: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(buildId)",
                parameters: queryParams,
                as: ASCBuildResponse.self
            )
            
            let processingState = response.data.attributes.processingState ?? "UNKNOWN"
            let uploadedDate = response.data.attributes.uploadedDate ?? ""
            let expirationDate = response.data.attributes.expirationDate ?? ""
            let expired = response.data.attributes.expired ?? false
            let version = response.data.attributes.version ?? ""
            let minOsVersion = response.data.attributes.minOsVersion ?? ""
            
            // Calculate processing time if still processing
            var processingDuration = ""
            if processingState == "PROCESSING", !uploadedDate.isEmpty {
                if let uploadDate = ISO8601DateFormatter().date(from: uploadedDate) {
                    let duration = Date().timeIntervalSince(uploadDate)
                    processingDuration = formatDuration(duration)
                }
            }
            
            let result = [
                "success": true,
                "buildId": buildId,
                "processingState": processingState,
                "isReady": processingState == "VALID",
                "version": version,
                "minOsVersion": minOsVersion,
                "uploadedDate": uploadedDate,
                "expirationDate": expirationDate,
                "expired": expired,
                "processingDuration": processingDuration,
                "stateDescription": getStateDescription(processingState)
            ] as [String: Any]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get processing state: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Updates encryption compliance via the build's App Encryption Declaration
    /// - Returns: JSON with updated encryption declaration details
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func updateEncryption(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue,
              let encryptionValue = arguments["uses_non_exempt_encryption"],
              let usesNonExemptEncryption = encryptionValue.boolValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'build_id' and 'uses_non_exempt_encryption' are missing")],
                isError: true
            )
        }

        do {
            // Step 1: Get the build's encryption declaration (raw JSON to avoid Codable issues)
            let declarationData = try await httpClient.get(
                "/v1/builds/\(buildId)/appEncryptionDeclaration",
                parameters: [:]
            )

            guard let declarationJson = try JSONSerialization.jsonObject(with: declarationData) as? [String: Any],
                  let dataObj = declarationJson["data"] as? [String: Any],
                  let declarationId = dataObj["id"] as? String else {
                return CallTool.Result(
                    content: [.text("Error: Could not parse encryption declaration response for build \(buildId). The build may not have an encryption declaration. Note: builds older than 90 days may have expired and no longer support this operation.")],
                    isError: true
                )
            }

            // Step 2: Build PATCH request body (usesEncryption is the declaration attribute)
            let requestBody: [String: Any] = [
                "data": [
                    "type": "appEncryptionDeclarations",
                    "id": declarationId,
                    "attributes": [
                        "usesEncryption": usesNonExemptEncryption
                    ]
                ]
            ]
            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

            // Step 3: Update the encryption declaration
            let responseData = try await httpClient.patch(
                "/v1/appEncryptionDeclarations/\(declarationId)",
                body: bodyData
            )

            // Step 4: Parse response (raw JSON)
            var state = "UNKNOWN"
            if let responseJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let respData = responseJson["data"] as? [String: Any],
               let attrs = respData["attributes"] as? [String: Any] {
                state = attrs["appEncryptionDeclarationState"] as? String ?? "UNKNOWN"
            }

            let result = [
                "success": true,
                "buildId": buildId,
                "declarationId": declarationId,
                "usesEncryption": usesNonExemptEncryption,
                "state": state,
                "message": "Encryption declaration updated successfully"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to update encryption declaration: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Checks current processing status of a build (non-blocking, single check)
    /// - Returns: JSON with processing state, readiness, and time since upload
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getProcessingStatus(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "fields[builds]": "processingState,uploadedDate,version"
            ]

            let response: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(buildId)",
                parameters: queryParams,
                as: ASCBuildResponse.self
            )

            let processingState = response.data.attributes.processingState ?? "UNKNOWN"
            let uploadedDate = response.data.attributes.uploadedDate ?? ""
            let version = response.data.attributes.version ?? ""

            let isReady = processingState == "VALID"
            let isFailed = processingState == "INVALID" || processingState == "FAILED"

            // Calculate time since upload
            var timeSinceUpload = ""
            if !uploadedDate.isEmpty,
               let uploadDate = ISO8601DateFormatter().date(from: uploadedDate) {
                timeSinceUpload = formatDuration(Date().timeIntervalSince(uploadDate))
            }

            var resultDict: [String: Any] = [
                "success": true,
                "buildId": buildId,
                "version": version,
                "processingState": processingState,
                "isReady": isReady,
                "isFailed": isFailed,
                "uploadedDate": uploadedDate,
                "timeSinceUpload": timeSinceUpload,
                "stateDescription": getStateDescription(processingState)
            ]

            if !isReady && !isFailed {
                resultDict["suggestion"] = "Build is still processing. Call this tool again to check progress."
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(resultDict))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get processing status: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Checks if a build is ready for submission or TestFlight distribution
    /// - Returns: JSON with readiness status, missing requirements, and warnings
    /// - Throws: CallTool.Result with error if build_id missing or check fails
    func checkReadiness(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }
        
        do {
            // Get build details including beta detail
            let queryParams: [String: String] = [
                "include": "buildBetaDetail",
                "fields[builds]": "processingState,expired,usesNonExemptEncryption,version,minOsVersion",
                "fields[buildBetaDetails]": "autoNotifyEnabled,internalBuildState,externalBuildState"
            ]
            
            let response: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(buildId)",
                parameters: queryParams,
                as: ASCBuildResponse.self
            )
            
            let processingState = response.data.attributes.processingState ?? "UNKNOWN"
            let expired = response.data.attributes.expired ?? false
            let usesNonExemptEncryption = response.data.attributes.usesNonExemptEncryption
            let version = response.data.attributes.version ?? ""
            let minOsVersion = response.data.attributes.minOsVersion ?? ""
            
            // Parse beta details if included
            var betaDetails: [String: Any] = [:]
            if let included = response.included {
                for item in included {
                    switch item {
                    case .buildBetaDetail(let detail):
                        betaDetails = [
                            "autoNotifyEnabled": detail.attributes.autoNotifyEnabled ?? false,
                            "internalBuildState": detail.attributes.internalBuildState ?? "",
                            "externalBuildState": detail.attributes.externalBuildState ?? ""
                        ]
                    default:
                        break
                    }
                }
            }
            
            // Check readiness conditions
            var issues: [String] = []
            var warnings: [String] = []
            
            let isProcessed = processingState == "VALID"
            let encryptionCompliant = usesNonExemptEncryption != nil
            let isNotExpired = !expired
            
            if !isProcessed {
                issues.append("Build is still processing (state: \(processingState))")
            }
            
            if !encryptionCompliant {
                issues.append("Encryption compliance not set")
            }
            
            if !isNotExpired {
                issues.append("Build has expired")
            }
            
            if processingState == "INVALID" || processingState == "FAILED" {
                issues.append("Build processing failed")
            }
            
            // Check beta states
            let internalState = betaDetails["internalBuildState"] as? String ?? ""
            let externalState = betaDetails["externalBuildState"] as? String ?? ""
            
            let isReadyForInternalTesting = internalState == "READY_FOR_BETA_TESTING" || 
                                            internalState == "IN_BETA_TESTING" ||
                                            internalState == "EXPIRED"
            
            let isReadyForExternalTesting = externalState == "READY_FOR_BETA_SUBMISSION" ||
                                            externalState == "IN_BETA_REVIEW" ||
                                            externalState == "READY_FOR_BETA_TESTING" ||
                                            externalState == "IN_BETA_TESTING"
            
            let isReadyForSubmission = isProcessed && encryptionCompliant && isNotExpired
            
            let result = [
                "success": true,
                "buildId": buildId,
                "version": version,
                "minOsVersion": minOsVersion,
                "readiness": [
                    "isProcessed": isProcessed,
                    "encryptionCompliant": encryptionCompliant,
                    "isNotExpired": isNotExpired,
                    "isReadyForSubmission": isReadyForSubmission,
                    "isReadyForInternalTesting": isReadyForInternalTesting,
                    "isReadyForExternalTesting": isReadyForExternalTesting
                ],
                "states": [
                    "processingState": processingState,
                    "internalBuildState": internalState,
                    "externalBuildState": externalState
                ],
                "issues": issues,
                "warnings": warnings,
                "betaDetails": betaDetails
            ] as [String: Any]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to check readiness: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}