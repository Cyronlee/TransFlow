import SwiftUI

/// Root view with NavigationSplitView providing a collapsible sidebar.
/// The sidebar starts collapsed (detail only) for a clean initial appearance.
///
/// The ViewModel is owned here so it survives sidebar navigation
/// (switching between Transcription / History / Settings).
/// This prevents a new session file from being created every time the user
/// navigates back to the transcription page.
struct MainView: View {
    @State private var selectedDestination: SidebarDestination = .transcription
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var viewModel = TransFlowViewModel()
    @State private var settings = AppSettings.shared

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
        .onChange(of: settings.selectedEngine) { _, _ in
            Task {
                await viewModel.loadSupportedLanguages()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedDestination {
        case .transcription:
            ContentView(viewModel: viewModel)
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }
}
