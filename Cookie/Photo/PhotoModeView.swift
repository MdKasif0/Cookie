import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drives Photo Mode: which pose and backdrop are chosen, and the frames they produce.
@MainActor
final class PhotoModeModel: ObservableObject {
    @Published var pose: PhotoPose = PhotoPose.all[0] { didSet { reload() } }
    @Published var backdrop: PhotoBackdrop = .transparent { didSet { reload() } }
    @Published private(set) var clip: CookiePhotoRenderer.Clip?
    @Published var message: String?

    private let store: CookieStore
    private let renderer = CookiePhotoRenderer()

    init(store: CookieStore) {
        self.store = store
        reload()
    }

    /// What she looks like today, including any seasonal outfit.
    private var config: CookieAppearanceConfig {
        let base = store.profile.customization
        guard store.profile.settings.seasonalOutfits else { return base }
        return base.withDailyOutfit(on: Date(), firstMet: store.statistics.firstLaunchedAt)
    }

    func reload() {
        clip = renderer.clip(for: pose, config: config, backdrop: backdrop)
    }

    var canSaveGIF: Bool { !(clip?.isStill ?? true) }

    func savePNG() {
        guard let frame = clip?.frames.first, let data = CookiePhotoRenderer.pngData(frame) else { return }
        save(data, suggestedName: "\(store.profile.displayName)-\(pose.id).png", type: .png)
    }

    func saveGIF() {
        guard let clip, let data = CookiePhotoRenderer.gifData(clip) else { return }
        save(data, suggestedName: "\(store.profile.displayName)-\(pose.id).gif", type: .gif)
    }

    func copyImage() {
        guard let frame = clip?.frames.first, let data = CookiePhotoRenderer.pngData(frame) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: .png)
        message = "Copied to the clipboard."
    }

    private func save(_ data: Data, suggestedName: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            message = "Saved \(url.lastPathComponent)."
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

struct PhotoModeView: View {
    @ObservedObject var model: PhotoModeModel

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(spacing: 14) {
            preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Pose").font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(PhotoPose.all) { pose in
                        Button {
                            model.pose = pose
                        } label: {
                            Text(pose.title)
                                .font(.system(size: 12, weight: model.pose == pose ? .bold : .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .modifier(PhotoChip(isSelected: model.pose == pose))
                        .accessibilityAddTraits(model.pose == pose ? [.isSelected] : [])
                    }
                }
            }
            HStack {
                Text("Backdrop").font(.headline)
                Spacer()
                ForEach(PhotoBackdrop.allCases) { backdrop in
                    Button {
                        model.backdrop = backdrop
                    } label: {
                        Circle()
                            .fill(backdrop.color.map { Color(cgColor: $0) } ?? Color.clear)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .overlay(backdrop == .transparent ? Image(systemName: "checkerboard.rectangle").font(.system(size: 11)).foregroundStyle(.secondary) : nil)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.cookieAccent, lineWidth: model.backdrop == backdrop ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(backdrop.title)
                    .accessibilityLabel("\(backdrop.title) backdrop")
                    .accessibilityAddTraits(model.backdrop == backdrop ? [.isSelected] : [])
                }
            }
            HStack {
                Button("Save PNG…") { model.savePNG() }
                Button("Save GIF…") { model.saveGIF() }
                    .disabled(!model.canSaveGIF)
                Button("Copy") { model.copyImage() }
                Spacer()
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if model.backdrop == .transparent, model.canSaveGIF {
                Text("A transparent GIF has hard edges. Pick a backdrop color for the smoothest result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(WindowBackdrop().ignoresSafeArea())
    }

    private var preview: some View {
        ZStack {
            Checkerboard()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let clip = model.clip {
                TimelineView(.animation(minimumInterval: 1 / max(clip.fps, 1), paused: clip.isStill || MotionSettings.reduceMotion)) { context in
                    let index = clip.isStill || MotionSettings.reduceMotion
                        ? 0 : Int(context.date.timeIntervalSinceReferenceDate * clip.fps) % clip.frames.count
                    Image(decorative: clip.frames[index], scale: 2)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(width: 260, height: 260)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

private struct PhotoChip: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.cookieSelectedGlass(cornerRadius: 10)
        } else {
            content.cookieGlass(cornerRadius: 10)
        }
    }
}

/// The classic transparency checkerboard, so a clear backdrop reads as clear.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(Color.primary.opacity(0.07))
                    )
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }
}
