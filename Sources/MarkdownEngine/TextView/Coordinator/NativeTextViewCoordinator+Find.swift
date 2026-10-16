//
//  NativeTextViewCoordinator+Find.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Find-in-document highlighting. The host app posts the bus notifications
//  registered in `MarkdownEditorBus.findScrollToRange` /
//  `findClearHighlights` to drive the highlight overlay; this extension
//  paints the highlights and scrolls the current match into view.
//
//  Highlights are TextKit 2 rendering attributes, drawn over the text without
//  touching the storage. Painting or clearing them neither restyles nor
//  invalidates layout, so a query that matches thousands of times stays cheap
//  to type. (They used to be storage attributes: every keystroke restyled each
//  paragraph the previous query had touched and laid out the whole document.)
//

import AppKit

extension NativeTextViewCoordinator {
    /// Legacy path: the host computes match ranges and posts them. Kept for compatibility, but
    /// it trusts SOURCE-coordinate ranges, which misalign wherever the displayed text is shorter
    /// than the source (node links etc.). Prefer `handleFindQuery`.
    @objc func handleFindScrollToRange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let currentIndex = info["currentIndex"] as? Int,
              let allRanges = info["allRanges"] as? [NSRange] else { return }
        renderFindMatches(allRanges, currentIndex: currentIndex)
    }

    /// Find against the engine's OWN displayed text (`tv.string`). Matches are computed in
    /// DISPLAY coordinates, so highlights land correctly even where the displayed text differs
    /// from the source (node links rendered shorter than `[[Name|UUID]]`, LaTeX, images). Posts
    /// the match count back via `bus.findResults` so the host can show "x of y".
    @objc func handleFindQuery(_ notification: Notification) {
        guard let tv = textView,
              let info = notification.userInfo,
              let query = info["query"] as? String else { return }
        let requestedIndex = info["currentIndex"] as? Int ?? 0

        let allRanges = findMatches(of: query, in: tv.string as NSString)
        let currentIndex = allRanges.isEmpty ? 0 : min(max(requestedIndex, 0), allRanges.count - 1)
        renderFindMatches(allRanges, currentIndex: currentIndex)
        postFindResults(count: allRanges.count)
    }

    /// All ranges of `query` in `haystack` (display coordinates), case- and
    /// diacritic-insensitive. Shared by find and replace.
    func findMatches(of query: String, in haystack: NSString) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        var ranges: [NSRange] = []
        let opts: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchStart = 0
        while searchStart < haystack.length {
            let scope = NSRange(location: searchStart, length: haystack.length - searchStart)
            let found = haystack.range(of: query, options: opts, range: scope)
            if found.location == NSNotFound { break }
            ranges.append(found)
            searchStart = found.location + max(found.length, 1)
        }
        return ranges
    }

    private func postFindResults(count: Int) {
        if let resultsName = configuration.services.bus.findResults {
            NotificationCenter.default.post(name: resultsName, object: nil, userInfo: ["count": count])
        }
    }

    /// Replace the current find match with the replacement string (one undo
    /// step), then re-highlight and report the remaining match count.
    @objc func handleReplaceCurrent(_ notification: Notification) {
        guard let tv = textView, tv.isEditable,
              let info = notification.userInfo,
              let query = info["query"] as? String, !query.isEmpty,
              let replacement = info["replacement"] as? String else { return }
        let requestedIndex = info["currentIndex"] as? Int ?? 0

        let matches = findMatches(of: query, in: tv.string as NSString)
        guard !matches.isEmpty else { postFindResults(count: 0); return }
        let idx = min(max(requestedIndex, 0), matches.count - 1)
        let target = matches[idx]
        guard NSMaxRange(target) <= (tv.string as NSString).length else { return }

        tv.breakUndoCoalescing()
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard tv.shouldChangeText(in: target, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: target, with: replacement)
        tv.didChangeText()
        tv.undoManager?.setActionName("Replace")
        tv.breakUndoCoalescing()

        // Re-find on the edited text; keep the index so focus lands on the next
        // occurrence (or clamps to the last remaining one).
        let updated = findMatches(of: query, in: tv.string as NSString)
        let nextIndex = updated.isEmpty ? 0 : min(idx, updated.count - 1)
        renderFindMatches(updated, currentIndex: nextIndex)
        postFindResults(count: updated.count)
    }

    /// Replace every find match in a single undo step, then re-highlight.
    @objc func handleReplaceAll(_ notification: Notification) {
        guard let tv = textView, tv.isEditable,
              let info = notification.userInfo,
              let query = info["query"] as? String, !query.isEmpty,
              let replacement = info["replacement"] as? String else { return }

        let matches = findMatches(of: query, in: tv.string as NSString)
        guard !matches.isEmpty else { postFindResults(count: 0); return }

        // Group as one undo; edit back-to-front so earlier ranges stay valid.
        let orderedRanges = matches.reversed().map { NSValue(range: $0) }
        let replacements = Array(repeating: replacement, count: matches.count)

        tv.breakUndoCoalescing()
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard tv.shouldChangeText(inRanges: orderedRanges, replacementStrings: replacements) else { return }
        tv.textStorage?.beginEditing()
        for match in matches.reversed() {
            tv.textStorage?.replaceCharacters(in: match, with: replacement)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
        tv.undoManager?.setActionName("Replace All")
        tv.breakUndoCoalescing()

        // Usually zero remain; non-zero only if the replacement contains the query.
        let remaining = findMatches(of: query, in: tv.string as NSString)
        renderFindMatches(remaining, currentIndex: 0)
        postFindResults(count: remaining.count)
    }

    /// Drop every find highlight. One call over the document: no storage edit,
    /// no restyle, no layout.
    private func clearFindHighlights(in textView: NSTextView) {
        guard let tlm = textView.textLayoutManager else { return }
        tlm.removeRenderingAttribute(.backgroundColor, for: tlm.documentRange)
    }

    /// Highlight all matches (current one stronger) and scroll the current match into view.
    private func renderFindMatches(_ allRanges: [NSRange], currentIndex: Int) {
        guard let tv = textView,
              let tlm = tv.textLayoutManager,
              let tcm = tlm.textContentManager else { return }
        let length = (tv.string as NSString).length

        clearFindHighlights(in: tv)

        // Highlight all matches; the focused match gets a stronger color.
        let theme = configuration.theme
        let matchAlpha = configuration.markers.findMatchHighlightAlpha
        let highlightColor = theme.findMatchHighlight.withAlphaComponent(matchAlpha)
        let currentHighlightColor = theme.findCurrentMatchHighlight

        // Matches come in document order: step each location from the previous
        // one rather than from the document start, so the walk stays linear.
        var cursor = tlm.documentRange.location
        var cursorOffset = 0
        var currentStart: NSTextLocation?
        for (i, match) in allRanges.enumerated() {
            guard NSMaxRange(match) <= length, match.location >= cursorOffset,
                  let start = tcm.location(cursor, offsetBy: match.location - cursorOffset),
                  let end = tcm.location(start, offsetBy: match.length),
                  let range = NSTextRange(location: start, end: end) else { continue }
            cursor = start
            cursorOffset = match.location
            if i == currentIndex { currentStart = start }
            tlm.addRenderingAttribute(.backgroundColor,
                                      value: i == currentIndex ? currentHighlightColor : highlightColor,
                                      for: range)
        }

        // Scroll the current match into view.
        guard let matchStart = currentStart else { return }
        // Scroll via TextKit 2 fragment layout, which works whether or not the
        // reading column is active. `scrollRangeToVisible` is unreliable for
        // off-screen content in a TextKit 2 text view (it routes through the
        // absent TextKit 1 layout manager), so it's only the last-resort fallback.
        // When the text view IS the document view, `tv.frame.origin.y` is 0 and
        // the offset below is a no-op, so the same math serves both layouts.
        guard let scrollView = tv.enclosingScrollView else {
            tv.scrollRangeToVisible(allRanges[currentIndex])
            return
        }
        // Lay out up to the match so its frame is real, not an estimate. Layout
        // is untouched by highlighting, so this is a no-op once it is valid.
        if let upToMatch = NSTextRange(location: tlm.documentRange.location, end: matchStart) {
            tlm.ensureLayout(for: upToMatch)
        }
        tlm.enumerateTextLayoutFragments(from: matchStart, options: [.ensuresLayout]) { fragment in
            let cv = scrollView.contentView
            let insetsTop = scrollView.contentInsets.top
            // Fragment frames are text-view-local; the scroll offset is in
            // document-view space — lift by the text view's offset inside the
            // container (the header band).
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: tv.frame.origin.y)
            let visibleTop = cv.bounds.origin.y + insetsTop
            let visibleBottom = cv.bounds.origin.y + cv.bounds.height
            // Only scroll when the match is off-screen; reveal it a little below the top.
            if frame.minY < visibleTop || frame.maxY > visibleBottom {
                let targetY = frame.minY - insetsTop - cv.bounds.height * 0.2
                cv.scroll(to: NSPoint(x: cv.bounds.origin.x, y: targetY))
                scrollView.reflectScrolledClipView(cv)
                (scrollView as? ClampedScrollView)?.clampToInsets()
            }
            return false
        }
    }

    /// Highlights are drawn, not stored, so clearing them moves nothing on screen.
    @objc func handleFindClearHighlights(_ notification: Notification) {
        guard let tv = textView else { return }
        clearFindHighlights(in: tv)
    }
}
