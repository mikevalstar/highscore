import SwiftUI
import AppKit

@MainActor
class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func open() {
        if let window {
            Log.settings.info("Settings window already open — bringing to front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        Log.settings.info("Opening settings window")

        let settingsView = SettingsView(settings: settings)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HighScore Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseDelegate.shared

        self.window = window

        // Show in dock while settings is open
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
        // Back to menubar-only
        NSApp.setActivationPolicy(.accessory)
    }

    /// Called by the window delegate when the user closes via the red button
    func windowDidClose() {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Shared delegate that routes windowWillClose back to the app delegate's controller
class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()

    func windowWillClose(_ notification: Notification) {
        Log.settings.info("Settings window closed")
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
