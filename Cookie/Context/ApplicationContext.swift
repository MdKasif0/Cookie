import Foundation
import CoreGraphics
import AppKit

/// Broad, privacy-conscious categorization of active macOS applications.
/// No document contents or user intentions are inferred.
enum ApplicationCategory: String, CaseIterable, Identifiable, Codable {
    case browser
    case codeEditor
    case creative
    case communication
    case fileManager
    case other
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .browser: return "Web Browser"
        case .codeEditor: return "Code / Text Editor"
        case .creative: return "Creative Tool"
        case .communication: return "Communication"
        case .fileManager: return "File Manager"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }

    /// Classifies an application based on bundle identifier and localized application name.
    /// Falls back safely to `.other` or `.unknown` without assuming user intent.
    static func classify(bundleId: String?, appName: String?) -> ApplicationCategory {
        let bId = (bundleId ?? "").lowercased()
        let name = (appName ?? "").lowercased()

        if bId.isEmpty && name.isEmpty {
            return .unknown
        }

        // 1. File Manager
        if bId == "com.apple.finder" || name == "finder" {
            return .fileManager
        }

        // 2. Web Browsers
        let browserTokens = ["safari", "chrome", "firefox", "browser", "edge", "brave", "arc", "opera", "vivaldi", "orion"]
        if browserTokens.contains(where: { bId.contains($0) || name.contains($0) }) {
            return .browser
        }

        // 3. Code / Text Editors & IDEs
        let editorTokens = ["xcode", "vscode", "vscodium", "cursor", "sublime", "textmate", "textedit", "intellij", "pycharm", "webstorm", "clion", "nova", "zed", "neovim", "macvim", "emacs", "bbedit"]
        if editorTokens.contains(where: { bId.contains($0) || name.contains($0) }) {
            return .codeEditor
        }

        // 4. Creative Applications
        let creativeTokens = ["photoshop", "illustrator", "figma", "blender", "finalcut", "sketch", "premiere", "aftereffects", "logicx", "audacity", "procreate", "cinema4d", "affinity", "pixelmator", "davinci"]
        if creativeTokens.contains(where: { bId.contains($0) || name.contains($0) }) {
            return .creative
        }

        // 5. Communication & Messaging
        let commTokens = ["slack", "discord", "messages", "telegram", "whatsapp", "signal", "teams", "mail", "outlook", "zoom", "wechat", "mattermost", "element"]
        if commTokens.contains(where: { bId.contains($0) || name.contains($0) }) {
            return .communication
        }

        return .other
    }
}

/// Overall desktop environment context state.
enum DesktopContextState: String, Codable {
    case cookieFrontmost
    case externalAppFrontmost
    case desktopVisible
    case unknown

    var displayName: String {
        switch self {
        case .cookieFrontmost: return "Cookie Active"
        case .externalAppFrontmost: return "Application Active"
        case .desktopVisible: return "Desktop Visible"
        case .unknown: return "Unknown"
        }
    }
}

/// Minimal, privacy-conscious model of the active macOS application context.
struct ApplicationContext: Equatable {
    let state: DesktopContextState
    let bundleIdentifier: String?
    let applicationName: String?
    let processIdentifier: pid_t?
    let category: ApplicationCategory
    let isCookieActive: Bool
    let frontmostWindowBounds: NSRect?
    let timestamp: Date

    static let unknown = ApplicationContext(
        state: .unknown,
        bundleIdentifier: nil,
        applicationName: nil,
        processIdentifier: nil,
        category: .unknown,
        isCookieActive: false,
        frontmostWindowBounds: nil,
        timestamp: .distantPast
    )
}
