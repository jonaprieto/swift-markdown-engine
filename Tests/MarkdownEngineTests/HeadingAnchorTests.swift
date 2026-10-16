//
//  HeadingAnchorTests.swift
//  MarkdownEngineTests
//
//  `[text](#heading)` targets the heading in the same document, the way GitHub
//  anchors it, instead of being sent to the browser as `https://#heading`.
//

import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Heading anchors")
struct HeadingAnchorTests {

    @Test func anchorTargetIsNotAWebAddress() {
        let url = MarkdownASTStyler.linkTarget("#second-heading")
        #expect(url?.scheme == nil)
        #expect(url?.fragment == "second-heading")
        #expect(MarkdownASTStyler.linkTarget("example.com") == URL(string: "https://example.com"))
    }

    @Test func headingAnchorsFollowGitHub() {
        #expect(NativeTextView.headingSlug("Monday: Envio, events to entities")
            == "monday-envio-events-to-entities")
        #expect(NativeTextView.headingSlug("Migración del PA ##") == "migración-del-pa")
        let text = "# Intro\n\n```\n# not a heading\n```\n## Notes\n## Notes\n"
        #expect(NativeTextView.headingLocation(anchor: "notes", in: text) == 33)
        #expect(NativeTextView.headingLocation(anchor: "notes-1", in: text) == 42)
        #expect(NativeTextView.headingLocation(anchor: "not-a-heading", in: text) == nil)
    }
}
