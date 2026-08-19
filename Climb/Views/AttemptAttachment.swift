import UIKit

/// Everything the inline row needs to draw, snapshotted so the attachment view never
/// reaches back into SwiftData off the main actor.
struct AttemptSnapshot {
    var ordinal: Int
    var duration: TimeInterval
    var rest: TimeInterval
    var notes: String
    var thumbnail: UIImage?
    var effort: Effort?
}

/// A text attachment standing in for one attempt. It renders as a full-width row via
/// TextKit 2's view-provider mechanism, which is how Notes gets interactive
/// attachments to participate in normal text layout.
///
/// The attempt's notes are not in here: they are text in the document on the line below,
/// bound to this attempt by `NoteDocument.noteQuote`. Editing them is ordinary typing,
/// which is the only way to get the caret, keyboard and undo to behave.
final class AttemptAttachment: NSTextAttachment, MarkerAttachment {
    let attemptID: UUID
    var snapshotProvider: ((UUID) -> AttemptSnapshot?)?
    var onTap: ((UUID) -> Void)?
    /// A tap on the name: closes the notes under this row and opens them again.
    var onToggleFold: ((UUID) -> Void)?
    /// Whether anything is written under this row. With nothing there the card closes
    /// off at the bottom of the row instead of running on into them, and the name has
    /// nothing to fold.
    var hasNotes = false
    /// Whether those notes are closed. They draw at hairline size while it is set, the
    /// same way a folded heading hides its group.
    var areNotesFolded = false
    /// The row currently on screen for this attachment, so a renumber can reach it
    /// without rebuilding the document.
    weak var rowView: AttemptRowView?
    /// Folded away under a collapsed climb heading: the row hides and its line shrinks
    /// to a hairline. Kept current by `NoteDocument.applyStyles` from document order.
    var isCollapsed = false

    var markerID: UUID { attemptID }
    var takesNotes: Bool { true }

    static let rowHeight: CGFloat = 74

    init(attemptID: UUID) {
        self.attemptID = attemptID
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The row's height, answered through `NSTextAttachmentContainer` too.
    ///
    /// TextKit 2 asks the view provider below; this is the older question, and the
    /// base class answers it out of `bounds`, which is never set here — so anything
    /// asking this way is told the row has no height. `NoteTextView`'s caret maths
    /// asks exactly this way when it needs a block line to answer for itself.
    ///
    /// Reads `lineFrag.width` and never its height, and must keep doing so: that call
    /// proposes a fragment of (container width x .greatestFiniteMagnitude).
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let available = (textContainer?.size.width ?? lineFrag.width) - padding
        let width = max(120, min(available, lineFrag.width))
        return CGRect(x: 0, y: 0, width: width, height: isCollapsed ? 0.1 : Self.rowHeight)
    }

    override func viewProvider(for parentView: UIView?,
                               location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = AttemptRowViewProvider(textAttachment: self,
                                              parentView: parentView,
                                              textLayoutManager: textContainer?.textLayoutManager,
                                              location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class AttemptRowViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let row = AttemptRowView()
        if let attachment = textAttachment as? AttemptAttachment {
            let id = attachment.attemptID
            if let snapshot = attachment.snapshotProvider?(id) {
                row.configure(with: snapshot)
            }
            row.onTap = { [weak attachment] in attachment?.onTap?(id) }
            row.onToggleFold = { [weak attachment] in attachment?.onToggleFold?(id) }
            row.showNotes(attachment.hasNotes, folded: attachment.areNotesFolded)
            row.isHidden = attachment.isCollapsed
            attachment.rowView = row
        }
        view = row
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: any NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        // Span the full text column so the row reads as a block, not an inline glyph.
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let available = (textContainer?.size.width ?? proposedLineFragment.width) - padding
        let width = max(120, min(available, proposedLineFragment.width))
        // Under a collapsed heading the row keeps its place in the text but no height.
        let collapsed = (textAttachment as? AttemptAttachment)?.isCollapsed == true
        return CGRect(x: 0, y: 0, width: width, height: collapsed ? 0.1 : AttemptAttachment.rowHeight)
    }
}

/// The little row that appears inline once an attempt is finished.
final class AttemptRowView: UIView {
    var onTap: (() -> Void)?
    var onToggleFold: (() -> Void)?

    /// Barely off black — just enough separation from the page to read as a card. The
    /// notes written under the row are drawn on the same ground by
    /// `BookmarkLayoutFragment`, so the row and its notes read as one box.
    static let cardFill = UIColor(white: 0.04, alpha: 1)
    static let cardRadius: CGFloat = 14

    static let thumbnailInset: CGFloat = 8
    static let thumbnailSide: CGFloat = 46
    /// The gap between the name and the video at the other end of the row.
    static let labelGap: CGFloat = 14
    /// Where the row's name starts: the same left edge as every other name in the
    /// note, and the edge the notes' words hang from, so a clip's text and the
    /// attempt's name read down one line.
    static let textColumn: CGFloat = NoteDocument.textIndent
    /// Where the bookmarks on the note lines below start. Its left edge, not its
    /// middle: the video is no longer over that lane, so the mark stands on the card's
    /// own left edge — flush with the "A" of the name above it — and the words of the
    /// clip step past it.
    static let glyphLeading: CGFloat = textColumn

    private let container = UIView()
    /// Whether anything is written under this row — what decides whether a tap on the
    /// name has notes to fold away.
    private var hasNotes = false

    private let thumbnailView = UIImageView()
    private let playGlyph = UIImageView(image: UIImage(systemName: "play.fill"))
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildHierarchy() {
        // The row reads as the head of one box: a near-black card with the name on the
        // card's own left edge, where every other name in the note starts, and the
        // video held at the far end. The notes themselves are drawn on the same ground
        // below, so the whole thing is one card.
        container.backgroundColor = Self.cardFill
        container.layer.cornerRadius = Self.cardRadius
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        thumbnailView.layer.cornerRadius = 10
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(thumbnailView)

        playGlyph.tintColor = .white
        playGlyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        playGlyph.layer.shadowOpacity = 0.35
        playGlyph.layer.shadowRadius = 3
        playGlyph.layer.shadowOffset = .zero
        playGlyph.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playGlyph)

        // The name carries the row — it is what you read to find the attempt you
        // want; the length beside it is a detail you check once. It reads a step above
        // the notes under it (body, 17) because the row is the head of that block.
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                    constant: -Self.thumbnailInset),
            thumbnailView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),

            playGlyph.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playGlyph.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                                constant: Self.textColumn),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor,
                                                 constant: -Self.labelGap),
            // Title sits just above center so the pair of labels reads as one centered block.
            titleLabel.bottomAnchor.constraint(equalTo: container.centerYAnchor, constant: 2),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor,
                                                  constant: -Self.labelGap),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
        ])
    }

    /// How far back the rating is held on a row — one number for the dot and the word,
    /// so they can never drift apart.
    private static let effortAlpha: CGFloat = 0.8

    /// The scale's colour as a small filled circle, sitting on the words' baseline —
    /// the same mark the picker puts beside each choice, shrunk to a detail.
    private static func dot(_ effort: Effort, on font: UIFont) -> NSAttributedString {
        let configuration = UIImage.SymbolConfiguration(pointSize: 7, weight: .black)
        guard let image = UIImage(systemName: "circle.fill", withConfiguration: configuration)?
            .withTintColor(effort.uiColor.withAlphaComponent(effortAlpha), renderingMode: .alwaysOriginal)
        else { return NSAttributedString() }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0,
                                   y: (font.capHeight - image.size.height) / 2,
                                   width: image.size.width,
                                   height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// A tap somewhere on this row, in the row's own coordinates.
    ///
    /// Driven from the text view's recognizer rather than one of this row's own,
    /// because the two would fight over the same touch and the caret would win: the
    /// row is a link into the attempt, and following it must not also drop the cursor
    /// into the note behind it. `NoteEditor` routes the tap here.
    ///
    /// The row is cut in two down its length, with no glyph to say so: the video and
    /// the end of the card it sits in open the clip, and the name, the length and the
    /// room beside them close the notes underneath. Split on the video's near edge and
    /// judged on x alone, so the whole height of each side answers the same way.
    func handleTap(at point: CGPoint) {
        let video = convert(thumbnailView.frame, from: container)
        // Nothing written under the row means nothing to fold, and a dead half of a
        // card is worse than a wide target: the whole thing opens the clip instead.
        if hasNotes, point.x < video.minX - Self.labelGap / 2 {
            onToggleFold?()
        } else {
            onTap?()
        }
    }

    /// Whether there are notes under this row, and whether they're closed. With notes
    /// the card carries on downward, so its own corners stop at the top; without them
    /// it is the whole box and rounds all four.
    func showNotes(_ has: Bool, folded: Bool) {
        hasNotes = has
        container.layer.maskedCorners = has && !folded
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner,
               .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    func configure(with snapshot: AttemptSnapshot) {
        // Name plus the video's length — the notes are the quote on the line below,
        // in the document itself.
        titleLabel.text = "Attempt \(snapshot.ordinal)"
        detailLabel.attributedText = Self.detail(for: snapshot)
        thumbnailView.image = snapshot.thumbnail
        playGlyph.isHidden = snapshot.thumbnail == nil
    }

    /// The length, and — once it has been answered — how hard it was, carrying the
    /// colour it was picked in. Scanning a session for the goes that cost something is
    /// the whole reason the rating is asked, so it reads off the row itself rather than
    /// only inside the attempt.
    private static func detail(for snapshot: AttemptSnapshot) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString()

        // How hard it was leads the line: it is the thing you scan a session for, and
        // the length is the detail you check once you have found the go you wanted.
        if let effort = snapshot.effort {
            text.append(dot(effort, on: font))
            text.append(NSAttributedString(
                string: " " + effort.label,
                // The same colour as the dot, exactly — the two are one mark, and held
                // back together so neither shouts over the video beside them.
                attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                             .foregroundColor: effort.uiColor.withAlphaComponent(effortAlpha)]))
            text.append(NSAttributedString(
                string: "  ·  ",
                attributes: [.font: font, .foregroundColor: UIColor.tertiaryLabel]))
        }

        text.append(NSAttributedString(
            string: "\(snapshot.duration.clockString) video",
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]))
        return text
    }
}
