import AppKit
import SwiftUI

/// A small borderless panel that floats above Cookie with a line of text and fades away.
/// It follows her while she walks, and never takes a click.
@MainActor
final class BubblePanelController {
    private let panel: NSPanel
    private let hosting = NSHostingView(rootView: BubbleView(text: ""))
    private weak var anchor: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var hideWork: DispatchWorkItem?

    /// Set while she is hidden, for example during a full-screen app.
    var isSuppressed = false {
        didSet { if isSuppressed { hide() } }
    }

    var window: NSWindow { panel }
    var isVisible: Bool { panel.isVisible }

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
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
    }

    /// Shows `text` above `companion` for a few seconds, replacing whatever was showing.
    func say(_ text: String, above companion: NSWindow?, seconds: TimeInterval = 4.5) {
        guard !isSuppressed, let companion else { return }

        hideWork?.cancel()
        hosting.rootView = BubbleView(text: text)
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)

        anchor = companion
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: companion, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        reposition()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide(animated: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        guard panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard self?.hideWork == nil else { return }
                    self?.panel.orderOut(nil)
                }
            })
        } else {
            panel.orderOut(nil)
        }
    }

    private func reposition() {
        guard let anchor else { return }
        let visible = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        panel.setFrameOrigin(Self.origin(bubbleSize: panel.frame.size, companionFrame: anchor.frame, visibleFrame: visible))
    }

    /// Centered over her head, kept inside the visible screen. If there is no room above,
    /// it sits beside her instead of off-screen.
    static func origin(bubbleSize: CGSize, companionFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        var x = companionFrame.midX - bubbleSize.width / 2
        var y = companionFrame.maxY - 14
        x = min(max(x, visibleFrame.minX + 4), visibleFrame.maxX - bubbleSize.width - 4)
        if y + bubbleSize.height > visibleFrame.maxY - 2 {
            y = max(visibleFrame.minY + 2, companionFrame.minY - bubbleSize.height + 14)
        }
        return CGPoint(x: x, y: y)
    }
}
