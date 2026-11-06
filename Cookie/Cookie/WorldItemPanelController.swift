import AppKit
import SwiftUI
import os

/// Desktop panel that renders whatever WorldItem (toy, food, or empty cardboard box)
/// is currently on Cookie's desk. Transparent, floating, click-through outside the
/// item, and automatically positioned alongside Cookie.
@MainActor
final class WorldItemPanelController: NSWindowController {
    static let panelSize = CGSize(width: 80, height: 80)
    static let boxDimension: CGFloat = 170

    private let behaviorEngine: CookieBehaviorEngine
    private let log = Logger(subsystem: "com.cookie.mac", category: "WorldItemPanel")
    private var hostingView: NSHostingView<WorldItemView>?

    init(behaviorEngine: CookieBehaviorEngine) {
        self.behaviorEngine = behaviorEngine
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { nil }

    func update(item: WorldItem?, companionFrame: NSRect, isCookieInBox: Bool) {
        guard let item, !isCookieInBox else {
            hide()
            return
        }

        // Items scale with Cookie. The box is large enough for her to climb into.
        let companionScale = companionFrame.width / CookieScreenGeometry.basePanelDimension
        let side = (item.kind.isBox ? Self.boxDimension : Self.panelSize.width) * companionScale

        // Each image's ground line is 10% up from its bottom edge. Rest it where her shadow sits.
        let groundY = companionFrame.minY + 8 * companionScale
        let frame = NSRect(x: item.x - side / 2, y: groundY - side * 0.1, width: side, height: side)

        let rootView = WorldItemView(
            item: item,
            isInteracting: item.isInteracting || behaviorEngine.state == .playing,
            isEating: behaviorEngine.state == .eating || behaviorEngine.state == .drinking,
            size: side,
            onDismiss: { [weak self] in
                self?.behaviorEngine.clearWorldItem()
            },
            onDragEnded: { [weak self] newX in
                self?.behaviorEngine.updateWorldItemPosition(newX: newX)
            }
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hosting = NSHostingView(rootView: rootView)
            window?.contentView = hosting
            self.hostingView = hosting
        }

        window?.setFrame(frame, display: true)
        show()
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
