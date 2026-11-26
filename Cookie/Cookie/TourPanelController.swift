import AppKit
import SwiftUI

/// Shows the helpers tour one step at a time in a small card beside Cookie that follows her as she moves.
/// The card takes clicks without pulling focus away from the app you're using.
@MainActor
final class TourPanelController {
    /// Called with each step as it appears, so Cookie can react to it.
    var onStepShown: ((HelpersTour.Step) -> Void)?
    var onAction: ((HelpersTour.Action) -> Void)?
    /// Called once when the tour ends: true if it was finished, false if skipped.
    var onEnd: ((Bool) -> Void)?

    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))
    private weak var anchor: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var steps: [HelpersTour.Step] = []
    private var index = 0

    var isShowing: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
    }

    func start(steps: [HelpersTour.Step], beside companion: NSWindow) {
        guard !steps.isEmpty else { return }
        self.steps = steps
        index = 0
        anchor = companion
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: companion, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        show()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    /// Hides the card without ending the tour, for example while a full-screen app is up.
    func setSuppressed(_ suppressed: Bool) {
        guard !steps.isEmpty else { return }
        if suppressed { panel.orderOut(nil) } else { reposition(); panel.orderFrontRegardless() }
    }

    func end(finished: Bool) {
        guard !steps.isEmpty else { return }
        steps = []
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        })
        onEnd?(finished)
    }

    private func show() {
        let step = steps[index]
        hosting.rootView = AnyView(TourCardView(
            step: step, index: index, count: steps.count,
            onTry: { [weak self] in if let action = step.action { self?.onAction?(action) } },
            onNext: { [weak self] in self?.advance() },
            onSkip: { [weak self] in self?.end(finished: false) }
        ))
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        reposition()
        onStepShown?(step)
    }

    private func advance() {
        if index + 1 < steps.count {
            index += 1
            show()
        } else {
            end(finished: true)
        }
    }

    private func reposition() {
        guard let anchor else { return }
        let visible = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        panel.setFrameOrigin(Self.origin(cardSize: panel.frame.size, companionFrame: anchor.frame, visibleFrame: visible))
    }

    /// Beside her, on whichever side has room, level with her head and kept inside the visible screen.
    nonisolated static func origin(cardSize: CGSize, companionFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        let gap: CGFloat = 4
        var x = companionFrame.maxX + gap
        if x + cardSize.width > visibleFrame.maxX - 4 {
            x = companionFrame.minX - cardSize.width - gap
        }
        x = min(max(x, visibleFrame.minX + 4), visibleFrame.maxX - cardSize.width - 4)
        var y = companionFrame.maxY - cardSize.height
        y = min(max(y, visibleFrame.minY + 4), visibleFrame.maxY - cardSize.height - 4)
        return CGPoint(x: x, y: y)
    }
}
