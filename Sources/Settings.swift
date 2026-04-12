import Foundation
import SwiftUI

enum OverlayPosition: String, CaseIterable, Codable {
    case topRight = "Top Right"
    case topLeft = "Top Left"
    case bottomRight = "Bottom Right"
    case bottomLeft = "Bottom Left"

    func origin(overlaySize: CGSize, screenFrame: CGRect, padding: CGFloat = 20) -> CGPoint {
        switch self {
        case .topRight:
            return CGPoint(
                x: screenFrame.maxX - overlaySize.width - padding,
                y: screenFrame.maxY - overlaySize.height - padding
            )
        case .topLeft:
            return CGPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - overlaySize.height - padding
            )
        case .bottomRight:
            return CGPoint(
                x: screenFrame.maxX - overlaySize.width - padding,
                y: screenFrame.minY + padding
            )
        case .bottomLeft:
            return CGPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        }
    }
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("overlayEnabled") var overlayEnabled = false
    @AppStorage("overlayPosition") var overlayPosition: OverlayPosition = .topRight
    @AppStorage("overlayOpacity") var overlayOpacity: Double = 0.85
    @AppStorage("overlayScale") var overlayScale: Double = 1.0
}
