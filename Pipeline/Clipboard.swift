import AppKit

/// Puts results on the clipboard (CORE.md §6.6): every output as a file, so it pastes as a
/// file in Finder, Slack and browser upload fields, and the first one also as a PNG picture,
/// so it pastes as an image in Figma, Notes and Messages.
@MainActor
enum Clipboard {
    static func put(_ outputs: [URL], picture: Data?) {
        let items = outputs.enumerated().map { index, url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if index == 0, let picture { item.setData(picture, forType: .png) }
            return item
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
