import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("HighScore Settings")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .padding(.top, 4)

            GroupBox("Overlay") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.overlayEnabled) {
                        Text("Show overlay")
                            .font(.system(size: 12, design: .monospaced))
                    }

                    Divider()

                    Text("Position")
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
                        Text("Opacity")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $settings.overlayOpacity, in: 0.3...1.0, step: 0.05)
                        Text("\(Int(settings.overlayOpacity * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 35, alignment: .trailing)
                    }

                    HStack {
                        Text("Size")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $settings.overlayScale, in: 0.5...2.0, step: 0.1)
                        Text("\(String(format: "%.1f", settings.overlayScale))x")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 35, alignment: .trailing)
                    }
                }
                .padding(8)
            }

            // Preview
            GroupBox("Preview") {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.8))
                        .frame(height: 60)

                    SevenSegmentScore(score: 1_234_567)
                        .frame(height: 36)
                        .opacity(settings.overlayOpacity)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 340)
    }
}
