import Foundation

enum ASCPathSegment {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ value: String, field: String = "resource identifier") throws -> String {
        guard !value.isEmpty else {
            throw invalid(field, reason: "must not be empty")
        }

        guard value != ".", value != ".." else {
            throw invalid(field, reason: "must not be a dot path segment")
        }

        guard !value.contains("/"),
              !value.contains("\\"),
              !value.contains("?"),
              !value.contains("#") else {
            throw invalid(field, reason: "must not contain path, query, or fragment separators")
        }

        guard !value.contains("%") else {
            throw invalid(field, reason: "must not contain percent escapes or pre-encoded data")
        }

        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw invalid(field, reason: "must not contain control characters")
        }

        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              !encoded.isEmpty else {
            throw invalid(field, reason: "could not be encoded as one URL path segment")
        }

        return encoded
    }

    private static func invalid(_ field: String, reason: String) -> ASCError {
        ASCError.parsing("Invalid \(field) for an App Store Connect URL: \(reason)")
    }
}

func validatedASCAPIEndpoint(_ endpoint: String) throws -> String {
    guard endpoint.hasPrefix("/v1/") || endpoint.hasPrefix("/v2/") else {
        throw invalidASCAPIEndpoint("must start with /v1/ or /v2/")
    }

    guard !endpoint.hasSuffix("/"),
          !endpoint.contains("//"),
          !endpoint.contains("\\"),
          !endpoint.contains("?"),
          !endpoint.contains("#") else {
        throw invalidASCAPIEndpoint("must be a canonical path without empty, query, or fragment components")
    }

    guard !endpoint.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw invalidASCAPIEndpoint("must not contain control characters")
    }

    guard endpoint.unicodeScalars.allSatisfy({ allowedRawEndpointCharacters.contains($0) }) else {
        throw invalidASCAPIEndpoint("contains an unencoded path character")
    }

    let segments = endpoint.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.first?.isEmpty == true,
          !segments.dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
        throw invalidASCAPIEndpoint("must not contain empty or dot path segments")
    }

    var index = endpoint.startIndex
    while index < endpoint.endIndex {
        guard endpoint[index] == "%" else {
            index = endpoint.index(after: index)
            continue
        }

        let first = endpoint.index(after: index)
        guard first < endpoint.endIndex else {
            throw invalidASCAPIEndpoint("contains an incomplete percent escape")
        }
        let second = endpoint.index(after: first)
        guard second < endpoint.endIndex,
              let high = hexValue(endpoint[first]),
              let low = hexValue(endpoint[second]) else {
            throw invalidASCAPIEndpoint("contains an invalid percent escape")
        }

        let byte = high * 16 + low
        guard !forbiddenPercentEncodedBytes.contains(byte) else {
            throw invalidASCAPIEndpoint("contains a percent-encoded separator, dot, control, or nested escape")
        }
        index = endpoint.index(after: second)
    }

    return endpoint
}

private let allowedRawEndpointCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/%"
)

private let forbiddenPercentEncodedBytes: Set<UInt8> = {
    var bytes = Set(UInt8(0)...UInt8(31))
    bytes.formUnion([UInt8(37), UInt8(46), UInt8(47), UInt8(63), UInt8(92), UInt8(127)])
    return bytes
}()

private func hexValue(_ character: Character) -> UInt8? {
    guard let value = character.asciiValue else {
        return nil
    }

    switch value {
    case 48...57:
        return value - 48
    case 97...102:
        return value - 97 + 10
    case 65...70:
        return value - 65 + 10
    default:
        return nil
    }
}

private func invalidASCAPIEndpoint(_ reason: String) -> ASCError {
    ASCError.parsing("Invalid App Store Connect endpoint: \(reason)")
}
