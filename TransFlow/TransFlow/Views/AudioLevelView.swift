import SwiftUI

/// A small waveform visualization of audio level history.
struct AudioLevelView: View {
    let levels: [Float]
    let isActive: Bool

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(
                        width: 2.5,
                        height: max(2, CGFloat(level) * 20)
                    )
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.1), value: levels)
    }
}
