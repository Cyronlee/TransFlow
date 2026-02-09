import SwiftUI

@main
struct TransFlowApp: App {
    @State private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.appAppearance.colorScheme)
                .onAppear {
                    updateChecker.checkOnceOnLaunch()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 720, height: 520)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("menu.clear_history") {
                    NotificationCenter.default.post(name: .clearHistory, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("menu.export_srt") {
                    NotificationCenter.default.post(name: .exportSRT, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Notification Names for menu commands

extension Notification.Name {
    static let clearHistory = Notification.Name("TransFlow.clearHistory")
    static let exportSRT = Notification.Name("TransFlow.exportSRT")
    static let navigateToSettings = Notification.Name("TransFlow.navigateToSettings")
}
