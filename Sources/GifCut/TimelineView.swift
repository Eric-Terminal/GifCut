import GifCutCore
import SwiftUI

struct TimelineView: View {
    @Bindable var model: EditorModel
    @State private var dragRange: ClipRange?
    @State private var dragBounds: ClosedRange<Double>?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button { model.step(-1) } label: { Image(systemName: "backward.frame.fill") }
                    .help("上一帧（←）")
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 22)
                }.keyboardShortcut(.space, modifiers: []).help("播放 / 暂停（空格）")
                Button { model.step(1) } label: { Image(systemName: "forward.frame.fill") }
                    .help("下一帧（→）")
                Text(timestamp(model.currentTime)).monospacedDigit().font(.system(size: 12))
                Slider(value: Binding(get: { model.currentTime }, set: { model.seek($0) }),
                       in: 0...max(0.001, model.range.duration), onEditingChanged: { editing in if editing { model.pause() } })
                    .accessibilityLabel("视频播放进度")
                Text(timestamp(model.range.duration)).monospacedDigit().font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle(isOn: Binding(get: { model.player.isMuted }, set: { model.player.isMuted = $0 })) {
                    Image(systemName: "speaker.slash.fill")
                }.toggleStyle(.button).help("静音")
            }
            .buttonStyle(.borderless)

            HStack {
                Label("截取片段", systemImage: "timeline.selection").font(.system(size: 12, weight: .semibold))
                Text("拖动两端调整 · 拖动中间平移").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Toggle("放大片段", isOn: $model.focusedTimeline).toggleStyle(.button).controlSize(.small)
            }

            GeometryReader { proxy in
                let width = max(1, proxy.size.width - 24)
                let bounds = dragBounds ?? model.timelineBounds
                let span = bounds.upperBound - bounds.lowerBound
                let left = 12 + (model.range.start - bounds.lowerBound) / span * width
                let right = 12 + (model.range.end - bounds.lowerBound) / span * width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.07))
                    if !model.focusedTimeline && !model.thumbnails.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: max(1, (proxy.size.width - 11) / 12), height: 48).clipped()
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 7)).opacity(0.6)
                    }
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.27))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: max(2, right - left), height: 48).offset(x: left)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            beginDrag(bounds)
                            guard var range = dragRange else { return }
                            range.move(to: range.start + value.translation.width / width * span)
                            model.range = range
                            model.seek(range.start)
                        }.onEnded { _ in endDrag() })
                    handle(x: left, isStart: true, width: width, bounds: bounds)
                    handle(x: right, isStart: false, width: width, bounds: bounds)
                    let playhead = 12 + (model.currentTime - bounds.lowerBound) / span * width
                    if playhead >= 0 && playhead <= proxy.size.width {
                        Rectangle().fill(.white).shadow(color: .black.opacity(0.5), radius: 1)
                            .frame(width: 2, height: 48).offset(x: playhead).allowsHitTesting(false)
                    }
                }
            }.frame(height: 48)

            HStack {
                Text(timestamp(model.timelineBounds.lowerBound))
                Spacer()
                Text("已选 \(model.range.length, specifier: "%.2f") 秒").foregroundStyle(Color.accentColor)
                Spacer()
                Text(timestamp(model.timelineBounds.upperBound))
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func handle(x: Double, isStart: Bool, width: Double, bounds: ClosedRange<Double>) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
            .overlay(Capsule().fill(.white).frame(width: 2, height: 18))
            .frame(width: 12, height: 52).padding(.horizontal, 5)
            .contentShape(Rectangle()).offset(x: x - 11, y: -2)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                beginDrag(bounds)
                guard let initial = dragRange else { return }
                let delta = value.translation.width / width * (bounds.upperBound - bounds.lowerBound)
                if isStart {
                    model.setStart(initial.start + delta)
                    model.seek(model.range.start)
                } else {
                    model.setEnd(initial.end + delta)
                    model.seek(max(model.range.start, model.range.end - 1 / model.frameRate))
                }
            }.onEnded { _ in endDrag() })
            .accessibilityElement()
            .accessibilityLabel(isStart ? "片段起点" : "片段终点")
            .accessibilityValue(timestamp(isStart ? model.range.start : model.range.end))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 1 / model.frameRate : -1 / model.frameRate
                if isStart { model.setStart(model.range.start + delta) }
                else { model.setEnd(model.range.end + delta) }
            }
    }

    private func beginDrag(_ bounds: ClosedRange<Double>) {
        if dragRange == nil { dragRange = model.range; dragBounds = bounds; model.pause() }
    }
    private func endDrag() { dragRange = nil; dragBounds = nil }
}
