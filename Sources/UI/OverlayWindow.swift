import SwiftUI
import AppKit
import Combine

@MainActor
class OverlayWindowController: ObservableObject {
    private var window: NSPanel?
    var settings: AppSettings?
    var scoreManager: ScoreManager?
    private var defaultsObserver: Any?
    private var settingsObserver: Any?
    private var scoreWidthObserver: AnyCancellable?

    func wireUp(settings: AppSettings, scoreManager: ScoreManager) {
        self.settings = settings
        self.scoreManager = scoreManager
        Log.overlay.info("Overlay controller wired up")

        // Watch for overlay toggle changes from the settings window
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let settings = self.settings else { return }
                if settings.overlayEnabled && self.window == nil {
                    Log.overlay.info("Overlay enabled via settings — showing")
                    self.show()
                } else if !settings.overlayEnabled && self.window != nil {
                    Log.overlay.info("Overlay disabled via settings — hiding")
                    self.hide()
                }
            }
        }
    }

    func show() {
        guard let settings, let scoreManager else {
            Log.overlay.warning("Cannot show overlay — not wired up yet")
            return
        }
        if window != nil {
            Log.overlay.debug("Show called but overlay already visible")
            return
        }

        Log.overlay.info("Creating overlay panel")

        let overlayView = OverlayContentView(scoreManager: scoreManager, settings: settings)
        let hostingView = NSHostingView(rootView: overlayView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView

        self.window = panel
        updatePosition()
        panel.orderFront(nil)

        Log.overlay.info("Overlay panel shown at position \(settings.overlayPosition.rawValue)")

        // Track score width changes to resize the overlay panel
        scoreWidthObserver = Publishers.CombineLatest3(
            scoreManager.$displayScore,
            scoreManager.$displayTodayScore,
            scoreManager.$displayWeekScore
        )
        .map { [weak self] total, today, week in
            self?.scorePanelBaseWidth(total: total, today: today, week: week) ?? 320
        }
        .removeDuplicates()
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }

        // Watch for position/scale/opacity changes
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }
    }

    func hide() {
        Log.overlay.info("Hiding overlay panel")
        window?.orderOut(nil)
        window = nil
        scoreWidthObserver = nil
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
            defaultsObserver = nil
        }
    }

    func toggle() {
        guard let settings else { return }
        if window != nil {
            hide()
            settings.overlayEnabled = false
        } else {
            show()
            settings.overlayEnabled = true
        }
        Log.overlay.info("Overlay toggled — now \(settings.overlayEnabled ? "enabled" : "disabled")")
    }

    func updatePosition() {
        guard let window, let settings, let screen = NSScreen.main else { return }

        let scale = settings.overlayScale
        let showScores = settings.overlayShowScores
        let showRPG = settings.overlayShowRPG

        let scoreWidth = scorePanelBaseWidth()
        let rpgWidth: CGFloat = scoreWidth * 2.5  // RPG is 2.5x wider than scores
        let xpExtra: CGFloat = settings.showXPPopups ? 48 : 0
        let scoreHeight: CGFloat = 120 + xpExtra
        let rpgHeight: CGFloat = 300
        let panelGap: CGFloat = 16

        var baseWidth: CGFloat
        var baseHeight: CGFloat

        if showScores && showRPG {
            // Side-by-side layout with gap between panels
            baseWidth = scoreWidth + rpgWidth + panelGap
            baseHeight = max(scoreHeight, rpgHeight)
        } else if showRPG {
            baseWidth = rpgWidth
            baseHeight = rpgHeight
        } else {
            baseWidth = scoreWidth
            baseHeight = scoreHeight
        }

        let size = CGSize(width: baseWidth * scale, height: baseHeight * scale)

        window.setContentSize(size)

        let origin = settings.overlayPosition.origin(
            overlaySize: size,
            screenFrame: screen.frame,
            offsetX: settings.overlayOffsetX,
            offsetY: settings.overlayOffsetY
        )
        window.setFrameOrigin(origin)
        Log.overlay.debug(
            "Position updated: \(settings.overlayPosition.rawValue), scale=\(String(format: "%.1f", scale)), offset=(\(Int(settings.overlayOffsetX)),\(Int(settings.overlayOffsetY))), origin=(\(Int(origin.x)),\(Int(origin.y)))"
        )
    }

    private func scorePanelBaseWidth(total: Int? = nil, today: Int? = nil, week: Int? = nil) -> CGFloat {
        guard let settings, let scoreManager else { return 320 }
        return ScoreDisplayMetrics.scorePanelBaseWidth(
            style: settings.displayStyle,
            total: total ?? scoreManager.displayScore,
            today: today ?? scoreManager.displayTodayScore,
            week: week ?? scoreManager.displayWeekScore
        )
    }
}

struct OverlayContentView: View {
    @ObservedObject var scoreManager: ScoreManager
    @ObservedObject var settings: AppSettings

    /// RPG goes toward the screen interior (away from the corner the overlay is pinned to).
    /// Left-pinned positions → RPG on the right. Right-pinned → RPG on the left.
    private var rpgOnRight: Bool {
        switch settings.overlayPosition {
        case .topLeft, .bottomLeft: return true
        case .topRight, .bottomRight: return false
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if settings.overlayShowRPG && !rpgOnRight {
                rpgPanel
            }

            if settings.overlayShowScores {
                scorePanel
            }

            if settings.overlayShowRPG && rpgOnRight {
                rpgPanel
            }
        }
        .fixedSize()
        .padding(.horizontal, 12 * settings.overlayScale)
        .padding(.vertical, 6 * settings.overlayScale)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(settings.overlayBackgroundOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(settings.scoreColor.opacity(0.3 * settings.overlayBackgroundOpacity), lineWidth: 1)
                )
        )
    }

    private var scorePanel: some View {
        VStack(spacing: 2) {
            if settings.showXPPopups {
                XPPopupView(
                    xpGain: scoreManager.lastXPGain,
                    color: settings.scoreColor,
                    scale: settings.overlayScale
                )
                .frame(height: 32 * settings.overlayScale)
            }

            ScoreDisplay(
                score: scoreManager.displayScore,
                color: settings.scoreColor,
                style: settings.displayStyle
            )
                .frame(maxHeight: .infinity)
                .opacity(settings.overlayScoreOpacity)

            if settings.showDailyScore || settings.showWeeklyScore {
                HStack(spacing: 12 * settings.overlayScale) {
                    if settings.showDailyScore {
                        HStack(spacing: 2 * settings.overlayScale) {
                            Text("T")
                                .font(.system(size: 9 * settings.overlayScale, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.todayScoreColor.opacity(0.6))
                            ScoreDisplay(
                                score: scoreManager.displayTodayScore,
                                color: settings.todayScoreColor,
                                style: settings.displayStyle
                            )
                        }
                    }
                    if settings.showWeeklyScore {
                        HStack(spacing: 2 * settings.overlayScale) {
                            Text("W")
                                .font(.system(size: 9 * settings.overlayScale, weight: .bold, design: .monospaced))
                                .foregroundStyle(settings.weekScoreColor.opacity(0.6))
                            ScoreDisplay(
                                score: scoreManager.displayWeekScore,
                                color: settings.weekScoreColor,
                                style: settings.displayStyle
                            )
                        }
                    }
                }
                .frame(height: 25 * settings.overlayScale)
                .opacity(settings.overlayScoreOpacity)
            }

            Text("HIGH SCORE")
                .font(.system(size: 8 * settings.overlayScale, weight: .bold, design: .monospaced))
                .foregroundStyle(settings.scoreColor.opacity(0.6))
                .opacity(settings.overlayScoreOpacity)
        }
        .frame(width: scorePanelWidth, height: ((settings.showDailyScore || settings.showWeeklyScore ? 120 : 90) + (settings.showXPPopups ? 32 : 0)) * settings.overlayScale)
    }

    private var rpgPanel: some View {
        RPGSceneView()
            .frame(width: 800 * settings.overlayScale, height: 280 * settings.overlayScale)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(settings.overlayRPGOpacity)
    }

    private var scorePanelWidth: CGFloat {
        ScoreDisplayMetrics.scorePanelBaseWidth(
            style: settings.displayStyle,
            total: scoreManager.displayScore,
            today: scoreManager.displayTodayScore,
            week: scoreManager.displayWeekScore
        ) * settings.overlayScale
    }
}

// MARK: - XP Popup

struct XPPopupView: View {
    let xpGain: XPGain?
    let color: Color
    let scale: CGFloat

    @State private var displayedGain: XPGain?
    @State private var animateOut: Bool = false

    var body: some View {
        ZStack {
            if let gain = displayedGain {
                Text("+\(formatCompact(gain.amount))")
                    .font(.system(size: 24 * scale, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.9), radius: 6)
                    .shadow(color: color.opacity(0.5), radius: 12)
                    .shadow(color: .black, radius: 2)
                    .offset(y: animateOut ? -16 * scale : 0)
                    .opacity(animateOut ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30 * scale)
        .allowsHitTesting(false)
        .onChange(of: xpGain) { _, newGain in
            guard let newGain, newGain.amount > 0 else { return }
            Log.overlay.notice("XP popup triggered: +\(newGain.amount) (id: \(newGain.id))")

            // Reset state for new popup
            animateOut = false
            displayedGain = newGain

            // Hold visible for 2s, then fade out over 2s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 2.0)) {
                    animateOut = true
                }
            }

            // Clean up after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                if displayedGain?.id == newGain.id {
                    displayedGain = nil
                    animateOut = false
                }
            }
        }
    }
}
