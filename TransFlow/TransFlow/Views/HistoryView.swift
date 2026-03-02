import SwiftUI
import AVKit

/// History view with a left session list and right content preview.
/// Supports both live transcription and video transcription sessions.
struct HistoryView: View {
    @Binding var initialSessionID: String?

    @State private var liveStore = JSONLStore()
    @State private var videoStore = VideoJSONLStore()
    @State private var allItems: [HistoryItem] = []
    @State private var selectedItemID: String?
    @State private var filter: HistoryFilter = .all

    private var filteredItems: [HistoryItem] {
        switch filter {
        case .all: return allItems
        case .live: return allItems.filter { $0.type == .live }
        case .video: return allItems.filter { $0.type == .video }
        }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                emptyState
            } else {
                HSplitView {
                    SessionListView(
                        items: filteredItems,
                        selectedItemID: $selectedItemID,
                        filter: $filter,
                        liveStore: liveStore,
                        videoStore: videoStore,
                        onRefresh: refreshSessions
                    )
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)

                    if let selected = allItems.first(where: { $0.id == selectedItemID }) {
                        switch selected.type {
                        case .live:
                            if let session = selected.liveSession {
                                SessionDetailView(session: session, store: liveStore)
                            }
                        case .video:
                            if let session = selected.videoSession {
                                VideoSessionDetailView(session: session, store: videoStore)
                            }
                        }
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
            consumeInitialSessionID()
        }
        .onChange(of: initialSessionID) {
            consumeInitialSessionID()
        }
    }

    private func consumeInitialSessionID() {
        if let id = initialSessionID {
            refreshSessions()
            selectedItemID = id
            initialSessionID = nil
        }
    }

    private func refreshSessions() {
        let liveSessions = liveStore.listSessions().map { HistoryItem(live: $0) }
        let videoSessions = videoStore.listSessions().map { HistoryItem(video: $0) }
        allItems = (liveSessions + videoSessions).sorted { $0.createdAt > $1.createdAt }
        if selectedItemID == nil || !allItems.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = filteredItems.first?.id
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
    let items: [HistoryItem]
    @Binding var selectedItemID: String?
    @Binding var filter: HistoryFilter
    let liveStore: JSONLStore
    let videoStore: VideoJSONLStore
    let onRefresh: () -> Void

    @State private var isEditMode = false
    @State private var selectedForDeletion: Set<String> = []
    @State private var renamingItemID: String?
    @State private var renameText: String = ""
    @State private var itemToDelete: HistoryItem?
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            listHeader

            Divider()

            if isEditMode {
                editableList
            } else {
                selectableList
            }

            if isEditMode {
                editModeFooter
            }
        }
        .alert("history.delete_confirm_title", isPresented: $showDeleteConfirmation) {
            Button("history.delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            if let item = itemToDelete {
                Text("history.delete_confirm_message \(item.name)")
            }
        }
        .alert("history.delete_selected_confirm_title", isPresented: $showBatchDeleteConfirmation) {
            Button("history.delete", role: .destructive) {
                deleteSelectedItems()
            }
            Button("session.cancel", role: .cancel) {}
        } message: {
            Text("history.delete_selected_confirm_message \(selectedForDeletion.count)")
        }
    }

    // MARK: - List Header

    private var listHeader: some View {
        HStack(spacing: 8) {
            Picker(selection: $filter) {
                ForEach(HistoryFilter.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .fixedSize()

            Text("\(items.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(.quaternary.opacity(0.4))
                )

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditMode.toggle()
                    if !isEditMode {
                        selectedForDeletion.removeAll()
                    }
                }
            } label: {
                Text(isEditMode ? "history.done" : "history.edit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isEditMode ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Lists

    private var selectableList: some View {
        List(selection: $selectedItemID) {
            ForEach(items) { item in
                sessionRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button {
                            renamingItemID = item.id
                            renameText = item.name
                        } label: {
                            Label("history.rename", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            itemToDelete = item
                            showDeleteConfirmation = true
                        } label: {
                            Label("history.delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private var editableList: some View {
        List {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    let isSelected = selectedForDeletion.contains(item.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                    sessionRow(item: item)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(item.id)
                }
            }
        }
        .listStyle(.inset)
    }

    private func sessionRow(item: HistoryItem) -> some View {
        HistoryRowView(
            item: item,
            isRenaming: renamingItemID == item.id,
            renameText: $renameText,
            onCommitRename: { commitRename(item: item) },
            onCancelRename: { renamingItemID = nil }
        )
    }

    // MARK: - Edit Mode Footer

    private var editModeFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    if selectedForDeletion.count == items.count {
                        selectedForDeletion.removeAll()
                    } else {
                        selectedForDeletion = Set(items.map(\.id))
                    }
                } label: {
                    Text(selectedForDeletion.count == items.count
                         ? "history.deselect_all" : "history.select_all")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) {
                    showBatchDeleteConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("history.delete_count \(selectedForDeletion.count)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selectedForDeletion.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red))
                }
                .buttonStyle(.plain)
                .disabled(selectedForDeletion.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.background)
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selectedForDeletion.contains(id) {
            selectedForDeletion.remove(id)
        } else {
            selectedForDeletion.insert(id)
        }
    }

    private func commitRename(item: HistoryItem) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != item.name else {
            renamingItemID = nil
            return
        }
        switch item.type {
        case .live:
            if liveStore.renameSession(from: item.name, to: newName) {
                renamingItemID = nil
                onRefresh()
                selectedItemID = "live_\(newName)"
            }
        case .video:
            if videoStore.renameSession(from: item.name, to: newName) {
                renamingItemID = nil
                onRefresh()
                selectedItemID = "video_\(newName)"
            }
        }
    }

    private func deleteItem(_ item: HistoryItem) {
        let wasSelected = selectedItemID == item.id
        switch item.type {
        case .live:
            liveStore.deleteSession(name: item.name)
        case .video:
            videoStore.deleteSession(name: item.name)
        }
        itemToDelete = nil
        onRefresh()
        if wasSelected {
            selectedItemID = items.first?.id
        }
    }

    private func deleteSelectedItems() {
        for id in selectedForDeletion {
            if let item = items.first(where: { $0.id == id }) {
                switch item.type {
                case .live:
                    liveStore.deleteSession(name: item.name)
                case .video:
                    videoStore.deleteSession(name: item.name)
                }
            }
        }
        selectedForDeletion.removeAll()
        isEditMode = false
        onRefresh()
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let item: HistoryItem
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
                HStack(spacing: 6) {
                    typeBadge

                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 8) {
                Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                if item.type == .live, let session = item.liveSession, session.hasRecording {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .medium))
                        Text(formatDuration(ms: session.totalRecordingDurationMs))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.orange)
                }

                if item.type == .video, let session = item.videoSession,
                   let duration = session.durationSeconds {
                    HStack(spacing: 3) {
                        Image(systemName: "video")
                            .font(.system(size: 9, weight: .medium))
                        Text(formatDurationSeconds(duration))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.blue)
                }

                HStack(spacing: 3) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9, weight: .medium))
                    Text("\(item.entryCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var typeBadge: some View {
        let color: Color = item.type == .live ? .orange : .blue
        return Text(item.type == .live ? "history.badge.live" : "history.badge.video")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func formatDuration(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatDurationSeconds(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview Mode

enum PreviewMode: String, CaseIterable {
    case rich
    case markdown
}

// MARK: - Session Detail (Live Preview)

struct SessionDetailView: View {
    let session: SessionFile
    let store: JSONLStore

    @State private var entries: [JSONLContentEntry] = []
    @State private var previewMode: PreviewMode = .rich
    @State private var showTimestamps = true
    @State private var showTranslation = true
    @State private var copyFeedback = false
    @State private var audioPlayer = SessionAudioPlayer()

    private var hasRecording: Bool { session.hasRecording }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar

            Divider()

            if hasRecording {
                AudioPlayerBarView(player: audioPlayer)
                Divider()
            }

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
                if previewMode == .rich {
                    richPreview
                } else {
                    markdownPreview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadSession() }
        .onChange(of: session.id) { loadSession() }
        .onDisappear { audioPlayer.unload() }
    }

    private func loadSession() {
        let allLines = store.readAllLines(from: session.url)
        entries = allLines.compactMap { if case .content(let e) = $0 { return e } else { return nil } }
        audioPlayer.unload()
        if hasRecording {
            audioPlayer.load(allLines: allLines)
        }
    }

    // MARK: - Rich Preview

    private var richPreview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        EntryRowView(
                            entry: entry,
                            isActive: audioPlayer.activeEntryIndex == index,
                            hasAudioOffset: audioPlayer.entryOffset(at: index) != nil,
                            onTimestampTap: {
                                if audioPlayer.entryOffset(at: index) != nil {
                                    audioPlayer.seekToEntry(at: index)
                                    if !audioPlayer.isPlaying {
                                        audioPlayer.play()
                                    }
                                }
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: audioPlayer.activeEntryIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Markdown Preview

    private var markdownText: String {
        generateMarkdownPreview(
            entries: entries,
            sessionName: session.name,
            showTimestamps: showTimestamps,
            showTranslation: showTranslation
        )
    }

    private var markdownPreview: some View {
        VStack(spacing: 0) {
            markdownOptionsBar

            Divider()

            ScrollView {
                Text(markdownText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
    }

    private var markdownOptionsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                markdownToggle(
                    "history.md.show_time",
                    icon: "clock",
                    isOn: $showTimestamps
                )
                markdownToggle(
                    "history.md.show_translation",
                    icon: "bubble.left.and.text.bubble.right",
                    isOn: $showTranslation
                )
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdownText, forType: .string)
                withAnimation(.easeInOut(duration: 0.2)) {
                    copyFeedback = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        copyFeedback = false
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text(copyFeedback ? "history.md.copied" : "history.md.copy_all")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(copyFeedback ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(copyFeedback ? AnyShapeStyle(Color.green.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.3)))
                )
            }
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }

    private func markdownToggle(
        _ titleKey: LocalizedStringKey,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(titleKey)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .primary : .tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn.wrappedValue ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary.opacity(isOn.wrappedValue ? 0 : 0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if hasRecording {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .medium))
                            Text(formatDuration(ms: session.totalRecordingDurationMs))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.1))
                        )
                    }

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

            previewModeToggle

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

    private var previewModeToggle: some View {
        HStack(spacing: 0) {
            previewModeButton(.rich, icon: "text.alignleft", titleKey: "history.mode.rich")
            previewModeButton(.markdown, icon: "text.page", titleKey: "history.mode.markdown")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary.opacity(0.2))
        )
        .padding(.trailing, 8)
    }

    private func previewModeButton(_ mode: PreviewMode, icon: String, titleKey: LocalizedStringKey) -> some View {
        let isSelected = previewMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                previewMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(titleKey)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? .primary : .tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Markdown Generation

    private func generateMarkdownPreview(
        entries: [JSONLContentEntry],
        sessionName: String,
        showTimestamps: Bool,
        showTranslation: Bool
    ) -> String {
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("# \(sessionName)")
        lines.append("")

        let formatter = ISO8601DateFormatter()

        for entry in entries {
            var line = ""

            if showTimestamps {
                let timeStr: String
                if let date = formatter.date(from: entry.startTime) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "HH:mm:ss"
                    timeStr = displayFormatter.string(from: date)
                } else {
                    timeStr = entry.startTime
                }
                line += "**[\(timeStr)]** "
            }

            line += entry.originalText
            lines.append(line)

            if showTranslation, let translation = entry.translatedText, !translation.isEmpty {
                lines.append("")
                lines.append("> \(translation)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatDuration(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Video Session Detail

/// Observable model for video playback state in history preview.
@Observable
@MainActor
final class VideoHistoryPlayerModel {
    var player: AVPlayer?
    var activeSegmentIndex: Int?
    var segments: [VideoTranscriptionSegment] = []
    private var timeObserverToken: Any?

    private var currentURL: URL?

    func setup(url: URL, segments: [VideoTranscriptionSegment]) {
        self.segments = segments
        guard url != currentURL else { return }
        cleanup()
        currentURL = url
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        startObservation()
    }

    func seekToSegment(at index: Int) {
        guard index >= 0, index < segments.count else { return }
        let segment = segments[index]
        let time = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
        activeSegmentIndex = index
    }

    func cleanup() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player?.pause()
        player = nil
        activeSegmentIndex = nil
        currentURL = nil
    }

    private func startObservation() {
        guard let player, timeObserverToken == nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let time = CMTimeGetSeconds(cmTime)
                var best: Int?
                for (i, seg) in self.segments.enumerated() {
                    if time >= seg.startTime && time < seg.endTime {
                        best = i
                        break
                    }
                }
                if self.activeSegmentIndex != best {
                    self.activeSegmentIndex = best
                }
            }
        }
    }
}

struct VideoSessionDetailView: View {
    let session: VideoSessionFile
    let store: VideoJSONLStore

    @State private var entries: [VideoJSONLContentEntry] = []
    @State private var playerModel = VideoHistoryPlayerModel()
    @State private var previewMode: PreviewMode = .rich
    @State private var showTimestamps = true
    @State private var showTranslation = true
    @State private var copyFeedback = false
    @State private var renamingSpeakerId: String?
    @State private var speakerRenameText: String = ""
    @State private var showSpeakerRenameAlert = false
    @State private var videoPlayerHeight: CGFloat = 280
    @GestureState private var dragOffset: CGFloat = 0

    private var sourceFileURL: URL? {
        if let path = session.originalFilePath {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private var isVideo: Bool {
        guard let url = sourceFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar

            Divider()

            if let url = sourceFileURL {
                if isVideo {
                    VideoPlayer(player: playerModel.player)
                        .frame(minWidth: 300, maxWidth: .infinity)
                        .frame(height: max(150, min(videoPlayerHeight + dragOffset, 600)))
                        .clipped()

                    videoResizeHandle
                } else {
                    audioPlayerHeader(url: url)
                    Divider()
                }
            }

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
                if previewMode == .rich {
                    richPreview
                } else {
                    markdownPreview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadSession() }
        .onChange(of: session.id) { loadSession() }
        .onDisappear { playerModel.cleanup() }
        .alert("speaker.rename_title", isPresented: $showSpeakerRenameAlert) {
            TextField("", text: $speakerRenameText)
            Button("session.cancel", role: .cancel) {
                renamingSpeakerId = nil
            }
            Button("history.done") {
                commitSpeakerRename()
            }
        } message: {
            Text("speaker.rename_prompt")
        }
    }

    private var videoResizeHandle: some View {
        Divider()
            .overlay(
                Color.clear
                    .frame(height: 8)
                    .contentShape(Rectangle())
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let final = videoPlayerHeight + value.translation.height
                        videoPlayerHeight = min(max(final, 150), 600)
                    }
            )
    }

    private func beginSpeakerRename(_ speakerId: String) {
        renamingSpeakerId = speakerId
        speakerRenameText = SpeakerDisplayName.displayName(for: speakerId)
        showSpeakerRenameAlert = true
    }

    private func commitSpeakerRename() {
        guard let oldId = renamingSpeakerId else { return }
        let newName = speakerRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != SpeakerDisplayName.displayName(for: oldId) else {
            renamingSpeakerId = nil
            return
        }

        store.renameSpeaker(in: session.url, from: oldId, to: newName)
        renamingSpeakerId = nil
        loadSession()
    }

    private func loadSession() {
        entries = store.readEntries(from: session.url)
        let segments = entries.map { entry in
            VideoTranscriptionSegment(
                startTime: entry.startTime,
                endTime: entry.endTime,
                text: entry.originalText,
                translation: entry.translatedText,
                speakerId: entry.speakerId
            )
        }
        if let url = sourceFileURL {
            DispatchQueue.main.async {
                playerModel.setup(url: url, segments: segments)
            }
        } else {
            playerModel.segments = segments
        }
    }

    // MARK: - Audio Player Header

    private func audioPlayerHeader(url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.videoFile ?? session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let duration = session.durationSeconds {
                    Text(TranscriptionExporter.formatTimestamp(duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                if playerModel.player?.rate == 0 {
                    playerModel.player?.play()
                } else {
                    playerModel.player?.pause()
                }
            } label: {
                Image(systemName: playerModel.player?.rate == 0 ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.quaternary.opacity(0.4)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Rich Preview

    private var richPreview: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(playerModel.segments.enumerated()), id: \.element.id) { index, segment in
                        VideoSegmentRow(
                            segment: segment,
                            isActive: playerModel.activeSegmentIndex == index,
                            onTap: {
                                playerModel.seekToSegment(at: index)
                            },
                            onSpeakerTap: { speakerId in
                                beginSpeakerRename(speakerId)
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: playerModel.activeSegmentIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Markdown Preview

    private var markdownText: String {
        generateVideoMarkdownPreview(
            entries: entries,
            sessionName: session.name,
            showTimestamps: showTimestamps,
            showTranslation: showTranslation
        )
    }

    private var markdownPreview: some View {
        VStack(spacing: 0) {
            markdownOptionsBar

            Divider()

            ScrollView {
                Text(markdownText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
    }

    private var markdownOptionsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                markdownToggle(
                    "history.md.show_time",
                    icon: "clock",
                    isOn: $showTimestamps
                )
                markdownToggle(
                    "history.md.show_translation",
                    icon: "bubble.left.and.text.bubble.right",
                    isOn: $showTranslation
                )
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdownText, forType: .string)
                withAnimation(.easeInOut(duration: 0.2)) {
                    copyFeedback = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        copyFeedback = false
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text(copyFeedback ? "history.md.copied" : "history.md.copy_all")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(copyFeedback ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(copyFeedback ? AnyShapeStyle(Color.green.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.3)))
                )
            }
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }

    private func markdownToggle(
        _ titleKey: LocalizedStringKey,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(titleKey)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .primary : .tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn.wrappedValue ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary.opacity(isOn.wrappedValue ? 0 : 0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if let duration = session.durationSeconds {
                        HStack(spacing: 3) {
                            Image(systemName: "video")
                                .font(.system(size: 9, weight: .medium))
                            Text(TranscriptionExporter.formatTimestamp(duration))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.blue.opacity(0.1))
                        )
                    }

                    if session.speakerCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2")
                                .font(.system(size: 9, weight: .medium))
                            Text("\(session.speakerCount)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.1))
                        )
                    }

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

            previewModeToggle

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        Task {
                            await TranscriptionExporter.exportVideoToFile(
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

    private var previewModeToggle: some View {
        HStack(spacing: 0) {
            previewModeButton(.rich, icon: "text.alignleft", titleKey: "history.mode.rich")
            previewModeButton(.markdown, icon: "text.page", titleKey: "history.mode.markdown")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary.opacity(0.2))
        )
        .padding(.trailing, 8)
    }

    private func previewModeButton(_ mode: PreviewMode, icon: String, titleKey: LocalizedStringKey) -> some View {
        let isSelected = previewMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                previewMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(titleKey)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? .primary : .tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Markdown

    private func generateVideoMarkdownPreview(
        entries: [VideoJSONLContentEntry],
        sessionName: String,
        showTimestamps: Bool,
        showTranslation: Bool
    ) -> String {
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("# \(sessionName)")
        lines.append("")

        for entry in entries {
            var line = ""
            if showTimestamps {
                line += "**[\(TranscriptionExporter.formatTimestamp(entry.startTime))]** "
            }
            if let speaker = entry.speakerId {
                line += "_\(SpeakerDisplayName.displayName(for: speaker))_: "
            }
            line += entry.originalText
            lines.append(line)

            if showTranslation, let translation = entry.translatedText, !translation.isEmpty {
                lines.append("")
                lines.append("> \(translation)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Entry Row

struct EntryRowView: View {
    let entry: JSONLContentEntry
    var isActive: Bool = false
    var hasAudioOffset: Bool = false
    var onTimestampTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(displayTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(hasAudioOffset ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(hasAudioOffset ? AnyShapeStyle(Color.accentColor.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.3)))
                    )
                    .onHover { inside in
                        if hasAudioOffset {
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                    .onTapGesture {
                        onTimestampTap?()
                    }

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
