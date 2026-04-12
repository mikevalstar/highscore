import SwiftUI
import AppKit

@MainActor
class OverlayWindowController: ObservableObject {
    private var window: NSPanel?
    var settings: AppSettings?
    var scoreManager: ScoreManager?
    private var defaultsObserver: Any?
    private var settingsObserver: Any?

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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
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
        let baseWidth: CGFloat = 320
        let baseHeight: CGFloat = 80
        let size = CGSize(width: baseWidth * scale, height: baseHeight * scale)

        window.setContentSize(size)

        let origin = settings.overlayPosition.origin(
            overlaySize: size,
            screenFrame: screen.visibleFrame
        )
        window.setFrameOrigin(origin)
        Log.overlay.debug(
            "Position updated: \(settings.overlayPosition.rawValue), scale=\(String(format: "%.1f", scale)), origin=(\(Int(origin.x)),\(Int(origin.y)))"
        )
    }
}

struct OverlayContentView: View {
    @ObservedObject var scoreManager: ScoreManager
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            SevenSegmentScore(score: scoreManager.displayScore, color: .green)
                .frame(maxHeight: .infinity)

            Text("HIGH SCORE")
                .font(.system(size: 8 * settings.overlayScale, weight: .bold, design: .monospaced))
                .foregroundStyle(.green.opacity(0.6))
        }
        .padding(.horizontal, 12 * settings.overlayScale)
        .padding(.vertical, 6 * settings.overlayScale)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.green.opacity(0.3), lineWidth: 1)
                )
        )
        .opacity(settings.overlayOpacity)
    }
}
