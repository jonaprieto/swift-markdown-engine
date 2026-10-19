//
//  NativeTextView+TableSelection.swift
//  MarkdownEngine
//
//  Clicks on a rendered table. A table is an image, so a single click or a
//  drag selects text in its cells here instead of moving the caret into the
//  table's source, and ⌘C copies that text. A double click edits the table.
//

import AppKit

/// Text selected in a rendered table, between two positions in its cells.
struct TableSelection {
    let table: TableImage
    /// Where the table is drawn in the text view; nil for a wide table, whose
    /// overlay draws the selection itself.
    let frame: CGRect?
    var anchor: TableImage.Position
    var head: TableImage.Position

    var rects: [CGRect] { table.selectionRects(anchor, head) }
    var text: String { table.text(anchor, head) }
}

/// Draws a table selection over the rendered table, in the table image's
/// coordinates. Clicks pass through to the view below.
final class TableSelectionView: NSView {
    var rects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Translucent: the selection lies over text already drawn into the image.
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).setFill()
        rects.forEach { $0.fill() }
    }
}

extension NativeTextView {
    /// The non-wide table rendered at the height of `viewPoint`, with the rect it
    /// is drawn in and its anchor; see `MarkdownTextLayoutFragment.renderedTable`.
    func renderedTable(atViewPoint viewPoint: CGPoint) -> (table: TableImage, frame: CGRect, anchor: Int)? {
        guard let tlm = textLayoutManager else { return nil }
        let point = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        guard let fragment = tlm.textLayoutFragment(for: point) as? MarkdownTextLayoutFragment else { return nil }
        let origin = fragment.layoutFragmentFrame.origin
        guard let hit = fragment.renderedTable(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        else { return nil }
        let frame = hit.rect.offsetBy(dx: origin.x + textContainerOrigin.x, dy: origin.y + textContainerOrigin.y)
        return (hit.table, frame, hit.anchor)
    }

    /// Takes a click on a table drawn in this view; false when there is none there.
    func handleRenderedTableClick(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.control),
              let hit = renderedTable(atViewPoint: convert(event.locationInWindow, from: nil))
        else { return false }
        trackTableClick(event, table: hit.table, anchor: hit.anchor, frame: hit.frame) { [unowned self] event in
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: p.x - hit.frame.minX, y: p.y - hit.frame.minY)
        }
        return true
    }

    /// A click on a rendered table: a double click moves the caret to `anchor`,
    /// which shows the table's source to edit; a click on a link opens it; any
    /// other click, or a drag, selects text in the cells. `imagePoint` maps an
    /// event into the table image (top-left origin).
    func trackTableClick(
        _ event: NSEvent,
        table: TableImage,
        anchor: Int,
        frame: CGRect?,
        imagePoint: (NSEvent) -> CGPoint
    ) {
        window?.makeFirstResponder(self)
        if event.clickCount >= 2 {
            let docLen = (string as NSString).length
            setSelectedRange(NSRange(location: min(max(anchor, 0), docLen), length: 0))
            return
        }
        let point = imagePoint(event)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.isEmpty, let url = table.link(at: point) {
            tableSelection = nil
            openLink(url)
            return
        }
        guard let start = table.position(at: point) else { return }
        let extended = mods.contains(.shift) && tableSelection?.table === table ? tableSelection?.anchor : nil
        tableSelection = TableSelection(table: table, frame: frame, anchor: extended ?? start, head: start)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if let head = table.position(at: imagePoint(next)) { tableSelection?.head = head }
            if next.type == .leftMouseUp { break }
        }
    }

    /// The selected table text, nil when nothing in a table is selected.
    var selectedTableText: String? {
        guard let text = tableSelection?.text, !text.isEmpty else { return nil }
        return text
    }

    /// Shows `tableSelection` over its table, and clears it from every other.
    func showTableSelection() {
        let rects = tableSelection?.rects ?? []
        if let frame = tableSelection?.frame {
            let view = tableSelectionView ?? {
                let view = TableSelectionView()
                addSubview(view)
                tableSelectionView = view
                return view
            }()
            view.frame = frame
            view.rects = rects
        } else {
            tableSelectionView?.removeFromSuperview()
        }
        for overlay in wideTableOverlays.values {
            overlay.showSelection(overlay.image === tableSelection?.table ? rects : [])
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        // A selection in the text replaces one in a table.
        if tableSelection != nil { tableSelection = nil }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }
}
