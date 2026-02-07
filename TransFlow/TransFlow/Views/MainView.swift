import SwiftUI

/// Root view with NavigationSplitView providing a collapsible sidebar.
/// The sidebar starts collapsed (detail only) for a clean initial appearance.
struct MainView: View {
    @State private var selectedDestination: SidebarDestination = .transcription
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedDestination)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedDestination {
        case .transcription:
            ContentView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }
}
