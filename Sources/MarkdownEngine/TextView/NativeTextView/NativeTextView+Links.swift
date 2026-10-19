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
              let url = tableLink(atViewPoint: convert(event.locationInWindow, from: nil))
        else { return false }
        openLink(url)
        return true
    }

    /// The link a rendered table draws under `viewPoint` (this view's coordinates).
    func tableLink(atViewPoint viewPoint: CGPoint) -> URL? {
        guard let tlm = textLayoutManager else { return nil }
        let point = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        guard let fragment = tlm.textLayoutFragment(for: point) as? MarkdownTextLayoutFragment else { return nil }
        return fragment.tableLink(at: CGPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                                              y: point.y - fragment.layoutFragmentFrame.minY))
    }

    /// Opens a link target: `#anchor` scrolls to it, anything else opens outside.
    func openLink(_ url: URL) {
        if url.scheme == nil, let anchor = url.fragment(percentEncoded: false) {
            scrollToAnchor(anchor)
        } else if url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    /// Scrolls what `anchor` names to the top: a heading (GitHub's anchor: the
    /// heading text slugged, `-1`, `-2` for repeats), else a footnote's definition
    /// (`fn-label`) or its first reference (`fnref-label`).
    func scrollToAnchor(_ anchor: String) {
        guard let location = Self.anchorLocation(anchor, in: string),
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let textLocation = tcm.location(tlm.documentRange.location, offsetBy: location) else { return }
        tlm.ensureLayout(for: NSTextRange(location: textLocation))
        guard let fragment = tlm.textLayoutFragment(for: textLocation) else { return }
        scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY + textContainerOrigin.y - 8)))
    }

    /// UTF-16 offset of what `anchor` names; see `scrollToAnchor`.
    static func anchorLocation(_ anchor: String, in text: String) -> Int? {
        if let heading = headingLocation(anchor: anchor, in: text) { return heading }
        for (prefix, definition) in [("fn-", true), ("fnref-", false)] where anchor.hasPrefix(prefix) {
            return footnoteLocation(label: String(anchor.dropFirst(prefix.count)), definition: definition, in: text)
        }
        return nil
    }

    /// UTF-16 offset of `[^label]:` (the definition) or of the first `[^label]`
    /// that is not one. Labels match case-insensitively.
    static func footnoteLocation(label: String, definition: Bool, in text: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = definition ? "^ {0,3}\\[\\^\(escaped)\\]:" : "\\[\\^\(escaped)\\](?!:)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
        else { return nil }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))?.range.location
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
