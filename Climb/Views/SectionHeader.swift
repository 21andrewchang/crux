import UIKit

/// The fold chevron every heading line — section or climb — wears at its trailing
/// edge: down while the group under it is open, right once it is folded away.
/// Drawn by the heading's own layout fragment, so whatever moves the text carries
/// the chevron with it.
enum HeadingChevron {
    /// One glyph for both states, spun rather than swapped: down at rest, a quarter
    /// turn anticlockwise once folded. Swapping in `chevron.right` instead would
    /// change the icon's width mid-fold, and everything laid out against its leading
    /// edge — the attempt count on a climb heading — would jump sideways with it.
    static func icon() -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return UIImage(systemName: "chevron.down", withConfiguration: config)!
            .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
    }

    /// The square the chevron turns inside: wide enough for the glyph lying down and
    /// tall enough for it standing up, so the box the rest of the line measures
    /// against is the same at every angle.
    private static func side(of icon: UIImage) -> CGFloat {
        max(icon.size.width, icon.size.height)
    }

    /// Where the chevron sits in a fragment's coordinates: against the text's own
    /// right edge, centred on the first line. The fragment's frame hugs the indented
    /// text, so right-alignment measures against the container's width, handed in by
    /// whoever vended the fragment.
    static func rect(for icon: UIImage, containerWidth: CGFloat,
                     in fragment: NSTextLayoutFragment) -> CGRect {
        let midY = fragment.textLineFragments.first.map(\.typographicBounds.midY)
            ?? fragment.layoutFragmentFrame.height / 2
        let side = side(of: icon)
        return CGRect(x: containerWidth - NoteDocument.textIndent - side
                          - fragment.layoutFragmentFrame.minX,
                      y: midY - side / 2,
                      width: side, height: side)
    }

    /// Draws the chevron centred in `rect`, turned by `progress`: 0 points it down at
    /// an open group, 1 points it right at a folded one, everything between is the
    /// spin.
    static func draw(_ icon: UIImage, in rect: CGRect, progress: CGFloat,
                     at origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x + rect.midX, y: origin.y + rect.midY)
        context.rotate(by: -.pi / 2 * progress)
        icon.draw(at: CGPoint(x: -icon.size.width / 2, y: -icon.size.height / 2))
        context.restoreGState()
    }
}

/// The example name a heading — section or climb — shows while nothing is typed into
/// it: what the line would say, said faintly. Drawn by the heading's own fragment
/// rather than written into the document, like the title's placeholder above it, so
/// it can never be typed over, serialized, or left behind in a heading since named.
enum HeadingPlaceholder {
    static func width(of text: String, font: UIFont) -> CGFloat {
        text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Exactly where the first character of a typed name would sit: the line's own
    /// left edge, on the line's own baseline — so the example reads as the heading
    /// itself rather than as a label sitting near it.
    static func rect(_ text: String, font: UIFont, in fragment: NSTextLayoutFragment) -> CGRect {
        guard let line = fragment.textLineFragments.first, !text.isEmpty else { return .null }
        let size = (text as NSString).size(withAttributes: [.font: font])
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        return CGRect(x: line.typographicBounds.minX + line.glyphOrigin.x,
                      y: baseline - font.ascender,
                      width: size.width, height: size.height)
    }

    static func draw(_ text: String, font: UIFont, color: UIColor,
                     in rect: CGRect, at origin: CGPoint) {
        guard !rect.isNull else { return }
        (text as NSString).draw(at: CGPoint(x: origin.x + rect.minX, y: origin.y + rect.minY),
                                withAttributes: [.font: font, .foregroundColor: color])
    }
}

/// Lays out a section heading's line exactly as standard — the subheader text is the
/// section — and draws the fold chevron beside it.
final class SectionHeaderLayoutFragment: NSTextLayoutFragment {
    var isFolded = false
    /// How far through its quarter turn the chevron is — 0 open, 1 folded. Set from
    /// `FoldAnimator` when the fragment is vended, so a fold spins rather than snaps.
    var foldProgress: CGFloat = 0
    var containerWidth: CGFloat = 0
    /// The heading's text, breaks trimmed. The example shows while it is empty.
    var name: String = ""

    private var example: String { name.isEmpty ? NoteDocument.sectionPlaceholder : "" }

    private var placeholderRect: CGRect {
        HeadingPlaceholder.rect(example, font: NoteDocument.sectionFont, in: self)
    }

    override var renderingSurfaceBounds: CGRect {
        let icon = HeadingChevron.icon()
        return super.renderingSurfaceBounds
            .union(HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self))
            .union(placeholderRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context)
        let icon = HeadingChevron.icon()
        let rect = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        HeadingChevron.draw(icon, in: rect, progress: foldProgress, at: point, in: context)
        HeadingPlaceholder.draw(example, font: NoteDocument.sectionFont,
                                color: .placeholderText, in: placeholderRect, at: point)
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}
