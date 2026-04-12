import SwiftUI

@main
struct HighScoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var scoreManager = ScoreManager()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                scoreManager: scoreManager,
                settings: settings,
                overlayController: appDelegate.overlayController,
                settingsController: appDelegate.settingsController
            )
            .onAppear {
                Log.app.info("MenuBarExtra appeared")
                if appDelegate.overlayController.scoreManager == nil {
                    Log.app.info("Wiring up overlay controller")
                    appDelegate.overlayController.wireUp(settings: settings, scoreManager: scoreManager)
                }
                if appDelegate.settingsController == nil {
                    Log.app.info("Creating settings window controller")
                    appDelegate.settingsController = SettingsWindowController(settings: settings)
                }
                if settings.overlayEnabled {
                    Log.app.info("Restoring overlay (was enabled)")
                    appDelegate.overlayController.show()
                }
            }
        } label: {
            Label("HighScore", systemImage: "trophy.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayController = OverlayWindowController()
    var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Application launched")
        NSApp.setActivationPolicy(.accessory)
    }
}
