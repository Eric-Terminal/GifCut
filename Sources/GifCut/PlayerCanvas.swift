import AVFoundation
import GifCutCore
import SwiftUI

struct PlayerCanvas: View {
    @Bindable var model: EditorModel

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / model.videoSize.width, proxy.size.height / model.videoSize.height)
            let size = CGSize(width: model.videoSize.width * scale, height: model.videoSize.height * scale)
            ZStack {
                Color.black
                ZStack {
                    NativePlayer(player: model.player)
                    CropOverlay(crop: $model.crop, drawing: $model.drawingCrop, onStart: model.pause)
                        .disabled(model.isExporting)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }
    func updateNSView(_ view: PlayerLayerView, context: Context) { view.playerLayer.player = player }
}

private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError("不支持归档初始化") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct CropOverlay: View {
    @Binding var crop: CropRegion
    @Binding var drawing: Bool
    let onStart: () -> Void
    @State private var initial: CropRegion?
    @State private var mode = -2

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rect = CGRect(x: crop.rect.minX * size.width, y: crop.rect.minY * size.height,
                              width: crop.rect.width * size.width, height: crop.rect.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(rect)
                }.fill(.black.opacity(0.48), style: FillStyle(eoFill: true))
                Rectangle().stroke(.white, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                ForEach(0..<4) { corner in
                    RoundedRectangle(cornerRadius: 2).fill(.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .position(x: corner % 2 == 0 ? rect.minX : rect.maxX,
                                  y: corner < 2 ? rect.minY : rect.maxY)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
                let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                if initial == nil {
                    initial = crop
                    onStart()
                    mode = -2
                    if !drawing && crop != .full {
                        for corner in 0..<4 {
                            let x = corner % 2 == 0 ? rect.minX : rect.maxX
                            let y = corner < 2 ? rect.minY : rect.maxY
                            if hypot(value.startLocation.x - x, value.startLocation.y - y) < 18 { mode = corner; break }
                        }
                        if mode == -2 && crop.rect.contains(start) { mode = -1 }
                    }
                }
                guard let initial else { return }
                if mode >= 0 {
                    crop = initial.resized(corner: mode, to: point)
                } else if mode == -1 {
                    crop = initial.moved(dx: value.translation.width / size.width, dy: value.translation.height / size.height)
                } else {
                    crop = .drawn(from: start, to: point)
                }
            }.onEnded { _ in initial = nil; drawing = false })
            .accessibilityLabel("画面裁切区域")
            .accessibilityHint("拖动框选画面；在选区内拖动可移动，拖动四角可调整大小。也可使用右侧裁切数值。")
        }
    }
}
