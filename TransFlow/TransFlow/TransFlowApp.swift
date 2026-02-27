import SwiftUI

@main
struct TransFlowApp: App {
    @State private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared
    @State private var viewModel = TransFlowViewModel()
    @State private var floatingPreviewManager = FloatingPreviewPanelManager()

    private let errorLogger = ErrorLogger.shared

    var body: some Scene {
        WindowGroup {
            MainView(
                viewModel: viewModel,
                floatingPreviewManager: floatingPreviewManager,
                settings: settings
            )
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.appAppearance.colorScheme)
                .onAppear {
                    updateChecker.checkOnceOnLaunch()
                    configureGlobalHotkeys()
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
            }
        }
    }

    private func configureGlobalHotkeys() {
        let mgr = GlobalHotkeyManager.shared
        mgr.configure(
            onToggleTranscription: { [viewModel] in
                viewModel.toggleListening()
            },
            onToggleTranslation: { [viewModel] in
                viewModel.translationService.isEnabled.toggle()
                if viewModel.translationService.isEnabled {
                    viewModel.translationService.updateSourceLanguage(from: viewModel.selectedLanguage)
                } else {
                    viewModel.translationService.updateConfiguration()
                }
            },
            onToggleFloatingPreview: { [floatingPreviewManager, settings] in
                floatingPreviewManager.toggle(
                    viewModel: viewModel,
                    locale: settings.locale,
                    colorScheme: settings.appAppearance.colorScheme
                )
            },
            onToggleMainWindow: {
                toggleMainWindow()
            }
        )
        mgr.start()
    }

    private func toggleMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Notification Names for menu commands

extension Notification.Name {
    static let clearHistory = Notification.Name("TransFlow.clearHistory")
    static let navigateToSettings = Notification.Name("TransFlow.navigateToSettings")
}
