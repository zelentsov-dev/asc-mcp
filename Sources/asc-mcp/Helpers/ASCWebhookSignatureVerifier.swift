import CryptoKit
import Foundation

enum ASCWebhookSignatureVerifier {
    static let algorithm = "hmacsha256"

    static func verify(secret: String, payload: Data, signatureHeader: String) -> ASCWebhookSignatureVerification {
        let computed = signatureHex(secret: secret, payload: payload)
        guard let provided = normalizedSignature(from: signatureHeader) else {
            return ASCWebhookSignatureVerification(
                valid: false,
                algorithm: algorithm,
                providedSignature: nil,
                computedSignature: computed,
                reason: "Signature must be a 64-character hex digest, optionally prefixed with 'hmacsha256='"
            )
        }

        let valid = constantTimeEqual(provided, computed)
        return ASCWebhookSignatureVerification(
            valid: valid,
            algorithm: algorithm,
            providedSignature: provided,
            computedSignature: computed,
            reason: valid ? nil : "Computed HMAC does not match the provided x-apple-signature value"
        )
    }

    static func signatureHex(secret: String, payload: Data) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedSignature(from signatureHeader: String) -> String? {
        var value = signatureHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("x-apple-signature:") {
            value = String(value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.lowercased().hasPrefix("\(algorithm)=") {
            value = String(value.dropFirst(algorithm.count + 1))
        }

        let normalized = value.lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return normalized
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let maxCount = max(left.count, right.count)
        var diff = left.count ^ right.count

        for index in 0..<maxCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            diff |= Int(leftByte ^ rightByte)
        }
        return diff == 0
    }
}

struct ASCWebhookSignatureVerification: Sendable {
    let valid: Bool
    let algorithm: String
    let providedSignature: String?
    let computedSignature: String
    let reason: String?

    var dictionary: [String: Any] {
        [
            "success": true,
            "valid": valid,
            "algorithm": algorithm,
            "providedSignature": providedSignature.jsonSafe,
            "computedSignature": computedSignature,
            "reason": reason.jsonSafe,
            "rawPayloadRequired": true
        ]
    }
}
