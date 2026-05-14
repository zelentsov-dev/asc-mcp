import Foundation

enum ASCWebhookReceiverParser {
    static func parse(_ payloadData: Data) throws -> ASCWebhookParsedPayload {
        let root = try decodeJSONValue(payloadData)
        guard let rootObject = root.objectValue,
              let dataObject = rootObject["data"]?.objectValue else {
            throw ASCError.parsing("Webhook payload must be a JSON:API object with a top-level data object")
        }

        let resourceType = dataObject["type"]?.stringValue
        let eventID = dataObject["id"]?.stringValue
        let attributes = dataObject["attributes"]?.objectValue
        let isWebhookEventEnvelope = resourceType == "webhookEvents"

        let eventType: String?
        let createdDate: String?
        let ping: Bool?
        let payloadText: String?
        let nestedPayload: JSONValue?
        let payloadFormat: String

        if isWebhookEventEnvelope {
            eventType = attributes?["eventType"]?.stringValue
            createdDate = attributes?["createdDate"]?.stringValue
            ping = attributes?["ping"]?.boolValue
            payloadText = attributes?["payload"]?.stringValue

            if let payloadText,
               let payloadData = payloadText.data(using: .utf8),
               let decoded = try? decodeJSONValue(payloadData) {
                nestedPayload = decoded
                payloadFormat = "json"
            } else if payloadText != nil {
                nestedPayload = nil
                payloadFormat = "text"
            } else {
                nestedPayload = nil
                payloadFormat = "none"
            }
        } else {
            eventType = resourceType.map(upperSnakeCase)
            createdDate = attributes?["timestamp"]?.stringValue ?? attributes?["createdDate"]?.stringValue
            ping = nil
            payloadText = nil
            nestedPayload = root
            payloadFormat = "json"
        }

        let relatedResource = relatedResource(from: nestedPayload ?? root)

        return ASCWebhookParsedPayload(
            eventID: eventID,
            resourceType: resourceType,
            eventType: eventType,
            ping: ping,
            createdDate: createdDate,
            payloadFormat: payloadFormat,
            payloadText: payloadText,
            payloadJSON: nestedPayload,
            rawJSON: root,
            relatedResource: relatedResource
        )
    }

    private static func decodeJSONValue(_ data: Data) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ASCError.parsing("Webhook payload is not valid JSON: \(error.localizedDescription)")
        }
    }

    private static func relatedResource(from value: JSONValue) -> ASCWebhookRelatedResource? {
        guard let dataObject = value.objectValue?["data"]?.objectValue else {
            return nil
        }
        if let relationships = dataObject["relationships"]?.objectValue {
            for preferredKey in ["instance", "build", "appStoreVersion", "betaFeedbackCrashSubmission", "betaFeedbackScreenshotSubmission"] {
                if let resource = relationshipResource(named: preferredKey, in: relationships) {
                    return resource
                }
            }
            for key in relationships.keys.sorted() {
                if let resource = relationshipResource(named: key, in: relationships) {
                    return resource
                }
            }
        }
        if let type = dataObject["type"]?.stringValue,
           let id = dataObject["id"]?.stringValue {
            return ASCWebhookRelatedResource(type: type, id: id)
        }
        return nil
    }

    private static func relationshipResource(named key: String, in relationships: [String: JSONValue]) -> ASCWebhookRelatedResource? {
        guard let dataValue = relationships[key]?.objectValue?["data"] else {
            return nil
        }
        if let object = dataValue.objectValue,
           let type = object["type"]?.stringValue,
           let id = object["id"]?.stringValue {
            return ASCWebhookRelatedResource(type: type, id: id)
        }
        if let first = dataValue.arrayValue?.compactMap(\.objectValue).first,
           let type = first["type"]?.stringValue,
           let id = first["id"]?.stringValue {
            return ASCWebhookRelatedResource(type: type, id: id)
        }
        return nil
    }

    private static func upperSnakeCase(_ value: String) -> String {
        guard !value.isEmpty else {
            return value
        }
        if value.contains("_") {
            return value.uppercased()
        }

        var result = ""
        for character in value {
            if character.isUppercase, !result.isEmpty {
                result.append("_")
            }
            result.append(character.uppercased())
        }
        return result
    }
}

struct ASCWebhookParsedPayload: Sendable {
    let eventID: String?
    let resourceType: String?
    let eventType: String?
    let ping: Bool?
    let createdDate: String?
    let payloadFormat: String
    let payloadText: String?
    let payloadJSON: JSONValue?
    let rawJSON: JSONValue
    let relatedResource: ASCWebhookRelatedResource?

    var dictionary: [String: Any] {
        var payload: [String: Any] = [
            "format": payloadFormat,
            "text": payloadText.jsonSafe
        ]
        if let payloadJSON {
            payload["json"] = payloadJSON.asAny
        }

        return [
            "success": true,
            "event": [
                "id": eventID.jsonSafe,
                "resourceType": resourceType.jsonSafe,
                "eventType": eventType.jsonSafe,
                "ping": ping.jsonSafe,
                "createdDate": createdDate.jsonSafe,
                "payloadFormat": payloadFormat,
                "relatedResource": relatedResource?.dictionary ?? NSNull()
            ],
            "payload": payload,
            "recommendedToolCalls": ASCWebhookTriagePolicy.recommendations(
                eventType: eventType,
                relatedResource: relatedResource,
                delivery: .empty
            ).map(\.dictionary)
        ]
    }
}

struct ASCWebhookRelatedResource: Sendable {
    let type: String
    let id: String

    var dictionary: [String: Any] {
        [
            "type": type,
            "id": id
        ]
    }
}

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else {
            return nil
        }
        return object
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else {
            return nil
        }
        return array
    }

    var stringValue: String? {
        guard case .string(let string) = self else {
            return nil
        }
        return string
    }

    var boolValue: Bool? {
        guard case .bool(let bool) = self else {
            return nil
        }
        return bool
    }
}
