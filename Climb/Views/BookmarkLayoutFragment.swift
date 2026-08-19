import UIKit

/// Lays out a note line exactly as standard, on the card its row started, and draws a
/// small bookmark in the gutter before its clock — the same mark the playbar uses for
/// the note.
///
/// The card is why this fragment exists for unstamped note lines too: the row above is
/// an attachment view and the notes are ordinary editable text, so the only way they
/// can read as one box is for the text to paint the rest of the box behind itself.
///
/// Drawn inside the fragment's own rendering pass rather than as a view positioned
/// over the text: whatever moves the text — scrolling, the keyboard, relayout
/// mid-animation — carries the card and the bookmark with it in the same frame.
final class BookmarkLayoutFragment: NSTextLayoutFragment {
    private static let icon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        // A comment bubble: the clearest "there's a note here" glyph SF Symbols has.
        // The plain variant — interior text lines turn to mud at marker size.
        return UIImage(systemName: "bubble.left.fill", withConfiguration: config)!
            .withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
    }()

    /// The first note line under its row.
    var opensCard = false
    /// The last note line under its row: the card's bottom corners are rounded here.
    var closesCard = false
    /// Only a line opening with a clock gets the mark in the gutter; the rest of a
    /// row's notes are on the card but carry no bookmark of their own.
    var showsBookmark = false

    /// The clock shown at the line's trailing edge. The token in the text renders at
    /// no size; this drawn copy is the one the reader sees.
    var clock: String?
    /// The container's line-fragment padding. The row above is an attachment laid out
    /// inside it, so the card has to start where the row starts or the two draw at
    /// different widths and stop reading as one box.
    var horizontalInset: CGFloat = 0
    /// The text container's full width, handed in when the fragment is vended.
    /// The fragment's own frame hugs the indented text, so right-alignment must be
    /// measured against the container, not the frame.
    var containerWidth: CGFloat = 0

    /// Smaller than the words it sits beside: the clock is a label on the note, not
    /// part of what the note says.
    static let clockAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.preferredFont(forTextStyle: .footnote),
        .foregroundColor: UIColor.tertiaryLabel,
    ]

    private var firstLineMidY: CGFloat {
        textLineFragments.first.map(\.typographicBounds.midY)
            ?? layoutFragmentFrame.height / 2
    }

    static var iconSize: CGSize { icon.size }

    /// A step in off the page's margin — the mark is a label on the clip, not the
    /// first letter of it, and standing dead on the edge it read as one. The words
    /// after it move with it, through `NoteDocument.bookmarkGutter`.
    static let iconLead: CGFloat = 5

    private var iconOrigin: CGPoint {
        CGPoint(x: AttemptRowView.glyphLeading + Self.iconLead - layoutFragmentFrame.minX,
                y: firstLineMidY - Self.icon.size.height / 2)
    }

    /// Room under the last line of a note, inside the card.
    static let cardBottomPadding: CGFloat = 8

    /// How far the first note line reaches up over the row above it — the gap between
    /// the two is the row's own trailing spacing, and the row's fragment draws nothing
    /// there. Overdrawing the row itself is free: same fill, and it is opaque.
    private static let topBleed: CGFloat = 24

    /// The card behind the line — this line's slice of it. Each note line's fragment
    /// ends exactly where the next one's begins, trailing spacing and all, so the
    /// slices tile into one box without any of them reaching into the next.
    ///
    /// Reaching anyway is what broke a row with more than one clip under it: these
    /// fragments each draw into their own layer, in no order anybody promises, so a
    /// card that bled downward was a card painted over the words of a line already
    /// drawn. Only upward, and only from the line that opens the card, where there is
    /// nothing but the row.
    ///
    /// As wide as the row's own card: out past the text column on both sides, into the
    /// page's margin, so the words inside it keep the note's one left edge.
    private var cardRect: CGRect {
        let frame = layoutFragmentFrame
        let top = opensCard ? -Self.topBleed : 0
        // Measured off the last line of text, never off the fragment: the fragment's
        // height already carries the paragraph's trailing spacing, so anything added
        // to it eats the gap under the card instead of padding the card. The closing
        // line holds `NoteDocument.quoteEndSpacing` of trailing space; this takes its
        // padding out of that, and what is left is the gap.
        let bottom = closesCard
            ? (textLineFragments.last?.typographicBounds.maxY ?? frame.height) + Self.cardBottomPadding
            : frame.height
        let bleed = AttemptRowView.cardBleed
        return CGRect(x: horizontalInset - bleed - frame.minX,
                      y: top,
                      width: containerWidth - horizontalInset * 2 + bleed * 2,
                      height: bottom - top)
    }

    private var clockRect: CGRect {
        guard let clock else { return .null }
        let size = (clock as NSString).size(withAttributes: Self.clockAttributes)
        return CGRect(x: containerWidth - NoteDocument.textIndent - size.width - layoutFragmentFrame.minX,
                      y: firstLineMidY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds
            .union(showsBookmark ? CGRect(origin: iconOrigin, size: Self.icon.size) : .null)
            .union(clockRect)
            .union(cardRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context)

        let card = cardRect.offsetBy(dx: point.x, dy: point.y)
        let radius = AttemptRowView.cardRadius
        let path = closesCard
            ? UIBezierPath(roundedRect: card,
                           byRoundingCorners: [.bottomLeft, .bottomRight],
                           cornerRadii: CGSize(width: radius, height: radius))
            : UIBezierPath(rect: card)
        AttemptRowView.cardFill.setFill()
        path.fill()

        if showsBookmark {
            Self.icon.draw(at: CGPoint(x: point.x + iconOrigin.x, y: point.y + iconOrigin.y))
        }
        if let clock {
            let rect = clockRect
            (clock as NSString).draw(at: CGPoint(x: point.x + rect.minX, y: point.y + rect.minY),
                                     withAttributes: Self.clockAttributes)
        }
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}
