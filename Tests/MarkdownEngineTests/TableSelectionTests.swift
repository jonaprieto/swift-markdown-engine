//
//  TableSelectionTests.swift
//  MarkdownEngineTests
//
//  A rendered table is an image, so selecting text in it goes through the
//  cell layouts the image keeps: a point maps to a cell and an offset in it,
//  and a selection copies as cells joined by tabs and rows by newlines.
//

import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Table text selection")
struct TableSelectionTests {

    private let source = """
    | Name | Value |
    |---|---|
    | alpha | one |
    | beta | two |
    """

    private func render() throws -> TableImage {
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let font = NSFont.systemFont(ofSize: 15)
        let ctx = MarkdownStyler.StylingContext(
            nsText: source as NSString, tokens: [], codeTokens: [], activeTokenIndices: [],
            baseFont: font, layoutBridge: nil, baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor, latexMarkerFont: font,
            configuration: .default, wikiLinkIDProvider: { _ in nil }
        )
        let aqua = try #require(NSAppearance(named: .aqua))
        let image = MarkdownStyler.tableImage(
            for: source, parsed: parsed, ctx: ctx, appearance: aqua, availableWidth: 600
        ).image
        return try #require(image as? TableImage)
    }

    @Test func cellsAreKeptInReadingOrder() throws {
        let table = try render()
        #expect(table.cells.map(\.text.string) == ["Name", "Value", "alpha", "one", "beta", "two"])
        #expect(table.cells.map(\.row) == [0, 0, 1, 1, 2, 2])
    }

    @Test func pointsMapToTheNearestCellAndBoundary() throws {
        let table = try render()
        let alpha = table.cells[2].rect
        // Left of a cell's text is its start, far right of the last column its end.
        #expect(table.position(at: CGPoint(x: alpha.minX - 4, y: alpha.midY)) == .init(cell: 2, offset: 0))
        let two = table.cells[5].rect
        #expect(table.position(at: CGPoint(x: two.maxX + 50, y: two.midY)) == .init(cell: 5, offset: 3))
    }

    @Test func selectionCopiesAsTabsAndNewlines() throws {
        let table = try render()
        // From "pha" in alpha to "tw" in two, either direction.
        let start = TableImage.Position(cell: 2, offset: 2)
        let end = TableImage.Position(cell: 5, offset: 2)
        #expect(table.text(start, end) == "pha\tone\nbeta\ttw")
        #expect(table.text(end, start) == "pha\tone\nbeta\ttw")
        #expect(table.selectionRects(start, end).count == 4)
        #expect(table.text(start, start).isEmpty)
    }
}
