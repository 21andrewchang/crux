import UIKit

/// Everything the inline row needs to draw, snapshotted so the attachment view never
/// reaches back into SwiftData off the main actor.
struct AttemptSnapshot {
    var ordinal: Int
    var duration: TimeInterval
    var rest: TimeInterval
    var notes: String
    var thumbnail: UIImage?
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
    /// The row currently on screen for this attachment, so a renumber can reach it
    /// without rebuilding the document.
    weak var rowView: AttemptRowView?

    var markerID: UUID { attemptID }
    var takesNotes: Bool { true }

    static let rowHeight: CGFloat = 60

    init(attemptID: UUID) {
        self.attemptID = attemptID
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        return CGRect(x: 0, y: 0, width: width, height: AttemptAttachment.rowHeight)
    }
}

/// The little row that appears inline once an attempt is finished.
final class AttemptRowView: UIView {
    var onTap: (() -> Void)?

    private let container = UIView()
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
        // The row reads as one bubble: a near-black card holding the title on the
        // left and the video on the right, the video tucked inside the bubble's
        // edges like a thumbnail in a list cell.
        // A shade past systemGray6: barely off black, just enough to read as a card.
        container.backgroundColor = UIColor(white: 0.07, alpha: 1)
        container.layer.cornerRadius = 14
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

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
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

            thumbnailView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            thumbnailView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 48),
            thumbnailView.heightAnchor.constraint(equalToConstant: 48),

            playGlyph.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playGlyph.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor, constant: -12),
            // Title sits just above center so the pair of labels reads as one centered block.
            titleLabel.bottomAnchor.constraint(equalTo: container.centerYAnchor, constant: 2),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailView.leadingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap() {
        onTap?()
    }

    func configure(with snapshot: AttemptSnapshot) {
        // Name plus the video's length — the notes are the quote on the line below,
        // in the document itself.
        titleLabel.text = "Attempt \(snapshot.ordinal)"
        detailLabel.text = "\(snapshot.duration.clockString) video"
        thumbnailView.image = snapshot.thumbnail
        playGlyph.isHidden = snapshot.thumbnail == nil
    }
}
