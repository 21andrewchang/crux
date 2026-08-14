import UIKit

/// Lays out a quote paragraph exactly as standard, and paints the bar beside it.
///
/// The bar is drawn here, inside the fragment's own rendering pass, rather than as a
/// view positioned over the text afterwards: whatever moves the text — scrolling, the
/// keyboard, relayout mid-animation — carries the bar with it in the same frame.
final class QuoteLayoutFragment: NSTextLayoutFragment {
    /// Rounded ends only where the quote actually ends. A quote spanning several
    /// paragraphs is several fragments, and the bar should read as one.
    var drawsTopCap = true
    var drawsBottomCap = true

    static let barWidth: CGFloat = 4
    /// Left edge of the bar, in from the container's leading edge. The quote text
    /// itself sits at `NoteDocument.quoteIndent`, leaving a gutter for the bar.
    static let barInset: CGFloat = 0
    static let barColor = UIColor.systemGray

    private var barRect: CGRect {
        // The fragment's frame includes the paragraph spacing under the text; the bar
        // should stop at the text. The last line's typographic bounds are where it ends.
        let textBottom = textLineFragments.last.map(\.typographicBounds.maxY)
            ?? layoutFragmentFrame.height

        // Local x = 0 is the fragment's own frame, which hugs the indented text — the
        // bar belongs at the container's margin, back left of the indent.
        var rect = CGRect(x: Self.barInset - layoutFragmentFrame.minX, y: 0,
                          width: Self.barWidth, height: textBottom)
        // An uncapped edge is a seam with the neighbouring fragment: run the bar a
        // little past it so paragraph spacing never reads as a gap in the bar.
        if !drawsTopCap {
            rect.origin.y -= 3
            rect.size.height += 3
        }
        if !drawsBottomCap {
            rect.size.height = layoutFragmentFrame.height + 3
        }
        return rect
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(barRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        var corners: UIRectCorner = []
        if drawsTopCap { corners.formUnion([.topLeft, .topRight]) }
        if drawsBottomCap { corners.formUnion([.bottomLeft, .bottomRight]) }

        let radius = CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
        let path = UIBezierPath(roundedRect: barRect.offsetBy(dx: point.x, dy: point.y),
                                byRoundingCorners: corners,
                                cornerRadii: radius)

        context.saveGState()
        context.addPath(path.cgPath)
        context.setFillColor(Self.barColor.cgColor)
        context.fillPath()
        context.restoreGState()

        super.draw(at: point, in: context)
    }
}
