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
}
