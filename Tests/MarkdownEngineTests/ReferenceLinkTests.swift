//
//  ReferenceLinkTests.swift
//  MarkdownEngineTests
//
//  Reference-style links (`[text][label]`, `[text][]`, `[label]`) resolve
//  against `[label]: url` definitions anywhere in the document, and footnotes
//  (`[^label]` with a `[^label]: …` definition) link to each other.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Reference links and footnotes")
struct ReferenceLinkTests {

    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    /// The last `.link` set on `pos`, as the text storage would end up with it.
    private func link(_ text: String, at pos: Int, caret: Int = -1) -> URL? {
        let attrs = MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: 14, caretLocation: caret)
        var url: URL?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let u = a[.link] as? URL { url = u }
        }
        return url
    }

    private func at(_ needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    @Test func fullReferenceResolves() {
        let text = "See [the docs][d] here.\n\n[d]: https://example.com/docs\n"
        #expect(link(text, at: at("the docs", in: text)) == URL(string: "https://example.com/docs"))
    }

    @Test func collapsedAndShortcutMatchCaseInsensitively() {
        let text = "[Docs][] and [docs] too.\n\n[DOCS]: <https://example.com>\n"
        #expect(link(text, at: 1) == URL(string: "https://example.com"))
        #expect(link(text, at: at("docs]", in: text)) == URL(string: "https://example.com"))
    }

    @Test func undefinedLabelStaysText() {
        let text = "[nope][x] and [plain] brackets.\n\n[d]: https://example.com\n"
        #expect(link(text, at: 1) == nil)
        #expect(link(text, at: at("plain", in: text)) == nil)
    }

    @Test func referenceInCodeIsNotALink() {
        let text = "`[d]` stays code.\n\n[d]: https://example.com\n"
        #expect(link(text, at: 1) == nil)
    }

    @Test func activeReferenceRevealsItsSource() {
        let text = "See [the docs][d] here.\n\n[d]: https://example.com/docs\n"
        let caret = at("docs]", in: text)
        #expect(link(text, at: at("the docs", in: text), caret: caret) == nil)
    }

    @Test func footnotesLinkBothWays() {
        let text = "A claim[^1].\n\n[^1]: The source.\n"
        #expect(link(text, at: at("1]", in: text)) == URL(string: "#fn-1"))
        let definition = at("[^1]:", in: text)
        #expect(link(text, at: definition + 2) == URL(string: "#fnref-1"))
    }

    @Test func footnoteWithoutDefinitionStaysText() {
        #expect(link("A claim[^9].\n", at: 9) == nil)
    }

    @Test func footnoteAnchorsFindDefinitionAndReference() {
        let text = "A claim[^Note].\n\n[^note]: The source.\n"
        #expect(NativeTextView.anchorLocation("fn-note", in: text) == at("[^note]:", in: text))
        #expect(NativeTextView.anchorLocation("fnref-note", in: text) == at("[^Note]", in: text))
        #expect(NativeTextView.anchorLocation("fn-missing", in: text) == nil)
    }
}
