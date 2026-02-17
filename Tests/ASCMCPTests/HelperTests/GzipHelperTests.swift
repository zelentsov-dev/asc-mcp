import Testing
import Foundation
import Compression
@testable import asc_mcp

@Suite("GzipHelper Tests")
struct GzipHelperTests {

    @Test func isGzipped_validMagicBytes() {
        let data = Data([0x1F, 0x8B, 0x08, 0x00])
        #expect(data.isGzipped)
    }

    @Test func isGzipped_invalidData() {
        let data = Data([0x50, 0x4B, 0x03, 0x04]) // ZIP magic
        #expect(!data.isGzipped)
    }

    @Test func isGzipped_emptyData() {
        let data = Data()
        #expect(!data.isGzipped)
    }

    @Test func isGzipped_singleByte() {
        let data = Data([0x1F])
        #expect(!data.isGzipped)
    }

    @Test func gunzipped_tooSmallData() {
        let data = Data([0x1F, 0x8B])
        #expect(data.gunzipped() == nil)
    }

    @Test func gunzipped_invalidMagic() {
        let data = Data(repeating: 0x00, count: 20)
        #expect(data.gunzipped() == nil)
    }

    @Test func gunzipped_validGzipRoundtrip() throws {
        // Compress known string, then decompress and verify
        let original = "Hello\tWorld\nFoo\tBar\n"
        let originalData = Data(original.utf8)

        let compressed = try gzipCompress(originalData)
        #expect(compressed.isGzipped)

        let decompressed = compressed.gunzipped()
        #expect(decompressed != nil)
        #expect(String(data: decompressed!, encoding: .utf8) == original)
    }

    @Test func gunzipped_tsvReportData() throws {
        let tsv = "Provider\tSKU\tUnits\nAPPLE\tcom.app\t10\nAPPLE\tcom.app2\t5\n"
        let compressed = try gzipCompress(Data(tsv.utf8))

        let result = compressed.gunzipped()
        #expect(result != nil)
        #expect(String(data: result!, encoding: .utf8) == tsv)
    }

    @Test func gunzipped_alreadyDecompressed() {
        // Plain UTF-8 is not gzip — should return nil
        let data = Data("plain text".utf8)
        #expect(data.gunzipped() == nil)
    }

    // MARK: - Helper

    /// Compress data using gzip format for testing
    private func gzipCompress(_ data: Data) throws -> Data {
        // Build a minimal gzip container:
        // Header (10 bytes) + DEFLATE payload + CRC32 (4 bytes) + ISIZE (4 bytes)

        // Compress with zlib (raw DEFLATE)
        let sourceSize = data.count
        let destinationSize = sourceSize + 512
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { (srcPointer: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = srcPointer.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                destinationSize,
                srcBase.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw GzipTestError.compressionFailed
        }

        var result = Data()

        // Gzip header (10 bytes): magic, method=deflate, flags=0, mtime=0, xfl=0, os=255
        result.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])

        // DEFLATE payload
        result.append(Data(bytes: destinationBuffer, count: compressedSize))

        // CRC32 (placeholder — gunzipped() doesn't verify CRC)
        let crc: UInt32 = 0
        result.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })

        // ISIZE (original size mod 2^32)
        let isize = UInt32(truncatingIfNeeded: sourceSize)
        result.append(contentsOf: withUnsafeBytes(of: isize.littleEndian) { Array($0) })

        return result
    }
}

private enum GzipTestError: Error {
    case compressionFailed
}
