import UIKit

/// Draws the bubble behind a climb heading line: a tinted pill hugging the name, the
/// same chip the old heading row drew — but the name is now just text in the note,
/// edited in place like anything else.
///
/// Drawn inside the fragment's own rendering pass rather than as a view positioned
/// over the text, so whatever moves the text carries the bubble with it.
final class ClimbHeaderLayoutFragment: NSTextLayoutFragment {
    /// The heading's text, breaks trimmed — measured for the pill's width and already
    /// reflected in `tint` by whoever vended the fragment.
    var name: String = ""
    var tint: UIColor = ClimbTint.fallback
    /// A climb heading folds like a section: chevron at the trailing edge, group
    /// hidden under it while folded.
    var isFolded = false
    var containerWidth: CGFloat = 0
    /// Attempts recorded under this heading in the note — drawn plain at the line's
    /// trailing edge, "0 attempts" included, so a fresh bubble reads as one too.
    var attemptCount = 0

    /// How far the pill swells past the text on each side.
    private static let inflate: CGFloat = 5

    private static let countAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13),
        .foregroundColor: UIColor.secondaryLabel,
    ]

    private var countText: NSString {
        (attemptCount == 1 ? "1 attempt" : "\(attemptCount) attempts") as NSString
    }

    /// Right-aligned against the chevron, centred on the bubble's line.
    private func countRect(before chevron: CGRect) -> CGRect {
        let size = countText.size(withAttributes: Self.countAttributes)
        let midY = textLineFragments.first.map(\.typographicBounds.midY)
            ?? layoutFragmentFrame.height / 2
        return CGRect(x: chevron.minX - 8 - size.width,
                      y: midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private var pillRect: CGRect {
        guard let line = textLineFragments.first else { return .null }
        let bounds = line.typographicBounds
        // An empty bubble — just dropped, nothing typed — still shows a caret's worth
        // of room to type into.
        let textWidth = name.isEmpty
            ? 22
            : ceil((name as NSString).size(withAttributes: [.font: NoteDocument.headerFont]).width)
        return CGRect(x: -layoutFragmentFrame.minX,
                      y: bounds.minY - Self.inflate,
                      width: textWidth + NoteDocument.textIndent * 2,
                      height: bounds.height + Self.inflate * 2)
    }

    override var renderingSurfaceBounds: CGRect {
        let icon = HeadingChevron.icon(folded: isFolded)
        let chevron = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        return super.renderingSurfaceBounds
            .union(pillRect)
            .union(chevron)
            .union(countRect(before: chevron))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let rect = pillRect
        UIGraphicsPushContext(context)
        if !rect.isNull {
            let path = UIBezierPath(roundedRect: rect.offsetBy(dx: point.x, dy: point.y),
                                    cornerRadius: rect.height / 2)
            // Same recipe as the old chip: a fill that carries the colour without
            // shouting it, under text drawn in the colour itself.
            tint.withAlphaComponent(0.22).setFill()
            path.fill()
        }
        let icon = HeadingChevron.icon(folded: isFolded)
        let iconRect = HeadingChevron.rect(for: icon, containerWidth: containerWidth, in: self)
        icon.draw(at: CGPoint(x: point.x + iconRect.minX, y: point.y + iconRect.minY))
        let count = countRect(before: iconRect)
        countText.draw(at: CGPoint(x: point.x + count.minX, y: point.y + count.minY),
                       withAttributes: Self.countAttributes)
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
