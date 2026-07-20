//
//  GzipHelper.swift
//  asc-mcp
//
//  Gzip container validation and decompression
//

import Foundation
import zlib

enum ReportDataLimits {
    static let maximumDecompressedBytes = 64 * 1_024 * 1_024
    static let maximumTSVColumns = 256
    static let maximumScannedTSVRows = 1_000_000
    static let maximumScannedTSVCells = 10_000_000
    static let maximumRetainedTSVRows = 100_000
    static let maximumRetainedTSVCells = 1_000_000
}

enum GzipError: Error, Equatable, LocalizedError, Sendable {
    case invalidMaximumSize
    case invalidHeader(String)
    case unsupportedCompressionMethod(UInt8)
    case reservedFlags(UInt8)
    case headerChecksumMismatch
    case decompressedSizeLimitExceeded(limit: Int, advertised: UInt32)
    case decompressionFailed
    case trailingData
    case decompressedSizeMismatch(expected: UInt32, actual: Int)
    case checksumMismatch(expected: UInt32, actual: UInt32)

    var errorDescription: String? {
        switch self {
        case .invalidMaximumSize:
            return "The maximum decompressed gzip size must be greater than zero."
        case .invalidHeader(let reason):
            return "Invalid gzip report header: \(reason). Retry the report download."
        case .unsupportedCompressionMethod(let method):
            return "Unsupported gzip compression method \(method); App Store Connect reports must use DEFLATE."
        case .reservedFlags(let flags):
            return "Invalid gzip report flags 0x\(String(flags, radix: 16)); reserved bits are set. Retry the report download."
        case .headerChecksumMismatch:
            return "Gzip report header checksum mismatch; the download is corrupt or incomplete. Retry the report download."
        case .decompressedSizeLimitExceeded(let limit, let advertised):
            return "Gzip report advertises \(advertised) decompressed bytes, exceeding the \(Self.mebibytes(limit)) MiB safety limit. Request a smaller report."
        case .decompressionFailed:
            return "Gzip report DEFLATE payload is corrupt or truncated. Retry the report download."
        case .trailingData:
            return "Gzip report contains trailing or concatenated data and was rejected. Retry the report download."
        case .decompressedSizeMismatch(let expected, let actual):
            return "Gzip report size mismatch: trailer advertises \(expected) bytes but decoding produced \(actual). Retry the report download."
        case .checksumMismatch(let expected, let actual):
            return "Gzip report checksum mismatch: expected 0x\(String(expected, radix: 16)), calculated 0x\(String(actual, radix: 16)). Retry the report download."
        }
    }

    private static func mebibytes(_ bytes: Int) -> Int {
        bytes / (1_024 * 1_024)
    }
}

extension Data {
    /// Decompresses one complete gzip member and validates its header, size, and CRC32 trailer.
    /// - Parameter maximumDecompressedSize: Hard upper bound for decoded bytes.
    /// - Returns: Fully validated decompressed data.
    /// - Throws: ``GzipError`` when the container is malformed, corrupt, truncated, or oversized.
    func gunzipped(
        maximumDecompressedSize: Int = ReportDataLimits.maximumDecompressedBytes
    ) throws -> Data {
        guard maximumDecompressedSize > 0 else {
            throw GzipError.invalidMaximumSize
        }
        guard count >= 18 else {
            throw GzipError.invalidHeader("the container is shorter than the minimum 18 bytes")
        }

        return try withUnsafeBytes { (source: UnsafeRawBufferPointer) throws -> Data in
            guard let sourceBaseAddress = source.baseAddress else {
                throw GzipError.invalidHeader("the container has no bytes")
            }
            guard source[0] == 0x1F, source[1] == 0x8B else {
                throw GzipError.invalidHeader("the magic bytes are missing")
            }
            guard source[2] == 0x08 else {
                throw GzipError.unsupportedCompressionMethod(source[2])
            }

            let flags = source[3]
            guard flags & 0xE0 == 0 else {
                throw GzipError.reservedFlags(flags)
            }

            let trailerOffset = source.count - 8
            var payloadOffset = 10

            if flags & 0x04 != 0 {
                guard payloadOffset <= trailerOffset - 2 else {
                    throw GzipError.invalidHeader("the FEXTRA length is truncated")
                }
                let extraLength = Int(source[payloadOffset]) | (Int(source[payloadOffset + 1]) << 8)
                payloadOffset += 2
                guard extraLength <= trailerOffset - payloadOffset else {
                    throw GzipError.invalidHeader("the FEXTRA field extends beyond the header")
                }
                payloadOffset += extraLength
            }

            if flags & 0x08 != 0 {
                payloadOffset = try Self.offsetAfterNullTerminatedField(
                    source,
                    from: payloadOffset,
                    before: trailerOffset,
                    name: "FNAME"
                )
            }

            if flags & 0x10 != 0 {
                payloadOffset = try Self.offsetAfterNullTerminatedField(
                    source,
                    from: payloadOffset,
                    before: trailerOffset,
                    name: "FCOMMENT"
                )
            }

            if flags & 0x02 != 0 {
                guard payloadOffset <= trailerOffset - 2 else {
                    throw GzipError.invalidHeader("the FHCRC field is truncated")
                }
                let expectedHeaderCRC = Self.littleEndianUInt16(source, at: payloadOffset)
                let headerBytes = UnsafeRawBufferPointer(start: sourceBaseAddress, count: payloadOffset)
                let actualHeaderCRC = UInt16(truncatingIfNeeded: CRC32.checksum(headerBytes))
                guard actualHeaderCRC == expectedHeaderCRC else {
                    throw GzipError.headerChecksumMismatch
                }
                payloadOffset += 2
            }

            guard payloadOffset < trailerOffset else {
                throw GzipError.invalidHeader("the DEFLATE payload is missing")
            }

            let expectedCRC = Self.littleEndianUInt32(source, at: trailerOffset)
            let expectedSize = Self.littleEndianUInt32(source, at: trailerOffset + 4)
            guard UInt64(expectedSize) <= UInt64(maximumDecompressedSize) else {
                throw GzipError.decompressedSizeLimitExceeded(
                    limit: maximumDecompressedSize,
                    advertised: expectedSize
                )
            }

            return try Self.inflateRawDeflate(
                sourceBaseAddress: sourceBaseAddress,
                payloadOffset: payloadOffset,
                payloadCount: trailerOffset - payloadOffset,
                expectedSize: expectedSize,
                expectedCRC: expectedCRC
            )
        }
    }

    /// Whether this data starts with gzip magic bytes.
    var isGzipped: Bool {
        guard count >= 2 else { return false }
        let secondIndex = index(after: startIndex)
        return self[startIndex] == 0x1F && self[secondIndex] == 0x8B
    }

    private static func offsetAfterNullTerminatedField(
        _ source: UnsafeRawBufferPointer,
        from start: Int,
        before end: Int,
        name: String
    ) throws -> Int {
        guard start < end else {
            throw GzipError.invalidHeader("the \(name) field is truncated")
        }
        var offset = start
        while offset < end {
            if source[offset] == 0 {
                return offset + 1
            }
            offset += 1
        }
        throw GzipError.invalidHeader("the \(name) field is not null-terminated")
    }

    private static func inflateRawDeflate(
        sourceBaseAddress: UnsafeRawPointer,
        payloadOffset: Int,
        payloadCount: Int,
        expectedSize: UInt32,
        expectedCRC: UInt32
    ) throws -> Data {
        guard payloadCount <= Int(UInt32.max) else {
            throw GzipError.decompressionFailed
        }

        var stream = z_stream()
        guard inflateInit2_(
            &stream,
            -15,
            zlibVersion(),
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw GzipError.decompressionFailed
        }
        defer { _ = inflateEnd(&stream) }
        stream.next_in = UnsafeMutablePointer<Bytef>(
            mutating: sourceBaseAddress.assumingMemoryBound(to: Bytef.self).advanced(by: payloadOffset)
        )
        stream.avail_in = uInt(payloadCount)

        let expectedByteCount = Int(expectedSize)
        var output = Data()
        output.reserveCapacity(Swift.min(expectedByteCount, 1_024 * 1_024))
        var outputBuffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var crc = CRC32.initialValue

        while true {
            let previousSourceCount = stream.avail_in
            let remainingAdvertisedBytes = expectedByteCount - output.count
            let destinationCount = Swift.min(
                remainingAdvertisedBytes,
                outputBuffer.count - 1
            ) + 1

            let status = outputBuffer.withUnsafeMutableBytes { destination -> Int32 in
                guard let destinationBaseAddress = destination.bindMemory(to: UInt8.self).baseAddress else {
                    return Z_STREAM_ERROR
                }
                stream.next_out = destinationBaseAddress
                stream.avail_out = uInt(destinationCount)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let producedCount = destinationCount - Int(stream.avail_out)

            if status == Z_STREAM_END, stream.avail_in != 0 {
                throw GzipError.trailingData
            }

            if producedCount > 0 {
                guard producedCount <= remainingAdvertisedBytes else {
                    throw GzipError.decompressedSizeMismatch(
                        expected: expectedSize,
                        actual: output.count + producedCount
                    )
                }
                outputBuffer.withUnsafeBytes { producedBytes in
                    let bytes = UnsafeRawBufferPointer(start: producedBytes.baseAddress, count: producedCount)
                    crc = CRC32.update(crc, with: bytes)
                    if let baseAddress = producedBytes.bindMemory(to: UInt8.self).baseAddress {
                        output.append(baseAddress, count: producedCount)
                    }
                }
            }

            if status == Z_STREAM_END {
                break
            }
            guard status == Z_OK else {
                throw GzipError.decompressionFailed
            }
            guard producedCount > 0 || stream.avail_in < previousSourceCount else {
                throw GzipError.decompressionFailed
            }
        }

        guard output.count == expectedByteCount else {
            throw GzipError.decompressedSizeMismatch(expected: expectedSize, actual: output.count)
        }

        let actualCRC = CRC32.finalize(crc)
        guard actualCRC == expectedCRC else {
            throw GzipError.checksumMismatch(expected: expectedCRC, actual: actualCRC)
        }
        return output
    }

    private static func littleEndianUInt16(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private enum CRC32 {
    static let initialValue = UInt32.max

    private static let table: [UInt32] = (0 ..< 256).map { value in
        var entry = UInt32(value)
        for _ in 0 ..< 8 {
            entry = (entry & 1) == 1 ? (entry >> 1) ^ 0xEDB8_8320 : entry >> 1
        }
        return entry
    }

    static func checksum(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        finalize(update(initialValue, with: bytes))
    }

    static func update(_ value: UInt32, with bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc = value
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc
    }

    static func finalize(_ value: UInt32) -> UInt32 {
        value ^ UInt32.max
    }
}
