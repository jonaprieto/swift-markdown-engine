//
//  TableLinkClickTests.swift
//  MarkdownEngineTests
//
//  A click on a link drawn in a rendered table opens it, also when the link
//  sits low in a cell that wraps over many lines: the rect the click is tested
//  against has to be where the cell actually drew the link. Any other single
//  click selects in the table; a double click edits it.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Table link clicks")
struct TableLinkClickTests {

    private static let target = URL(string: "https://example.com/target")!

    /// One column whose cell wraps over a dozen lines, the link on the last.
    private static let note = """
    Intro.

    | Notes |
    |---|
    | \(String(repeating: "words that wrap ", count: 40))[Target](https://example.com/target) |

    End.
    """

    /// The coordinator holds its text view weakly; keep both for the test.
    private static var coordinators: [NativeTextViewCoordinator] = []

    /// Text view styled like the wrapper's, at 16 pt: a size where string
    /// drawing and NSLayoutManager space lines differently.
    private func makeTextView(_ text: String) -> NativeTextView {
        _ = NSApplication.shared
        var config = MarkdownEditorConfiguration.default
        config.theme.link = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.configuration = config
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 800))
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = NSSize(width: 16, height: 12)
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        tv.textLayoutManager?.delegate = layoutDelegate
        coordinator.layoutDelegate = layoutDelegate
        tv.configuration = config
        tv.isEditable = true
        tv.delegate = coordinator
        let font = NSFont.systemFont(ofSize: 16)
        tv.font = font
        tv.baseFont = font
        let bridge = tv.textLayoutManager.map(LayoutBridge.init)
        coordinator.layoutBridge = bridge
        tv.layoutBridge = bridge
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        if let tlm = tv.textLayoutManager { tlm.ensureLayout(for: tlm.documentRange) }
        Self.coordinators.append(coordinator)
        return tv
    }

    /// Where the link was drawn: the box around the link-red pixels of the
    /// rendered table, top-left origin like the image's link rects.
    private func drawnLinkBox(_ image: NSImage) -> CGRect? {
        let w = Int(image.size.width), h = Int(image.size.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var box = CGRect.null
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      c.alphaComponent > 0.5, c.redComponent > 0.6,
                      c.greenComponent < 0.4, c.blueComponent < 0.4 else { continue }
                box = box.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return box.isNull ? nil : box
    }

    @Test("a click on a link low in a wrapped cell opens it")
    func clickOnLinkInWrappedCell() throws {
        let tv = makeTextView(Self.note)
        let storage = try #require(tv.textStorage)
        let tlm = try #require(tv.textLayoutManager)
        let tcm = try #require(tlm.textContentManager)

        var found: (anchor: Int, image: TableImage)?
        storage.enumerateAttribute(.latexImage, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let image = value as? TableImage { found = (range.location, image); stop.pointee = true }
        }
        let (anchor, image) = try #require(found)
        let drawn = try #require(drawnLinkBox(image))
        // The cell must wrap far enough for a per-line drift to add up.
        #expect(drawn.minY > image.size.height / 2)

        // The image sits on the anchor's line, vertically centred in it.
        let location = try #require(tcm.location(tlm.documentRange.location, offsetBy: anchor))
        let fragment = try #require(tlm.textLayoutFragment(for: location))
        let fragmentStart = tcm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
        let line = try #require(fragment.textLineFragments.first {
            NSLocationInRange(anchor - fragmentStart, $0.characterRange)
        })
        let lineBounds = line.typographicBounds
        let imageOrigin = CGPoint(
            x: fragment.layoutFragmentFrame.minX + lineBounds.minX
                + line.locationForCharacter(at: anchor - fragmentStart).x,
            y: fragment.layoutFragmentFrame.minY + lineBounds.minY + (lineBounds.height - image.size.height) / 2
        )
        let click = CGPoint(
            x: tv.textContainerOrigin.x + imageOrigin.x + drawn.midX,
            y: tv.textContainerOrigin.y + imageOrigin.y + drawn.midY
        )
        let hit = try #require(tv.renderedTable(atViewPoint: click))
        #expect(hit.table.link(at: CGPoint(x: click.x - hit.frame.minX, y: click.y - hit.frame.minY)) == Self.target)
    }

    private func click(_ tv: NativeTextView, at viewPoint: CGPoint, count: Int) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: tv.convert(viewPoint, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1
        ))
        tv.mouseDown(with: event)
    }

    @Test("a single click selects in the table, a double click edits it")
    func singleClickSelectsDoubleClickEdits() throws {
        let tv = makeTextView(Self.note)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        let storage = try #require(tv.textStorage)
        var anchor: Int?
        storage.enumerateAttribute(.latexImage, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is TableImage { anchor = range.location; stop.pointee = true }
        }
        let tableAnchor = try #require(anchor)
        let tlm = try #require(tv.textLayoutManager)
        let tcm = try #require(tlm.textContentManager)
        let location = try #require(tcm.location(tlm.documentRange.location, offsetBy: tableAnchor))
        let fragment = try #require(tlm.textLayoutFragment(for: location))
        // Inside the header cell, well away from the link at the bottom.
        let point = CGPoint(x: tv.textContainerOrigin.x + fragment.layoutFragmentFrame.minX + 20,
                            y: tv.textContainerOrigin.y + fragment.layoutFragmentFrame.midY)
        let hit = try #require(tv.renderedTable(atViewPoint: point))
        let header = CGPoint(x: hit.frame.minX + 20, y: hit.frame.minY + 12)

        try click(tv, at: header, count: 1)
        #expect(tv.tableSelection != nil)
        #expect(tv.selectedRange() == NSRange(location: 0, length: 0), "a single click must not move the caret into the table")

        try click(tv, at: header, count: 2)
        #expect(tv.tableSelection == nil)
        #expect(tv.selectedRange() == NSRange(location: tableAnchor, length: 0))
    }
}
