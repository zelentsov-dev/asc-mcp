import Foundation

// MARK: - Parser Methods
extension BuildBetaDetailsWorker {
    
    // MARK: - Model Formatters (for Sendable models)
    
    /// Format beta detail model to dictionary
    func formatBetaDetail(_ detail: ASCBuildBetaDetail) -> [String: Any] {
        var result: [String: Any] = [
            "id": detail.id,
            "type": detail.type
        ]
        
        result["autoNotifyEnabled"] = detail.attributes.autoNotifyEnabled.jsonSafe
        result["internalBuildState"] = detail.attributes.internalBuildState.jsonSafe
        result["externalBuildState"] = detail.attributes.externalBuildState.jsonSafe
        
        // Add relationships if present
        if let relationships = detail.relationships {
            var rels: [String: Any] = [:]
            
            if let build = relationships.build,
               let buildData = build.data {
                rels["buildId"] = buildData.id
            }
            
            if let localizations = relationships.betaBuildLocalizations {
                rels["localizationsLink"] = localizations.links?.related
            }
            
            result["relationships"] = rels
        }
        
        return result
    }
    
    /// Format beta build localization model to dictionary
    func formatBetaBuildLocalization(_ localization: ASCBetaBuildLocalization) -> [String: Any] {
        var result: [String: Any] = [
            "id": localization.id,
            "type": localization.type
        ]
        
        result["locale"] = localization.attributes.locale.jsonSafe
        result["whatsNew"] = localization.attributes.whatsNew.jsonSafe

        if let build = localization.relationships?.build?.data {
            result["build"] = [
                "type": build.type,
                "id": build.id
            ]
        }
        
        return result
    }
    
    /// Format beta group model to dictionary
    func formatBetaGroup(_ group: ASCBetaGroup) -> [String: Any] {
        var result: [String: Any] = [
            "id": group.id,
            "type": group.type
        ]
        
        result["name"] = group.attributes.name.jsonSafe
        result["createdDate"] = group.attributes.createdDate.jsonSafe
        result["isInternalGroup"] = group.attributes.isInternalGroup.jsonSafe
        result["hasAccessToAllBuilds"] = group.attributes.hasAccessToAllBuilds.jsonSafe
        result["publicLinkEnabled"] = group.attributes.publicLinkEnabled.jsonSafe
        result["publicLinkLimit"] = group.attributes.publicLinkLimit.jsonSafe
        result["publicLinkLimitEnabled"] = group.attributes.publicLinkLimitEnabled.jsonSafe
        result["publicLink"] = group.attributes.publicLink.jsonSafe
        result["publicLinkId"] = group.attributes.publicLinkId.jsonSafe
        result["feedbackEnabled"] = group.attributes.feedbackEnabled.jsonSafe
        result["iosBuildsAvailableForAppleSiliconMac"] = group.attributes.iosBuildsAvailableForAppleSiliconMac.jsonSafe
        result["iosBuildsAvailableForAppleVision"] = group.attributes.iosBuildsAvailableForAppleVision.jsonSafe

        if let relationships = group.relationships {
            var relationIds: [String: Any] = [:]
            if let app = relationships.app?.data {
                relationIds["appId"] = app.id
            }
            if let builds = relationships.builds?.data {
                relationIds["buildIds"] = builds.map(\.id)
            }
            if let testers = relationships.betaTesters?.data {
                relationIds["betaTesterIds"] = testers.map(\.id)
            }
            if let criteria = relationships.betaRecruitmentCriteria?.data {
                relationIds["betaRecruitmentCriteriaId"] = criteria.id
            }
            if let compatibilityURL = relationships.betaRecruitmentCriterionCompatibleBuildCheck?.links?.related {
                relationIds["betaRecruitmentCriterionCompatibleBuildCheckURL"] = compatibilityURL
            }
            result["relationships"] = relationIds
        }
        
        return result
    }
    
    /// Format beta tester model to dictionary
    func formatBetaTester(_ tester: ASCBetaTester) -> [String: Any] {
        var result: [String: Any] = [
            "id": tester.id,
            "type": tester.type
        ]
        
        result["email"] = tester.attributes.email.jsonSafe
        result["firstName"] = tester.attributes.firstName.jsonSafe
        result["lastName"] = tester.attributes.lastName.jsonSafe
        result["inviteType"] = tester.attributes.inviteType.jsonSafe
        result["state"] = tester.attributes.state.jsonSafe
        result["appDevices"] = tester.attributes.appDevices.map { devices in
            devices.map { device in
                [
                    "model": device.model.jsonSafe,
                    "platform": (device.platform?.rawValue).jsonSafe,
                    "osVersion": device.osVersion.jsonSafe,
                    "appBuildVersion": device.appBuildVersion.jsonSafe
                ] as [String: Any]
            }
        }.jsonSafe
        
        return result
    }
    
    // MARK: - Legacy Parsers (kept for compatibility)
    
    /// Parse beta detail data
    func parseBetaDetail(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let id = data["id"] as? String {
            result["id"] = id
        }
        
        if let attributes = data["attributes"] as? [String: Any] {
            result["autoNotifyEnabled"] = attributes["autoNotifyEnabled"] as? Bool ?? false
            result["internalBuildState"] = attributes["internalBuildState"] as? String
            result["externalBuildState"] = attributes["externalBuildState"] as? String
        }
        
        // Parse relationships
        if let relationships = data["relationships"] as? [String: Any] {
            var rels: [String: Any] = [:]
            
            if let build = relationships["build"] as? [String: Any],
               let buildData = build["data"] as? [String: Any],
               let buildId = buildData["id"] as? String {
                rels["buildId"] = buildId
            }
            
            if let localizations = relationships["betaBuildLocalizations"] as? [String: Any],
               let localizationLinks = localizations["links"] as? [String: Any],
               let related = localizationLinks["related"] as? String {
                rels["localizationsLink"] = related
            }
            
            result["relationships"] = rels
        }
        
        return result
    }
    
    /// Parse beta build localization data
    func parseBetaBuildLocalization(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let id = data["id"] as? String {
            result["id"] = id
        }

        if let type = data["type"] as? String {
            result["type"] = type
        }
        
        if let attributes = data["attributes"] as? [String: Any] {
            result["locale"] = attributes["locale"] as? String
            result["whatsNew"] = attributes["whatsNew"] as? String
        }

        if let relationships = data["relationships"] as? [String: Any],
           let build = relationships["build"] as? [String: Any],
           let linkage = build["data"] as? [String: Any],
           let type = linkage["type"] as? String,
           let id = linkage["id"] as? String {
            result["build"] = ["type": type, "id": id]
        }
        
        return result
    }
    
    /// Parse beta group data
    func parseBetaGroup(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let id = data["id"] as? String {
            result["id"] = id
        }
        
        if let attributes = data["attributes"] as? [String: Any] {
            result["name"] = attributes["name"] as? String
            result["createdDate"] = attributes["createdDate"] as? String
            result["isInternalGroup"] = attributes["isInternalGroup"] as? Bool ?? false
            result["hasAccessToAllBuilds"] = attributes["hasAccessToAllBuilds"] as? Bool ?? false
            result["publicLinkEnabled"] = attributes["publicLinkEnabled"] as? Bool ?? false
            result["publicLinkLimit"] = attributes["publicLinkLimit"] as? Int
            result["publicLinkLimitEnabled"] = attributes["publicLinkLimitEnabled"] as? Bool ?? false
            result["publicLink"] = attributes["publicLink"] as? String
            result["publicLinkId"] = attributes["publicLinkId"] as? String
            result["feedbackEnabled"] = attributes["feedbackEnabled"] as? Bool ?? false
        }
        
        return result
    }
    
    /// Parse beta tester data
    func parseBetaTester(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let id = data["id"] as? String {
            result["id"] = id
        }
        
        if let attributes = data["attributes"] as? [String: Any] {
            result["email"] = attributes["email"] as? String
            result["firstName"] = attributes["firstName"] as? String
            result["lastName"] = attributes["lastName"] as? String
            result["inviteType"] = attributes["inviteType"] as? String
            result["state"] = attributes["state"] as? String
        }
        
        return result
    }
}
