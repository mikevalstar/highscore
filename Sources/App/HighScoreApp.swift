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
    lazy var settingsController = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Application launched")
        NSApp.setActivationPolicy(.accessory)
        settings.initializeStartDateIfNeeded()

        overlayController.wireUp(settings: settings, scoreManager: scoreManager)

        if settings.overlayEnabled {
            Log.app.info("Restoring overlay on launch")
            overlayController.show()
        }
    }
}
