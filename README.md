# 帧选 · GifCut

一个本机视频转 GIF 小工具：打开视频，拖选片段，在画面上框出区域，然后导出循环 GIF。

使用 SwiftUI、AVFoundation 和电脑现有的 FFmpeg。视频不会上传，原视频不会被修改。

## 使用

双击 `帧选.app`，也可以把视频拖到窗口或应用图标上。

1. **打开视频**：支持 macOS 原生可播放的视频，例如 H.264 / HEVC 编码的 MP4、MOV。文件扩展名本身不能保证编码受支持。
2. **找到片段**：上方播放进度条定位，空格播放或暂停，左右方向键逐帧微调。
3. **选择时间**：下方绿色区域的两端控制起止时间，中间可以整体平移。长视频可以启用「放大片段」。也可以先定位，再按 `I` 设起点、`O` 设终点；右侧支持直接输入秒数。
4. **裁切画面**：直接在视频上拖出矩形。拖动矩形内部移动，拖动四角缩放。「重新框选」重画，「完整画面」取消裁切；「精确调整选区」支持输入百分比。
5. **检查并导出**：「循环预览片段」检查动作衔接，选择 GIF 宽度和帧率，按「导出 GIF…」保存。完成后显示实际文件大小，可打开结果或在 Finder 中查看。

默认宽度 480 px、15 fps。输出保持选区比例，不放大小于目标宽度的画面。GIF 无声且无限循环；减小宽度、帧率或片段时长可以降低文件大小。GIF 时间以百分之一秒存储，帧延时可能发生舍入。

快捷键：`⌘O` 打开，`空格` 播放 / 暂停，`←` / `→` 逐帧，`I` / `O` 标记起止，`⌘L` 循环预览，`⌘E` 导出。

## 构建

需要 macOS 15 或更高版本、Swift 6 工具链，以及 FFmpeg。当前开发电脑已有全部依赖。

```sh
# 换到其他电脑且尚未安装 FFmpeg 时执行
brew install ffmpeg

swift test
bash scripts/build-app.sh
open dist/帧选.app
```

应用位于 `dist/帧选.app`，可复制到 `~/Applications`。构建脚本进行本机临时签名，不包含 Developer ID 公证。FFmpeg 不打包进应用，会从 Homebrew 标准路径或 `PATH` 查找。

开发时可运行 `swift run GifCut`，也可以在 Xcode 中打开 `Package.swift`。可选传入一个本地视频路径：`swift run GifCut /path/to/video.mp4`。

## 实现与验证

- `Sources/GifCut`：原生播放器、画面选区、时间轴和导出界面。
- `Sources/GifCutCore`：时间/裁切几何、FFmpeg 导出和取消控制。
- `Tests/GifCutCoreTests`：选区边界、短视频、真实 GIF 尺寸/颜色/时长/循环次数、旋转视频、特殊文件名、取消和失败时的文件保护。

预览和导出使用同一组归一化裁切坐标，不把播放器黑边算进画面。导出分两遍生成和使用调色板，避免单条 `split` 滤镜缓存整个片段。临时文件放在目标目录，编码成功后才替换目标文件；取消或失败会清理临时文件。

参考：[Apple AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)、[FFmpeg 滤镜文档](https://ffmpeg.org/ffmpeg-filters.html)。
