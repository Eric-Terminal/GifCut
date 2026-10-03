import Foundation
import CoreGraphics

public struct ClipRange: Equatable, Sendable {
    public let duration: Double
    public private(set) var start: Double
    public private(set) var end: Double
    public var length: Double { end - start }
    public var minimumLength: Double { min(0.04, duration) }

    public init(duration: Double) {
        self.duration = max(0, duration)
        start = 0
        end = min(5, self.duration)
    }

    public mutating func setStart(_ value: Double) {
        guard value.isFinite else { return }
        start = min(max(0, value), end - minimumLength)
    }

    public mutating func setEnd(_ value: Double) {
        guard value.isFinite else { return }
        end = max(min(duration, value), start + minimumLength)
    }

    public mutating func move(to value: Double) {
        guard value.isFinite else { return }
        let span = length
        start = min(max(0, value), duration - span)
        end = start + span
    }
}

/// 使用显示画面的左上角归一化坐标，避免窗口缩放和视频黑边改变实际裁切区域。
public struct CropRegion: Equatable, Sendable {
    public var rect: CGRect
    public static let full = CropRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

    public init(rect: CGRect) { self.rect = rect }

    public static func drawn(from start: CGPoint, to end: CGPoint) -> CropRegion {
        let a = CGPoint(x: start.x.clamped, y: start.y.clamped)
        let b = CGPoint(x: end.x.clamped, y: end.y.clamped)
        let width = max(0.01, abs(a.x - b.x))
        let height = max(0.01, abs(a.y - b.y))
        return CropRegion(rect: CGRect(x: min(min(a.x, b.x), 1 - width),
                                       y: min(min(a.y, b.y), 1 - height),
                                       width: width, height: height))
    }

    public func moved(dx: Double, dy: Double) -> CropRegion {
        CropRegion(rect: CGRect(x: min(max(0, rect.minX + dx), 1 - rect.width),
                                y: min(max(0, rect.minY + dy), 1 - rect.height),
                                width: rect.width, height: rect.height))
    }

    public func resized(corner: Int, to point: CGPoint) -> CropRegion {
        let left = corner == 0 || corner == 2
        let top = corner < 2
        let x1 = left ? min(point.x.clamped, rect.maxX - 0.01) : rect.minX
        let y1 = top ? min(point.y.clamped, rect.maxY - 0.01) : rect.minY
        let x2 = left ? rect.maxX : max(point.x.clamped, rect.minX + 0.01)
        let y2 = top ? rect.maxY : max(point.y.clamped, rect.minY + 0.01)
        return CropRegion(rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1))
    }
}

private extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}

public func timestamp(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let milliseconds = Int((value * 1000).rounded())
    let hours = milliseconds / 3_600_000
    let minutes = (milliseconds / 60_000) % 60
    let secondsPart = (milliseconds / 1000) % 60
    let fraction = milliseconds % 1000
    if hours > 0 {
        return String(format: "%d:%02d:%02d.%03d", hours, minutes, secondsPart, fraction)
    }
    return String(format: "%02d:%02d.%03d", minutes, secondsPart, fraction)
}
