import SwiftUI

/// A compact waveform visualization of audio level history.
struct AudioLevelView: View {
    let levels: [Float]
    let isActive: Bool

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(levels.suffix(20).enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: level))
                    .frame(
                        width: 2,
                        height: max(2, CGFloat(level) * 16)
                    )
            }
        }
        .frame(width: 70, height: 16)
        .animation(.linear(duration: 0.08), value: levels)
    }

    private func barColor(for level: Float) -> Color {
        guard isActive else {
            return .secondary.opacity(0.2)
        }
        if level > 0.7 {
            return .orange
        } else if level > 0.4 {
            return .accentColor
        } else {
            return .accentColor.opacity(0.6)
        }
    }
}
