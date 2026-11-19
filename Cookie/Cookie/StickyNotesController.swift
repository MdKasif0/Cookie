import AppKit
import SwiftUI

/// Shows sticky notes as small paper panels on the desktop. A new note lands beside Cookie (or
/// her bed, if she has one); drag it anywhere and it stays there.
@MainActor
final class StickyNotesController: NSObject, NSWindowDelegate {
    private var panels: [UUID: NSPanel] = [:]
    private let store: CookieStore
    private var sharingType: NSWindow.SharingType = .none

    var onEdit: ((StickyNote) -> Void)?
    var onRemove: ((UUID) -> Void)?

    static let size = CGSize(width: 180, height: 150)

    init(store: CookieStore) {
        self.store = store
    }

    func setSharing(hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
        panels.values.forEach { $0.sharingType = sharingType }
    }

    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
    }

    /// Where a new note goes: just above and to the side of `anchor` (Cookie or her bed), on screen.
    static func origin(beside anchor: CGRect, visible: CGRect, index: Int) -> CGPoint {
        let offset = CGFloat(index % 5) * 18
        var x = anchor.maxX + 12 + offset
        if x + size.width > visible.maxX - 8 { x = anchor.minX - size.width - 12 - offset }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(anchor.minY + 20 + offset, visible.minY + 8), visible.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }

    /// Brings the panels in line with the saved notes.
    func update(visible: Bool) {
        let notes = store.profile.stickyNotes
        let wanted = Set(notes.map(\.id))
        for id in Array(panels.keys) where !wanted.contains(id) || !visible {
            panels[id]?.orderOut(nil)
            panels[id] = nil
        }
        guard visible else { return }

        for note in notes {
            let origin = note.origin ?? CGPoint(x: 200, y: 200)
            let view = StickyNoteView(
                note: note,
                onEdit: { [weak self] in self?.onEdit?(note) },
                onRecolor: { [weak self] in self?.recolor(note.id) },
                onRemove: { [weak self] in self?.onRemove?(note.id) }
            )
            if let panel = panels[note.id] {
                (panel.contentView as? NSHostingView<StickyNoteView>)?.rootView = view
            } else {
                let panel = NSPanel(contentRect: NSRect(origin: origin, size: Self.size),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.isMovableByWindowBackground = true
                panel.sharingType = sharingType
                panel.delegate = self
                panel.identifier = NSUserInterfaceItemIdentifier(note.id.uuidString)
                panel.contentView = NSHostingView(rootView: view)
                panels[note.id] = panel
                panel.orderFrontRegardless()
            }
        }
    }

    private func recolor(_ id: UUID) {
        guard let index = store.profile.stickyNotes.firstIndex(where: { $0.id == id }) else { return }
        store.profile.stickyNotes[index].color = store.profile.stickyNotes[index].color.next
        update(visible: true)
    }

    // Saves where you dragged it.
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let raw = panel.identifier?.rawValue, let id = UUID(uuidString: raw),
              let index = store.profile.stickyNotes.firstIndex(where: { $0.id == id }) else { return }
        store.profile.stickyNotes[index].origin = panel.frame.origin
    }
}

struct StickyNoteView: View {
    let note: StickyNote
    let onEdit: () -> Void
    let onRecolor: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hexString: note.color.hex))
                .overlay(alignment: .top) {
                    // A strip of tape, as if Cookie stuck it there.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 46, height: 12)
                        .rotationEffect(.degrees(-4))
                        .offset(y: -4)
                }
            Text(note.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .onTapGesture(count: 2, perform: onEdit)
                .accessibilityLabel("Sticky note: \(note.text)")
            if hovering {
                HStack(spacing: 6) {
                    noteButton("paintpalette", label: "Change color", action: onRecolor)
                    noteButton("pencil", label: "Edit note", action: onEdit)
                    noteButton("checkmark", label: "Done with this note", action: onRemove)
                }
                .padding(6)
            }
        }
        .frame(width: StickyNotesController.size.width - 12, height: StickyNotesController.size.height - 12)
        .padding(6)
        .onHover { hovering = $0 }
        .environment(\.colorScheme, .light)
    }

    private func noteButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.65))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

extension Color {
    /// "#RRGGBB"
    init(hexString: String) {
        let value = UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFF1A8
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
