import UIKit

/// Draws the mark on a climb heading line: a filled circle in the climb's colour,
/// standing in the gutter before the name — the colour said once, quietly, instead of
/// a chip wrapped around the whole heading. The name is plain text in the note,
/// edited in place like anything else.
///
/// Drawn inside the fragment's own rendering pass rather than as a view positioned
/// over the text, so whatever moves the text carries the dot with it.
final class ClimbHeaderLayoutFragment: NSTextLayoutFragment {
    /// The heading's text, breaks trimmed — already reflected in `tint` by whoever
    /// vended the fragment.
    var name: String = ""
    var tint: UIColor = ClimbTint.fallback
    /// A climb heading folds like a section: chevron at the trailing edge, group
    /// hidden under it while folded.
    var isFolded = false
    /// How far through its quarter turn the fold chevron is — 0 open, 1 folded. Set
    /// from `FoldAnimator` when the fragment is vended.
    var foldProgress: CGFloat = 0
    var containerWidth: CGFloat = 0
    /// Attempts recorded under this heading in the note — drawn plain at the line's
    /// trailing edge, "0 attempts" included, so a fresh heading reads as one too.
    var attemptCount = 0

    /// The colour dot before the name, and the lane held open for it. The dot stands
    /// on the note's own left edge — flush with the "A" of an attempt row's name — and
    /// the heading's words start a clear step past it, the same way a bookmark sits
    /// before the words of a clip.
    static let dotSide: CGFloat = 14
    static let dotGutter: CGFloat = dotSide + 9

    private var countText: NSString {
        (attemptCount == 1 ? "1 attempt" : "\(attemptCount) attempts") as NSString
    }

    /// The example name an empty heading shows — see `HeadingPlaceholder`.
    private var example: String { name.isEmpty ? NoteDocument.climbExample : "" }

    private var placeholderRect: CGRect {
        HeadingPlaceholder.rect(example, font: NoteDocument.headerFont, in: self)
    }

    /// Centred on the name's own capitals rather than on its line box, so the dot
    /// reads as the first mark of the heading and not as something floating beside it.
    private var dotRect: CGRect {
        guard let line = textLineFragments.first else { return .null }
        let font = NoteDocument.headerFont
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        return CGRect(x: NoteDocument.textIndent - layoutFragmentFrame.minX,
                      y: baseline - font.capHeight / 2 - Self.dotSide / 2,
                      width: Self.dotSide,
                      height: Self.dotSide)
    }

    override var renderingSurfaceBounds: CGRect {
        let icon = HeadingChevron.icon()
        let chevron = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        return super.renderingSurfaceBounds
            .union(dotRect)
            .union(chevron)
            .union(HeadingCount.rect(countText, before: chevron, in: self))
            .union(placeholderRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let rect = dotRect
        UIGraphicsPushContext(context)
        if !rect.isNull {
            // The colour at full strength: it is one small mark now, and a wash of it
            // this size would read as grey.
            tint.setFill()
            UIBezierPath(ovalIn: rect.offsetBy(dx: point.x, dy: point.y)).fill()
        }
        let icon = HeadingChevron.icon()
        let iconRect = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        HeadingChevron.draw(icon, in: iconRect, progress: foldProgress, at: point, in: context)
        HeadingCount.draw(countText, in: HeadingCount.rect(countText, before: iconRect, in: self),
                          at: point)
        // The name's own colour, faded — the example says what the line would say,
        // in the colour the name it stands for would be written in.
        HeadingPlaceholder.draw(example, font: NoteDocument.headerFont,
                                color: tint.withAlphaComponent(0.5),
                                in: placeholderRect, at: point)
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}

/// Maps a climb's name to the hold colour it is named after. Anything with no colour
/// word in it — "Cave Traverse", "The Arete" — comes back gray.
enum ClimbTint {
    static let fallback = UIColor.systemGray

    /// Tuned for black: every entry has to stay legible as both a 22%-alpha fill and as
    /// label text on top of it, which is why "black" is a light gray and not black.
    private static let colors: [String: UIColor] = [
        "red": .systemRed,
        "crimson": .systemRed,
        "orange": .systemOrange,
        "yellow": .systemYellow,
        "gold": .systemYellow,
        "green": .systemGreen,
        "lime": UIColor(red: 0.62, green: 0.90, blue: 0.25, alpha: 1),
        "mint": .systemMint,
        "teal": .systemTeal,
        "cyan": .systemCyan,
        "aqua": .systemCyan,
        "turquoise": .systemTeal,
        "blue": .systemBlue,
        "navy": UIColor(red: 0.35, green: 0.48, blue: 0.95, alpha: 1),
        "indigo": .systemIndigo,
        "purple": .systemPurple,
        "violet": .systemPurple,
        "pink": .systemPink,
        "magenta": .systemPink,
        "salmon": UIColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 1),
        "brown": .systemBrown,
        "tan": .systemBrown,
        "beige": UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1),
        "cream": UIColor(red: 0.93, green: 0.90, blue: 0.78, alpha: 1),
        "white": UIColor(white: 0.92, alpha: 1),
        "black": UIColor(white: 0.62, alpha: 1),
        "gray": .systemGray,
        "grey": .systemGray,
        "silver": UIColor(white: 0.75, alpha: 1),
    ]

    /// First colour word wins: "Blue V4" and "V4 blue slab" both read as blue.
    static func color(for name: String) -> UIColor {
        for word in name.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let color = colors[String(word)] { return color }
        }
        return fallback
    }
}
