import SwiftUI

/// Audio player bar with play/pause + stop on the left, seek slider with segment markers, and time labels.
struct AudioPlayerBarView: View {
    @Bindable var player: SessionAudioPlayer

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(.quaternary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .contentTransition(.symbolEffect(.replace))

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(.quaternary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
            }

            Text(formatTime(player.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                .controlSize(.small)

                if player.duration > 0 {
                    GeometryReader { geo in
                        ForEach(Array(player.segmentOffsets.dropFirst().enumerated()), id: \.offset) { _, offset in
                            let fraction = offset / player.duration
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(width: 1.5, height: 10)
                                .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }

            Text(formatTime(player.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 48)
        .background(.bar)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
