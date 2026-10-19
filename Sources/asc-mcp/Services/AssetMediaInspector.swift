import Foundation
import CryptoKit
import Darwin
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import CoreMedia
import CoreVideo
import AudioToolbox

struct AssetMediaFacts: Sendable {
    let width: Double
    let height: Double
    let mimeType: String
    let hasAlpha: Bool
    let duration: Double?
    let framesPerSecond: Double?
    let hasAudio: Bool
}

enum AssetMediaInspector {
    static let maximumFileSize: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumDecodedPixels: Double = 64 * 1_024 * 1_024
    static let maximumVideoDuration: Double = 600
    static let maximumFrameRate: Double = 240

    static func snapshot(path: String, directory: URL = FileManager.default.temporaryDirectory) throws -> (UploadFileSnapshot, String) {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw AssetLibraryError("file_path must be an absolute local file path") }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot open the upload file; symbolic links are not accepted") }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size > 0, before.st_size <= maximumFileSize else {
            throw AssetLibraryError("Upload requires a nonempty regular file of at most 2 GiB")
        }
        let source = URL(fileURLWithPath: path)
        let destination = directory
            .appendingPathComponent("asc-mcp-asset-" + UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        let outputDescriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputDescriptor >= 0 else { throw AssetLibraryError("Cannot create private upload snapshot") }
        let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        var completed = false
        defer {
            try? output.close()
            if !completed { try? FileManager.default.removeItem(at: destination) }
        }
        var sha = SHA256()
        var md5 = Insecure.MD5()
        var count: Int64 = 0
        while let bytes = try input.read(upToCount: 1_024 * 1_024), !bytes.isEmpty {
            try Task.checkCancellation()
            count += Int64(bytes.count)
            guard count <= before.st_size, count <= maximumFileSize else { throw AssetLibraryError("Source file changed while preparing its snapshot") }
            sha.update(data: bytes)
            md5.update(data: bytes)
            try output.write(contentsOf: bytes)
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, count == before.st_size, after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else {
            throw AssetLibraryError("Source file changed while preparing its snapshot")
        }
        try output.synchronize()
        completed = true
        return (UploadFileSnapshot(url: destination, fileName: source.lastPathComponent, fileSize: Int(count), md5Checksum: hex(md5.finalize())), hex(sha.finalize()))
    }

    static func sha256(_ snapshot: UploadFileSnapshot) throws -> String {
        let descriptor = open(snapshot.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Upload snapshot is no longer available") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size == snapshot.fileSize, info.st_mode & 0o077 == 0 else {
            throw AssetLibraryError("Upload snapshot no longer matches its protected file metadata")
        }
        var hash = SHA256()
        var count = 0
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            try Task.checkCancellation()
            count += data.count
            guard count <= snapshot.fileSize else { throw AssetLibraryError("Upload snapshot changed") }
            hash.update(data: data)
        }
        guard count == snapshot.fileSize else { throw AssetLibraryError("Upload snapshot changed") }
        return hex(hash.finalize())
    }

    static func inspect(_ snapshot: UploadFileSnapshot, kind: AssetLibraryKind) async throws -> AssetMediaFacts {
        try Task.checkCancellation()
        if kind == .image {
            guard let source = CGImageSourceCreateWithURL(snapshot.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let type = CGImageSourceGetType(source),
                  let detectedType = UTType(type as String),
                  let extensionType = UTType(filenameExtension: snapshot.url.pathExtension),
                  detectedType.conforms(to: extensionType),
                  let mimeType = detectedType.preferredMIMEType,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw AssetLibraryError("File content is not a supported single image")
            }
            try validateDimensions(width: width.doubleValue, height: height.doubleValue)
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  image.width == width.intValue, image.height == height.intValue else {
                throw AssetLibraryError("Image data could not be completely decoded")
            }
            let alpha: Bool
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: alpha = false
            case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly: alpha = true
            @unknown default: throw AssetLibraryError("Image has an unknown alpha format")
            }
            try Task.checkCancellation()
            return AssetMediaFacts(width: Double(image.width), height: Double(image.height), mimeType: mimeType,
                                   hasAlpha: alpha,
                                   duration: nil, framesPerSecond: nil, hasAudio: false)
        }
        let mimeType = try videoMIMEType(snapshot)
        let extensionName = snapshot.url.pathExtension.lowercased()
        let compatibleExtensions = mimeType == "video/quicktime" ? ["mov"] : ["mp4", "m4v"]
        guard compatibleExtensions.contains(extensionName) else {
            throw AssetLibraryError("Video extension does not match its detected container format")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        let asset = AVURLAsset(url: snapshot.url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let (durationTime, readable, protected) = try await asset.load(.duration, .isReadable, .hasProtectedContent)
        let duration = durationTime.seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard readable, !protected, tracks.count == 1, let track = tracks.first,
              duration.isFinite, duration > 0, duration <= maximumVideoDuration else {
            throw AssetLibraryError("Video must be readable, unprotected, have one video track, and fit the 10 minute local inspection limit")
        }
        let (size, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        try validateDimensions(width: size.width, height: size.height)
        let transformed = CGRect(origin: .zero, size: size).applying(transform).size
        try validateDimensions(width: transformed.width, height: transformed.height)
        guard fps.isFinite, fps > 0, Double(fps) <= maximumFrameRate else {
            throw AssetLibraryError("Video frame rate must be finite, positive, and at most 240 fps for local inspection")
        }
        let (characteristics, formats) = try await track.load(.mediaCharacteristics, .formatDescriptions)
        let alpha = characteristics.contains(.containsAlphaChannel) || formats.contains {
            (CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_Depth) as? NSNumber)?.intValue == 32
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard audio.count <= 8 else { throw AssetLibraryError("Video exceeds the eight audio track local inspection limit") }
        try decodeTrack(asset: asset, track: track, video: true, duration: duration, deadline: deadline)
        for audioTrack in audio {
            try decodeTrack(asset: asset, track: audioTrack, video: false, duration: duration, deadline: deadline)
        }
        return AssetMediaFacts(width: transformed.width, height: transformed.height,
                               mimeType: mimeType, hasAlpha: alpha,
                               duration: duration, framesPerSecond: Double(fps), hasAudio: !audio.isEmpty)
    }

    static func matchingSpecs(snapshot: UploadFileSnapshot, facts: AssetMediaFacts, specs: [JSONValue]) throws -> [String] {
        try validateDimensions(width: facts.width, height: facts.height)
        if let duration = facts.duration {
            guard duration.isFinite, duration > 0, duration <= maximumVideoDuration,
                  let fps = facts.framesPerSecond, fps.isFinite, fps > 0, fps <= maximumFrameRate else {
                throw AssetLibraryError("Video duration or frame rate exceeds local inspection limits")
            }
        }
        let matches = specs.compactMap { value -> String? in
            guard let spec = value.objectValue, let id = spec["specId"]?.stringValue,
                  let dimensions = spec["dimensions"]?.objectValue,
                  let minWidth = number(dimensions["minWidth"]), let maxWidth = number(dimensions["maxWidth"]),
                  let minHeight = number(dimensions["minHeight"]), let maxHeight = number(dimensions["maxHeight"]),
                  minWidth > 0, minHeight > 0, minWidth <= maxWidth, minHeight <= maxHeight,
                  facts.width >= minWidth, facts.width <= maxWidth, facts.height >= minHeight, facts.height <= maxHeight,
                  matchesAspectRatio(spec["aspectRatio"], width: facts.width, height: facts.height),
                  let maxSize = number(spec["maxFileSize"]), maxSize >= 1, snapshot.fileSize > 0, Double(snapshot.fileSize) <= maxSize,
                  strings(spec["fileExtensions"]).map({ $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }).contains(snapshot.url.pathExtension.lowercased()),
                  strings(spec["mimeTypes"]).contains(facts.mimeType) else { return nil }
            if facts.hasAlpha, spec["alphaAllowed"]?.boolValue != true { return nil }
            if let duration = facts.duration {
                guard let range = spec["duration"]?.objectValue,
                      let minimum = durationSeconds(range["min"]?.stringValue), let maximum = durationSeconds(range["max"]?.stringValue),
                      minimum <= maximum,
                      duration >= minimum, duration <= maximum,
                      let fps = facts.framesPerSecond,
                      (spec["frameRates"]?.arrayValue ?? []).contains(where: {
                          guard let r = $0.objectValue, let low = number(r["minFps"]), let high = number(r["maxFps"]), low > 0, low <= high else { return false }
                          return fps >= low - 0.05 && fps <= high + 0.05
                      }) else { return nil }
                if spec["audioRequired"]?.boolValue == true, !facts.hasAudio { return nil }
            }
            return id
        }
        guard !matches.isEmpty else { throw AssetLibraryError("File content does not match any currently available Apple specification") }
        return Array(Set(matches)).sorted()
    }

    static func number(_ value: JSONValue?) -> Double? {
        let result: Double?
        switch value { case .int(let number): result = Double(number); case .double(let number): result = number; default: result = nil }
        return result?.isFinite == true ? result : nil
    }

    static func strings(_ value: JSONValue?) -> [String] { value?.arrayValue?.compactMap(\.stringValue) ?? [] }

    static func durationSeconds(_ value: String?) -> Double? {
        guard let value, value.count <= 64, let regex = try? NSRegularExpression(pattern: "^PT(?:([0-9]+(?:\\.[0-9]+)?)H)?(?:([0-9]+(?:\\.[0-9]+)?)M)?(?:([0-9]+(?:\\.[0-9]+)?)S)?$"),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), value != "PT" else { return nil }
        var total = 0.0
        for index in 1...3 {
            guard let range = Range(match.range(at: index), in: value) else { continue }
            guard let number = Double(value[range]), number.isFinite else { return nil }
            total += number * [3_600.0, 60.0, 1.0][index - 1]
        }
        return total.isFinite ? total : nil
    }

    private static func matchesAspectRatio(_ value: JSONValue?, width: Double, height: Double) -> Bool {
        guard let value else { return true }
        guard let ratio = value.stringValue, ratio.count <= 64 else { return false }
        let parts = ratio.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
              numerator.isFinite, denominator.isFinite, numerator > 0, denominator > 0 else { return false }
        let expected = numerator / denominator
        guard expected.isFinite, expected > 0 else { return false }
        return abs(width - height * expected) <= max(1, expected)
    }

    private static func validateDimensions(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 16_384, height <= 16_384, width * height <= maximumDecodedPixels else {
            throw AssetLibraryError("Media dimensions exceed the 64 megapixel/16384 pixel local inspection limits")
        }
    }

    static func videoMIMEType(_ snapshot: UploadFileSnapshot) throws -> String {
        let descriptor = open(snapshot.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot open video snapshot") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size == snapshot.fileSize, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              snapshot.fileSize > 0, Int64(snapshot.fileSize) <= maximumFileSize else {
            throw AssetLibraryError("Unsafe video snapshot")
        }
        let fileSize = UInt64(snapshot.fileSize)
        var offset: UInt64 = 0
        var movie = false
        var media = false
        for _ in 0..<128 where offset < fileSize {
            try handle.seek(toOffset: offset)
            let header = try handle.read(upToCount: 16) ?? Data()
            guard header.count >= 8, let type = String(data: header[4..<8], encoding: .ascii) else {
                throw AssetLibraryError("Video contains an incomplete container header")
            }
            var length = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let headerSize: UInt64
            if length == 1 {
                guard header.count == 16 else { throw AssetLibraryError("Video contains an incomplete extended container header") }
                length = header[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                headerSize = 16
            } else {
                headerSize = 8
                if length == 0 { length = fileSize - offset }
            }
            guard length >= headerSize, length <= fileSize - offset else { throw AssetLibraryError("Video container length is invalid") }
            if type == "ftyp" {
                guard length >= headerSize + 8 else { throw AssetLibraryError("Video file type header is incomplete") }
                try handle.seek(toOffset: offset + headerSize)
                let data = try handle.read(upToCount: 4) ?? Data()
                guard let brand = String(data: data, encoding: .ascii), data.count == 4 else { throw AssetLibraryError("Unknown video container") }
                if brand == "qt  " { return "video/quicktime" }
                let mp4Brands: Set<String> = ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9", "mp41", "mp42", "avc1", "M4V ", "M4VH", "M4VP", "MSNV"]
                guard mp4Brands.contains(brand) else { throw AssetLibraryError("Video has an unsupported container brand") }
                return "video/mp4"
            }
            movie = movie || type == "moov"
            media = media || type == "mdat"
            offset += length
        }
        guard offset == fileSize, movie, media else { throw AssetLibraryError("Video is not a supported self-contained QuickTime or MPEG-4 container") }
        return "video/quicktime"
    }

    private static func decodeTrack(asset: AVURLAsset, track: AVAssetTrack, video: Bool, duration: Double, deadline: ContinuousClock.Instant) throws {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = video
            ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AssetLibraryError("Media track cannot be decoded for inspection") }
        reader.add(output)
        guard reader.startReading() else { throw AssetLibraryError("Media decoding could not start") }
        defer { reader.cancelReading() }
        var buffers = 0
        var nonempty = 0
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw AssetLibraryError("Media inspection exceeded its two minute time limit") }
            let more = try autoreleasepool { () throws -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                buffers += 1
                guard buffers <= 150_000, CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else {
                    throw AssetLibraryError("Media contains invalid samples or exceeds the local sample count limit")
                }
                if CMSampleBufferGetNumSamples(sample) == 0 { return true }
                nonempty += 1
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard timestamp.isFinite, timestamp >= -1, timestamp <= duration + 1 else { throw AssetLibraryError("Media sample timestamp is outside its duration") }
                if video {
                    guard Double(nonempty) <= ceil(duration * maximumFrameRate) + 1 else {
                        throw AssetLibraryError("Decoded video frame count exceeds the local frame rate limit")
                    }
                    guard let frame = CMSampleBufferGetImageBuffer(sample) else { throw AssetLibraryError("Video frame did not decode") }
                    try validateDimensions(width: Double(CVPixelBufferGetWidth(frame)), height: Double(CVPixelBufferGetHeight(frame)))
                } else {
                    guard let bytes = CMSampleBufferGetDataBuffer(sample), CMBlockBufferGetDataLength(bytes) > 0 else { throw AssetLibraryError("Audio sample did not decode") }
                }
                return true
            }
            if !more { break }
        }
        guard reader.status == .completed, nonempty > 0 else { throw AssetLibraryError("Media track could not be completely decoded") }
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
