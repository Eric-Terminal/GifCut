import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import GifCutCore

private let originalEncoding = GIFEncoding(paletteSize: .colors256, dithering: .smooth)

@Suite("真实 FFmpeg 导出", .serialized)
struct ExportTests {
    @Test("不足一个输出帧间隔的片段仍能导出画面")
    func veryShortClip() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("short.mp4")
        try fixture(input)
        var range = ClipRange(duration: 4)
        range.setEnd(0.04)
        let settings = ExportSettings(input: input, range: range, crop: .full,
                                      videoSize: CGSize(width: 320, height: 240), maximumWidth: 80, fps: 10, encoding: originalEncoding)
        let output = folder.appendingPathComponent("short.gif")
        try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) >= 1)
    }

    @Test("正确截取时间、裁切画面、设置尺寸与无限循环；支持特殊文件名")
    func croppedGIF() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("视频 空格 ' $().mp4")
        try fixture(input)
        var range = ClipRange(duration: 4)
        range.setStart(2.25)
        range.setEnd(3.25)
        let settings = ExportSettings(input: input, range: range,
            crop: CropRegion(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            videoSize: CGSize(width: 320, height: 240), maximumWidth: 80, fps: 10, encoding: originalEncoding)
        let output = folder.appendingPathComponent("结果.gif")
        try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        let properties = try #require(CGImageSourceCopyProperties(source, nil) as? [String: Any])
        let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        #expect(gif[kCGImagePropertyGIFLoopCount as String] as? Int == 0)
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let frameProperties = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let frameGIF = try #require(frameProperties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            duration += (frameGIF[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? 0
        }
        #expect(abs(duration - 1) < 0.02)
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame.width == 80 && frame.height == 60)
        let rgb = try color(frame, at: CGPoint(x: 0.5, y: 0.5))
        // 起点在 2 秒之后，上左象限应从红色变成品红；同时验证时间定位和裁切原点。
        #expect(rgb.0 > 210 && rgb.1 < 40 && rgb.2 > 210)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".gifcut-") })
    }

    @Test("带旋转信息的视频，导出裁切与原生播放器方向一致")
    func rotatedVideo() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.mp4")
        let input = folder.appendingPathComponent("portrait.mp4")
        try fixture(original)
        try ffmpeg(["-display_rotation", "90", "-i", original.path, "-c", "copy", input.path])
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
        generator.appliesPreferredTrackTransform = true
        let reference = try await generator.image(at: .zero).image
        #expect(reference.width == 240 && reference.height == 320)
        let expected = try color(reference, at: CGPoint(x: 0.75, y: 0.25))
        var range = ClipRange(duration: 4)
        range.setEnd(1)
        let settings = ExportSettings(input: input, range: range,
            crop: CropRegion(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            videoSize: CGSize(width: 240, height: 320), maximumWidth: 120, fps: 10, encoding: originalEncoding)
        let output = folder.appendingPathComponent("portrait.gif")
        try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame.width == 120 && frame.height == 160)
        let actual = try color(frame, at: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(actual.0 - expected.0) < 20 && abs(actual.1 - expected.1) < 20 && abs(actual.2 - expected.2) < 20)
    }

    @Test("取消和失败不覆盖已有文件，成功才替换")
    func safeReplacement() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.mp4")
        let output = folder.appendingPathComponent("existing.gif")
        let original = Data("原来的 GIF 内容".utf8)
        try original.write(to: output)
        var settings = ExportSettings(input: input, range: ClipRange(duration: 1), crop: .full,
                                      videoSize: CGSize(width: 320, height: 240), maximumWidth: 80, fps: 10, encoding: originalEncoding)
        let token = ExportCancellation()
        token.cancel()
        do {
            try await GIFExporter.export(settings, to: output, cancellation: token) { _ in }
            Issue.record("取消后不应继续导出")
        } catch is CancellationError { }
        #expect(try Data(contentsOf: output) == original)
        do {
            try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
            Issue.record("不存在的视频不应导出成功")
        } catch is ExportError { }
        #expect(try Data(contentsOf: output) == original)
        try fixture(input)
        settings = ExportSettings(input: input, range: ClipRange(duration: 1), crop: .full,
                                  videoSize: CGSize(width: 320, height: 240), maximumWidth: 80, fps: 10, encoding: originalEncoding)
        try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
        #expect(try Data(contentsOf: output).starts(with: Data("GIF89a".utf8)))
    }

    @Test("编码过程中取消会终止进程并清理临时文件")
    func cancelDuringEncoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("source.mp4")
        try fixture(input)
        let settings = ExportSettings(input: input, range: ClipRange(duration: 4), crop: .full,
                                      videoSize: CGSize(width: 320, height: 240), maximumWidth: 320, fps: 30, encoding: originalEncoding)
        let output = folder.appendingPathComponent("cancelled.gif")
        let token = ExportCancellation()
        do {
            try await GIFExporter.export(settings, to: output, cancellation: token) { value in
                if value >= 0.45 { token.cancel() }
            }
            Issue.record("编码过程中取消不应返回成功")
        } catch is CancellationError { }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.mp4"])
    }

    @Test("各预设实际限制输出颜色并保持尺寸和帧数", arguments: GIFEncodingPreset.allCases.filter { $0 != .custom })
    func encodingPresets(_ preset: GIFEncodingPreset) async throws {
        let encoding = try #require(preset.encoding)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("gradient.mp4")
        try gradientFixture(input)
        let settings = ExportSettings(input: input, range: ClipRange(duration: 1), crop: .full,
            videoSize: CGSize(width: 96, height: 64), maximumWidth: 96, fps: 10, encoding: encoding)
        let output = folder.appendingPathComponent("\(preset.rawValue).gif")
        try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(frame.width == 96 && frame.height == 64)
        let count = Set(try pixels(frame)).count
        #expect(count <= encoding.paletteSize.rawValue)
        // 渐变素材必须实际使用足够多的颜色，不能用错误的灰度或空白输出通过上限检查。
        #expect(count > encoding.paletteSize.rawValue / 2)
    }

    @Test("自定义 32 色生效，三种抖色生成不同的画面")
    func customEncoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("gradient.mp4")
        try gradientFixture(input)
        var renderedFrames: [[UInt32]] = []
        for dithering in GIFDithering.allCases {
            let encoding = GIFEncoding(paletteSize: .colors32, dithering: dithering)
            let settings = ExportSettings(input: input, range: ClipRange(duration: 1), crop: .full,
                videoSize: CGSize(width: 96, height: 64), maximumWidth: 96, fps: 10, encoding: encoding)
            let output = folder.appendingPathComponent("\(dithering.rawValue).gif")
            try await GIFExporter.export(settings, to: output, cancellation: ExportCancellation()) { _ in }
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let rendered = try pixels(frame)
            #expect(Set(rendered).count <= 32)
            renderedFrames.append(rendered)
        }
        #expect(renderedFrames[0] != renderedFrames[1])
        #expect(renderedFrames[0] != renderedFrames[2])
        #expect(renderedFrames[1] != renderedFrames[2])
    }

    private func gradientFixture(_ output: URL) throws {
        try ffmpeg(["-f", "lavfi", "-i", "nullsrc=s=96x64:r=10:d=1,geq=r='255*X/W':g='255*Y/H':b='255*(1-X/W)'",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", output.path])
    }

    private func pixels(_ image: CGImage) throws -> [UInt32] {
        var values = [UInt32](repeating: 0, count: image.width * image.height)
        try values.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return values
    }

    private func fixture(_ output: URL) throws {
        try ffmpeg(["-f", "lavfi", "-i", "color=red:s=320x240:r=20:d=4,drawbox=x=160:y=0:w=160:h=120:color=green:t=fill,drawbox=x=0:y=120:w=160:h=120:color=blue:t=fill,drawbox=x=160:y=120:w=160:h=120:color=yellow:t=fill,drawbox=x=0:y=0:w=160:h=120:color=magenta:t=fill:enable='gte(t,2)'",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", output.path])
    }

    private func ffmpeg(_ arguments: [String]) throws {
        let process = Process()
        let executable: URL = try #require(GIFExporter.executable())
        process.executableURL = executable
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y"] + arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GifCutTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func color(_ image: CGImage, at point: CGPoint) throws -> (Int, Int, Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let index = (Int(Double(image.height) * point.y) * image.width + Int(Double(image.width) * point.x)) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }
}
