import SwiftUI

/// Navigation destinations for the sidebar.
enum SidebarDestination: String, CaseIterable, Identifiable {
    case transcription
    case history
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .transcription: "sidebar.transcription"
        case .history: "sidebar.history"
        case .settings: "sidebar.settings"
        }
    }

    var icon: String {
        switch self {
        case .transcription: "waveform"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// Apple-style sidebar with navigation destinations.
struct SidebarView: View {
    @Binding var selection: SidebarDestination

    var body: some View {
        List(SidebarDestination.allCases, selection: $selection) { destination in
            Label(destination.title, systemImage: destination.icon)
                .tag(destination)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
    }
}
