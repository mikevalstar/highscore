import SwiftUI

/// Which of the 7 segments are lit for each digit (and blank)
///
///  _0_
/// |   |
/// 5   1
/// |_6_|
/// |   |
/// 4   2
/// |_3_|
///
private let segmentMap: [Character: [Bool]] = [
    "0": [true,  true,  true,  true,  true,  true,  false],
    "1": [false, true,  true,  false, false, false, false],
    "2": [true,  true,  false, true,  true,  false, true],
    "3": [true,  true,  true,  true,  false, false, true],
    "4": [false, true,  true,  false, false, true,  true],
    "5": [true,  false, true,  true,  false, true,  true],
    "6": [true,  false, true,  true,  true,  true,  true],
    "7": [true,  true,  true,  false, false, false, false],
    "8": [true,  true,  true,  true,  true,  true,  true],
    "9": [true,  true,  true,  true,  false, true,  true],
    ",": [],  // handled specially
    " ": [false, false, false, false, false, false, false],
]

struct SevenSegmentDigit: View {
    let character: Character
    let litColor: Color
    let unlitColor: Color

    init(_ character: Character, litColor: Color = .green, unlitColor: Color = Color.green.opacity(0.08)) {
        self.character = character
        self.litColor = litColor
        self.unlitColor = unlitColor
    }

    var body: some View {
        if character == "," {
            CommaView(color: litColor)
        } else {
            DigitCanvas(segments: segmentMap[character] ?? segmentMap[" "]!, litColor: litColor, unlitColor: unlitColor)
        }
    }
}

private struct CommaView: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Circle()
                .fill(color)
                .frame(width: w * 0.35, height: w * 0.35)
                .position(x: w * 0.5, y: h * 0.9)
        }
        .aspectRatio(0.25, contentMode: .fit)
    }
}

private struct DigitCanvas: View {
    let segments: [Bool]
    let litColor: Color
    let unlitColor: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let t = max(w * 0.15, 2) // segment thickness
            let gap: CGFloat = t * 0.15  // gap between segments
            let inset = t * 0.1

            // Segment 0 — top horizontal
            SegmentShape.horizontal()
                .fill(segments[0] ? litColor : unlitColor)
                .frame(width: w - t * 2 - gap * 2, height: t)
                .position(x: w / 2, y: inset + t / 2)

            // Segment 1 — top-right vertical
            SegmentShape.vertical()
                .fill(segments[1] ? litColor : unlitColor)
                .frame(width: t, height: h / 2 - t - gap * 2)
                .position(x: w - inset - t / 2, y: h * 0.25)

            // Segment 2 — bottom-right vertical
            SegmentShape.vertical()
                .fill(segments[2] ? litColor : unlitColor)
                .frame(width: t, height: h / 2 - t - gap * 2)
                .position(x: w - inset - t / 2, y: h * 0.75)

            // Segment 3 — bottom horizontal
            SegmentShape.horizontal()
                .fill(segments[3] ? litColor : unlitColor)
                .frame(width: w - t * 2 - gap * 2, height: t)
                .position(x: w / 2, y: h - inset - t / 2)

            // Segment 4 — bottom-left vertical
            SegmentShape.vertical()
                .fill(segments[4] ? litColor : unlitColor)
                .frame(width: t, height: h / 2 - t - gap * 2)
                .position(x: inset + t / 2, y: h * 0.75)

            // Segment 5 — top-left vertical
            SegmentShape.vertical()
                .fill(segments[5] ? litColor : unlitColor)
                .frame(width: t, height: h / 2 - t - gap * 2)
                .position(x: inset + t / 2, y: h * 0.25)

            // Segment 6 — middle horizontal
            SegmentShape.horizontal()
                .fill(segments[6] ? litColor : unlitColor)
                .frame(width: w - t * 2 - gap * 2, height: t)
                .position(x: w / 2, y: h / 2)
        }
        .aspectRatio(0.55, contentMode: .fit)
    }
}

/// Hexagonal segment shapes for that authentic LED look
enum SegmentShape {
    struct horizontal: Shape {
        func path(in rect: CGRect) -> Path {
            let h = rect.height
            let pointInset = h / 2
            var path = Path()
            path.move(to: CGPoint(x: pointInset, y: 0))
            path.addLine(to: CGPoint(x: rect.width - pointInset, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: h / 2))
            path.addLine(to: CGPoint(x: rect.width - pointInset, y: h))
            path.addLine(to: CGPoint(x: pointInset, y: h))
            path.addLine(to: CGPoint(x: 0, y: h / 2))
            path.closeSubpath()
            return path
        }
    }

    struct vertical: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width
            let pointInset = w / 2
            var path = Path()
            path.move(to: CGPoint(x: w / 2, y: 0))
            path.addLine(to: CGPoint(x: w, y: pointInset))
            path.addLine(to: CGPoint(x: w, y: rect.height - pointInset))
            path.addLine(to: CGPoint(x: w / 2, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height - pointInset))
            path.addLine(to: CGPoint(x: 0, y: pointInset))
            path.closeSubpath()
            return path
        }
    }
}

/// Displays a score as seven-segment digits with comma separators
struct SevenSegmentScore: View {
    let score: Int
    var color: Color = .green

    private var displayText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: score)) ?? "\(score)"
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(displayText.enumerated()), id: \.offset) { _, char in
                SevenSegmentDigit(char, litColor: color)
            }
        }
    }
}
