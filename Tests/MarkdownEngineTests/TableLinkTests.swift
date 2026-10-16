//
//  TableLinkTests.swift
//  MarkdownEngineTests
//
//  Links inside table cells: a cell shows a link's label as a link (not its
//  `[text](url)` source), and the rendered table records where each link
//  landed so a click can open it.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Table links")
struct TableLinkTests {

    private func cell(_ raw: String) -> NSAttributedString {
        _ = NSApplication.shared
        let cfg = MarkdownEditorConfiguration.default
        return MarkdownStyler.formattedCellString(
            raw, baseFont: NSFont.systemFont(ofSize: 14), header: false,
            theme: cfg.theme, codeBackgroundColor: .clear, latex: cfg.services.latex
        )
    }

    private func link(_ s: NSAttributedString, at index: Int) -> URL? {
        s.attribute(.tableCellLink, at: index, effectiveRange: nil) as? URL
    }

    @Test func markdownLinkShowsItsLabel() {
        let s = cell("[Example](https://example.com)")
        #expect(s.string == "Example")
        #expect(link(s, at: 0) == URL(string: "https://example.com"))
    }

    @Test func anchorTargetStaysInTheDocument() {
        let s = cell("[Second](#second-heading)")
        let url = link(s, at: 0)
        #expect(url?.scheme == nil)
        #expect(url?.fragment == "second-heading")
    }

    @Test func bareAndAngleURLsAreLinks() {
        #expect(link(cell("see https://example.com"), at: 4) != nil)
        #expect(link(cell("<https://example.com>"), at: 1) != nil)
    }

    @Test func urlInCodeSpanIsNotALink() {
        #expect(link(cell("`https://example.com`"), at: 0) == nil)
    }

    @Test func renderedTableRecordsWhereLinksLanded() throws {
        let source = "| Kind | Example |\n|---|---|\n| Link | [Example](https://example.com) |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let aqua = try #require(NSAppearance(named: .aqua))
        let font = NSFont.systemFont(ofSize: 15)
        let ctx = MarkdownStyler.StylingContext(
            nsText: source as NSString, tokens: [], codeTokens: [], activeTokenIndices: [],
            baseFont: font, layoutBridge: nil, baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor, latexMarkerFont: font,
            configuration: .default, wikiLinkIDProvider: { _ in nil }
        )
        let image = try #require(MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: ctx, appearance: aqua, availableWidth: 2000
        ).image as? TableImage)
        let only = try #require(image.links.first)
        #expect(image.links.count == 1)
        #expect(only.url == URL(string: "https://example.com"))
        // Second column, body row: right of the first column, below the header.
        #expect(only.rect.minX > image.size.width / 4)
        #expect(only.rect.minY > image.size.height / 3)
        #expect(image.link(at: CGPoint(x: only.rect.midX, y: only.rect.midY)) == only.url)
        #expect(image.link(at: CGPoint(x: 2, y: 2)) == nil)
    }
}
