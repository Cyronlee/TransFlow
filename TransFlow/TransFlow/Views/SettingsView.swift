import SwiftUI
import Speech

/// Settings page with Apple-grade design.
/// Sections: General (Language), Speech Models, Feedback, About (Version).
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    @State private var modelManager = SpeechModelManager.shared
    @State private var hasLoadedModels = false

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

                // ── Speech Models Section ──
                settingsSection(
                    header: "settings.speech_models",
                    icon: "waveform.badge.mic",
                    iconColor: .indigo
                ) {
                    speechModelsContent
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
        .task {
            guard !hasLoadedModels else { return }
            hasLoadedModels = true
            await modelManager.refreshAllStatuses()
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

            default:
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
            if modelManager.supportedLocales.isEmpty {
                // Loading state
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
                ForEach(Array(modelManager.supportedLocales.enumerated()), id: \.element.identifier) { index, locale in
                    if index > 0 {
                        Divider().padding(.leading, 46)
                    }
                    speechModelRow(for: locale)
                }
            }
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
                }
            } label: {
                Text("model_action.download")
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
            Text("model_status.ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)

        case .unsupported, .checking:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
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

    private func openFeedback() {
        if let url = URL(string: "https://github.com/Cyronlee/TransFlow/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}
