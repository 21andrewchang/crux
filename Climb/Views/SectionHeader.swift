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
    /// Drawn a step fainter than the counts beside it: with a chevron on every
    /// heading and every row, a column of them at label strength reads as clutter
    /// down the right edge. Faint enough to fall back, still there when looked for.
    static func icon() -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return UIImage(systemName: "chevron.down", withConfiguration: config)!
            .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
    }

    /// The square the chevron turns inside: wide enough for the glyph lying down and
    /// tall enough for it standing up, so the box the rest of the line measures
    /// against is the same at every angle. Public, because the attempt row hangs its
    /// own chevron in the same column and has to match it.
    static let side: CGFloat = {
        let icon = HeadingChevron.icon()
        return max(icon.size.width, icon.size.height)
    }()

    /// How long a chevron takes to turn, wherever it is drawn.
    static let spinDuration: TimeInterval = 0.24

    /// Where the chevron sits in a fragment's coordinates: against the text's own
    /// right edge, centred on the first line. The fragment's frame hugs the indented
    /// text, so right-alignment measures against the container's width, handed in by
    /// whoever vended the fragment.
    static func rect(for icon: UIImage, containerWidth: CGFloat,
                     in fragment: NSTextLayoutFragment) -> CGRect {
        let midY = fragment.textLineFragments.first.map(\.typographicBounds.midY)
            ?? fragment.layoutFragmentFrame.height / 2
        let side = Self.side
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

/// The tally a heading — section or climb — carries at its trailing edge: attempts
/// filed under a climb, climbs filed under a section. One set of attributes and one
/// placement for both, so the two lines read as a single column down the note's right
/// edge rather than two decorations that merely resemble each other.
enum HeadingCount {
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13),
        .foregroundColor: UIColor.secondaryLabel,
    ]

    /// Right-aligned against the chevron, centred on the heading's line.
    static func rect(_ text: NSString, before chevron: CGRect,
                     in fragment: NSTextLayoutFragment) -> CGRect {
        let size = text.size(withAttributes: attributes)
        let midY = fragment.textLineFragments.first.map(\.typographicBounds.midY)
            ?? fragment.layoutFragmentFrame.height / 2
        return CGRect(x: chevron.minX - 8 - size.width,
                      y: midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func draw(_ text: NSString, in rect: CGRect, at origin: CGPoint) {
        text.draw(at: CGPoint(x: origin.x + rect.minX, y: origin.y + rect.minY),
                  withAttributes: attributes)
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
    /// Climbs filed under this heading in the note — drawn at the line's trailing
    /// edge exactly as an attempt count is on a climb, "0 climbs" included, so a
    /// fresh section reads as one too.
    var climbCount = 0
    /// How far through its quarter turn the chevron is — 0 open, 1 folded. Set from
    /// `FoldAnimator` when the fragment is vended, so a fold spins rather than snaps.
    var foldProgress: CGFloat = 0
    var containerWidth: CGFloat = 0
    /// The heading's text, breaks trimmed. The example shows while it is empty.
    var name: String = ""

    private var example: String { name.isEmpty ? NoteDocument.sectionExample : "" }

    private var countText: NSString {
        (climbCount == 1 ? "1 climb" : "\(climbCount) climbs") as NSString
    }

    private var placeholderRect: CGRect {
        HeadingPlaceholder.rect(example, font: NoteDocument.sectionFont, in: self)
    }

    override var renderingSurfaceBounds: CGRect {
        let icon = HeadingChevron.icon()
        let chevron = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        return super.renderingSurfaceBounds
            .union(chevron)
            .union(HeadingCount.rect(countText, before: chevron, in: self))
            .union(placeholderRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context)
        let icon = HeadingChevron.icon()
        let rect = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        HeadingChevron.draw(icon, in: rect, progress: foldProgress, at: point, in: context)
        HeadingCount.draw(countText, in: HeadingCount.rect(countText, before: rect, in: self),
                          at: point)
        HeadingPlaceholder.draw(example, font: NoteDocument.sectionFont,
                                color: .placeholderText, in: placeholderRect, at: point)
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}
