import SwiftUI

/// Placeholder history view showing past transcription sessions.
/// Will be fully implemented in a future iteration.
struct HistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("history.empty_title")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text("history.empty_description")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
