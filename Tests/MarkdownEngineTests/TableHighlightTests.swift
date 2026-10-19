//
//  TableHighlightTests.swift
//  MarkdownEngineTests
//
//  The highlight toggle inside a table's source: it wraps words in a cell,
//  unwraps a highlight in a cell, and never wraps across a `|`, which would
//  split the markers into two cells and break the table.
//

import AppKit
import Testing
@testable import MarkdownEngine
import SwiftUI

@MainActor
@Suite("Table highlight")
struct TableHighlightTests {

    private func highlight(_ text: String, selecting target: String) -> NativeTextView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let textView = NativeTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = true
        var config = MarkdownEditorConfiguration.default
        config.extensions = [HighlightExtension(), StrikethroughExtension()]
        textView.configuration = config
        let coordinator = NativeTextViewCoordinator(
            text: .constant(""),
            fontName: "SF Pro Text",
            fontSize: 14,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        coordinator.configuration = config
        textView.string = text
        textView.setSelectedRange((text as NSString).range(of: target))
        coordinator.didMarkdownHighlight(nil)
        return textView
    }

    private let header = "| A | B |\n|---|---|\n"

    @Test func wrapsWordsInACell() {
        let tv = highlight(header + "| one two | three |", selecting: "two")
        #expect(tv.string == header + "| one ==two== | three |")
    }

    @Test func unwrapsAHighlightInACell() {
        let tv = highlight(header + "| one ==two== | three |", selecting: "two")
        #expect(tv.string == header + "| one two | three |")
    }

    @Test func wrapsEachCellOfASelectionThatCrossesAPipe() {
        let tv = highlight(header + "| one two | three |", selecting: "two | three")
        #expect(tv.string == header + "| one ==two== | ==three== |")
    }

    @Test func selectionAcrossRowsSkipsTheDelimiterRow() {
        let tv = highlight(header + "| one two | three |", selecting: "B |\n|---|---|\n| one")
        #expect(tv.string == "| A | ==B== |\n|---|---|\n| ==one== two | three |")
    }

    @Test func pipeOutsideATableIsWrappedAsText() {
        let tv = highlight("a | b", selecting: "a | b")
        #expect(tv.string == "==a | b==")
    }
}
