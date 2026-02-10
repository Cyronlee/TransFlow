import SwiftUI
import Speech

/// Settings page with Apple-grade design.
/// Sections: General (Language), Speech Models, Feedback, About (Version).
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    @State private var modelManager = SpeechModelManager.shared
    @State private var localModelManager = LocalModelManager.shared
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

                // ── Speech Recognition Engine Section ──
                settingsSection(
                    header: "settings.engine",
                    icon: "brain",
                    iconColor: .green
                ) {
                    enginePickerRow
                    if settings.selectedEngine == .local {
                        Divider().padding(.leading, 46)
                        localModelContent
                    }
                }

                // ── Speech Models Section (Apple engine only) ──
                if settings.selectedEngine == .apple {
                    settingsSection(
                        header: "settings.speech_models",
                        icon: "waveform.badge.mic",
                        iconColor: .indigo
                    ) {
                        speechModelsContent
                    }
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
            localModelManager.checkAllStatuses()
        }
        .onChange(of: settings.selectedEngine) { _, newEngine in
            switch newEngine {
            case .apple:
                Task {
                    await modelManager.refreshAllStatuses()
                }
            case .local:
                localModelManager.checkStatus(for: settings.selectedLocalModel)
            }
        }
        .onChange(of: settings.selectedLocalModel) { _, newModel in
            localModelManager.checkStatus(for: newModel)
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

    // MARK: - Engine Picker

    private var enginePickerRow: some View {
        HStack {
            Label {
                Text("settings.engine")
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(width: 24)
            }

            Spacer()

            Picker("", selection: $settings.selectedEngine) {
                ForEach(TranscriptionEngineKind.allCases) { engine in
                    Text(engine.displayName)
                        .tag(engine)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .tint(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Local Model Content

    private var localModelContent: some View {
        VStack(spacing: 0) {
            localModelPickerRow
            Divider().padding(.leading, 46)
            // Model status row
            localModelStatusRow
            Divider().padding(.leading, 46)
            // Action row (download / delete)
            localModelActionRow
            Divider().padding(.leading, 46)
            // License notice
            localModelLicenseRow
        }
    }

    private var localModelPickerRow: some View {
        HStack {
            Label {
                Text("settings.local_model")
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.mint)
                    .frame(width: 24)
            }

            Spacer()

            Picker("", selection: $settings.selectedLocalModel) {
                ForEach(LocalTranscriptionModelKind.allCases) { model in
                    Text(model.displayName)
                        .tag(model)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .tint(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var localModelStatusRow: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.selectedLocalModel.displayName)
                        .font(.system(size: 13, weight: .regular))
                    Text(localModelStatusText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(localModelStatusColor)
                    if let progressText = localDownloadProgressText {
                        Text(progressText)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                localModelStatusIcon
                    .frame(width: 24)
            }

            Spacer()

            if localModelStatus.isReady {
                Text(formattedDiskSize)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var localModelStatusIcon: some View {
        switch localModelStatus {
        case .ready:
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
        }
    }

    private var localModelStatusText: LocalizedStringKey {
        switch localModelStatus {
        case .ready:
            "settings.model.status.ready"
        case .notDownloaded:
            selectedLocalModelNotDownloadedKey
        case .downloading(let progress):
            if localModelDownloadDetail?.isResuming == true {
                "settings.model.status.resuming \(Int(progress * 100))"
            } else {
                "settings.model.status.downloading \(Int(progress * 100))"
            }
        case .failed(let message):
            "settings.model.status.failed \(message)"
        }
    }

    private var localModelStatusColor: Color {
        switch localModelStatus {
        case .ready: .green
        case .notDownloaded: .secondary
        case .downloading: .blue
        case .failed: .orange
        }
    }

    private var localModelActionRow: some View {
        HStack {
            Label {
                Text("settings.model.manage")
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: "internaldrive")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            Spacer()

            switch localModelStatus {
            case .notDownloaded, .failed:
                Button {
                    localModelManager.download(for: settings.selectedLocalModel)
                } label: {
                    Text(localModelManager.hasResumeData(for: settings.selectedLocalModel) ? "settings.model.action.resume" : "settings.model.download")
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
                HStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .tint(.blue)

                    Button {
                        localModelManager.cancelDownload(for: settings.selectedLocalModel)
                    } label: {
                        Text("settings.model.action.cancel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.orange)
                            )
                    }
                    .buttonStyle(.plain)
                }

            case .ready:
                Button {
                    localModelManager.delete(for: settings.selectedLocalModel)
                } label: {
                    Text("settings.model.delete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.red)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var localModelLicenseRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.selectedLocalModel.licenseNoticeKey)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            } icon: {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var localModelStatus: LocalModelStatus {
        localModelManager.status(for: settings.selectedLocalModel)
    }

    private var localModelDownloadDetail: LocalModelDownloadDetail? {
        localModelManager.downloadDetail(for: settings.selectedLocalModel)
    }

    private var selectedLocalModelNotDownloadedKey: LocalizedStringKey {
        switch settings.selectedLocalModel {
        case .parakeetOfflineInt8:
            "settings.model.status.not_downloaded.parakeet"
        case .nemotronStreamingInt8:
            "settings.model.status.not_downloaded.nemotron"
        }
    }

    private var formattedDiskSize: String {
        let bytes = localModelManager.diskSizeBytes(for: settings.selectedLocalModel)
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else if bytes < 1_000_000_000 {
            return String(format: "%.0f MB", Double(bytes) / 1_000_000)
        } else {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
    }

    private var localDownloadProgressText: String? {
        guard case .downloading = localModelStatus,
              let detail = localModelDownloadDetail
        else {
            return nil
        }

        let bytesText: String
        if let totalBytes = detail.totalBytes, totalBytes > 0 {
            bytesText = "\(formatBytes(detail.downloadedBytes)) / \(formatBytes(totalBytes))"
        } else {
            bytesText = formatBytes(detail.downloadedBytes)
        }

        var segments: [String] = [bytesText]
        if let speed = detail.bytesPerSecond, speed > 0 {
            segments.append(String(localized: "settings.model.progress.speed \(formatBytes(Int64(speed)))/s"))
        }
        if let eta = detail.etaSeconds, eta.isFinite, eta > 0 {
            segments.append(String(localized: "settings.model.progress.eta \(formatDuration(eta))"))
        }
        return segments.joined(separator: " · ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "--"
    }

    // MARK: - Helpers

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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
