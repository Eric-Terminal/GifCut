import AppKit
import AVFoundation
import GifCutCore
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class EditorModel {
    let player = AVPlayer()
    var source: URL?
    var videoSize = CGSize(width: 16, height: 9)
    var frameRate: Double = 30
    var range = ClipRange(duration: 0)
    var crop = CropRegion.full
    var drawingCrop = false
    var currentTime: Double = 0
    var isPlaying = false
    var loopSelection = false
    var isLoading = false
    var isExporting = false
    var progress: Double = 0
    var maximumWidth = 480
    var fps = 15
    var encodingPreset = GIFEncodingPreset.balanced
    var customEncoding = GIFEncoding(paletteSize: .colors128, dithering: .ordered)
    var error: String?
    var exportedURL: URL?
    var exportedSize = ""
    var exportedEncodingSummary = ""
    var thumbnails: [NSImage] = []
    var focusedTimeline = false
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var cancellation: ExportCancellation?
    @ObservationIgnored private var loadingID = UUID()
    @ObservationIgnored private var seekID = UUID()

    init() {
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 30.0, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.updatePlayback(time.seconds) }
        }
    }

    var settings: ExportSettings? {
        guard let source else { return nil }
        return ExportSettings(input: source, range: range, crop: crop, videoSize: videoSize,
                              maximumWidth: maximumWidth, fps: fps, encoding: encoding)
    }

    var encoding: GIFEncoding { encodingPreset.encoding ?? customEncoding }

    func selectEncodingPreset(_ preset: GIFEncodingPreset) {
        if preset == .custom { customEncoding = encoding }
        encodingPreset = preset
    }

    var timelineBounds: ClosedRange<Double> {
        guard focusedTimeline else { return 0...max(0.001, range.duration) }
        let span = min(range.duration, max(10, range.length * 3))
        let start = max(0, min(range.start - (span - range.length) / 2, range.duration - span))
        return start...max(start + 0.001, start + span)
    }

    func chooseVideo() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false
        panel.prompt = "打开视频"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !isExporting, url.isFileURL else { return }
        pause()
        loadTask?.cancel()
        thumbnailTask?.cancel()
        let id = UUID()
        loadingID = id
        isLoading = true
        error = nil
        loadTask = Task { [self] in
            do {
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration).seconds
                guard playable, duration.isFinite, duration > 0,
                      let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw MediaError.unplayable
                }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                let rate = try await track.load(.nominalFrameRate)
                try Task.checkCancellation()
                guard id == loadingID else { return }
                source = url
                videoSize = CGSize(width: abs(size.width), height: abs(size.height))
                frameRate = rate > 0 ? Double(rate) : 30
                range = ClipRange(duration: duration)
                crop = .full
                drawingCrop = true
                loopSelection = false
                focusedTimeline = false
                currentTime = 0
                exportedURL = nil
                thumbnails = []
                let item = AVPlayerItem(asset: asset)
                itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "无法解码这个视频。"
                    Task { @MainActor [weak self] in
                        guard self?.loadingID == id else { return }
                        self?.pause()
                        self?.error = message
                    }
                }
                player.replaceCurrentItem(with: item)
                isLoading = false
                generateThumbnails(url, id: id, duration: duration)
            } catch is CancellationError {
                // 新文件接管加载状态，旧任务不再改写界面。
            } catch {
                guard id == loadingID else { return }
                isLoading = false
                self.error = "无法打开视频：\(error.localizedDescription)"
            }
        }
    }

    private func generateThumbnails(_ url: URL, id: UUID, duration: Double) {
        thumbnailTask = Task.detached(priority: .utility) { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 100)
            for index in 0..<12 {
                guard !Task.isCancelled else { return }
                let time = CMTime(seconds: duration * Double(index) / 12, preferredTimescale: 600)
                if let frame = try? await generator.image(at: time) {
                    guard !Task.isCancelled else { return }
                    await self?.appendThumbnail(frame.image, id: id)
                }
            }
        }
    }

    private func appendThumbnail(_ image: CGImage, id: UUID) {
        guard id == loadingID else { return }
        thumbnails.append(NSImage(cgImage: image, size: .zero))
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        guard source != nil, !isLoading else { return }
        if isPlaying { pause(); return }
        if loopSelection && (currentTime < range.start || currentTime >= range.end - 0.01) {
            seek(range.start)
        } else if currentTime >= range.duration - 0.01 {
            seek(0)
        }
        isPlaying = true
        player.play()
    }

    func previewSelection() {
        loopSelection = true
        seek(range.start)
        isPlaying = true
        player.play()
    }

    func seek(_ seconds: Double) {
        let value = min(max(0, seconds), range.duration)
        currentTime = value
        let id = UUID()
        seekID = id
        // 连续拖动时取消前一次定位；播放器的旧进度回调不能把拖动中的游标拉回去。
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: CMTime(seconds: value, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekID == id else { return }
                self.isSeeking = false
            }
        }
        isSeeking = true
    }

    @ObservationIgnored private var isSeeking = false

    func step(_ direction: Double) {
        pause()
        seek(currentTime + direction / frameRate)
    }

    func setStart(_ value: Double) { range.setStart(value) }
    func setEnd(_ value: Double) { range.setEnd(value) }

    func markStart() {
        if currentTime >= range.end { range.move(to: currentTime) }
        range.setStart(currentTime)
    }

    func markEnd() {
        if currentTime <= range.start { range.move(to: max(0, currentTime - range.length)) }
        range.setEnd(currentTime)
    }

    private func updatePlayback(_ seconds: Double) {
        guard seconds.isFinite, !isSeeking else { return }
        currentTime = seconds
        if isPlaying && loopSelection && seconds >= range.end - 0.005 {
            seek(range.start)
            player.play()
        } else if isPlaying && seconds >= range.duration - 0.005 {
            pause()
        }
    }

    func exportGIF() {
        guard let settings, !isExporting else { return }
        pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = settings.input.deletingPathExtension().lastPathComponent + "-片段.gif"
        panel.prompt = "导出 GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        progress = 0
        exportedURL = nil
        let token = ExportCancellation()
        cancellation = token
        exportTask = Task { [self] in
            defer { isExporting = false; cancellation = nil }
            do {
                try await GIFExporter.export(settings, to: url, cancellation: token) { [weak self] value in
                    Task { @MainActor [weak self] in self?.progress = max(self?.progress ?? 0, value) }
                }
                exportedURL = url
                exportedEncodingSummary = settings.encoding.summary
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                exportedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            } catch is CancellationError {
                progress = 0
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancelExport() { cancellation?.cancel() }

    func finishExportBeforeQuitting() async {
        cancelExport()
        await exportTask?.value
    }

    func shutDown() {
        cancellation?.cancel()
        loadTask?.cancel()
        thumbnailTask?.cancel()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }
}

private enum MediaError: LocalizedError {
    case unplayable
    var errorDescription: String? { "这个文件没有可播放的视频轨道。请使用 macOS 支持的视频，例如 H.264 / HEVC 编码的 MP4 或 MOV。" }
}
