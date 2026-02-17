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
        result["feedbackEmail"] = localization.attributes.feedbackEmail.jsonSafe
        result["marketingUrl"] = localization.attributes.marketingUrl.jsonSafe
        result["privacyPolicyUrl"] = localization.attributes.privacyPolicyUrl.jsonSafe
        result["tvOsPrivacyPolicy"] = localization.attributes.tvOsPrivacyPolicy.jsonSafe
        
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
        
        if let attributes = data["attributes"] as? [String: Any] {
            result["locale"] = attributes["locale"] as? String
            result["whatsNew"] = attributes["whatsNew"] as? String
            result["feedbackEmail"] = attributes["feedbackEmail"] as? String
            result["marketingUrl"] = attributes["marketingUrl"] as? String
            result["privacyPolicyUrl"] = attributes["privacyPolicyUrl"] as? String
            result["tvOsPrivacyPolicy"] = attributes["tvOsPrivacyPolicy"] as? String
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