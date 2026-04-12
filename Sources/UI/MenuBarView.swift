import SwiftUI

struct MenuBarView: View {
    @ObservedObject var scoreManager: ScoreManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var overlayController: OverlayWindowController
    var settingsController: SettingsWindowController?

    private var showScores: Bool {
        settings.displayMode == "scores" || settings.displayMode == "both"
    }

    private var showRPG: Bool {
        false
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with display mode toggle
            HStack {
                Spacer()
                Text("HIGH SCORE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                DisplayModeToggle(displayMode: $settings.displayMode)
            }

            if showScores {
                // Seven segment preview of the score
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.8))

                    VStack(spacing: 4) {
                        SevenSegmentScore(score: scoreManager.displayScore, color: .green)
                            .frame(height: 36)

                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Text("T")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan.opacity(0.6))
                                SevenSegmentScore(score: scoreManager.displayTodayScore, color: .cyan)
                            }
                            HStack(spacing: 4) {
                                Text("W")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.orange.opacity(0.6))
                                SevenSegmentScore(score: scoreManager.displayWeekScore, color: .orange)
                            }
                        }
                        .frame(height: 22)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(height: 76)

                // Per-source breakdown (only sources with tokens > 0)
                VStack(spacing: 6) {
                    ForEach(
                        scoreManager.readerScores.filter { $0.score.total > 0 },
                        id: \.name
                    ) { reader in
                        SourceRowView(
                            name: reader.name,
                            score: reader.score,
                            icon: iconForSource(reader.name)
                        )
                    }
                }
            }

            if showRPG {
                RPGSceneView()
            }

            Divider()

            // Overlay toggle
            HStack {
                Toggle(isOn: Binding(
                    get: { settings.overlayEnabled },
                    set: { _ in overlayController.toggle() }
                )) {
                    Label("Overlay", systemImage: "rectangle.inset.topright.filled")
                        .font(.system(size: 12, design: .monospaced))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            HStack {
                Button {
                    settingsController?.open()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",")

                Spacer()

                Button("Refresh") {
                    scoreManager.refresh()
                }
                .keyboardShortcut("r")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Display Mode Toggle

struct DisplayModeToggle: View {
    @Binding var displayMode: String

    var body: some View {
        HStack(spacing: 2) {
            ModeButton(icon: "number.square", mode: "scores", current: $displayMode, tooltip: "Scores only")
            ModeButton(icon: "gamecontroller", mode: "rpg", current: $displayMode, tooltip: "RPG only")
            ModeButton(icon: "square.grid.2x2", mode: "both", current: $displayMode, tooltip: "Both")
        }
    }
}

struct ModeButton: View {
    let icon: String
    let mode: String
    @Binding var current: String
    let tooltip: String

    var body: some View {
        Button {
            current = mode
            Log.app.info("Display mode changed to \(mode, privacy: .public)")
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
                .foregroundStyle(current == mode ? .white : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(current == mode ? .blue.opacity(0.6) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Source Row (collapsed/expanded per-source view)

struct SourceRowView: View {
    let name: String
    let score: TokenScore
    let icon: String

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact row: icon, name, bar, total
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)

                    TokenBar(score: score)
                        .frame(height: 12)

                    Text(formatScore(score.total))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // Expanded legend
            if isExpanded {
                VStack(spacing: 4) {
                    HStack(spacing: 12) {
                        TokenLegendItem(label: "IN", value: score.inputTokens, color: .blue)
                        TokenLegendItem(label: "OUT", value: score.outputTokens, color: .green)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        TokenLegendItem(label: "CACHE", value: score.cacheReadTokens, color: .orange)
                        if score.reasoningTokens > 0 {
                            TokenLegendItem(label: "RSN", value: score.reasoningTokens, color: .pink)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Token Bar (improved visuals)

struct TokenBar: View {
    let score: TokenScore

    private var segments: [(label: String, value: Int, color: Color)] {
        [
            ("IN", score.inputTokens, .blue),
            ("OUT", score.outputTokens, .green),
            ("CACHE", score.cacheReadTokens, .orange),
            ("RSN", score.reasoningTokens, .pink),
        ].filter { $0.value > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let total = segments.reduce(0) { $0 + $1.value }

            // Dark inset track
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.05), lineWidth: 0.5)
                )
                .overlay {
                    if total > 0 {
                        HStack(spacing: 1) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                let fraction = CGFloat(segment.value) / CGFloat(total)
                                let segmentWidth = (geo.size.width - CGFloat(segments.count - 1)) * fraction

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                segment.color.opacity(0.9),
                                                segment.color.opacity(0.6),
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white.opacity(0.15))
                                            .frame(height: geo.size.height * 0.4)
                                            .offset(y: -geo.size.height * 0.15),
                                        alignment: .top
                                    )
                                    .frame(width: max(segmentWidth, 3))
                            }
                        }
                        .padding(1.5)
                    }
                }
        }
    }
}

// MARK: - Token Legend Item

struct TokenLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.9), color.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 8, height: 8)
            Text("\(label): \(formatCompact(value))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Source Icon Mapping

func iconForSource(_ name: String) -> String {
    switch name {
    case "Claude Code": return "terminal.fill"
    case "Cursor": return "cursorarrow.rays"
    case "Copilot": return "airplane"
    case "OpenCode": return "chevron.left.forwardslash.chevron.right"
    case "Codex": return "book.closed.fill"
    default: return "questionmark.circle"
    }
}

func formatScore(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

func formatCompact(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.0fM", Double(value) / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.0fK", Double(value) / 1_000)
    }
    return "\(value)"
}
