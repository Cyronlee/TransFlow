import SwiftUI
import AppKit

/// Redesigned control bar: Audio source (left) | Record button (center) | Language & Translation (right).
/// Apple-inspired clean layout with a prominent circular record button.
struct ControlBarView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var floatingPreviewManager: FloatingPreviewPanelManager
    @Bindable var settings: AppSettings
    @State private var diarizationModelManager = DiarizationModelManager.shared

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: Audio source + waveform ──
            leftControls
                .frame(maxWidth: .infinity, alignment: .leading)

            // ── Center: Record button ──
            VStack(spacing: 4) {
                recordButton
                if isDownloadingModel {
                    Text("control.downloading_model")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isDownloadingModel)

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
                    if isDownloadingModel {
                        Circle()
                            .trim(from: 0, to: viewModel.modelManager.downloadProgress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: viewModel.modelManager.downloadProgress)
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.secondary)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.listeningState)
            .frame(width: 70, height: 70)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .disabled(viewModel.listeningState == .starting || viewModel.listeningState == .stopping)
        .help(Text(recordButtonHelpText))
        .accessibilityLabel(Text(recordButtonAccessibilityLabel))
    }

    private var isDownloadingModel: Bool {
        viewModel.listeningState == .starting && viewModel.modelManager.currentModelStatus.isDownloading
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

            // Speaker diarization toggle
            diarizationToggle

            // Floating preview button
            popUpPreviewButton
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

            Button {
                viewModel.audioSource = .systemAudio
            } label: {
                Label("control.system_audio", systemImage: "speaker.wave.2.fill")
                if case .systemAudio = viewModel.audioSource {
                    Image(systemName: "checkmark")
                }
            }

            Button {
                viewModel.audioSource = .microphoneAndSystemAudio
            } label: {
                Label("control.mic_and_system", systemImage: "mic.and.signal.meter.fill")
                if case .microphoneAndSystemAudio = viewModel.audioSource {
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
                        if let iconData = app.iconData,
                           let nsImage = NSImage(data: iconData) {
                            Label { Text(app.name) } icon: { Image(nsImage: nsImage) }
                        } else {
                            Label(app.name, systemImage: "app.fill")
                        }
                        if case .appAudio(let target) = viewModel.audioSource, target?.id == app.id {
                            Image(systemName: "checkmark")
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
        case .systemAudio:
            Image(systemName: "speaker.wave.2.fill")
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
        case .microphoneAndSystemAudio:
            Image(systemName: "mic.and.signal.meter.fill")
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var audioSourceName: String {
        switch viewModel.audioSource {
        case .microphone: String(localized: "control.microphone")
        case .systemAudio: String(localized: "control.system_audio")
        case .appAudio(let target): target?.name ?? String(localized: "control.app")
        case .microphoneAndSystemAudio: String(localized: "control.mic_and_system")
        }
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        Menu {
            if viewModel.availableLanguages.isEmpty {
                Label("control.language_none_warning", systemImage: "exclamationmark.triangle")
            } else {
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
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .navigateToSettings, object: nil)
            } label: {
                Label("model_action.manage_languages", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.availableLanguages.isEmpty ? "exclamationmark.triangle" : "globe")
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
        guard !viewModel.availableLanguages.isEmpty else {
            return String(localized: "control.language_none")
        }
        return viewModel.selectedLanguage.localizedString(
            forIdentifier: viewModel.selectedLanguage.identifier
        ) ?? viewModel.selectedLanguage.identifier
    }

    // MARK: - Translation Controls

    private var translationControls: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.translationService.isEnabled.toggle()
                if viewModel.translationService.isEnabled {
                    viewModel.translationService.updateSourceLanguage(from: viewModel.selectedLanguage)
                    Task {
                        await viewModel.translationService.refreshAndAutoSelect(force: true)
                    }
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

            if viewModel.translationService.isEnabled {
                Menu {
                    let available = viewModel.translationService.availableTargetLanguages
                    if available.isEmpty {
                        Text("control.translation_none_available")
                    } else {
                        ForEach(available, id: \.minimalIdentifier) { lang in
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
                    }

                    Divider()

                    Button {
                        NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                    } label: {
                        Label("model_action.manage_languages", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(targetLanguageDisplayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: 56, alignment: .leading)
                    }
                    .foregroundStyle(targetLanguageIsAvailable ? .primary : .secondary)
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

    private var targetLanguageIsAvailable: Bool {
        viewModel.translationService.availableTargetLanguages.contains {
            $0.minimalIdentifier == viewModel.translationService.targetLanguage.minimalIdentifier
        }
    }

    private var targetLanguageDisplayName: String {
        if viewModel.translationService.availableTargetLanguages.isEmpty {
            return String(localized: "control.translation_unavailable")
        }
        return Locale.current.localizedString(
            forIdentifier: viewModel.translationService.targetLanguage.minimalIdentifier
        ) ?? viewModel.translationService.targetLanguage.minimalIdentifier
    }

    // MARK: - Diarization Toggle

    private var diarizationToggle: some View {
        Button {
            settings.liveEnableDiarization.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 12, weight: .medium))

                if viewModel.isDiarizationEnabled && viewModel.activeSpeakerCount > 0 {
                    Text("\(viewModel.activeSpeakerCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(settings.liveEnableDiarization ? .white : .primary)
            .frame(height: 26)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(settings.liveEnableDiarization
                          ? AnyShapeStyle(Color.orange)
                          : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
        }
        .buttonStyle(.plain)
        .disabled(!diarizationModelManager.modelStatus.isReady)
        .opacity(diarizationModelManager.modelStatus.isReady ? 1.0 : 0.4)
        .help(diarizationHelpText)
        .task(id: "diarization-status") {
            diarizationModelManager.checkStatus()
        }
    }

    private var diarizationHelpText: Text {
        if !diarizationModelManager.modelStatus.isReady {
            Text("control.diarization_model_required")
        } else if settings.liveEnableDiarization {
            Text("control.disable_diarization")
        } else {
            Text("control.enable_diarization")
        }
    }

    // MARK: - Pop Up Preview Button

    private var popUpPreviewButton: some View {
        Button {
            floatingPreviewManager.toggle(
                viewModel: viewModel,
                locale: settings.locale,
                colorScheme: settings.appAppearance.colorScheme
            )
        } label: {
            Image(systemName: "rectangle.dock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(floatingPreviewManager.isVisible ? .white : .primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(floatingPreviewManager.isVisible
                              ? AnyShapeStyle(Color.accentColor)
                              : AnyShapeStyle(.quaternary.opacity(0.5)))
                )
        }
        .buttonStyle(.plain)
        .help(floatingPreviewManager.isVisible ? Text("control.close_preview") : Text("control.pop_up_preview"))
        .accessibilityLabel(floatingPreviewManager.isVisible ? Text("control.close_preview") : Text("control.pop_up_preview"))
    }

    // MARK: - Constants

    private var commonTranslationLanguages: [Locale.Language] {
        TranslationService.supportedTargetLanguages
    }
}
