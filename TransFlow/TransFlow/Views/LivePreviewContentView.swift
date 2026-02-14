import SwiftUI

/// Reusable live preview card used by the bottom panel.
struct LivePreviewContentView: View {
    let partialText: String
    let partialTranslation: String?
    let isListening: Bool
    var idleTextKey: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !partialText.isEmpty {
                Text(partialText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let partialTranslation, !partialTranslation.isEmpty {
                    Text(partialTranslation)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .italic()
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isListening {
                HStack(spacing: 6) {
                    TypingIndicatorView()
                    Text("control.listening")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let idleTextKey {
                Text(idleTextKey)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
    }
}

/// An animated three-dot indicator for the "Listening..." state.
struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.tertiary)
                    .frame(width: 4, height: 4)
                    .offset(y: animating ? -2 : 2)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
