import UIKit

/// Lays out a stamped note line exactly as standard, and draws a small grey bookmark
/// in the gutter before its clock — the same mark the playbar uses for the note.
///
/// Drawn inside the fragment's own rendering pass rather than as a view positioned
/// over the text: whatever moves the text — scrolling, the keyboard, relayout
/// mid-animation — carries the bookmark with it in the same frame.
final class BookmarkLayoutFragment: NSTextLayoutFragment {
    private static let icon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        // A comment bubble: the clearest "there's a note here" glyph SF Symbols has.
        // The plain variant — interior text lines turn to mud at marker size.
        return UIImage(systemName: "bubble.left.fill", withConfiguration: config)!
            .withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
    }()

    /// The clock shown at the line's trailing edge. The token in the text renders at
    /// no size; this drawn copy is the one the reader sees.
    var clock: String?
    /// The text container's full width, handed in when the fragment is vended.
    /// The fragment's own frame hugs the indented text, so right-alignment must be
    /// measured against the container, not the frame.
    var containerWidth: CGFloat = 0

    static let clockAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.preferredFont(forTextStyle: .body),
        .foregroundColor: UIColor.tertiaryLabel,
    ]

    private var firstLineMidY: CGFloat {
        textLineFragments.first.map(\.typographicBounds.midY)
            ?? layoutFragmentFrame.height / 2
    }

    private var iconOrigin: CGPoint {
        CGPoint(x: NoteDocument.textIndent - layoutFragmentFrame.minX,
                y: firstLineMidY - Self.icon.size.height / 2)
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
            .union(CGRect(origin: iconOrigin, size: Self.icon.size))
            .union(clockRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        UIGraphicsPushContext(context)
        Self.icon.draw(at: CGPoint(x: point.x + iconOrigin.x, y: point.y + iconOrigin.y))
        if let clock {
            let rect = clockRect
            (clock as NSString).draw(at: CGPoint(x: point.x + rect.minX, y: point.y + rect.minY),
                                     withAttributes: Self.clockAttributes)
        }
        UIGraphicsPopContext()
        super.draw(at: point, in: context)
    }
}
