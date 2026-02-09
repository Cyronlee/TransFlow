import SwiftUI
import Translation

/// Main content view with history area on top and unified bottom panel
/// (live preview + controls).
///
/// The ViewModel is injected from `MainView` so it is created only once
/// at app launch — not every time the user navigates to this tab.
struct ContentView: View {
    @Bindable var viewModel: TransFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: Session bar ──
            SessionBarView(
                sessionName: viewModel.jsonlStore.currentSessionName
            ) { name in
                viewModel.createNewSession(name: name)
            }

            // ── Middle: Transcription history ──
            TranscriptionView(
                sentences: viewModel.sentences,
                isTranslationEnabled: viewModel.translationService.isEnabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Bottom: Unified live preview + controls ──
            BottomPanelView(viewModel: viewModel)
        }
        .frame(minWidth: 640, minHeight: 460)
        // Translation session provider
        .translationTask(viewModel.translationService.configuration) { session in
            await viewModel.translationService.handleSession(session)
        }
        // Empty state
        .overlay {
            if viewModel.sentences.isEmpty && viewModel.currentPartialText.isEmpty {
                emptyStateView
            }
        }
        // Model not ready alert — prompts user to download in Settings
        .alert(
            "model_alert.title",
            isPresented: $viewModel.showModelNotReadyAlert
        ) {
            Button("model_alert.go_to_settings") {
                NotificationCenter.default.post(name: .navigateToSettings, object: nil)
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            Text("model_alert.message")
        }
        // Menu command handlers
        .onReceive(NotificationCenter.default.publisher(for: .clearHistory)) { _ in
            viewModel.clearHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportSRT)) { _ in
            Task {
                await viewModel.exportSRT()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("empty_state.title")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if !viewModel.micPermissionGranted {
                Label("empty_state.mic_permission", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .allowsHitTesting(false)
        .offset(y: -40) // shift up slightly since bottom panel takes space
    }
}

// MARK: - Bottom Panel (Live Preview + Controls)

/// Unified bottom panel containing the live transcription preview and controls.
struct BottomPanelView: View {
    @Bindable var viewModel: TransFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Subtle top border
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)

            VStack(spacing: 12) {
                // ── Live transcription preview ──
                livePreviewSection

                // ── Controls row ──
                ControlBarView(viewModel: viewModel)
            }
            .animation(.easeInOut(duration: 0.25), value: shouldShowPreview)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(.background)
        }
    }

    private var shouldShowPreview: Bool {
        viewModel.listeningState == .active
            || viewModel.listeningState == .starting
            || !viewModel.currentPartialText.isEmpty
    }

    @ViewBuilder
    private var livePreviewSection: some View {
        if shouldShowPreview {
            VStack(alignment: .leading, spacing: 3) {
                if !viewModel.currentPartialText.isEmpty {
                    Text(viewModel.currentPartialText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.translationService.isEnabled,
                       !viewModel.translationService.currentPartialTranslation.isEmpty {
                        Text(viewModel.translationService.currentPartialTranslation)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .italic()
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Listening indicator when active but no partial text yet
                    HStack(spacing: 6) {
                        TypingIndicatorView()
                        Text("control.listening")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
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
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - Typing Indicator

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

#Preview {
    ContentView(viewModel: TransFlowViewModel())
}
