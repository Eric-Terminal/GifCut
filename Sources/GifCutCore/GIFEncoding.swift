public enum GIFPaletteSize: Int, CaseIterable, Sendable {
    case colors32 = 32
    case colors64 = 64
    case colors128 = 128
    case colors256 = 256
}

public enum GIFDithering: String, CaseIterable, Sendable {
    case smooth
    case ordered
    case none

    public var title: String {
        switch self {
        case .smooth: "平滑渐变"
        case .ordered: "有序抖色"
        case .none: "关闭抖色"
        }
    }

    public var explanation: String {
        switch self {
        case .smooth: "用细小噪点模拟渐变，过渡更柔和，文件通常较大。"
        case .ordered: "用规则点阵模拟渐变，兼顾颜色过渡和体积。"
        case .none: "减少细碎噪点，文件通常更小，渐变可能出现色块。"
        }
    }

    var filterValue: String {
        switch self {
        case .smooth: "sierra2_4a"
        case .ordered: "bayer:bayer_scale=4"
        case .none: "none"
        }
    }
}

public struct GIFEncoding: Equatable, Sendable {
    public var paletteSize: GIFPaletteSize
    public var dithering: GIFDithering

    public init(paletteSize: GIFPaletteSize, dithering: GIFDithering) {
        self.paletteSize = paletteSize
        self.dithering = dithering
    }

    public var summary: String { "\(paletteSize.rawValue) 色 · \(dithering.title)" }

    // 生成调色板和使用调色板必须来自同一份导出快照，避免两遍编码参数不一致。
    var paletteFilter: String { "palettegen=max_colors=\(paletteSize.rawValue):stats_mode=diff" }
    var useFilter: String { "paletteuse=dither=\(dithering.filterValue):diff_mode=rectangle" }
}

public enum GIFEncodingPreset: String, CaseIterable, Sendable {
    case quality
    case balanced
    case compact
    case smallest
    case custom

    public var title: String {
        switch self {
        case .quality: "画质优先"
        case .balanced: "均衡"
        case .compact: "体积优先"
        case .smallest: "更小体积"
        case .custom: "自定义"
        }
    }

    public var encoding: GIFEncoding? {
        switch self {
        case .quality: GIFEncoding(paletteSize: .colors256, dithering: .smooth)
        case .balanced: GIFEncoding(paletteSize: .colors128, dithering: .ordered)
        case .compact: GIFEncoding(paletteSize: .colors128, dithering: .none)
        case .smallest: GIFEncoding(paletteSize: .colors64, dithering: .none)
        case .custom: nil
        }
    }
}
