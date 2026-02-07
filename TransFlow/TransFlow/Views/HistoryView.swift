import SwiftUI

/// History view with a left session list and right content preview.
struct HistoryView: View {
    @State private var store = JSONLStore()
    @State private var sessions: [SessionFile] = []
    @State private var selectedSessionID: String?

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                HSplitView {
                    // ── Left: Session list ──
                    SessionListView(
                        sessions: $sessions,
                        selectedSessionID: $selectedSessionID,
                        store: store,
                        onRefresh: refreshSessions
                    )
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                    // ── Right: Content preview ──
                    if let selected = sessions.first(where: { $0.id == selectedSessionID }) {
                        SessionDetailView(session: selected, store: store)
                    } else {
                        noSelectionView
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            refreshSessions()
        }
    }

    private func refreshSessions() {
        sessions = store.listSessions()
        // Auto-select the first session if none selected
        if selectedSessionID == nil || !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("history.empty_title")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text("history.empty_description")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.quaternary)

            Text("history.select_session")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Session List

struct SessionListView: View {
    @Binding var sessions: [SessionFile]
    @Binding var selectedSessionID: String?
    let store: JSONLStore
    let onRefresh: () -> Void

    @State private var renamingSessionID: String?
    @State private var renameText: String = ""
    @State private var sessionToDelete: SessionFile?
    @State private var showDeleteConfirmation = false
    @State private var showClearAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // List header
            HStack {
                Text("history.transcriptions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(.quaternary.opacity(0.4))
                    )

                // 3-dot menu
                Menu {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Label("history.clear_all", systemImage: "trash")
                    }
                    .disabled(sessions.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Session list
            List(selection: $selectedSessionID) {
                ForEach(sessions) { session in
                    SessionRowView(
                        session: session,
                        isRenaming: renamingSessionID == session.id,
                        renameText: $renameText,
                        onCommitRename: { commitRename(session: session) },
                        onCancelRename: { renamingSessionID = nil }
                    )
                    .tag(session.id)
                    .contextMenu {
                        Button {
                            renamingSessionID = session.id
                            renameText = session.name
                        } label: {
                            Label("history.rename", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        } label: {
                            Label("history.delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .alert("history.delete_confirm_title", isPresented: $showDeleteConfirmation) {
            Button("history.delete", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session)
                }
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            if let session = sessionToDelete {
                Text("history.delete_confirm_message \(session.name)")
            }
        }
        .alert("history.clear_all_confirm_title", isPresented: $showClearAllConfirmation) {
            Button("history.clear_all", role: .destructive) {
                clearAllSessions()
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            Text("history.clear_all_confirm_message")
        }
    }

    private func commitRename(session: SessionFile) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != session.name else {
            renamingSessionID = nil
            return
        }
        if store.renameSession(from: session.name, to: newName) {
            renamingSessionID = nil
            onRefresh()
            // Keep selection on the renamed item
            selectedSessionID = newName
        }
    }

    private func deleteSession(_ session: SessionFile) {
        let wasSelected = selectedSessionID == session.id
        if store.deleteSession(name: session.name) {
            sessionToDelete = nil
            onRefresh()
            if wasSelected {
                selectedSessionID = sessions.first?.id
            }
        }
    }

    private func clearAllSessions() {
        store.deleteAllSessions()
        selectedSessionID = nil
        onRefresh()
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: SessionFile
    let isRenaming: Bool
    @Binding var renameText: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
            } else {
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                // Creation time
                Text(session.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                // Entry count badge
                HStack(spacing: 3) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9, weight: .medium))
                    Text("\(session.entryCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail (Preview)

struct SessionDetailView: View {
    let session: SessionFile
    let store: JSONLStore

    @State private var entries: [JSONLContentEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // ── Top toolbar with export ──
            detailToolbar

            Divider()

            // ── Content preview — reuses TranscriptionView style ──
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.page.slash")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("history.no_entries")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            EntryRowView(entry: entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadEntries() }
        .onChange(of: session.id) { loadEntries() }
    }

    private func loadEntries() {
        entries = store.readEntries(from: session.url)
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack {
            // Session info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    // Entry count badge
                    HStack(spacing: 3) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9, weight: .medium))
                        Text("\(entries.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(.quaternary.opacity(0.4))
                    )
                }
                Text(session.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Export menu button
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        Task {
                            await TranscriptionExporter.exportToFile(
                                entries: entries,
                                format: format,
                                sessionName: session.name
                            )
                        }
                    } label: {
                        Label(
                            "history.export_format \(format.displayName)",
                            systemImage: format == .srt ? "captions.bubble" : "doc.richtext"
                        )
                    }
                }
            } label: {
                Label("history.export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }
}

// MARK: - Entry Row (mirrors SentenceRow from TranscriptionView)

struct EntryRowView: View {
    let entry: JSONLContentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top separator
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Timestamp badge
                Text(displayTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.quaternary.opacity(0.3))
                    )

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.originalText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    if let translation = entry.translatedText, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    private var displayTime: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: entry.startTime) {
            let display = DateFormatter()
            display.dateFormat = "HH:mm:ss"
            return display.string(from: date)
        }
        return entry.startTime
    }
}
