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
    /// Delete, chosen from the row's own press-and-hold menu.
    var onDelete: ((UUID) -> Void)?
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

    static let rowHeight: CGFloat = 64

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
            row.onDelete = { [weak attachment] in attachment?.onDelete?(id) }
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
    /// Chosen from the menu a press and hold puts up. The row goes out of the
    /// document; the attempt behind it is only detached, so undo hands it back.
    var onDelete: (() -> Void)?

    /// A dark dark grey — a step off the page, nowhere near a light card. The notes
    /// written under the row are drawn on the same ground by `BookmarkLayoutFragment`,
    /// so the row and its notes read as one box.
    static let cardFill = UIColor(white: 0.06, alpha: 1)
    static let cardRadius: CGFloat = 14
    /// The card runs the width of the text column, edge to edge: its left edge is the
    /// left edge of the dot on the climb heading above it, and its right edge is where
    /// that heading's own chevron stops. Everything written inside it steps in by
    /// `cardPadding` to clear those edges.
    static let cardPadding: CGFloat = 12

    static let thumbnailInset: CGFloat = cardPadding
    /// The gap between the name and the rating under it. Read by the video too: it is
    /// squared off the pair of lines beside it, so the three edges line up.
    static let lineGap: CGFloat = 6
    /// The gap between the name and the video at the other end of the row.
    static let labelGap: CGFloat = 14
    /// Where the row's name starts: a step inside the card, the same step the clips
    /// written under it take, so a clip's text and the attempt's name read down one
    /// line.
    static let textColumn: CGFloat = cardPadding
    /// Where the bookmarks on the note lines below start. Its left edge, not its
    /// middle: the mark stands flush with the "A" of the name above it, and the words
    /// of the clip step past it.
    static let glyphLeading: CGFloat = textColumn

    private let container = UIView()
    /// Whether anything is written under this row — what decides whether a tap on the
    /// name has notes to fold away.
    private var hasNotes = false

    private let thumbnailView = UIImageView()
    private let playGlyph = UIImageView(image: UIImage(systemName: "play.fill"))
    private let titleLabel = UILabel()
    /// The rating, worn as a tinted tag — the chip a climb heading used to wear.
    private let effortPill = TagPillLabel()
    /// How long the take ran — the detail you check once you have found the go you
    /// wanted, so it follows the rating.
    private let lengthLabel = UILabel()
    /// How many clips were cut out of it, at the end of the line: the count stands in
    /// for the clips themselves, and slides away when they are written out below.
    private let detailLabel = UILabel()
    private lazy var detailRow = UIStackView(arrangedSubviews: [effortPill, lengthLabel, detailLabel])

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildHierarchy()
        // Press and hold for what the row can do. An interaction of the row's own
        // rather than another branch of `handleTap`: the menu, its preview and the
        // dismissal all come from the system this way. The text view behind it is
        // told to keep its hands off a long press here — see `NoteTextView`.
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildHierarchy() {
        // The row reads as the head of one box: a card in the page's own margin with
        // the name on the same left edge every other name in the note starts from, and
        // the video held at the far end. The notes are drawn on the same ground below,
        // so the whole thing is one card.
        container.backgroundColor = Self.cardFill
        container.layer.cornerRadius = Self.cardRadius
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        // The frame it is given is the whole of its size: a still off a 1080p video
        // has an intrinsic size in the thousands, and left able to argue for it the
        // image view pushes the labels it is squared against apart instead.
        thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        thumbnailView.setContentHuggingPriority(.defaultLow, for: .vertical)
        thumbnailView.setContentHuggingPriority(.defaultLow, for: .horizontal)
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
        // want; the length beside it is a detail you check once. The bottom rung of
        // the note's three: a step under the climb heading it is filed under, and a
        // step over the notes written below it.
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        // The name is exactly as tall as one line of it — it, not the video beside it,
        // is what sets the height the two share.
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // How hard it was leads the line, worn as a tag — the thing you scan a
        // session for. The length follows it as the detail you check once you have
        // found the go you wanted.
        effortPill.setContentCompressionResistancePriority(.required, for: .horizontal)

        lengthLabel.font = .systemFont(ofSize: 13)
        lengthLabel.textColor = .secondaryLabel
        lengthLabel.numberOfLines = 1
        lengthLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1

        detailRow.axis = .horizontal
        detailRow.alignment = .center
        detailRow.spacing = 8
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailRow)
        // The count slides in from behind the length rather than out from beside it,
        // so everything to its left has to be in front of it.
        detailRow.bringSubviewToFront(effortPill)
        detailRow.bringSubviewToFront(lengthLabel)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                    constant: -Self.thumbnailInset),
            // Squared off the two lines beside it: the video's top edge is the name's,
            // its bottom edge the rating's, and its width follows its height — so the
            // block of text and the block of picture are the same object seen twice.
            thumbnailView.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: detailRow.bottomAnchor),
            thumbnailView.widthAnchor.constraint(equalTo: thumbnailView.heightAnchor),

            playGlyph.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playGlyph.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                constant: Self.textColumn),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor,
                                                 constant: -Self.labelGap),
            // The name, the rating and the video are one block, centred as one — so
            // the room over the name and the room under the rating are the same, and a
            // row with its clips folded away sits in the middle of its own card.
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailRow.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor,
                                                constant: -Self.labelGap),
            detailRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Self.lineGap),
            // Held at the tag's own height whether or not there is a tag on it, so an
            // unrated attempt's video is the same square as a rated one's.
            detailRow.heightAnchor.constraint(equalToConstant: TagPillLabel.height),
        ])
    }

    /// The same mark the clips themselves carry in their gutter, held back to a
    /// fraction of its yellow: down here it is a label on a count, not a link to
    /// follow, and at full strength it pulled the eye off the name above it.
    private static let clipGlyphAlpha: CGFloat = 0.55

    private static let clipGlyph: UIImage = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let mark = UIImage(systemName: "bubble.left.fill", withConfiguration: configuration)!
            .withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        // Drawn down rather than tinted down: an alpha carried on the tint colour is
        // not honoured the same way everywhere a symbol is composed.
        return UIGraphicsImageRenderer(size: mark.size).image { _ in
            mark.draw(at: .zero, blendMode: .normal, alpha: clipGlyphAlpha)
        }
    }()

    /// The mark the length wears, in the text's own grey: it says the number after it
    /// is a running time and not a count, which is the only thing the word "video"
    /// was there to do.
    private static let lengthGlyph: UIImage = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        return UIImage(systemName: "play.fill", withConfiguration: configuration)!
            .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
    }()

    /// A mark and a number, set the way the clip count beside it is set: the glyph
    /// centred on the digits' own cap height so the two sit on one line.
    private static func glyphed(_ glyph: UIImage, _ text: String) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 13)
        let attachment = NSTextAttachment()
        attachment.image = glyph
        attachment.bounds = CGRect(x: 0,
                                   y: (font.capHeight - glyph.size.height) / 2,
                                   width: glyph.size.width,
                                   height: glyph.size.height)

        let line = NSMutableAttributedString(attachment: attachment)
        line.append(NSAttributedString(
            string: " " + text,
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]))
        return line
    }

    /// How many clips were cut out of the take: the number alone, behind the mark they
    /// all wear — the mark says what is being counted.
    private static func clipCount(_ clips: Int) -> NSAttributedString {
        glyphed(clipGlyph, "\(clips)")
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

    /// Whether the count is currently out. A restyle walks every row and says this
    /// again whether or not anything changed, and re-running the slide on each one
    /// would stutter it.
    private var showsClipCount = true

    /// The count tucked away: far enough left that it is behind the length beside it,
    /// which is the direction it came from — the clips it counts are written out below
    /// the row once the row is open, and a number saying how many of them there are is
    /// the same thing said twice.
    private var tuckedTransform: CGAffineTransform {
        CGAffineTransform(translationX: -(detailLabel.intrinsicContentSize.width + detailRow.spacing),
                          y: 0)
    }

    private func setClipCount(shown: Bool, animated: Bool) {
        guard shown != showsClipCount else { return }
        showsClipCount = shown
        let apply = {
            self.detailLabel.transform = shown ? .identity : self.tuckedTransform
            self.detailLabel.alpha = shown ? 1 : 0
        }
        guard animated else { return apply() }
        UIView.animate(withDuration: 0.32,
                       delay: 0,
                       usingSpringWithDamping: 0.9,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: apply)
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
        // Open, the clips speak for themselves. Off screen the row is being built or
        // rebuilt, and there is nothing to animate from.
        setClipCount(shown: !(has && !folded), animated: window != nil)
    }

    func configure(with snapshot: AttemptSnapshot) {
        // Name, rating, length, and how many clips were cut out of the take — the clips
        // themselves are the lines under the row, in the document itself.
        titleLabel.text = "Attempt \(snapshot.ordinal)"
        effortPill.show(snapshot.effort)
        lengthLabel.attributedText = Self.glyphed(Self.lengthGlyph, snapshot.duration.clockString)
        let clips = NoteTimestamp.clips(in: snapshot.notes).count
        detailLabel.attributedText = Self.clipCount(clips)
        // A different number is a different width to hide behind the tag.
        if !showsClipCount { detailLabel.transform = tuckedTransform }
        thumbnailView.image = snapshot.thumbnail
        playGlyph.isHidden = snapshot.thumbnail == nil
    }

}

extension AttemptRowView: UIContextMenuInteractionDelegate {
    /// One item, and the one thing a row can't otherwise be told to do from the note
    /// itself: get rid of it. Everything else the row does is a tap on one half of it.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint)
        -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Delete Attempt",
                         image: UIImage(systemName: "trash"),
                         attributes: .destructive) { _ in self?.onDelete?() }
            ])
        }
    }

    /// The card lifts, not the whole line it sits on: the row's own rounded box, on
    /// its own fill, so what rises under the menu is the thing the menu is about.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration)
        -> UITargetedPreview? {
        cardPreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration)
        -> UITargetedPreview? {
        cardPreview()
    }

    /// The card as the menu lifts it: the row itself, on a platter painted its own
    /// fill.
    ///
    /// The platter is the whole point of answering this at all. Left to the system it
    /// is a background colour of the system's choosing, which on a black page is
    /// black — the card arriving under the menu with its fill gone. Everything else
    /// here is UIKit's: it takes the row away and puts it back on its own schedule,
    /// and anything this side did to help — a drawn copy, the row faded out under it —
    /// was a second schedule for the same view, which is where the flicker came from.
    private func cardPreview() -> UITargetedPreview? {
        guard window != nil, bounds.width > 0 else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = Self.cardFill
        // All four corners, whichever two the card happens to be masking: with the
        // clips open it runs on below the row and only rounds its top, but the piece
        // that lifts is the row alone and a card cut square at the bottom reads as
        // torn.
        parameters.visiblePath = UIBezierPath(roundedRect: bounds,
                                              cornerRadius: Self.cardRadius)
        return UITargetedPreview(view: self, parameters: parameters)
    }
}

/// A word in a tinted capsule: the tag a climb heading used to wear, now the rating's.
/// Nothing but a label with room held around its text.
final class TagPillLabel: UILabel {
    private static let insets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
    private static let pillFont = UIFont.systemFont(ofSize: 12, weight: .semibold)

    /// What the tag stands at, text or no text — the row squares its video off this.
    static let height = ceil(pillFont.lineHeight) + insets.top + insets.bottom

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = Self.pillFont
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The rating, in its own colour on a wash of it. Unanswered it still stands
    /// there, saying so in grey — the question is part of what a row is, and a row
    /// that simply left it out gave no sign there was anything to answer.
    func show(_ effort: Effort?) {
        text = effort?.label ?? "Effort"
        let tint = effort?.uiColor ?? .systemGray
        textColor = effort == nil ? .secondaryLabel : tint
        backgroundColor = tint.withAlphaComponent(effort == nil ? 0.14 : 0.22)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.insets.left + Self.insets.right,
                      height: size.height + Self.insets.top + Self.insets.bottom)
    }

    /// A capsule, not a rounded box: a continuous curve at half the height reads as a
    /// squircle, so the ends are drawn circular and the radius follows the height.
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerCurve = .circular
        layer.cornerRadius = bounds.height / 2
        layer.masksToBounds = true
    }
}
