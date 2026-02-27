import SwiftUI
import AppKit

/// Manages the lifecycle of the detachable floating live preview window.
@MainActor
@Observable
final class FloatingPreviewPanelManager: NSObject, NSWindowDelegate {
    /// Whether the panel should stay above other app windows.
    var isPinned: Bool = false

    /// Whether the floating preview panel is currently visible.
    var isVisible: Bool = false

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

        panel?.orderFront(nil)
        isVisible = true
    }

    /// Closes the panel (same behavior as clicking the red close button).
    func close() {
        panel?.close()
        isVisible = false
    }

    /// Toggles the floating preview panel open/closed.
    func toggle(
        viewModel: TransFlowViewModel,
        locale: Locale,
        colorScheme: ColorScheme?
    ) {
        if isVisible {
            close()
        } else {
            show(viewModel: viewModel, locale: locale, colorScheme: colorScheme)
        }
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
        if panel == nil || notification.object as? NSPanel === panel {
            isPinned = false
            isVisible = false
        }
    }

    private func createPanel() {
        let styleMask: NSWindow.StyleMask = [
            .resizable,
            .nonactivatingPanel,
        ]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )

        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 360, height: 160)
        panel.delegate = self
        panel.setFrameAutosaveName("TransFlow.FloatingPreviewPanel")

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

        if isPinned {
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
            ]
        } else {
            panel.collectionBehavior = [
                .moveToActiveSpace,
                .fullScreenAuxiliary,
            ]
        }
    }
}
