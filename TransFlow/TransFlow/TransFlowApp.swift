import SwiftUI

@main
struct TransFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 720, height: 520)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Clear History") {
                    NotificationCenter.default.post(name: .clearHistory, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Export SRT…") {
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
}
