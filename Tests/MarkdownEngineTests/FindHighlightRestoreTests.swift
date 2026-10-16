//
//  FindHighlightRestoreTests.swift
//  MarkdownEngineTests
//
//  Created by Luca Chen on 31.07.26.
//
//  Find paints with `.backgroundColor`, and so do extension spans, code fences
//  and table cells. Find's highlights are drawn as rendering attributes, so
//  painting and clearing them never touches the text's own backgrounds.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// `==text==` painted as an inverted block, like the Nodes app registers.
private struct InvertingHighlight: MarkdownExtension {
    var id: String { HighlightExtension.identifier }
    var inline: InlineSyntax? { InlineSyntax(open: "==", close: "==") }
    func contentAttributes(theme: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] {
        [.backgroundColor: NSColor.white, .foregroundColor: NSColor.black]
    }
    func html(childrenHTML: String) -> String { "<mark>\(childrenHTML)</mark>" }
}

@MainActor
@Suite("Find highlights leave the text's own styling alone")
struct FindHighlightRestoreTests {

    // "plain ==marked== tail": content `marked` is {8, 6}, `tail` is {17, 4}.
    private static let text = "plain ==marked== tail"
    private static let blockContent = NSRange(location: 8, length: 6)

    private func makeEditor(_ text: String) -> (NativeTextViewCoordinator, NativeTextView) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.configuration.extensions = [InvertingHighlight()]
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        tv.delegate = coordinator
        // The find path scrolls the current match into view; give it a real
        // scroll view so it takes the TextKit 2 route instead of the TextKit 1
        // fallback, which has no layout manager to route through here.
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = tv
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        return (coordinator, tv)
    }

    private func background(_ tv: NativeTextView, at location: Int) -> NSColor? {
        tv.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    /// Whether find drew a highlight over `location`.
    private func highlighted(_ tv: NativeTextView, at location: Int) -> Bool {
        guard let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager,
              let loc = tcm.location(tlm.documentRange.location, offsetBy: location) else { return false }
        var found = false
        tlm.enumerateRenderingAttributes(from: tlm.documentRange.location, reverse: false) { _, attrs, range in
            if range.contains(loc), attrs[.backgroundColor] != nil { found = true }
            return !found
        }
        return found
    }

    private func find(_ query: String, _ coordinator: NativeTextViewCoordinator) {
        coordinator.handleFindQuery(Notification(
            name: Notification.Name("findQuery"),
            object: nil,
            userInfo: ["query": query, "currentIndex": 0]
        ))
    }

    private func done(_ coordinator: NativeTextViewCoordinator) {
        coordinator.handleFindClearHighlights(
            Notification(name: Notification.Name("findClearHighlights"), object: nil)
        )
    }

    @Test("a match inside the block is drawn over it; the block's background stays")
    func blockKeepsItsBackground() {
        let (coordinator, tv) = makeEditor(Self.text)
        #expect(background(tv, at: Self.blockContent.location) == NSColor.white)

        find("marked", coordinator)
        #expect(highlighted(tv, at: Self.blockContent.location))
        #expect(background(tv, at: Self.blockContent.location) == NSColor.white)

        done(coordinator)
        #expect(!highlighted(tv, at: Self.blockContent.location))
        #expect(background(tv, at: Self.blockContent.location) == NSColor.white)
    }

    @Test("re-running the query drops the previous highlight instead of stacking")
    func repeatedQueriesLeaveNoResidue() {
        let (coordinator, tv) = makeEditor(Self.text)

        find("marked", coordinator)
        find("tail", coordinator)

        #expect(!highlighted(tv, at: Self.blockContent.location))
        #expect(highlighted(tv, at: 17))
        #expect(background(tv, at: 17) == nil)
    }
}
