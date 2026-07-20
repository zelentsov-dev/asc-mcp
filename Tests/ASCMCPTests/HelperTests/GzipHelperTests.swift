import Compression
import Foundation
import Testing
@testable import asc_mcp

@Suite("GzipHelper Tests")
struct GzipHelperTests {
    @Test func isGzipped_validMagicBytes() {
        #expect(Data([0x1F, 0x8B, 0x08, 0x00]).isGzipped)
    }

    @Test func isGzipped_invalidData() {
        #expect(!Data([0x50, 0x4B, 0x03, 0x04]).isGzipped)
    }

    @Test func isGzipped_emptyData() {
        #expect(!Data().isGzipped)
    }

    @Test func isGzipped_singleByte() {
        #expect(!Data([0x1F]).isGzipped)
    }

    @Test func gunzipped_tooSmallData() {
        #expect(throws: GzipError.self) {
            try Data([0x1F, 0x8B]).gunzipped()
        }
    }

    @Test func gunzipped_invalidMagic() {
        #expect(throws: GzipError.self) {
            try Data(repeating: 0, count: 20).gunzipped()
        }
    }

    @Test func gunzipped_validGzipRoundtrip() throws {
        let original = "Hello\tWorld\nFoo\tBar\n"
        let decompressed = try gzipCompress(Data(original.utf8)).gunzipped()

        #expect(String(data: decompressed, encoding: .utf8) == original)
    }

    @Test func gunzipped_tsvReportData() throws {
        let tsv = "Provider\tSKU\tUnits\nAPPLE\tcom.app\t10\nAPPLE\tcom.app2\t5\n"
        let result = try gzipCompress(Data(tsv.utf8)).gunzipped()

        #expect(String(data: result, encoding: .utf8) == tsv)
    }

    @Test func gunzipped_validHeaderCRC() throws {
        let original = Data("header checksum".utf8)
        let compressed = try gzipWithHeaderCRC(original)

        #expect(try compressed.gunzipped() == original)
    }

    @Test func gunzipped_rejectsUnsupportedMethod() throws {
        var compressed = try gzipCompress(Data("method".utf8))
        compressed[2] = 0

        #expect(throws: GzipError.unsupportedCompressionMethod(0)) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsReservedFlags() throws {
        var compressed = try gzipCompress(Data("flags".utf8))
        compressed[3] = 0x20

        #expect(throws: GzipError.reservedFlags(0x20)) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsMalformedExtraField() {
        let malformed = Data([
            0x1F, 0x8B, 0x08, 0x04, 0, 0, 0, 0, 0, 0,
            0xFF, 0xFF,
            0, 0, 0, 0, 0, 0, 0, 0
        ])

        #expect(throws: GzipError.self) {
            try malformed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsUnterminatedFileName() {
        let malformed = Data([
            0x1F, 0x8B, 0x08, 0x08, 0, 0, 0, 0, 0, 0,
            0x41,
            0, 0, 0, 0, 0, 0, 0, 0
        ])

        #expect(throws: GzipError.self) {
            try malformed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsBadHeaderCRC() throws {
        var compressed = try gzipWithHeaderCRC(Data("header checksum".utf8))
        compressed[10] ^= 0xFF

        #expect(throws: GzipError.headerChecksumMismatch) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsBadDataCRC() throws {
        var compressed = try gzipCompress(Data("data checksum".utf8))
        compressed[compressed.count - 8] ^= 0xFF

        #expect {
            try compressed.gunzipped()
        } throws: { error in
            guard let gzipError = error as? GzipError,
                  case .checksumMismatch = gzipError else { return false }
            return true
        }
    }

    @Test func gunzipped_rejectsSizeMismatch() throws {
        let original = Data("size mismatch".utf8)
        var compressed = try gzipCompress(original)
        writeLittleEndian(UInt32(original.count - 1), to: &compressed, at: compressed.count - 4)

        #expect {
            try compressed.gunzipped()
        } throws: { error in
            guard let gzipError = error as? GzipError,
                  case .decompressedSizeMismatch = gzipError else { return false }
            return true
        }
    }

    @Test func gunzipped_rejectsAdvertisedSizeLargerThanOutput() throws {
        let original = Data("short output".utf8)
        var compressed = try gzipCompress(original)
        writeLittleEndian(UInt32(original.count + 1), to: &compressed, at: compressed.count - 4)

        #expect(throws: GzipError.decompressedSizeMismatch(
            expected: UInt32(original.count + 1),
            actual: original.count
        )) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsMaliciousISIZEBeforeAllocation() throws {
        var compressed = try gzipCompress(Data("small payload".utf8))
        writeLittleEndian(UInt32.max, to: &compressed, at: compressed.count - 4)

        #expect(throws: GzipError.decompressedSizeLimitExceeded(limit: 1_024, advertised: .max)) {
            try compressed.gunzipped(maximumDecompressedSize: 1_024)
        }
    }

    @Test func gunzipped_enforcesExplicitSizeLimit() throws {
        let compressed = try gzipCompress(Data(repeating: 0x41, count: 2_048))

        #expect(throws: GzipError.decompressedSizeLimitExceeded(limit: 1_024, advertised: 2_048)) {
            try compressed.gunzipped(maximumDecompressedSize: 1_024)
        }
    }

    @Test func gunzipped_rejectsInvalidMaximumSize() throws {
        let compressed = try gzipCompress(Data("limit".utf8))

        #expect(throws: GzipError.invalidMaximumSize) {
            try compressed.gunzipped(maximumDecompressedSize: 0)
        }
    }

    @Test func gunzipped_rejectsTruncatedPayload() throws {
        let compressed = try gzipCompress(Data(repeating: 0x41, count: 128))
        let truncated = Data(compressed.dropLast(9))

        #expect(throws: GzipError.self) {
            try truncated.gunzipped()
        }
    }

    @Test func gunzipped_rejectsTrailingMemberData() throws {
        var compressed = try gzipCompress(Data("trailing data".utf8))
        let trailer = Data(compressed.suffix(8))
        compressed.append(trailer)

        #expect(throws: GzipError.trailingData) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsConcatenatedMembers() throws {
        var compressed = try gzipCompress(Data("first".utf8))
        compressed.append(try gzipCompress(Data("second".utf8)))

        #expect(throws: GzipError.trailingData) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_rejectsConcatenatedMemberWithSmallerFinalSize() throws {
        var compressed = try gzipCompress(Data("first member is longer".utf8))
        compressed.append(try gzipCompress(Data("x".utf8)))

        #expect(throws: GzipError.decompressedSizeMismatch(expected: 1, actual: 2)) {
            try compressed.gunzipped()
        }
    }

    @Test func gunzipped_alreadyDecompressed() {
        #expect(throws: GzipError.self) {
            try Data("plain text".utf8).gunzipped()
        }
    }

    private func gzipCompress(_ data: Data) throws -> Data {
        let destinationSize = max(data.count + 512, 512)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { source -> Int in
            guard let sourceBaseAddress = source.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                destinationSize,
                sourceBaseAddress.assumingMemoryBound(to: UInt8.self),
                source.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard compressedSize > 0 else {
            throw GzipTestError.compressionFailed
        }

        var result = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0, 0xFF])
        result.append(destinationBuffer, count: compressedSize)
        appendLittleEndian(crc32(data), to: &result)
        appendLittleEndian(UInt32(truncatingIfNeeded: data.count), to: &result)
        return result
    }

    private func gzipWithHeaderCRC(_ data: Data) throws -> Data {
        let compressed = try gzipCompress(data)
        var header = Data(compressed.prefix(10))
        header[3] = 0x02
        let headerCRC = UInt16(truncatingIfNeeded: crc32(header))

        var result = header
        result.append(UInt8(truncatingIfNeeded: headerCRC))
        result.append(UInt8(truncatingIfNeeded: headerCRC >> 8))
        result.append(contentsOf: compressed.dropFirst(10))
        return result
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ UInt32.max
    }

    private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private func writeLittleEndian(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}

private enum GzipTestError: Error {
    case compressionFailed
}
