import GifCutCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: EditorModel
    @State private var dropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "crop.rotate").font(.system(size: 23, weight: .medium)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("帧选").font(.system(size: 19, weight: .semibold))
                    Text(model.source?.lastPathComponent ?? "把喜欢的一小段，留成 GIF")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(action: model.chooseVideo) { Label("打开视频", systemImage: "folder") }
                    .keyboardShortcut("o").disabled(model.isExporting)
            }.padding(.horizontal, 24).padding(.vertical, 17)
            Divider()
            if model.source != nil {
                editor
            } else {
                emptyState
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if model.isLoading {
                ZStack { Color.black.opacity(0.25); ProgressView("正在打开视频…").padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
        }
        .overlay {
            if dropTarget { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 3).padding(8).allowsHitTesting(false) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isExporting else { return false }
            model.open(url)
            return true
        } isTargeted: { dropTarget = $0 }
        .alert("没能完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onOpenURL { model.open($0) }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("从一个视频开始").font(.system(size: 24, weight: .semibold))
                Text("拖入视频，选好时间和画面，再导出 GIF。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Button("选择视频…", action: model.chooseVideo).buttonStyle(.borderedProminent).controlSize(.large)
            Text("MP4、MOV 等 macOS 支持的视频 · 全程在本机处理")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Label(model.drawingCrop ? "在画面上拖出选区" : "拖动选区移动，拖动四角缩放", systemImage: "crop")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("重新框选") { model.drawingCrop = true }.controlSize(.small)
                    Button("完整画面") { model.crop = .full; model.drawingCrop = true }.controlSize(.small)
                }
                PlayerCanvas(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                TimelineView(model: model)
            }
            .padding(22)
            .disabled(model.isLoading || model.isExporting)
            Divider()
            VStack(spacing: 16) {
                ScrollView { exportPanel }
                exportControls
            }.frame(width: 250).padding(22)
        }
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("片段", icon: "scissors")
                HStack(spacing: 12) {
                    timeField("起点（秒）", value: model.range.start, setter: model.setStart)
                    timeField("终点（秒）", value: model.range.end, setter: model.setEnd)
                }
                HStack {
                    Button("设为起点", action: model.markStart).keyboardShortcut("i", modifiers: [])
                    Button("设为终点", action: model.markEnd).keyboardShortcut("o", modifiers: [])
                }.controlSize(.small)
                Button(action: model.previewSelection) { Label("循环预览片段", systemImage: "repeat") }.frame(maxWidth: .infinity)
                Toggle("仅循环所选片段", isOn: $model.loopSelection).font(.system(size: 11)).toggleStyle(.checkbox)
            }.disabled(model.isExporting)
            Divider()
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("画面", icon: "viewfinder")
                HStack {
                    Text(model.crop == .full ? "完整画面" : "已裁切").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(model.videoSize.width * model.crop.rect.width)) × \(Int(model.videoSize.height * model.crop.rect.height))")
                        .monospacedDigit()
                }.font(.system(size: 12))
                DisclosureGroup("精确调整选区") {
                    VStack(spacing: 8) {
                        cropField("左", keyPath: \.origin.x)
                        cropField("上", keyPath: \.origin.y)
                        cropField("宽", keyPath: \.size.width)
                        cropField("高", keyPath: \.size.height)
                    }.padding(.top, 8)
                }.font(.system(size: 11))
            }.disabled(model.isExporting)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("GIF", icon: "photo.stack")
                Picker("宽度", selection: $model.maximumWidth) {
                    ForEach([240, 320, 480, 640, 960, 1280], id: \.self) { Text("\($0) px").tag($0) }
                }
                Picker("帧率", selection: $model.fps) {
                    ForEach([10, 12, 15, 20, 24, 30], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("编码方式", selection: Binding(get: { model.encodingPreset }, set: { model.selectEncodingPreset($0) })) {
                    ForEach(GIFEncodingPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if model.encodingPreset == .custom {
                    Picker("颜色上限", selection: $model.customEncoding.paletteSize) {
                        ForEach(GIFPaletteSize.allCases, id: \.self) { Text("\($0.rawValue) 色").tag($0) }
                    }
                    Picker("抖色", selection: $model.customEncoding.dithering) {
                        ForEach(GIFDithering.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.encoding.summary).fontWeight(.medium)
                    Text(model.encoding.dithering.explanation)
                }.font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let settings = model.settings {
                    Text("输出 \(Int(settings.outputSize.width)) × \(Int(settings.outputSize.height)) · \(model.range.length, specifier: "%.2f") 秒")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text("宽度和帧率越低，文件越小。GIF 无声，自动循环。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(model.isExporting)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isExporting {
                VStack(spacing: 10) {
                    ProgressView(value: model.progress)
                    HStack {
                        Text("正在导出 \(Int(model.progress * 100))%").font(.system(size: 11)).monospacedDigit()
                        Spacer()
                        Button("取消", action: model.cancelExport).controlSize(.small)
                    }
                }
            } else {
                if let url = model.exportedURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("已导出 · \(model.exportedSize)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(model.exportedEncodingSummary).foregroundStyle(.secondary)
                        HStack {
                            Button("打开 GIF") { NSWorkspace.shared.open(url) }
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }.controlSize(.small)
                    }.font(.system(size: 11))
                }
                Button(action: model.exportGIF) {
                    Label("导出 GIF…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("e")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
    }

    private func timeField(_ title: String, value: Double, setter: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { value }, set: setter), format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel(title)
        }
    }

    private func cropField(_ title: String, keyPath: WritableKeyPath<CGRect, CGFloat>) -> some View {
        HStack {
            Text(title).frame(width: 18)
            TextField(title, value: Binding(get: { model.crop.rect[keyPath: keyPath] * 100 }, set: { value in
                guard value.isFinite else { return }
                var rect = model.crop.rect
                rect[keyPath: keyPath] = value / 100
                rect.size.width = min(max(0.01, rect.width), 1)
                rect.size.height = min(max(0.01, rect.height), 1)
                rect.origin.x = min(max(0, rect.minX), 1 - rect.width)
                rect.origin.y = min(max(0, rect.minY), 1 - rect.height)
                model.crop = CropRegion(rect: rect)
                model.drawingCrop = false
            }), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder)
            Text("%")
        }.accessibilityLabel("裁切\(title)，百分比")
    }
}
