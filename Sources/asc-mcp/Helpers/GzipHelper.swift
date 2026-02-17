//
//  GzipHelper.swift
//  asc-mcp
//
//  Gzip decompression using Apple's Compression framework
//

import Foundation
import Compression

extension Data {
    /// Decompresses gzip-compressed data using Compression framework
    /// - Returns: Decompressed data or nil if input is not valid gzip
    func gunzipped() -> Data? {
        // Minimum gzip: 10-byte header + 8-byte trailer
        guard count >= 18 else { return nil }

        // Verify gzip magic bytes
        let magic = self.prefix(2)
        guard magic[magic.startIndex] == 0x1F,
              magic[magic.startIndex + 1] == 0x8B else {
            return nil
        }

        // Parse gzip header to find start of DEFLATE payload
        var offset = 10 // Skip: magic(2) + method(1) + flags(1) + mtime(4) + xfl(1) + os(1)
        let flags = self[3]

        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= count else { return nil }
            let extraLen = Int(self[offset]) | (Int(self[offset + 1]) << 8)
            offset += 2 + extraLen
        }

        // FNAME — null-terminated string
        if flags & 0x08 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            offset += 1 // skip null terminator
        }

        // FCOMMENT — null-terminated string
        if flags & 0x10 != 0 {
            while offset < count && self[offset] != 0 { offset += 1 }
            offset += 1
        }

        // FHCRC — 2-byte header CRC
        if flags & 0x02 != 0 {
            offset += 2
        }

        guard offset < count - 8 else { return nil }

        // Read expected uncompressed size from trailer (last 4 bytes, little-endian)
        let trailerStart = count - 4
        let expectedSize = UInt32(self[trailerStart])
            | (UInt32(self[trailerStart + 1]) << 8)
            | (UInt32(self[trailerStart + 2]) << 16)
            | (UInt32(self[trailerStart + 3]) << 24)

        // DEFLATE payload is between header and 8-byte trailer (CRC32 + ISIZE)
        let compressedData = self[offset ..< (count - 8)]

        // Allocate destination buffer — use expected size with some headroom
        let bufferSize = Swift.max(Int(expectedSize), compressedData.count * 4)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { (srcPointer: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = srcPointer.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                srcBase.assumingMemoryBound(to: UInt8.self),
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    /// Whether this data starts with gzip magic bytes
    var isGzipped: Bool {
        count >= 2 && self[startIndex] == 0x1F && self[startIndex + 1] == 0x8B
    }
}
