import Foundation
import SwiftUI

enum OverlayPosition: String, CaseIterable, Codable {
    case topRight = "Top Right"
    case topLeft = "Top Left"
    case bottomRight = "Bottom Right"
    case bottomLeft = "Bottom Left"

    /// Calculates the window origin (bottom-left in macOS coords) so the overlay's
    /// named corner is pinned to the matching screen corner, offset inward by (offsetX, offsetY).
    func origin(overlaySize: CGSize, screenFrame: CGRect, offsetX: CGFloat, offsetY: CGFloat) -> CGPoint {
        switch self {
        case .topRight:
            return CGPoint(
                x: screenFrame.maxX - overlaySize.width - offsetX,
                y: screenFrame.maxY - overlaySize.height - offsetY
            )
        case .topLeft:
            return CGPoint(
                x: screenFrame.minX + offsetX,
                y: screenFrame.maxY - overlaySize.height - offsetY
            )
        case .bottomRight:
            return CGPoint(
                x: screenFrame.maxX - overlaySize.width - offsetX,
                y: screenFrame.minY + offsetY
            )
        case .bottomLeft:
            return CGPoint(
                x: screenFrame.minX + offsetX,
                y: screenFrame.minY + offsetY
            )
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("overlayEnabled") var overlayEnabled = false
    @AppStorage("overlayPosition") var overlayPosition: OverlayPosition = .topRight
    @AppStorage("overlayBackgroundOpacity") var overlayBackgroundOpacity: Double = 0.75
    @AppStorage("overlayDisplayOpacity") var overlayDisplayOpacity: Double = 0.85
    @AppStorage("overlayScale") var overlayScale: Double = 1.0
    @AppStorage("overlayOffsetX") var overlayOffsetX: Double = 20
    @AppStorage("overlayOffsetY") var overlayOffsetY: Double = 20

    /// Whether to show the score panel in the overlay
    @AppStorage("overlayShowScores") var overlayShowScores: Bool = true

    /// Whether to show the RPG panel in the overlay
    @AppStorage("overlayShowRPG") var overlayShowRPG: Bool = false

    /// Opacity for the score panel (independent from RPG)
    @AppStorage("overlayScoreOpacity") var overlayScoreOpacity: Double = 0.85

    /// Opacity for the RPG panel (independent from scores)
    @AppStorage("overlayRPGOpacity") var overlayRPGOpacity: Double = 0.85

    /// Show floating "+XP" popups above the overlay when new usage is detected
    @AppStorage("showXPPopups") var showXPPopups: Bool = false

    /// Which panel to show in the menubar popover: "scores", "rpg", or "both"
    @AppStorage("displayMode") var displayMode: String = "scores"

    /// Whether to show the daily (T) score in the menubar and overlay
    @AppStorage("showDailyScore") var showDailyScore: Bool = true

    /// Whether to show the weekly (W) score in the menubar and overlay
    @AppStorage("showWeeklyScore") var showWeeklyScore: Bool = true

    /// Hex color for the main score display (default green)
    @AppStorage("scoreColorHex") var scoreColorHex: String = "#00FF00"

    /// Hex color for the today score display (default cyan)
    @AppStorage("todayScoreColorHex") var todayScoreColorHex: String = "#00FFFF"

    /// Hex color for the week score display (default orange)
    @AppStorage("weekScoreColorHex") var weekScoreColorHex: String = "#FF8C00"

    /// Which visual style to use for score digits across the app.
    @AppStorage("displayStyle") var displayStyle: ScoreDisplayStyle = .sevenSegment

    /// How often (in seconds) to re-scan files for new token usage.
    @AppStorage("refreshInterval") var refreshInterval: Double = 5

    /// Whether to include cached tokens (cache reads and cache creations) in the
    /// total score. When off, only input/output/reasoning tokens count toward
    /// totals and period (daily/weekly) calculations.
    @AppStorage("includeCachedTokens") var includeCachedTokens: Bool = true

    /// Unix timestamp (seconds since 1970) for when to start counting tokens.
    /// Files modified before this date are excluded. Set to 0 means "not yet initialized".
    @AppStorage("startDate") var startDate: Double = 0

    /// Initializes startDate to now on first launch. Call once at app startup.
    func initializeStartDateIfNeeded() {
        if startDate == 0 {
            startDate = Date().timeIntervalSince1970
            Log.settings.notice("First launch — startDate set to \(self.startDate, privacy: .public)")
        } else {
            Log.settings.info("startDate already set: \(self.startDate, privacy: .public)")
        }
    }

    /// Resets startDate to now and returns the new value.
    @discardableResult
    func resetStartDate() -> Double {
        startDate = Date().timeIntervalSince1970
        Log.settings.notice("startDate reset to \(self.startDate, privacy: .public)")
        return startDate
    }

    // MARK: - Computed Color Properties

    var scoreColor: Color {
        get { Color(hex: scoreColorHex) ?? .green }
        set { scoreColorHex = newValue.toHex() ?? "#00FF00" }
    }

    var todayScoreColor: Color {
        get { Color(hex: todayScoreColorHex) ?? .cyan }
        set { todayScoreColorHex = newValue.toHex() ?? "#00FFFF" }
    }

    var weekScoreColor: Color {
        get { Color(hex: weekScoreColorHex) ?? .orange }
        set { weekScoreColorHex = newValue.toHex() ?? "#FF8C00" }
    }

    /// Resets all score colors to their defaults.
    func resetColorsToDefaults() {
        scoreColorHex = "#00FF00"
        todayScoreColorHex = "#00FFFF"
        weekScoreColorHex = "#FF8C00"
        Log.settings.notice("Score colors reset to defaults")
    }
}

// MARK: - Color ↔ Hex Conversion

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(components.redComponent * 255))
        let g = Int(round(components.greenComponent * 255))
        let b = Int(round(components.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
