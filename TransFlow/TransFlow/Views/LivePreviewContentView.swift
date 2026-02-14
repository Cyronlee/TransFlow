import SwiftUI

/// Reusable live preview card used by both the bottom panel and floating window.
struct LivePreviewContentView: View {
    let partialText: String
    let partialTranslation: String?
    let isListening: Bool
    var idleTextKey: LocalizedStringKey? = nil
    var usesGlassStyle: Bool = false
    var maxContentHeight: CGFloat? = nil
    var allowsScrolling: Bool = false
    var prioritizeNewestText: Bool = false

    var body: some View {
        Group {
            if allowsScrolling {
                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: maxContentHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardFillStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(usesGlassStyle ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.6)
        )
    }

    private var cardFillStyle: AnyShapeStyle {
        if usesGlassStyle {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(.quaternary.opacity(0.3))
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !partialText.isEmpty {
                Text(partialText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(allowsScrolling ? nil : 3)
                    .truncationMode(prioritizeNewestText ? .head : .tail)
                    .fixedSize(horizontal: false, vertical: allowsScrolling)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let partialTranslation, !partialTranslation.isEmpty {
                    Text(partialTranslation)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .italic()
                        .lineLimit(allowsScrolling ? nil : 2)
                        .fixedSize(horizontal: false, vertical: allowsScrolling)
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
