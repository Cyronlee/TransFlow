import SwiftUI

/// Bottom control bar with listening controls, audio source, language selection, translation, and export.
struct ControlBarView: View {
    @Bindable var viewModel: TransFlowViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Start/Stop button
            listenButton

            Divider()
                .frame(height: 20)

            // Audio source picker
            audioSourcePicker

            Divider()
                .frame(height: 20)

            // Transcription language picker
            languagePicker

            Divider()
                .frame(height: 20)

            // Translation toggle + target language
            translationControls

            Spacer()

            // Waveform
            AudioLevelView(
                levels: viewModel.audioLevelHistory,
                isActive: viewModel.listeningState == .active
            )

            Divider()
                .frame(height: 20)

            // Export button
            exportButton

            // Error indicator
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Subviews

    private var listenButton: some View {
        Button {
            viewModel.toggleListening()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: listenButtonIcon)
                    .symbolEffect(.pulse, isActive: viewModel.listeningState == .starting)
                Text(listenButtonTitle)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.listeningState == .active ? .red : .accentColor)
        .disabled(viewModel.listeningState == .starting || viewModel.listeningState == .stopping)
    }

    private var listenButtonIcon: String {
        switch viewModel.listeningState {
        case .idle: "record.circle"
        case .starting: "hourglass"
        case .active: "stop.circle.fill"
        case .stopping: "hourglass"
        }
    }

    private var listenButtonTitle: String {
        switch viewModel.listeningState {
        case .idle: "Start"
        case .starting: "Starting..."
        case .active: "Stop"
        case .stopping: "Stopping..."
        }
    }

    private var audioSourcePicker: some View {
        Menu {
            Button {
                viewModel.audioSource = .microphone
            } label: {
                Label("Microphone", systemImage: "mic.fill")
            }

            Divider()

            if viewModel.availableApps.isEmpty {
                Text("No apps available")
            } else {
                ForEach(viewModel.availableApps) { app in
                    Button {
                        viewModel.audioSource = .appAudio(app)
                    } label: {
                        Text(app.name)
                    }
                }
            }

            Divider()

            Button("Refresh Apps") {
                Task {
                    await viewModel.refreshAvailableApps()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: audioSourceIcon)
                Text(audioSourceName)
                    .lineLimit(1)
                    .frame(maxWidth: 100)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var audioSourceIcon: String {
        switch viewModel.audioSource {
        case .microphone: "mic.fill"
        case .appAudio: "app.fill"
        }
    }

    private var audioSourceName: String {
        switch viewModel.audioSource {
        case .microphone: "Mic"
        case .appAudio(let target): target?.name ?? "App"
        }
    }

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
                Text(viewModel.selectedLanguage.localizedString(
                    forIdentifier: viewModel.selectedLanguage.identifier
                ) ?? viewModel.selectedLanguage.identifier)
                .lineLimit(1)
                .frame(maxWidth: 80)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var translationControls: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Bindable(viewModel.translationService).isEnabled) {
                Image(systemName: "translate")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: viewModel.translationService.isEnabled) {
                // Ensure source language is synced before creating config
                viewModel.translationService.updateSourceLanguage(from: viewModel.selectedLanguage)
            }

            if viewModel.translationService.isEnabled {
                Text("→")
                    .foregroundStyle(.secondary)

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
                    Text(Locale.current.localizedString(
                        forIdentifier: viewModel.translationService.targetLanguage.minimalIdentifier
                    ) ?? viewModel.translationService.targetLanguage.minimalIdentifier)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var exportButton: some View {
        Button {
            Task {
                await viewModel.exportSRT()
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(viewModel.sentences.isEmpty)
        .help("Export SRT")
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
