import Foundation

/// A nullable App Store Connect value that preserves explicit JSON null separately from omission.
public enum ASCNullable<Value: Codable & Sendable>: Codable, Sendable {
    case value(Value)
    case null

    /// Decodes either a concrete value or an explicit JSON null.
    /// - Parameter decoder: Decoder positioned at the nullable value.
    /// - Throws: A decoding error when the payload is neither the expected value nor null.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            self = .value(try container.decode(Value.self))
        }
    }

    /// Encodes the concrete value or an explicit JSON null.
    /// - Parameter encoder: Encoder that receives the nullable value.
    /// - Throws: An encoding error when the value cannot be written.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension ASCNullable: Equatable where Value: Equatable {}

extension KeyedDecodingContainer {
    func decodeASCNullable<Value: Codable & Sendable>(
        _ type: Value.Type,
        forKey key: Key
    ) throws -> ASCNullable<Value>? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return .null
        }
        return .value(try decode(type, forKey: key))
    }
}
