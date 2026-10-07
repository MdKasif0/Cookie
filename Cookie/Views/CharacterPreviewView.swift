import SwiftUI
import SpriteKit

/// A small live SpriteKit preview of the character. The scene observes
/// the store itself, so customization changes appear immediately.
struct CharacterPreviewView: View {
    @State private var scene = CookieScene(size: CGSize(width: 160, height: 160))

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
    }
}
