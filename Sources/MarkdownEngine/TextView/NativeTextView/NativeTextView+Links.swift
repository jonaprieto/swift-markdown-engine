//
//  NativeTextView+Links.swift
//  MarkdownEngine
//
//  Links the text view opens itself: links drawn inside rendered tables, which
//  are images and carry no `.link`, and in-document `#heading` anchors.
//

import AppKit

extension NativeTextView {
    /// A plain click on a link drawn in a rendered table opens it, as in body text.
    /// Elsewhere in the table the click still moves the caret in to edit.
    func openTableLinkIfHit(event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              let tlm = textLayoutManager else { return false }
        let local = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x - textContainerOrigin.x, y: local.y - textContainerOrigin.y)
        guard let fragment = tlm.textLayoutFragment(for: point) as? MarkdownTextLayoutFragment,
              let url = fragment.tableLink(at: CGPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                                                       y: point.y - fragment.layoutFragmentFrame.minY))
        else { return false }
        openLink(url)
        return true
    }

    /// Opens a link target: `#anchor` scrolls to its heading, anything else opens outside.
    func openLink(_ url: URL) {
        if url.scheme == nil, let anchor = url.fragment(percentEncoded: false) {
            scrollToHeading(anchor: anchor)
        } else if url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    /// Scrolls the heading whose anchor is `anchor` to the top. Anchors follow
    /// GitHub: the heading text slugged, with `-1`, `-2` for repeats.
    func scrollToHeading(anchor: String) {
        guard let location = Self.headingLocation(anchor: anchor, in: string),
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let textLocation = tcm.location(tlm.documentRange.location, offsetBy: location) else { return }
        tlm.ensureLayout(for: NSTextRange(location: textLocation))
        guard let fragment = tlm.textLayoutFragment(for: textLocation) else { return }
        scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY + textContainerOrigin.y - 8)))
    }

    /// UTF-16 offset of the ATX heading `anchor` points at, skipping fenced code.
    static func headingLocation(anchor: String, in text: String) -> Int? {
        let wanted = anchor.lowercased()
        var seen: [String: Int] = [:]
        var inFence = false
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            defer { offset += (line as NSString).length + 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            guard !inFence, trimmed.hasPrefix("#") else { continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard hashes <= 6, trimmed.dropFirst(hashes).first == " " else { continue }
            let base = headingSlug(String(trimmed.dropFirst(hashes)))
            let count = seen[base, default: 0]
            seen[base] = count + 1
            if (count == 0 ? base : "\(base)-\(count)") == wanted { return offset }
        }
        return nil
    }

    /// GitHub's heading anchor: lowercased, punctuation dropped, spaces to hyphens.
    static func headingSlug(_ heading: String) -> String {
        var text = heading.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }   // closing `##` of an ATX heading
        let kept = text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_"
        }
        return String(String.UnicodeScalarView(kept))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
    }
}
