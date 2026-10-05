import SwiftUI
import SpriteKit

/// A small live SpriteKit preview of the character. Used by the welcome
/// window and the Appearance tab. When the final artwork replaces the
/// placeholder provider, every preview updates automatically.
struct CharacterPreviewView: View {
    @EnvironmentObject private var store: CookieStore
    @State private var scene = CookieScene(size: CGSize(width: 160, height: 160))

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .onAppear {
                scene.applyAppearance(store.profile.appearance)
            }
            .onChange(of: store.profile.appearance) { _, newAppearance in
                scene.applyAppearance(newAppearance)
            }
    }
}
