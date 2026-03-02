import SwiftUI

/// Root view with NavigationSplitView providing a collapsible sidebar.
/// The sidebar starts collapsed (detail only) for a clean initial appearance.
///
/// The shared ViewModel is injected from app root so it survives sidebar navigation
/// (switching between Transcription / History / Settings) and can be reused by
/// other UI surfaces like the floating preview window.
struct MainView: View {
    @Bindable var viewModel: TransFlowViewModel
    @Bindable var floatingPreviewManager: FloatingPreviewPanelManager
    @Bindable var settings: AppSettings

    @State private var selectedDestination: SidebarDestination = .transcription
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var pendingHistorySessionID: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedDestination)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
            selectedDestination = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHistory)) { notification in
            pendingHistorySessionID = notification.userInfo?["sessionID"] as? String
            selectedDestination = .history
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedDestination {
        case .transcription:
            ContentView(
                viewModel: viewModel,
                floatingPreviewManager: floatingPreviewManager,
                settings: settings
            )
        case .videoTranscription:
            VideoTranscriptionView()
        case .history:
            HistoryView(initialSessionID: $pendingHistorySessionID)
        case .settings:
            SettingsView()
        }
    }
}
