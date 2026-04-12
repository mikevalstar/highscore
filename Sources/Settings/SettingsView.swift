import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scoreManager: ScoreManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("HighScore Settings")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            TabView {
                GeneralSettingsTab(settings: settings)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                SourcesSettingsTab(scoreManager: scoreManager)
                    .tabItem {
                        Label("Sources", systemImage: "list.bullet")
                    }

                OverlaySettingsTab(settings: settings)
                    .tabItem {
                        Label("Overlay", systemImage: "rectangle.on.rectangle")
                    }
            }
        }
        .frame(width: 460, height: 520)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var showResetConfirmation = false

    private var startDateValue: Date {
        Date(timeIntervalSince1970: settings.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Score Display") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose the visual style used in the menubar and overlay score panels.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Picker("Style", selection: $settings.displayStyle) {
                        ForEach(ScoreDisplayStyle.allCases) { style in
                            Text(style.shortLabel).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(settings.displayStyle.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Tracking Start Date") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Only count tokens from files modified after this date.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    DatePicker(
                        "Start date",
                        selection: Binding(
                            get: { startDateValue },
                            set: { newDate in
                                settings.startDate = newDate.timeIntervalSince1970
                                Log.settings.notice("Start date changed to \(newDate.description)")
                            }
                        ),
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.system(size: 12, design: .monospaced))

                    Divider()

                    HStack {
                        Text("Reset to now to start fresh.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to Now") {
                            showResetConfirmation = true
                        }
                        .alert("Reset Start Date?", isPresented: $showResetConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Reset", role: .destructive) {
                                settings.resetStartDate()
                            }
                        } message: {
                            Text("This will reset the tracking start date to now. Your score will drop to zero until new token usage is recorded.")
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Refresh Rate") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How often to scan for new token usage.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Interval")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $settings.refreshInterval, in: 1...60, step: 1)
                        Text("\(Int(settings.refreshInterval))s")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Overlay Tab

struct OverlaySettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Display") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.overlayEnabled) {
                            Text("Show overlay")
                                .font(.system(size: 12, design: .monospaced))
                        }

                        Divider()

                        HStack {
                            Text("Size")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayScale, in: 0.5...2.0, step: 0.1)
                            Text("\(String(format: "%.1f", settings.overlayScale))x")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Panels") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Score panel
                        HStack {
                            Toggle(isOn: $settings.overlayShowScores) {
                                Text("Score panel")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }

                        HStack {
                            Text("Opacity")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayScoreOpacity, in: 0.1...1.0, step: 0.05)
                                .disabled(!settings.overlayShowScores)
                            Text("\(Int(settings.overlayScoreOpacity * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                        .opacity(settings.overlayShowScores ? 1 : 0.4)

                        Divider()

                        // RPG panel
                        HStack {
                            Toggle(isOn: $settings.overlayShowRPG) {
                                Text("RPG panel")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }

                        HStack {
                            Text("Opacity")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayRPGOpacity, in: 0.1...1.0, step: 0.05)
                                .disabled(!settings.overlayShowRPG)
                            Text("\(Int(settings.overlayRPGOpacity * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                        .opacity(settings.overlayShowRPG ? 1 : 0.4)
                    }
                    .padding(8)
                }

                GroupBox("Position") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pin corner")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Picker("Position", selection: $settings.overlayPosition) {
                            ForEach(OverlayPosition.allCases, id: \.self) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Divider()

                        HStack {
                            Text("Offset X")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayOffsetX, in: 0...500, step: 5)
                            Text("\(Int(settings.overlayOffsetX))px")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }

                        HStack {
                            Text("Offset Y")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayOffsetY, in: 0...500, step: 5)
                            Text("\(Int(settings.overlayOffsetY))px")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Background") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Opacity")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Slider(value: $settings.overlayBackgroundOpacity, in: 0.0...1.0, step: 0.05)
                            Text("\(Int(settings.overlayBackgroundOpacity * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(8)
                }

                // Preview
                GroupBox("Preview") {
                    ZStack {
                        // Checkerboard to show background transparency
                        CheckerboardView()
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(spacing: 2) {
                            ScoreDisplay(
                                score: 1_234_567,
                                color: .green,
                                style: settings.displayStyle
                            )
                                .frame(height: 36)
                                .opacity(settings.overlayDisplayOpacity)

                            Text("HIGH SCORE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.6))
                                .opacity(settings.overlayDisplayOpacity)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.black.opacity(settings.overlayBackgroundOpacity))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.green.opacity(0.3 * settings.overlayBackgroundOpacity), lineWidth: 1)
                                )
                        )
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Sources Tab

struct SourcesSettingsTab: View {
    @ObservedObject var scoreManager: ScoreManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Token Usage by Source") {
                    VStack(alignment: .leading, spacing: 12) {
                        if scoreManager.readerScores.isEmpty {
                            Text("No sources loaded yet.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(scoreManager.readerScores.enumerated()), id: \.offset) { _, entry in
                                SourceRow(name: entry.name, score: entry.score)

                                if entry.name != scoreManager.readerScores.last?.name {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Combined Total") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total Tokens")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text(formatScore(scoreManager.combinedScore.total))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }

                        HStack(spacing: 16) {
                            StatLabel(label: "IN", value: scoreManager.combinedScore.inputTokens, color: .blue)
                            StatLabel(label: "OUT", value: scoreManager.combinedScore.outputTokens, color: .green)
                            StatLabel(label: "CACHE R", value: scoreManager.combinedScore.cacheReadTokens, color: .orange)
                            StatLabel(label: "CACHE W", value: scoreManager.combinedScore.cacheCreationTokens, color: .purple)
                            StatLabel(label: "RSN", value: scoreManager.combinedScore.reasoningTokens, color: .pink)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
    }
}

struct SourceRow: View {
    let name: String
    let score: TokenScore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconForSource(name))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Text(formatScore(score.total))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(score.total > 0 ? .primary : .secondary)
            }

            if score.total > 0 {
                HStack(spacing: 16) {
                    StatLabel(label: "IN", value: score.inputTokens, color: .blue)
                    StatLabel(label: "OUT", value: score.outputTokens, color: .green)
                    StatLabel(label: "CACHE R", value: score.cacheReadTokens, color: .orange)
                    StatLabel(label: "CACHE W", value: score.cacheCreationTokens, color: .purple)
                    if score.reasoningTokens > 0 {
                        StatLabel(label: "RSN", value: score.reasoningTokens, color: .pink)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
            } else {
                Text("No usage detected")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconForSource(_ name: String) -> String {
        switch name {
        case "Claude Code": return "terminal.fill"
        case "OpenCode": return "chevron.left.forwardslash.chevron.right"
        case "Codex": return "brain"
        default: return "cpu"
        }
    }
}

struct StatLabel: View {
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

// MARK: - Helpers

/// Checkerboard pattern to visualize transparency in the preview
struct CheckerboardView: View {
    let size: CGFloat = 8

    var body: some View {
        Canvas { context, canvasSize in
            let rows = Int(canvasSize.height / size) + 1
            let cols = Int(canvasSize.width / size) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size)
                    context.fill(Path(rect), with: .color(isLight ? .gray.opacity(0.3) : .gray.opacity(0.15)))
                }
            }
        }
    }
}
