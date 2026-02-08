import SwiftUI

/// Settings page with Apple-grade design.
/// Sections: General (Language), Feedback, About (Version).
struct SettingsView: View {
    @State private var settings = AppSettings.shared

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

                // ── Feedback Section ──
                settingsSection(
                    header: "settings.feedback",
                    icon: "bubble.left.fill",
                    iconColor: .blue
                ) {
                    feedbackRow
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

    // MARK: - Helpers

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func openFeedback() {
        if let url = URL(string: "https://github.com/Cyronlee/TransFlow/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}
