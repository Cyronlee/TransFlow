import SwiftUI
import AppKit

/// Redesigned control bar: Audio source (left) | Record button (center) | Language & Translation (right).
/// Apple-inspired clean layout with a prominent circular record button.
struct ControlBarView: View {
    @Bindable var viewModel: TransFlowViewModel

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: Audio source + waveform ──
            leftControls
                .frame(maxWidth: .infinity, alignment: .leading)

            // ── Center: Record button ──
            recordButton

            // ── Right: Language + Translation + Export ──
            rightControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Left Controls

    private var leftControls: some View {
        HStack(spacing: 10) {
            // Audio source menu
            audioSourcePicker

            // Waveform visualization (only when active)
            if viewModel.listeningState == .active {
                AudioLevelView(
                    levels: viewModel.audioLevelHistory,
                    isActive: true
                )
                .transition(.opacity)
            }

            // Error indicator
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                    .help(error)
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            viewModel.toggleListening()
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(recordButtonRingColor, lineWidth: 2.5)
                    .frame(width: 52, height: 52)

                // Animated pulse ring when active
                if viewModel.listeningState == .active {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 60, height: 60)
                        .scaleEffect(viewModel.listeningState == .active ? 1.15 : 1.0)
                        .opacity(viewModel.listeningState == .active ? 0 : 0.5)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: viewModel.listeningState
                        )
                }

                // Inner shape: circle for idle, rounded square for active (stop)
                if viewModel.listeningState == .active {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(recordButtonFillColor)
                        .frame(width: 36, height: 36)
                        .transition(.scale.combined(with: .opacity))
                }

                // Loading state overlay
                if viewModel.listeningState == .starting || viewModel.listeningState == .stopping {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.secondary)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.listeningState)
            .frame(width: 70, height: 70)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.listeningState == .starting || viewModel.listeningState == .stopping)
        .help(Text(recordButtonHelpText))
        .accessibilityLabel(Text(recordButtonAccessibilityLabel))
    }

    private var recordButtonRingColor: Color {
        switch viewModel.listeningState {
        case .idle: .secondary.opacity(0.4)
        case .starting, .stopping: .secondary.opacity(0.3)
        case .active: .red.opacity(0.6)
        }
    }

    private var recordButtonFillColor: Color {
        switch viewModel.listeningState {
        case .idle: .red
        case .starting, .stopping: .red.opacity(0.4)
        case .active: .red
        }
    }

    private var recordButtonHelpText: LocalizedStringKey {
        switch viewModel.listeningState {
        case .idle: "control.start_transcription"
        case .starting: "control.starting"
        case .active: "control.stop_transcription"
        case .stopping: "control.stopping"
        }
    }

    private var recordButtonAccessibilityLabel: LocalizedStringKey {
        switch viewModel.listeningState {
        case .idle: "control.start_recording"
        case .starting: "control.starting"
        case .active: "control.stop_recording"
        case .stopping: "control.stopping"
        }
    }

    // MARK: - Right Controls

    private var rightControls: some View {
        HStack(spacing: 10) {
            // Transcription language picker
            languagePicker

            // Translation controls
            translationControls

            // Export button
            exportButton
        }
    }

    // MARK: - Audio Source Picker

    private var audioSourcePicker: some View {
        Menu {
            Button {
                viewModel.audioSource = .microphone
            } label: {
                Label("control.microphone", systemImage: "mic.fill")
                if case .microphone = viewModel.audioSource {
                    Image(systemName: "checkmark")
                }
            }

            Divider()

            if viewModel.availableApps.isEmpty {
                Text("control.no_apps")
            } else {
                ForEach(viewModel.availableApps) { app in
                    Button {
                        viewModel.audioSource = .appAudio(app)
                    } label: {
                        HStack {
                            Text(app.name)
                            if case .appAudio(let target) = viewModel.audioSource, target?.id == app.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                Task {
                    await viewModel.refreshAvailableApps()
                }
            } label: {
                Label("control.refresh_apps", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 5) {
                audioSourceIconView
                Text(audioSourceName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("control.audio_source"))
    }

    @ViewBuilder
    private var audioSourceIconView: some View {
        switch viewModel.audioSource {
        case .microphone:
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
        case .appAudio(let target):
            if let target, let iconData = target.iconData,
               let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var audioSourceName: String {
        switch viewModel.audioSource {
        case .microphone: String(localized: "control.microphone")
        case .appAudio(let target): target?.name ?? String(localized: "control.app")
        }
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        Menu {
            ForEach(viewModel.availableLanguages, id: \.identifier) { locale in
                Button {
                    viewModel.switchLanguage(to: locale)
                } label: {
                    HStack {
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                        if locale.identifier == viewModel.selectedLanguage.identifier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                Text(languageDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 72, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("control.transcription_language"))
    }

    private var languageDisplayName: String {
        viewModel.selectedLanguage.localizedString(
            forIdentifier: viewModel.selectedLanguage.identifier
        ) ?? viewModel.selectedLanguage.identifier
    }

    // MARK: - Translation Controls

    private var translationControls: some View {
        HStack(spacing: 6) {
            // Translation toggle as a compact icon button
            Button {
                viewModel.translationService.isEnabled.toggle()
                if viewModel.translationService.isEnabled {
                    viewModel.translationService.updateSourceLanguage(from: viewModel.selectedLanguage)
                } else {
                    viewModel.translationService.updateConfiguration()
                }
            } label: {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.translationService.isEnabled ? .white : .primary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(viewModel.translationService.isEnabled
                                  ? AnyShapeStyle(Color.accentColor)
                                  : AnyShapeStyle(.quaternary.opacity(0.5)))
                    )
            }
            .buttonStyle(.plain)
            .help(viewModel.translationService.isEnabled ? Text("control.disable_translation") : Text("control.enable_translation"))

            // Target language picker (shown when translation enabled)
            if viewModel.translationService.isEnabled {
                Menu {
                    ForEach(commonTranslationLanguages, id: \.minimalIdentifier) { lang in
                        Button {
                            viewModel.translationService.targetLanguage = lang
                            viewModel.translationService.updateConfiguration()
                        } label: {
                            HStack {
                                Text(Locale.current.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier)
                                if lang.minimalIdentifier == viewModel.translationService.targetLanguage.minimalIdentifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(targetLanguageShortName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 56, alignment: .leading)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Text("control.translation_target"))
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.translationService.isEnabled)
    }

    private var targetLanguageShortName: String {
        Locale.current.localizedString(
            forIdentifier: viewModel.translationService.targetLanguage.minimalIdentifier
        ) ?? viewModel.translationService.targetLanguage.minimalIdentifier
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            Task {
                await viewModel.exportSRT()
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(viewModel.sentences.isEmpty ? .tertiary : .primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.sentences.isEmpty)
        .help(Text("control.export_srt"))
    }

    // MARK: - Constants

    private var commonTranslationLanguages: [Locale.Language] {
        [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "en"),
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "ko"),
            Locale.Language(identifier: "fr"),
            Locale.Language(identifier: "de"),
            Locale.Language(identifier: "es"),
            Locale.Language(identifier: "pt"),
            Locale.Language(identifier: "ru"),
            Locale.Language(identifier: "ar"),
            Locale.Language(identifier: "it"),
        ]
    }
}
