import SwiftUI
import AppKit

enum ScoreDisplayStyle: String, CaseIterable, Codable, Identifiable {
    case sevenSegment = "Seven Segment"
    case dotMatrix = "Dot Matrix"
    case pixel = "Pixel Arcade"
    case terminal = "Terminal CRT"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .sevenSegment: return "7-Seg"
        case .dotMatrix: return "Dots"
        case .pixel: return "Pixel"
        case .terminal: return "CRT"
        }
    }

    var description: String {
        switch self {
        case .sevenSegment:
            return "Retro LED scoreboard"
        case .dotMatrix:
            return "Printed LED board look"
        case .pixel:
            return "Chunky arcade digits"
        case .terminal:
            return "Green phosphor monitor"
        }
    }
}

struct ScoreDisplay: View {
    let score: Int
    var color: Color = .green
    var style: ScoreDisplayStyle = .sevenSegment

    var body: some View {
        switch style {
        case .sevenSegment:
            SevenSegmentScore(score: score, color: color)
        case .dotMatrix:
            DotMatrixScore(score: score, color: color)
        case .pixel:
            PixelArcadeScore(score: score, color: color)
        case .terminal:
            TerminalCRTScore(score: score, color: color)
        }
    }
}

func displayText(for score: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: score)) ?? "\(score)"
}

enum ScoreDisplayMetrics {
    static func width(for score: Int, style: ScoreDisplayStyle, height: CGFloat) -> CGFloat {
        width(for: displayText(for: score), style: style, height: height)
    }

    static func width(for text: String, style: ScoreDisplayStyle, height: CGFloat) -> CGFloat {
        if style == .terminal {
            return terminalTextWidth(for: text, height: height)
        }

        let spacing = interCharacterSpacing(for: style)
        let characterWidths = text.map { widthUnits(for: $0, style: style) * height }
        let totalCharacterWidth = characterWidths.reduce(0, +)
        let totalSpacing = spacing * CGFloat(max(text.count - 1, 0))
        return ceil(totalCharacterWidth + totalSpacing)
    }

    static func scorePanelBaseWidth(style: ScoreDisplayStyle, total: Int, today: Int, week: Int) -> CGFloat {
        let mainWidth = width(for: total, style: style, height: 72)
        let todayWidth = width(for: today, style: style, height: 25)
        let weekWidth = width(for: week, style: style, height: 25)
        let secondaryWidth = todayWidth + weekWidth + 42
        return max(320, mainWidth + 32, secondaryWidth + 40)
    }

    private static func interCharacterSpacing(for style: ScoreDisplayStyle) -> CGFloat {
        switch style {
        case .sevenSegment: return 1
        case .dotMatrix: return 2
        case .pixel: return 3
        case .terminal: return 0
        }
    }

    private static func widthUnits(for character: Character, style: ScoreDisplayStyle) -> CGFloat {
        switch style {
        case .sevenSegment:
            return character == "," ? 0.16 : 0.55
        case .dotMatrix:
            let glyph = dotMatrixGlyphs[character] ?? dotMatrixGlyphs[" "]!
            let columns = glyph.map(\.count).max() ?? 1
            return CGFloat(columns) / CGFloat(max(glyph.count, 1))
        case .pixel:
            let glyph = pixelGlyphs[character] ?? pixelGlyphs[" "]!
            let columns = glyph.map(\.count).max() ?? 1
            return CGFloat(columns) / CGFloat(max(glyph.count, 1))
        case .terminal:
            return character == "," ? 0.18 : 0.5
        }
    }

    private static func terminalTextWidth(for text: String, height: CGFloat) -> CGFloat {
        let fontSize = terminalFontSize(for: height)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(measuredWidth + fontSize * 0.35)
    }
}

private struct DotMatrixScore: View {
    let score: Int
    let color: Color

    private var text: String {
        displayText(for: score)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                MatrixGlyphView(
                    glyph: dotMatrixGlyphs[character] ?? dotMatrixGlyphs[" "]!,
                    litColor: color,
                    unlitColor: color.opacity(0.10),
                    cellStyle: .dot,
                    showsUnlitCells: true
                )
            }
        }
        .drawingGroup()  // Rasterize many cell shadows into a single Metal texture
    }
}

private struct PixelArcadeScore: View {
    let score: Int
    let color: Color

    private var text: String {
        displayText(for: score)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                MatrixGlyphView(
                    glyph: pixelGlyphs[character] ?? pixelGlyphs[" "]!,
                    litColor: color,
                    unlitColor: .clear,
                    cellStyle: .pixel,
                    showsUnlitCells: false
                )
            }
        }
        .drawingGroup()  // Rasterize many cell shadows into a single Metal texture
    }
}

private struct TerminalCRTScore: View {
    let score: Int
    let color: Color

    private var text: String {
        displayText(for: score)
    }

    var body: some View {
        GeometryReader { geo in
            let fontSize = terminalFontSize(for: geo.size.height)

            ZStack {
                Text(text)
                    .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                    .fontWidth(.compressed)
                    .foregroundStyle(color.opacity(0.22))
                    .blur(radius: fontSize * 0.12)

                Text(text)
                    .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                    .fontWidth(.compressed)
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.75), radius: fontSize * 0.06)
                    .overlay {
                        VStack(spacing: max(fontSize * 0.08, 1)) {
                            ForEach(0..<12, id: \.self) { _ in
                                Rectangle()
                                    .fill(.black.opacity(0.12))
                                    .frame(height: 1)
                            }
                        }
                        .padding(.vertical, fontSize * 0.1)
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                    }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .drawingGroup()  // Rasterize blur/shadow/scanlines into a single Metal texture
        }
    }
}

private func terminalFontSize(for height: CGFloat) -> CGFloat {
    max(height * 0.72, 12)
}

private enum MatrixCellStyle {
    case dot
    case pixel
}

private struct MatrixGlyphView: View {
    let glyph: [String]
    let litColor: Color
    let unlitColor: Color
    let cellStyle: MatrixCellStyle
    let showsUnlitCells: Bool

    private var rowCount: Int { glyph.count }
    private var columnCount: Int { glyph.map(\.count).max() ?? 1 }

    var body: some View {
        GeometryReader { geo in
            let spacing = max(min(geo.size.width, geo.size.height) * 0.05, 1)
            let cellWidth = max((geo.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 1)
            let cellHeight = max((geo.size.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount), 1)

            VStack(alignment: .center, spacing: spacing) {
                ForEach(Array(glyph.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: spacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, bit in
                            cell(isLit: bit == "1", cellWidth: cellWidth, cellHeight: cellHeight)
                                .id("\(rowIndex)-\(columnIndex)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(columnCount) / CGFloat(max(rowCount, 1)), contentMode: .fit)
    }

    @ViewBuilder
    private func cell(isLit: Bool, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let fillColor = isLit ? litColor : (showsUnlitCells ? unlitColor : .clear)

        switch cellStyle {
        case .dot:
            Circle()
                .fill(fillColor)
                .frame(width: cellWidth, height: cellHeight)
                .shadow(color: isLit ? litColor.opacity(0.6) : .clear, radius: cellWidth * 0.35)
        case .pixel:
            RoundedRectangle(cornerRadius: max(min(cellWidth, cellHeight) * 0.2, 1))
                .fill(fillColor)
                .frame(width: cellWidth, height: cellHeight)
                .shadow(color: isLit ? litColor.opacity(0.25) : .clear, radius: cellWidth * 0.1, y: 1)
        }
    }
}

private let dotMatrixGlyphs: [Character: [String]] = [
    "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    ",": ["0", "0", "0", "0", "0", "0", "1"],
    " ": ["000", "000", "000", "000", "000", "000", "000"],
]

private let pixelGlyphs: [Character: [String]] = [
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "010", "010", "010"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
    ",": ["0", "0", "0", "0", "1"],
    " ": ["000", "000", "000", "000", "000"],
]
