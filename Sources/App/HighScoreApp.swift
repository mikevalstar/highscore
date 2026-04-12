import SwiftUI

@main
struct HighScoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                scoreManager: appDelegate.scoreManager,
                settings: appDelegate.settings,
                overlayController: appDelegate.overlayController,
                settingsController: appDelegate.settingsController
            )
        } label: {
            Label("HighScore", systemImage: "trophy.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let scoreManager = ScoreManager()
    let overlayController = OverlayWindowController()
    lazy var settingsController = SettingsWindowController(settings: settings, scoreManager: scoreManager)

    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Application launched")
        NSApp.setActivationPolicy(.accessory)
        settings.initializeStartDateIfNeeded()

        updateAppIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateAppIcon()
            }
        }

        overlayController.wireUp(settings: settings, scoreManager: scoreManager)

        if settings.overlayEnabled {
            Log.app.info("Restoring overlay on launch")
            overlayController.show()
        }
    }

    private func updateAppIcon() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let iconName = isDark ? "AppIcon-dark" : "AppIcon"
        if let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            Log.app.info("Set app icon to \(iconName, privacy: .public)")
        }
    }
}
