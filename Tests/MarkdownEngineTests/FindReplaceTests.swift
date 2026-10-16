//
//  FindReplaceTests.swift
//  MarkdownEngineTests
//
//  Replace edits the text view in place, as one undo step, instead of the host
//  rewriting the whole document.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Find and replace")
struct FindReplaceTests {

    private func makeEditor(_ text: String) -> (NativeTextViewCoordinator, NativeTextView, UndoManager) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        tv.allowsUndo = true
        tv.delegate = coordinator
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = tv
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        let undo = tv.undoManager!
        undo.groupsByEvent = false
        return (coordinator, tv, undo)
    }

    private func post(_ handler: (Notification) -> Void, _ info: [String: Any], undo: UndoManager) {
        undo.beginUndoGrouping()
        handler(Notification(name: Notification.Name("replace"), object: nil, userInfo: info))
        undo.endUndoGrouping()
    }

    @Test("replace changes only the current match, and undoes")
    func replaceCurrent() {
        let (c, tv, undo) = makeEditor("cat dog cat")
        post(c.handleReplaceCurrent, ["query": "cat", "replacement": "owl", "currentIndex": 1], undo: undo)
        #expect(tv.string == "cat dog owl")
        undo.undo()
        #expect(tv.string == "cat dog cat")
    }

    @Test("replace all is one undo step")
    func replaceAll() {
        let (c, tv, undo) = makeEditor("cat dog Cat")
        post(c.handleReplaceAll, ["query": "cat", "replacement": "owl"], undo: undo)
        #expect(tv.string == "owl dog owl")
        undo.undo()
        #expect(tv.string == "cat dog Cat")
    }

    @Test("case-sensitive replace all leaves other cases")
    func caseSensitiveReplaceAll() {
        let (c, tv, undo) = makeEditor("cat dog Cat")
        post(c.handleReplaceAll, ["query": "cat", "replacement": "owl", "caseSensitive": true], undo: undo)
        #expect(tv.string == "owl dog Cat")
    }
}
