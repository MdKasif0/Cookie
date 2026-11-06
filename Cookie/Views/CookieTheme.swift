import SwiftUI
import AppKit

extension Color {
    /// A color that follows the system appearance.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func adaptive(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        adaptive(
            light: NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: light.3),
            dark: NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
        )
    }
}

extension Color {
    /// Cookie's warm orange. The system accent can be any color the user picks.
    static let cookieAccent = Color("AccentColor")
}

/// The soft backdrop behind Cookie on preview stages, warm in both appearances.
enum CookieStageColors {
    static let top = Color.adaptive(light: (0.98, 0.95, 0.89, 1), dark: (0.25, 0.21, 0.19, 1))
    static let bottom = Color.adaptive(light: (0.95, 0.90, 0.80, 1), dark: (0.17, 0.15, 0.14, 1))
    static let floor = Color.adaptive(light: (0.45, 0.30, 0.18, 0.13), dark: (0, 0, 0, 0.30))
    static var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Translucency behind a whole window, so desktop color shows through.
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later, regular material on earlier systems.
    @ViewBuilder
    func cookieGlass(cornerRadius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Selected-state glass, tinted with the app's accent color.
    @ViewBuilder
    func cookieSelectedGlass(cornerRadius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(Color.cookieAccent.opacity(0.35)).interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(Color.cookieAccent.opacity(0.22), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// The main call-to-action style.
    @ViewBuilder
    func cookieProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(Color.cookieAccent)
        } else {
            self.buttonStyle(.borderedProminent).tint(Color.cookieAccent)
        }
    }
}
