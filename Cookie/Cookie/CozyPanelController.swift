import AppKit
import SwiftUI

/// Shows Cookie's cozy items as small panels resting on the floor behind her.
/// Positions are stored as fractions of the main screen's width.
@MainActor
final class CozyPanelController {
    private var panels: [CozyKind: NSPanel] = [:]
    private var hostings: [CozyKind: NSHostingView<CozyItemView>] = [:]

    var onMove: ((CozyKind, Double) -> Void)?
    var onRemove: ((CozyKind) -> Void)?
    private(set) var sharingType: NSWindow.SharingType = .readOnly

    var windows: [NSWindow] { Array(panels.values) }

    /// Center x of a placed item on the main screen.
    static func centerX(for placement: CozyPlacement, primaryFrame: CGRect) -> CGFloat {
        primaryFrame.minX + CGFloat(placement.position) * primaryFrame.width
    }

    static func position(forCenterX x: CGFloat, primaryFrame: CGRect) -> Double {
        Double((x - primaryFrame.minX) / primaryFrame.width)
    }

    /// The y of the floor Cookie walks on: the bottom of the visible area plus her margin.
    static func floorY(primaryVisible: CGRect) -> CGFloat { primaryVisible.minY + 8 }

    func setSharing(hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
        panels.values.forEach { $0.sharingType = sharingType }
    }

    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
    }

    /// Brings the panels in line with `placements`. Pass `companion` so they sit behind her.
    func update(placements: [CozyPlacement], companion: NSWindow?, scale: CGFloat) {
        guard let primary = NSScreen.screens.first else { return }

        let wanted = Set(placements.map(\.kind))
        for kind in Array(panels.keys) where !wanted.contains(kind) {
            panels[kind]?.orderOut(nil)
            panels[kind] = nil
            hostings[kind] = nil
        }

        let floor = Self.floorY(primaryVisible: primary.visibleFrame) + 8 * scale
        for placement in placements {
            let side = placement.kind.panelSide * scale
            let centerX = Self.centerX(for: placement, primaryFrame: primary.frame)
            let frame = NSRect(x: centerX - side / 2, y: floor - side * 0.1, width: side, height: side)
            let view = makeView(for: placement.kind, side: side, centerX: centerX, primary: primary.frame)

            if let hosting = hostings[placement.kind], let panel = panels[placement.kind] {
                hosting.rootView = view
                panel.setFrame(frame, display: true)
            } else {
                let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.sharingType = sharingType
                let hosting = NSHostingView(rootView: view)
                panel.contentView = hosting
                panels[placement.kind] = panel
                hostings[placement.kind] = hosting
            }

            if let panel = panels[placement.kind] {
                if let companion, companion.isVisible {
                    panel.order(.below, relativeTo: companion.windowNumber)
                } else {
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    private func makeView(for kind: CozyKind, side: CGFloat, centerX: CGFloat, primary: CGRect) -> CozyItemView {
        CozyItemView(
            kind: kind,
            side: side,
            onDismiss: { [weak self] in self?.onRemove?(kind) },
            onDragEnded: { [weak self] delta in
                self?.onMove?(kind, Self.position(forCenterX: centerX + delta, primaryFrame: primary))
            }
        )
    }
}
