import Foundation

// MARK: - Parsers
extension BuildsWorker {
    
    // MARK: - Model Formatters (for Sendable models)
    
    /// Format build model to dictionary
    func formatBuild(_ build: ASCBuild) -> [String: Any] {
        var result: [String: Any] = [
            "id": build.id,
            "type": build.type
        ]
        
        // Add attributes
        result["version"] = build.attributes.version.jsonSafe
        result["uploadedDate"] = build.attributes.uploadedDate.jsonSafe
        result["expirationDate"] = build.attributes.expirationDate.jsonSafe
        result["expired"] = build.attributes.expired.jsonSafe
        result["processingState"] = build.attributes.processingState.jsonSafe
        result["minOsVersion"] = build.attributes.minOsVersion.jsonSafe
        result["usesNonExemptEncryption"] = build.attributes.usesNonExemptEncryption.jsonSafe
        
        // Add relationships if present
        if let relationships = build.relationships {
            var rels: [String: Any] = [:]
            
            if let app = relationships.app,
               let appData = app.data {
                rels["appId"] = appData.id
            }
            
            if let betaDetail = relationships.buildBetaDetail,
               let betaDetailData = betaDetail.data {
                rels["betaDetailId"] = betaDetailData.id
            }
            
            if let preReleaseVersion = relationships.preReleaseVersion,
               let versionData = preReleaseVersion.data {
                rels["preReleaseVersionId"] = versionData.id
            }
            
            result["relationships"] = rels
        }
        
        return result
    }
    
    /// Format included resource to dictionary
    func formatIncludedResource(_ resource: ASCBuildIncludedResource) -> [String: Any] {
        switch resource {
        case .app(let app):
            return [
                "id": app.id,
                "type": app.type,
                "name": SafeJSONHelpers.safeString(app.attributes?.name),
                "bundleId": SafeJSONHelpers.safeString(app.attributes?.bundleId)
            ]
        case .buildBetaDetail(let detail):
            return [
                "id": detail.id,
                "type": detail.type,
                "autoNotifyEnabled": detail.attributes.autoNotifyEnabled.jsonSafe,
                "internalBuildState": detail.attributes.internalBuildState.jsonSafe,
                "externalBuildState": detail.attributes.externalBuildState.jsonSafe
            ]
        case .preReleaseVersion(let version):
            return [
                "id": version.id,
                "type": version.type,
                "version": version.attributes.version.jsonSafe,
                "platform": version.attributes.platform.jsonSafe
            ]
        case .buildBundle(let bundle):
            return [
                "id": bundle.id,
                "type": bundle.type,
                "bundleId": bundle.attributes.bundleId.jsonSafe,
                "bundleType": bundle.attributes.bundleType.jsonSafe,
                "fileName": bundle.attributes.fileName.jsonSafe
            ]
        case .betaGroup(let group):
            return [
                "id": group.id,
                "type": group.type,
                "name": group.attributes.name.jsonSafe,
                "isInternalGroup": group.attributes.isInternalGroup.jsonSafe
            ]
        case .betaTester(let tester):
            return [
                "id": tester.id,
                "type": tester.type,
                "email": tester.attributes.email.jsonSafe,
                "firstName": tester.attributes.firstName.jsonSafe,
                "lastName": tester.attributes.lastName.jsonSafe
            ]
        }
    }
    
    // MARK: - Legacy Parsers (kept for compatibility)
    
    func parseBuild(_ data: [String: Any]) -> [String: Any] {
        guard let id = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any] else {
            return [:]
        }
        
        return [
            "id": id,
            "version": attributes["version"] as? String ?? "",
            "uploadedDate": attributes["uploadedDate"] as? String ?? "",
            "expirationDate": attributes["expirationDate"] as? String ?? "",
            "expired": attributes["expired"] as? Bool ?? false,
            "minOsVersion": attributes["minOsVersion"] as? String ?? "",
            "processingState": attributes["processingState"] as? String ?? "",
            "buildAudienceType": attributes["buildAudienceType"] as? String ?? "",
            "usesNonExemptEncryption": attributes["usesNonExemptEncryption"] as? Bool ?? false,
            "iconAssetToken": parseIconAssetToken(attributes["iconAssetToken"])
        ]
    }
    
    func parseBetaDetail(_ data: [String: Any]) -> [String: Any] {
        guard let id = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any] else {
            return [:]
        }
        
        return [
            "id": id,
            "autoNotifyEnabled": attributes["autoNotifyEnabled"] as? Bool ?? false,
            "internalBuildState": attributes["internalBuildState"] as? String ?? "",
            "externalBuildState": attributes["externalBuildState"] as? String ?? ""
        ]
    }
    
    func parseApp(_ data: [String: Any]) -> [String: Any] {
        guard let id = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any] else {
            return [:]
        }
        
        return [
            "id": id,
            "name": attributes["name"] as? String ?? "",
            "bundleId": attributes["bundleId"] as? String ?? "",
            "sku": attributes["sku"] as? String ?? ""
        ]
    }
    
    func parsePreReleaseVersion(_ data: [String: Any]) -> [String: Any] {
        guard let id = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any] else {
            return [:]
        }
        
        return [
            "id": id,
            "version": attributes["version"] as? String ?? "",
            "platform": attributes["platform"] as? String ?? ""
        ]
    }
    
    func parseBuildBundle(_ data: [String: Any]) -> [String: Any] {
        guard let id = data["id"] as? String,
              let attributes = data["attributes"] as? [String: Any] else {
            return [:]
        }
        
        return [
            "id": id,
            "bundleId": attributes["bundleId"] as? String ?? "",
            "bundleType": attributes["bundleType"] as? String ?? "",
            "sdkBuild": attributes["sdkBuild"] as? String ?? "",
            "platformBuild": attributes["platformBuild"] as? String ?? "",
            "fileName": attributes["fileName"] as? String ?? "",
            "hasSirikit": attributes["hasSirikit"] as? Bool ?? false,
            "hasOnDemandResources": attributes["hasOnDemandResources"] as? Bool ?? false,
            "hasPrerenderedIcon": attributes["hasPrerenderedIcon"] as? Bool ?? false,
            "usesLocationServices": attributes["usesLocationServices"] as? Bool ?? false,
            "isIosBuildMacAppStoreCompatible": attributes["isIosBuildMacAppStoreCompatible"] as? Bool ?? false,
            "includesSymbols": attributes["includesSymbols"] as? Bool ?? false,
            "dSYMUrl": attributes["dSYMUrl"] as? String ?? "",
            "supportedArchitectures": attributes["supportedArchitectures"] as? [String] ?? [],
            "requiredCapabilities": attributes["requiredCapabilities"] as? [String] ?? [],
            "deviceProtocols": attributes["deviceProtocols"] as? [String] ?? [],
            "locales": attributes["locales"] as? [String] ?? [],
            "entitlements": attributes["entitlements"] as? [String: Any] ?? [:]
        ]
    }
    
    func parseIconAssetToken(_ token: Any?) -> [String: Any] {
        guard let tokenData = token as? [String: Any] else {
            return [:]
        }
        
        return [
            "templateUrl": tokenData["templateUrl"] as? String ?? "",
            "width": tokenData["width"] as? Int ?? 0,
            "height": tokenData["height"] as? Int ?? 0
        ]
    }
}