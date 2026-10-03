import SwiftUI

@main
struct GifCutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = EditorModel()

    var body: some Scene {
        Window("帧选 · GifCut", id: "editor") {
            ContentView(model: model)
                .tint(Color(red: 0.18, green: 0.55, blue: 0.53))
                .accentColor(Color(red: 0.18, green: 0.55, blue: 0.53))
                .onAppear {
                    delegate.model = model
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if let path = CommandLine.arguments.dropFirst().first, !path.hasPrefix("-") {
                        model.open(URL(fileURLWithPath: path))
                    }
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开视频…", action: model.chooseVideo).keyboardShortcut("o").disabled(model.isExporting)
            }
            CommandMenu("播放") {
                Button("上一帧") { model.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(model.source == nil || model.isExporting)
                Button("下一帧") { model.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(model.source == nil || model.isExporting)
                Button("循环预览片段", action: model.previewSelection).keyboardShortcut("l")
                    .disabled(model.source == nil || model.isExporting)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURL: URL?
    weak var model: EditorModel? {
        didSet {
            if let pendingURL, let model {
                self.pendingURL = nil
                model.open(pendingURL)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isExporting else { return .terminateNow }
        // 让编码任务清理临时文件后退出，避免关闭窗口留下后台 FFmpeg。
        Task {
            await model.finishExportBeforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model?.shutDown() }
    func application(_ sender: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let model { model.open(url) }
        else { pendingURL = url }
    }
}
