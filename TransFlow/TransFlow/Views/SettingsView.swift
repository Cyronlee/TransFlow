import SwiftUI
import Speech
import Carbon.HIToolbox

/// Settings page with Apple-grade design.
/// Sections: General (Language), Speech Models, Diarization Models, Feedback, About (Version).
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    @State private var modelManager = SpeechModelManager.shared
    @State private var diarizationModelManager = DiarizationModelManager.shared
    @State private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var hasLoadedModels = false
    @State private var isManagingSpeechLanguages = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── General Section ──
                settingsSection(
                    header: "settings.general",
                    icon: "gearshape.fill",
                    iconColor: .gray
                ) {
                    languageRow
                    Divider().padding(.leading, 46)
                    appearanceRow
                }

                // ── Hotkeys Section ──
                settingsSection(
                    header: "settings.hotkeys",
                    icon: "keyboard.fill",
                    iconColor: .orange
                ) {
                    hotkeyAccessibilityHintRow

                    hotkeyRow(
                        label: "settings.hotkey.toggle_transcription",
                        icon: "waveform",
                        iconColor: .red,
                        binding: $settings.hotkeyToggleTranscription
                    )
                    Divider().padding(.leading, 46)
                    hotkeyRow(
                        label: "settings.hotkey.toggle_translation",
                        icon: "translate",
                        iconColor: .blue,
                        binding: $settings.hotkeyToggleTranslation
                    )
                    Divider().padding(.leading, 46)
                    hotkeyRow(
                        label: "settings.hotkey.toggle_floating_preview",
                        icon: "rectangle.dock",
                        iconColor: .purple,
                        binding: $settings.hotkeyToggleFloatingPreview
                    )
                    Divider().padding(.leading, 46)
                    hotkeyRow(
                        label: "settings.hotkey.toggle_main_window",
                        icon: "macwindow",
                        iconColor: .green,
                        binding: $settings.hotkeyToggleMainWindow
                    )
                }

                // ── Speech Models Section ──
                settingsSection(
                    header: "settings.speech_models",
                    icon: "waveform.badge.mic",
                    iconColor: .indigo
                ) {
                    speechModelsContent
                }

                // ── Diarization Models Section ──
                settingsSection(
                    header: "settings.diarization_models",
                    icon: "person.2.fill",
                    iconColor: .orange
                ) {
                    diarizationModelContent
                }

                // ── Feedback Section ──
                settingsSection(
                    header: "settings.feedback",
                    icon: "bubble.left.fill",
                    iconColor: .blue
                ) {
                    feedbackRow
                    Divider().padding(.leading, 46)
                    openLogsRow
                }

                // ── About Section ──
                settingsSection(
                    header: "settings.about",
                    icon: "info.circle.fill",
                    iconColor: .secondary
                ) {
                    versionRow
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task(id: "initial-load") {
            guard !hasLoadedModels else { return }
            hasLoadedModels = true
            await modelManager.refreshAllStatuses()
            diarizationModelManager.checkStatus()
        }
        .onAppear {
            if hasLoadedModels {
                Task {
                    await modelManager.refreshAllStatuses()
                    diarizationModelManager.checkStatus()
                }
            }
        }
        .onAppear {
            updateChecker.checkOnceOnLaunch()
        }
        .sheet(isPresented: $isManagingSpeechLanguages) {
            manageSpeechLanguagesSheet
        }
        .onChange(of: isManagingSpeechLanguages) {
            if !isManagingSpeechLanguages {
                Task {
                    await modelManager.refreshAllStatuses()
                }
            }
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(
        header: LocalizedStringKey,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 8)
            .padding(.top, 20)

            // Section content card
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Language Row

    private var languageRow: some View {
        HStack {
            Label {
                Text("settings.language")
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }

            Spacer()

            Picker("", selection: $settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .tint(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Appearance Row

    private var appearanceRow: some View {
        HStack {
            Label {
                Text("settings.appearance")
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: 24)
            }

            Spacer()

            Picker("", selection: $settings.appAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .tint(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Feedback Row

    private var feedbackRow: some View {
        Button {
            openFeedback()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.send_feedback")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("settings.feedback_description")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Version Row

    private var versionRow: some View {
        Group {
            switch updateChecker.status {
            case .updateAvailable(let version, let url):
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.version")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.primary)
                                Text("settings.update_available \(version)")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.orange)
                            }
                        } icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(appVersionString)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            case .upToDate:
                HStack {
                    Label {
                        Text("settings.version")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                            .frame(width: 24)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("settings.up_to_date")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                        Text(appVersionString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            case .checking:
                HStack {
                    Label {
                        Text("settings.version")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        Image(systemName: "number")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appVersionString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            case .failed:
                HStack {
                    Label {
                        Text("settings.version")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.yellow)
                            .frame(width: 24)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("settings.check_failed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(appVersionString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            case .idle:
                HStack {
                    Label {
                        Text("settings.version")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        Image(systemName: "number")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }

                    Spacer()

                    Text(appVersionString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Speech Models Content

    private var speechModelsContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text("settings.speech_models_limit_hint \(modelManager.maximumReservedLocales)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().padding(.leading, 46)

            if modelManager.supportedLocales.isEmpty {
                HStack {
                    Label {
                        Text("settings.models_loading")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 14)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if installedSpeechLocales.isEmpty {
                HStack {
                    Label {
                        Text("settings.speech_models_no_installed")
                            .font(.system(size: 13, weight: .regular))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                ForEach(Array(installedSpeechLocales.enumerated()), id: \.element.identifier) { index, locale in
                    if index > 0 {
                        Divider().padding(.leading, 46)
                    }
                    speechModelRow(for: locale)
                }
            }

            Divider().padding(.leading, 46)

            Button {
                Task {
                    await modelManager.refreshAllStatuses()
                }
            } label: {
                HStack {
                    Label {
                        Text("settings.speech_models_refresh")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 46)

            Button {
                isManagingSpeechLanguages = true
            } label: {
                HStack {
                    Label {
                        Text("settings.speech_models_manage")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var installedSpeechLocales: [Locale] {
        modelManager.supportedLocales
            .filter { (modelManager.localeStatuses[$0.identifier] ?? .checking).isReady }
            .sorted { $0.identifier < $1.identifier }
    }

    private var manageSpeechLanguagesSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("settings.speech_models_manage_title")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if modelManager.supportedLocales.isEmpty {
                        HStack {
                            Label {
                                Text("settings.models_loading")
                                    .font(.system(size: 13, weight: .regular))
                            } icon: {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 24, height: 14)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    } else {
                        ForEach(Array(modelManager.supportedLocales.sorted { $0.identifier < $1.identifier }.enumerated()), id: \.element.identifier) { index, locale in
                            if index > 0 {
                                Divider().padding(.leading, 46)
                            }
                            speechModelRow(for: locale)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("settings.done") {
                    isManagingSpeechLanguages = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 520, height: 420)
        .task {
            await modelManager.refreshAllStatuses()
        }
    }

    private func speechModelRow(for locale: Locale) -> some View {
        let status = modelManager.localeStatuses[locale.identifier] ?? .checking
        let displayName = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier

        return HStack(spacing: 8) {
            // Locale icon and name
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .regular))
                    Text(statusDescription(for: status))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(statusColor(for: status))
                }
            } icon: {
                statusIcon(for: status)
                    .frame(width: 24)
            }

            Spacer()

            // Action button or progress
            speechModelAction(for: locale, status: status)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusIcon(for status: SpeechModelStatus) -> some View {
        switch status {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
        case .unsupported:
            Image(systemName: "xmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        }
    }

    private func statusDescription(for status: SpeechModelStatus) -> LocalizedStringKey {
        switch status {
        case .installed:
            "model_status.installed"
        case .notDownloaded:
            "model_status.not_downloaded"
        case .downloading(let progress):
            "model_status.downloading_percent \(Int(progress * 100))"
        case .failed(let message):
            LocalizedStringKey("model_status.failed_detail \(message)")
        case .unsupported:
            "model_status.unsupported"
        case .checking:
            "model_status.checking"
        }
    }

    private func statusColor(for status: SpeechModelStatus) -> Color {
        switch status {
        case .installed: .green
        case .notDownloaded: .secondary
        case .downloading: .blue
        case .failed: .orange
        case .unsupported: .secondary.opacity(0.5)
        case .checking: .secondary
        }
    }

    @ViewBuilder
    private func speechModelAction(for locale: Locale, status: SpeechModelStatus) -> some View {
        switch status {
        case .notDownloaded, .failed:
            Button {
                Task {
                    await modelManager.downloadModel(for: locale)
                    await modelManager.refreshAllStatuses()
                }
            } label: {
                Text("model_action.add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)

        case .downloading(let progress):
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 60)
                .tint(.blue)

        case .installed:
            Button {
                Task {
                    await modelManager.releaseLocale(locale)
                    await modelManager.refreshAllStatuses()
                }
            } label: {
                Text("model_action.remove")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.quaternary.opacity(0.7))
                    )
            }
            .buttonStyle(.plain)

        case .unsupported, .checking:
            EmptyView()
        }
    }

    // MARK: - Diarization Model Content

    private var diarizationModelContent: some View {
        VStack(spacing: 0) {
            // Model status row
            HStack(spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.diarization.pyannote_model")
                            .font(.system(size: 13, weight: .regular))
                        Text(diarizationStatusDescription)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(diarizationStatusColor)
                    }
                } icon: {
                    diarizationStatusIcon
                        .frame(width: 24)
                }

                Spacer()

                Text("~100 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)

                diarizationModelAction
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var diarizationStatusIcon: some View {
        switch diarizationModelManager.modelStatus {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        }
    }

    private var diarizationStatusDescription: LocalizedStringKey {
        switch diarizationModelManager.modelStatus {
        case .installed: "model_status.installed"
        case .notDownloaded: "model_status.not_downloaded"
        case .downloading(let progress): "model_status.downloading_percent \(Int(progress * 100))"
        case .failed(let message): LocalizedStringKey("model_status.failed_detail \(message)")
        case .checking: "model_status.checking"
        }
    }

    private var diarizationStatusColor: Color {
        switch diarizationModelManager.modelStatus {
        case .installed: .green
        case .notDownloaded: .secondary
        case .downloading: .blue
        case .failed: .orange
        case .checking: .secondary
        }
    }

    @ViewBuilder
    private var diarizationModelAction: some View {
        switch diarizationModelManager.modelStatus {
        case .notDownloaded, .failed:
            Button {
                Task {
                    await diarizationModelManager.downloadModels()
                }
            } label: {
                Text("model_action.select")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)

        case .downloading(let progress):
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 60)
                .tint(.blue)

        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("model_status.ready")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.green.opacity(0.12))
            )

        case .checking:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0"
    }

    // MARK: - Open Logs Row

    private var openLogsRow: some View {
        Button {
            ErrorLogger.shared.openLogsFolder()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.open_logs")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("settings.open_logs_description")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                }

                Spacer()

                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hotkey Accessibility Hint

    @ViewBuilder
    private var hotkeyAccessibilityHintRow: some View {
        if hotkeyManager.isAccessibilityGranted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
                Text("settings.hotkey.accessibility_granted")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.leading, 46)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                Text("settings.hotkey.accessibility_hint")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                Button {
                    hotkeyManager.requestAccessibility()
                } label: {
                    Text("settings.hotkey.grant_access")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("settings.hotkey.open_accessibility")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.leading, 46)
        }
    }

    // MARK: - Hotkey Row

    private func hotkeyRow(
        label: LocalizedStringKey,
        icon: String,
        iconColor: Color,
        binding: Binding<HotkeyBinding>
    ) -> some View {
        HStack {
            Label {
                Text(label)
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
            }

            Spacer()

            HotkeyRecorderView(binding: binding)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openFeedback() {
        if let url = URL(string: "https://github.com/Cyronlee/TransFlow/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if !binding.isEmpty {
                Button {
                    binding = .empty
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(displayText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? .white : (binding.isEmpty ? .secondary : .primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minWidth: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isRecording
                                  ? AnyShapeStyle(Color.accentColor)
                                  : AnyShapeStyle(.quaternary.opacity(0.5)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = event.keyCode

            if keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if modifiers.isEmpty { return nil }

            binding = HotkeyBinding(
                keyCode: keyCode,
                modifiers: modifiers.rawValue
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private var displayText: String {
        if isRecording {
            return String(localized: "settings.hotkey.recording")
        }
        if binding.isEmpty {
            return String(localized: "settings.hotkey.not_set")
        }
        return binding.displayString
    }
}
