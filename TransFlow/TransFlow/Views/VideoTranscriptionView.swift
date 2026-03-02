import SwiftUI
import AVKit
@preconcurrency import Translation

/// Main video transcription page.
/// - Idle: file picker + configuration
/// - Processing: progress display
/// - Completed: video player (top) + synced transcript (bottom)
struct VideoTranscriptionView: View {
    @State private var viewModel = VideoTranscriptionViewModel()
    @State private var isDroppingFile = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .completed:
                resultView
            case .idle, .selectingFile:
                setupView
            case .failed(let message):
                VStack(spacing: 0) {
                    setupView
                    errorBanner(message)
                }
            default:
                progressView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .translationTask(viewModel.translationService.configuration) { session in
            await viewModel.translationService.handleSession(session)
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                filePickerSection
                configurationSection
                startButton
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }

    // MARK: - File Picker

    private var filePickerSection: some View {
        VStack(spacing: 16) {
            if viewModel.selectedFileURL != nil {
                selectedFileCard
            } else {
                dropZone
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(isDroppingFile ? Color.accentColor : .secondary)

            Text("video.drop_zone.title")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text("video.drop_zone.subtitle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Button {
                openFilePicker()
            } label: {
                Text("video.drop_zone.browse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDroppingFile ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDroppingFile ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFile) { providers in
            handleDrop(providers)
        }
    }

    private var selectedFileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedFileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if viewModel.videoDuration > 0 {
                    Text(formatDuration(viewModel.videoDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                viewModel.clearFile()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.gray)
                Text("video.config.title")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                // Transcription language
                configRow {
                    Label {
                        Text("video.config.source_language")
                            .font(.system(size: 13))
                    } icon: {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                    }
                } trailing: {
                    Picker("", selection: $viewModel.selectedLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .tint(.secondary)
                }

                Divider().padding(.leading, 46)

                // Translation toggle
                configRow {
                    Label {
                        Text("video.config.enable_translation")
                            .font(.system(size: 13))
                    } icon: {
                        Image(systemName: "translate")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(width: 24)
                    }
                } trailing: {
                    Toggle("", isOn: $viewModel.enableTranslation)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: viewModel.enableTranslation) {
                            viewModel.translationService.isEnabled = viewModel.enableTranslation
                            if viewModel.enableTranslation {
                                viewModel.translationService.updateSourceLanguage(from: viewModel.selectedLanguage)
                                viewModel.translationService.updateConfiguration()
                            }
                        }
                }

                if viewModel.enableTranslation {
                    Divider().padding(.leading, 46)

                    configRow {
                        Label {
                            Text("video.config.target_language")
                                .font(.system(size: 13))
                        } icon: {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                        }
                    } trailing: {
                        Picker("", selection: $viewModel.targetLanguage) {
                            Text("中文 (简体)").tag(Locale.Language(identifier: "zh-Hans"))
                            Text("English").tag(Locale.Language(identifier: "en"))
                            Text("日本語").tag(Locale.Language(identifier: "ja"))
                            Text("한국어").tag(Locale.Language(identifier: "ko"))
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .tint(.secondary)
                        .onChange(of: viewModel.targetLanguage) {
                            viewModel.translationService.targetLanguage = viewModel.targetLanguage
                            viewModel.translationService.updateConfiguration()
                        }
                    }
                }

                Divider().padding(.leading, 46)

                // Diarization toggle
                configRow {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("video.config.enable_diarization")
                                .font(.system(size: 13))
                            Text("video.config.diarization_description")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                    }
                } trailing: {
                    Toggle("", isOn: $viewModel.enableDiarization)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func configRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            viewModel.startTranscription()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("video.start_transcription")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(viewModel.selectedFileURL != nil ? Color.accentColor : Color.gray)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedFileURL == nil)
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.overallProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 400)
                .tint(.accentColor)

            VStack(spacing: 8) {
                Text(viewModel.progressMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Text("\(Int(viewModel.overallProgress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                viewModel.cancelProcessing()
            } label: {
                Text("video.cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result View

    private var resultView: some View {
        VSplitView {
            // Video player (top)
            videoPlayerSection
                .frame(minHeight: 200, idealHeight: 300)

            // Transcript (bottom)
            transcriptSection
                .frame(minHeight: 200)
        }
    }

    private var videoPlayerSection: some View {
        VStack(spacing: 0) {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 40, weight: .thin))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isVideoPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Text(formatTime(viewModel.currentPlaybackTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { viewModel.currentPlaybackTime },
                        set: { newValue in
                            let time = CMTime(seconds: newValue, preferredTimescale: 600)
                            viewModel.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                            viewModel.currentPlaybackTime = newValue
                        }
                    ),
                    in: 0...max(viewModel.videoDuration, 0.1)
                )
                .tint(.accentColor)

                Text(formatTime(viewModel.videoDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 50, alignment: .leading)

                Button {
                    viewModel.clearFile()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("video.new_transcription")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.background)
        }
    }

    private var transcriptSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                        VideoSegmentRow(
                            segment: segment,
                            isActive: viewModel.activeSegmentIndex == index,
                            onTap: {
                                viewModel.seekToSegment(at: index)
                                if !viewModel.isVideoPlaying {
                                    viewModel.togglePlayback()
                                }
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.activeSegmentIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.state = .idle
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - File Picker Helpers

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.selectFile(url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await viewModel.selectFile(url)
            }
        }
        return true
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Segment Row

struct VideoSegmentRow: View {
    let segment: VideoTranscriptionSegment
    var isActive: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(height: 0.5)
                .padding(.vertical, 8)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Timestamp badge
                Text(timeString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AnyShapeStyle(Color.accentColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .onTapGesture {
                        onTap?()
                    }

                // Speaker badge
                if let speakerId = segment.speakerId {
                    speakerBadge(speakerId)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    if let translation = segment.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }

    private func speakerBadge(_ speakerId: String) -> some View {
        let colorHex = SpeakerColor.color(for: speakerId)
        let displayName = speakerId.replacingOccurrences(of: "_", with: " ")

        return Text(displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: colorHex))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: colorHex).opacity(0.12))
            )
    }

    private var timeString: String {
        let m = Int(segment.startTime) / 60
        let s = Int(segment.startTime) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
