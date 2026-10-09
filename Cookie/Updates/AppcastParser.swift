import Foundation

/// Fast, secure XML parser for Sparkle appcast feeds.
final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [UpdateInfo] = []

    // Current item parsing state
    private var inItem = false
    private var currentElement = ""
    private var currentText = ""

    private var currentTitle = ""
    private var currentVersion = ""
    private var currentBuild = ""
    private var currentReleaseNotes = ""
    private var currentMinSystem = ""
    private var currentPubDate: Date?
    private var isCritical = false

    private var currentURL: URL?
    private var currentLength: Int64 = 0
    private var currentEdSignature: String?

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df
    }()

    /// Parses XML data from an HTTPS feed and returns available update items.
    static func parse(data: Data) throws -> [UpdateInfo] {
        let parser = AppcastParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? NSError(domain: "AppcastParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid XML appcast"])
        }
        return parser.items
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            inItem = true
            currentTitle = ""
            currentVersion = ""
            currentBuild = ""
            currentReleaseNotes = ""
            currentMinSystem = ""
            currentPubDate = nil
            isCritical = false
            currentURL = nil
            currentLength = 0
            currentEdSignature = nil
        } else if inItem && elementName == "enclosure" {
            if let urlStr = attributeDict["url"], let url = URL(string: urlStr) {
                currentURL = url
            }
            if let lengthStr = attributeDict["length"], let len = Int64(lengthStr) {
                currentLength = len
            }
            if let sig = attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"] {
                currentEdSignature = sig
            }
            if let ver = attributeDict["sparkle:version"] {
                if currentBuild.isEmpty { currentBuild = ver }
            }
            if let shortVer = attributeDict["sparkle:shortVersionString"] {
                if currentVersion.isEmpty { currentVersion = shortVer }
            }
        } else if inItem && elementName == "sparkle:criticalUpdate" {
            isCritical = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inItem, let str = String(data: CDATABlock, encoding: .utf8) {
            currentText += str
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !inItem { return }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            currentTitle = trimmed
        case "sparkle:version":
            currentBuild = trimmed
        case "sparkle:shortVersionString":
            currentVersion = trimmed
        case "sparkle:minimumSystemVersion":
            currentMinSystem = trimmed
        case "description":
            currentReleaseNotes = trimmed
        case "pubDate":
            currentPubDate = Self.dateFormatter.date(from: trimmed)
        case "item":
            inItem = false
            // Fallback: if shortVersion is empty, use build or title
            let finalVersion = !currentVersion.isEmpty ? currentVersion : (!currentBuild.isEmpty ? currentBuild : currentTitle)
            let finalBuild = !currentBuild.isEmpty ? currentBuild : finalVersion

            if let url = currentURL {
                let info = UpdateInfo(
                    version: finalVersion,
                    buildNumber: finalBuild,
                    title: currentTitle.isEmpty ? "Version \(finalVersion)" : currentTitle,
                    releaseNotes: cleanReleaseNotes(currentReleaseNotes),
                    downloadURL: url,
                    fileSize: currentLength,
                    edSignature: currentEdSignature,
                    minimumSystemVersion: currentMinSystem.isEmpty ? nil : currentMinSystem,
                    isCritical: isCritical,
                    publishedDate: currentPubDate
                )
                items.append(info)
            }
        default:
            break
        }
    }

    /// Strips raw HTML tags for clean display in native SwiftUI text views.
    private func cleanReleaseNotes(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Bug fixes and improvements for Cookie." }
        var text = raw
        // Replace common HTML tags
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        text = text.replacingOccurrences(of: "<li>", with: "• ")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
