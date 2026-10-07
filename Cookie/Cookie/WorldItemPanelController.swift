import AppKit
import SwiftUI
import os

/// Desktop panel that renders whatever WorldItem (toy, food, or empty cardboard box)
/// is currently on Cookie's desk. Transparent, floating, click-through outside the
/// item, and automatically positioned alongside Cookie.
@MainActor
final class WorldItemPanelController: NSWindowController {
    static let panelSize = CGSize(width: 80, height: 80)

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

        // Align the item's baseline with Cookie's feet
        let itemX = item.x - Self.panelSize.width / 2
        let itemY = companionFrame.minY + 8 // rests comfortably on the floor next to Cookie
        let frame = NSRect(x: itemX, y: itemY, width: Self.panelSize.width, height: Self.panelSize.height)

        let rootView = WorldItemView(
            item: item,
            isInteracting: item.isInteracting || behaviorEngine.state == .playing,
            isEating: behaviorEngine.state == .eating || behaviorEngine.state == .drinking,
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
