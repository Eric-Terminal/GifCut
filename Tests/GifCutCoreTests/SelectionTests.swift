import Foundation
import CoreGraphics
import Testing
@testable import GifCutCore

@Suite("时间和画面选区")
struct SelectionTests {
    @Test("起止时间不交叉，移动保留片段长度")
    func rangeBounds() {
        var range = ClipRange(duration: 100)
        range.setStart(9)
        #expect(abs(range.start - 4.96) < 0.0001)
        range.setEnd(-2)
        #expect(abs(range.length - 0.04) < 0.0001)
        range.setEnd(20)
        let length = range.length
        range.move(to: 200)
        #expect(range.end == 100)
        #expect(abs(range.length - length) < 0.0001)
        range.move(to: -30)
        #expect(range.start == 0)
        range.setStart(.nan)
        #expect(range.start == 0)
    }

    @Test("极短视频仍可选取完整片段")
    func shortVideo() {
        var range = ClipRange(duration: 0.02)
        range.setStart(4)
        range.setEnd(-5)
        #expect(range.start == 0)
        #expect(range.end == 0.02)
    }

    @Test("反向框选和越界拖动保持在画面内")
    func cropBounds() {
        let crop = CropRegion.drawn(from: CGPoint(x: 0.8, y: 0.9), to: CGPoint(x: 0.2, y: 0.3))
        #expect(abs(crop.rect.width - 0.6) < 0.0001)
        #expect(abs(crop.rect.minY - 0.3) < 0.0001)
        let moved = crop.moved(dx: 1, dy: -1)
        #expect(abs(moved.rect.maxX - 1) < 0.0001)
        #expect(moved.rect.minY == 0)
        let resized = crop.resized(corner: 0, to: CGPoint(x: 1, y: -1))
        #expect(abs(resized.rect.width - 0.01) < 0.0001)
        #expect(resized.rect.minY == 0)
        let corner = CropRegion.drawn(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 2, y: 2))
        #expect(corner.rect.maxX <= 1 && corner.rect.maxY <= 1)
    }

    @Test("输出不放大小画面，长时间标签不丢失小时")
    func outputSizeAndTime() {
        let settings = ExportSettings(input: URL(fileURLWithPath: "/tmp/test.mp4"), range: ClipRange(duration: 10),
                                      crop: .full, videoSize: CGSize(width: 320, height: 180), maximumWidth: 640, fps: 15,
                                      encoding: GIFEncoding(paletteSize: .colors256, dithering: .smooth))
        #expect(settings.outputSize == CGSize(width: 320, height: 180))
        #expect(timestamp(3661.125) == "1:01:01.125")
        #expect(timestamp(59.9998) == "01:00.000")
    }
}
