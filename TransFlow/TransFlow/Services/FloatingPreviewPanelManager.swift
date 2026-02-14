import SwiftUI
import AppKit

/// Manages the lifecycle of the detachable floating live preview window.
@MainActor
@Observable
final class FloatingPreviewPanelManager: NSObject, NSWindowDelegate {
    /// Whether the panel should stay above other app windows.
    var isPinned: Bool = false

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    /// Opens the panel if needed, updates its content, and brings it to front.
    func show(
        viewModel: TransFlowViewModel,
        locale: Locale,
        colorScheme: ColorScheme?
    ) {
        if panel == nil {
            createPanel()
        }

        updateRootView(
            viewModel: viewModel,
            locale: locale,
            colorScheme: colorScheme
        )
        applyPinState()

        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }

    /// Closes the panel (same behavior as clicking the red close button).
    func close() {
        panel?.close()
    }

    /// Toggles the pin state and reapplies z-order behavior.
    func togglePin() {
        isPinned.toggle()
        applyPinState()

        if isPinned {
            panel?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Keep runtime-only pin behavior simple: closing the panel unpins it.
        if panel == nil || notification.object as? NSPanel === panel {
            isPinned = false
        }
    }

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .resizable,
            .fullSizeContentView,
        ]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )

        panel.title = String(localized: "floating_preview.title")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 320, height: 150)
        panel.delegate = self
        panel.setFrameAutosaveName("TransFlow.FloatingPreviewPanel")

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.panel = panel
    }

    private func updateRootView(
        viewModel: TransFlowViewModel,
        locale: Locale,
        colorScheme: ColorScheme?
    ) {
        let rootView = AnyView(
            FloatingPreviewView(
                viewModel: viewModel,
                panelManager: self
            )
            .environment(\.locale, locale)
            .preferredColorScheme(colorScheme)
        )

        if let hostingController {
            hostingController.rootView = rootView
            panel?.contentViewController = hostingController
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            self.hostingController = hostingController
            panel?.contentViewController = hostingController
        }
    }

    private func applyPinState() {
        guard let panel else { return }

        panel.level = isPinned ? .floating : .normal
        panel.isFloatingPanel = isPinned

        var behavior: NSWindow.CollectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
        ]
        if isPinned {
            behavior.insert(.canJoinAllSpaces)
        }
        panel.collectionBehavior = behavior
    }
}
