import UIKit

/// The fold chevron every heading line — section or climb — wears at its trailing
/// edge: down while the group under it is open, right once it is folded away.
/// Drawn by the heading's own layout fragment, so whatever moves the text carries
/// the chevron with it.
enum HeadingChevron {
    static func icon(folded: Bool) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return UIImage(systemName: folded ? "chevron.right" : "chevron.down",
                       withConfiguration: config)!
            .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
    }

    /// Where the chevron sits in a fragment's coordinates: against the text's own
    /// right edge, centred on the first line. The fragment's frame hugs the indented
    /// text, so right-alignment measures against the container's width, handed in by
    /// whoever vended the fragment.
    static func rect(for icon: UIImage, containerWidth: CGFloat,
                     in fragment: NSTextLayoutFragment) -> CGRect {
        let midY = fragment.textLineFragments.first.map(\.typographicBounds.midY)
            ?? fragment.layoutFragmentFrame.height / 2
        return CGRect(x: containerWidth - NoteDocument.textIndent - icon.size.width
                          - fragment.layoutFragmentFrame.minX,
                      y: midY - icon.size.height / 2,
                      width: icon.size.width, height: icon.size.height)
    }
}

/// Lays out a section heading's line exactly as standard — the subheader text is the
/// section — and draws the fold chevron beside it.
final class SectionHeaderLayoutFragment: NSTextLayoutFragment {
    var isFolded = false
    var containerWidth: CGFloat = 0

    override var renderingSurfaceBounds: CGRect {
        let icon = HeadingChevron.icon(folded: isFolded)
        return super.renderingSurfaceBounds
            .union(HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context)
        let icon = HeadingChevron.icon(folded: isFolded)
        let rect = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        icon.draw(at: CGPoint(x: point.x + rect.minX, y: point.y + rect.minY))
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}
