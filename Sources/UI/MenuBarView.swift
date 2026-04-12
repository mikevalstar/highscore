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
        settings.overlayShowRPG && (settings.displayMode == "rpg" || settings.displayMode == "both")
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

                ScoreSegmentView(
                    label: "All Sources",
                    score: scoreManager.combinedScore,
                    icon: "terminal.fill"
                )
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

struct ScoreSegmentView: View {
    let label: String
    let score: TokenScore
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Text(formatScore(score.total))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }

            HStack(spacing: 0) {
                ScoreBar(label: "IN", value: score.inputTokens, color: .blue)
                ScoreBar(label: "OUT", value: score.outputTokens, color: .green)
                ScoreBar(label: "CACHE", value: score.cacheReadTokens, color: .orange)
                ScoreBar(label: "RSN", value: score.reasoningTokens, color: .pink)
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                ScoreLegend(label: "IN", value: score.inputTokens, color: .blue)
                Spacer()
                ScoreLegend(label: "OUT", value: score.outputTokens, color: .green)
                Spacer()
                ScoreLegend(label: "CACHE", value: score.cacheReadTokens, color: .orange)
                if score.reasoningTokens > 0 {
                    Spacer()
                    ScoreLegend(label: "RSN", value: score.reasoningTokens, color: .pink)
                }
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScoreBar: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if value > 0 {
                Rectangle()
                    .fill(color.opacity(0.7))
                    .overlay {
                        if geo.size.width > 30 {
                            Text(label)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
    }
}

struct ScoreLegend: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 6, height: 6)
            Text("\(label): \(formatCompact(value))")
                .foregroundStyle(.secondary)
        }
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
