import Foundation
import CoreGraphics

public struct ExportSettings: Sendable {
    public let input: URL
    public let range: ClipRange
    public let crop: CropRegion
    public let videoSize: CGSize
    public let maximumWidth: Int
    public let fps: Int
    public let encoding: GIFEncoding

    public init(input: URL, range: ClipRange, crop: CropRegion, videoSize: CGSize,
                maximumWidth: Int, fps: Int, encoding: GIFEncoding) {
        self.input = input
        self.range = range
        self.crop = crop
        self.videoSize = videoSize
        self.maximumWidth = maximumWidth
        self.fps = fps
        self.encoding = encoding
    }

    public var outputSize: CGSize {
        let width = max(1, (videoSize.width * crop.rect.width).rounded(.down))
        let height = max(1, (videoSize.height * crop.rect.height).rounded(.down))
        let target = min(width, Double(maximumWidth))
        return CGSize(width: target, height: max(1, (target * height / width).rounded()))
    }

    public var videoFilter: String {
        let rect = crop.rect
        // FFmpeg 先按视频旋转信息还原画面，再按归一化区域裁切；exact 避免色度对齐移动边界。
        return "fps=\(fps),crop=w='max(1,floor(iw*\(decimal(rect.width))))':h='max(1,floor(ih*\(decimal(rect.height))))':x='floor(iw*\(decimal(rect.minX)))':y='floor(ih*\(decimal(rect.minY)))':exact=1,scale=\(Int(outputSize.width)):\(Int(outputSize.height)):flags=lanczos,setsar=1"
    }
}

public enum ExportError: LocalizedError {
    case missingFFmpeg
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFFmpeg: "找不到 FFmpeg。请先在终端运行 brew install ffmpeg，再重新导出。"
        case .failed(let detail): "GIF 导出失败：\(detail)"
        }
    }
}

/// 取消可能来自主线程；进程注册和启动持同一把锁，避免取消后又启动下一遍编码。
public final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    public init() {}

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    fileprivate func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }

    fileprivate func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }

    fileprivate func clear() {
        lock.lock()
        defer { lock.unlock() }
        process = nil
    }
}

public enum GIFExporter {
    public static func executable() -> URL? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/ffmpeg" }
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    public static func export(_ settings: ExportSettings, to destination: URL,
                              cancellation: ExportCancellation,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let executable = executable() else { throw ExportError.missingFFmpeg }
            let fm = FileManager.default
            // 在目标目录编码临时文件，完成后才原子替换；取消和失败都保留原有 GIF。
            let scratch = destination.deletingLastPathComponent()
                .appendingPathComponent(".gifcut-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: scratch, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: scratch) }
            let palette = scratch.appendingPathComponent("palette.png")
            let output = scratch.appendingPathComponent("result.gif")
            let common = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-ss", decimal(settings.range.start),
                          "-t", decimal(settings.range.length), "-i", settings.input.path]
            // 两遍编码只保留一张调色板，避免长片段在 split/palettegen 中缓存所有画面。
            try run(executable, arguments: common + ["-vf", settings.videoFilter + "," + settings.encoding.paletteFilter,
                "-frames:v", "1", "-update", "1", "-progress", "pipe:1", palette.path],
                scratch: scratch, cancellation: cancellation) { value in
                progress(min(0.45, value / settings.range.length * 0.45))
            }
            progress(0.45)
            try run(executable, arguments: common + ["-i", palette.path, "-filter_complex",
                "[0:v:0]\(settings.videoFilter)[v];[v][1:v]\(settings.encoding.useFilter)[out]",
                "-map", "[out]", "-an", "-loop", "0", "-final_delay", String(max(1, Int((100.0 / Double(settings.fps)).rounded()))),
                "-progress", "pipe:1", output.path], scratch: scratch, cancellation: cancellation) { value in
                progress(0.45 + min(0.54, value / settings.range.length * 0.54))
            }
            try cancellation.check()
            guard let size = try fm.attributesOfItem(atPath: output.path)[.size] as? Int, size > 0 else {
                throw ExportError.failed("所选片段没有可导出的画面，请调整起止时间。")
            }
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: output)
            } else {
                try fm.moveItem(at: output, to: destination)
            }
            progress(1)
        }.value
    }

    private static func run(_ executable: URL, arguments: [String], scratch: URL,
                            cancellation: ExportCancellation, progress: (Double) -> Void) throws {
        try cancellation.check()
        let errorURL = scratch.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorHandle
        try cancellation.launch(process)
        defer { cancellation.clear() }
        var pending = ""
        while let data = try pipe.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {
            pending += String(decoding: data, as: UTF8.self)
            while let newline = pending.firstIndex(of: "\n") {
                let line = String(pending[..<newline])
                pending.removeSubrange(...newline)
                if line.hasPrefix("out_time_us="), let value = Double(line.dropFirst(12)) {
                    progress(max(0, value / 1_000_000))
                }
            }
        }
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "编码器异常退出。"
            throw ExportError.failed(String(message.suffix(2000)))
        }
    }
}

private func decimal(_ value: Double) -> String {
    String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
}
