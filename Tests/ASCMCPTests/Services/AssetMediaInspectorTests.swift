import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import asc_mcp

@Suite("Asset Media Inspector Tests")
struct AssetMediaInspectorTests {
    @Test("malformed reference ranges fail without trapping")
    func malformedRanges() throws {
        let invalidBounds: [[String: JSONValue]] = [
            ["minWidth": .int(201), "maxWidth": .int(200), "minHeight": .int(1), "maxHeight": .int(200)],
            ["minWidth": .int(1), "maxWidth": .int(200), "minHeight": .int(201), "maxHeight": .int(200)],
            ["minWidth": .double(.nan), "maxWidth": .int(200), "minHeight": .int(1), "maxHeight": .int(200)],
            ["minWidth": .int(0), "maxWidth": .double(.infinity), "minHeight": .int(1), "maxHeight": .int(200)]
        ]
        for bounds in invalidBounds {
            var malformed = imageSpec()
            malformed["dimensions"] = .object(bounds)
            #expect(throws: AssetLibraryError.self) {
                _ = try AssetMediaInspector.matchingSpecs(snapshot: placeholder(), facts: facts(), specs: [.object(malformed)])
            }
            #expect(try AssetMediaInspector.matchingSpecs(
                snapshot: placeholder(), facts: facts(), specs: [.object(malformed), .object(imageSpec())]
            ) == ["test-spec"])
        }
    }

    @Test("aspect ratio is enforced within otherwise valid dimension ranges")
    func aspectRatio() throws {
        #expect(try AssetMediaInspector.matchingSpecs(
            snapshot: placeholder(), facts: facts(width: 160, height: 90), specs: [.object(imageSpec())]
        ) == ["test-spec"])
        #expect(throws: AssetLibraryError.self) {
            _ = try AssetMediaInspector.matchingSpecs(
                snapshot: placeholder(), facts: facts(width: 100, height: 100), specs: [.object(imageSpec())]
            )
        }
        for value in ["16:0", "0:9", "NaN:9", "Infinity:1", "-16:9", "16/9"] {
            var spec = imageSpec()
            spec["aspectRatio"] = .string(value)
            #expect(throws: AssetLibraryError.self) {
                _ = try AssetMediaInspector.matchingSpecs(snapshot: placeholder(), facts: facts(), specs: [.object(spec)])
            }
        }
    }

    @Test("video facts and catalog ranges remain finite and bounded")
    func boundedVideoFacts() throws {
        var spec = imageSpec()
        spec["fileExtensions"] = .array([.string("mp4")])
        spec["mimeTypes"] = .array([.string("video/mp4")])
        spec["duration"] = .object(["min": .string("PT1S"), "max": .string("PT30S")])
        spec["frameRates"] = .array([.object(["minFps": .int(24), "maxFps": .int(30)])])
        for (duration, fps) in [(Double.infinity, 30.0), (20.0, Double.nan), (601.0, 30.0), (20.0, 241.0), (20.0, 0.0)] {
            let video = AssetMediaFacts(width: 160, height: 90, mimeType: "video/mp4", hasAlpha: false, duration: duration, framesPerSecond: fps, hasAudio: false)
            #expect(throws: AssetLibraryError.self) {
                _ = try AssetMediaInspector.matchingSpecs(snapshot: placeholder("mp4"), facts: video, specs: [.object(spec)])
            }
        }
        let validVideo = AssetMediaFacts(width: 160, height: 90, mimeType: "video/mp4", hasAlpha: false, duration: 20, framesPerSecond: 30, hasAudio: false)
        var reversedDuration = spec
        reversedDuration["duration"] = .object(["min": .string("PT30S"), "max": .string("PT1S")])
        var reversedFrameRate = spec
        reversedFrameRate["frameRates"] = .array([.object(["minFps": .int(60), "maxFps": .int(24)])])
        for malformed in [reversedDuration, reversedFrameRate] {
            #expect(throws: AssetLibraryError.self) {
                _ = try AssetMediaInspector.matchingSpecs(snapshot: placeholder("mp4"), facts: validVideo, specs: [.object(malformed)])
            }
        }
        #expect(AssetMediaInspector.durationSeconds("PT1M2.5S") == 62.5)
        #expect(AssetMediaInspector.durationSeconds("PT") == nil)
        #expect(AssetMediaInspector.durationSeconds("PT" + String(repeating: "9", count: 400) + "S") == nil)
        #expect(AssetMediaInspector.durationSeconds("PT١S") == nil)
    }

    @Test("snapshot rejects symbolic links, directories, devices, and FIFOs")
    func rejectsSpecialFiles() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try Data([1, 2, 3, 4]).write(to: source)
        let link = directory.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let fifo = directory.appendingPathComponent("fifo.png")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        for path in [link.path, directory.path, fifo.path, "/dev/null"] {
            #expect(throws: AssetLibraryError.self) {
                _ = try AssetMediaInspector.snapshot(path: path, directory: directory)
            }
        }
    }

    @Test("snapshot remains independent of source and detects tampering")
    func snapshotIntegrity() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try Data([1, 2, 3, 4]).write(to: source)
        let (snapshot, digest) = try AssetMediaInspector.snapshot(path: source.path, directory: directory)
        defer { snapshot.discard() }
        try Data([5, 6, 7, 8]).write(to: source)
        #expect(try AssetMediaInspector.sha256(snapshot) == digest)
        let handle = try FileHandle(forWritingTo: snapshot.url)
        try handle.write(contentsOf: Data([9, 9, 9, 9]))
        try handle.close()
        #expect(try AssetMediaInspector.sha256(snapshot) != digest)
        #expect(chmod(snapshot.url.path, 0o644) == 0)
        #expect(throws: AssetLibraryError.self) { _ = try AssetMediaInspector.sha256(snapshot) }
        #expect(chmod(snapshot.url.path, 0o600) == 0)
        try FileManager.default.removeItem(at: snapshot.url)
        try FileManager.default.createSymbolicLink(at: snapshot.url, withDestinationURL: source)
        #expect(throws: AssetLibraryError.self) { _ = try AssetMediaInspector.sha256(snapshot) }
    }

    @Test("image inspection decodes pixels and preserves alpha evidence")
    func imageDecodingAndAlpha() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makePNG(in: directory)
        let (snapshot, _) = try AssetMediaInspector.snapshot(path: source.path, directory: directory)
        defer { snapshot.discard() }
        let inspected = try await AssetMediaInspector.inspect(snapshot, kind: .image)
        #expect(inspected.width == 4 && inspected.height == 4)
        #expect(inspected.mimeType == "image/png")
        #expect(inspected.hasAlpha)
    }

    @Test("image header without pixels and misleading extensions are rejected")
    func rejectsIncompleteAndMislabeledImages() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makePNG(in: directory)
        let bytes = try Data(contentsOf: source)
        let truncated = directory.appendingPathComponent("truncated.png")
        try bytes.prefix(33).write(to: truncated)
        let misleading = directory.appendingPathComponent("misleading.jpeg")
        try bytes.write(to: misleading)
        for url in [truncated, misleading] {
            let (snapshot, _) = try AssetMediaInspector.snapshot(path: url.path, directory: directory)
            defer { snapshot.discard() }
            await #expect(throws: AssetLibraryError.self) {
                _ = try await AssetMediaInspector.inspect(snapshot, kind: .image)
            }
        }
    }

    @Test("a complete H264 video is decoded and audio requirements are enforced")
    func completeVideoDecoding() async throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/asset-inspection-video.mp4").standardizedFileURL
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (snapshot, _) = try AssetMediaInspector.snapshot(path: source.path, directory: directory)
        defer { snapshot.discard() }
        let facts = try await AssetMediaInspector.inspect(snapshot, kind: .video)
        #expect(facts.width == 32 && facts.height == 32)
        #expect(facts.mimeType == "video/mp4")
        #expect(abs((facts.duration ?? 0) - 1) < 0.01)
        #expect(abs((facts.framesPerSecond ?? 0) - 30) < 0.01)
        #expect(!facts.hasAudio && !facts.hasAlpha)
        var spec = imageSpec()
        spec["aspectRatio"] = .string("1:1")
        spec["maxFileSize"] = .int(1_000_000)
        spec["fileExtensions"] = .array([.string("mp4")])
        spec["mimeTypes"] = .array([.string("video/mp4")])
        spec["duration"] = .object(["min": .string("PT0.5S"), "max": .string("PT2S")])
        spec["frameRates"] = .array([.object(["minFps": .int(24), "maxFps": .int(30)])])
        #expect(try AssetMediaInspector.matchingSpecs(snapshot: snapshot, facts: facts, specs: [.object(spec)]) == ["test-spec"])
        spec["audioRequired"] = .bool(true)
        #expect(throws: AssetLibraryError.self) {
            _ = try AssetMediaInspector.matchingSpecs(snapshot: snapshot, facts: facts, specs: [.object(spec)])
        }
    }

    @Test("video MIME comes from container bytes and incomplete media never passes inspection")
    func videoContentSignature() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("misleading.mov")
        try ftyp(brand: "mp42").write(to: source)
        let (snapshot, _) = try AssetMediaInspector.snapshot(path: source.path, directory: directory)
        defer { snapshot.discard() }
        #expect(try AssetMediaInspector.videoMIMEType(snapshot) == "video/mp4")
        await #expect(throws: AssetLibraryError.self) { _ = try await AssetMediaInspector.inspect(snapshot, kind: .video) }

        let incomplete = directory.appendingPathComponent("incomplete.mp4")
        try ftyp(brand: "mp42").write(to: incomplete)
        let (incompleteSnapshot, _) = try AssetMediaInspector.snapshot(path: incomplete.path, directory: directory)
        defer { incompleteSnapshot.discard() }
        do {
            _ = try await AssetMediaInspector.inspect(incompleteSnapshot, kind: .video)
            Issue.record("A container header without video samples passed inspection")
        } catch {}

        let invalid = directory.appendingPathComponent("invalid.mp4")
        try Data([0, 0, 0, 4] + Array("ftyp".utf8)).write(to: invalid)
        let (invalidSnapshot, _) = try AssetMediaInspector.snapshot(path: invalid.path, directory: directory)
        defer { invalidSnapshot.discard() }
        #expect(throws: AssetLibraryError.self) { _ = try AssetMediaInspector.videoMIMEType(invalidSnapshot) }
    }

    private func imageSpec() -> [String: JSONValue] {
        ["specId": .string("test-spec"),
         "dimensions": .object(["minWidth": .int(1), "maxWidth": .int(200), "minHeight": .int(1), "maxHeight": .int(200)]),
         "aspectRatio": .string("16:9"), "maxFileSize": .int(1024), "alphaAllowed": .bool(false),
         "fileExtensions": .array([.string("png")]), "mimeTypes": .array([.string("image/png")])]
    }

    private func facts(width: Double = 160, height: Double = 90) -> AssetMediaFacts {
        AssetMediaFacts(width: width, height: height, mimeType: "image/png", hasAlpha: false, duration: nil, framesPerSecond: nil, hasAudio: false)
    }

    private func placeholder(_ suffix: String = "png") -> UploadFileSnapshot {
        UploadFileSnapshot(url: URL(fileURLWithPath: "/unused/file." + suffix), fileName: "file." + suffix, fileSize: 512, md5Checksum: "unused")
    }

    private func scratchDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../.build/asset-media-tests").standardizedFileURL
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func makePNG(in directory: URL) throws -> URL {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func ftyp(brand: String) -> Data {
        Data([0, 0, 0, 16] + Array("ftyp".utf8) + Array(brand.utf8) + [0, 0, 0, 0])
    }
}
