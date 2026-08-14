import UIKit

/// Everything the inline climb heading draws, snapshotted so the attachment view never
/// reaches back into SwiftData while laying out.
struct ClimbSnapshot {
    var name: String
    /// Every go ever taken on this climb, not just the ones in this note.
    var attemptCount: Int
}

/// A text attachment standing for a climb heading in the note. Same view-provider
/// mechanism as `AttemptAttachment`, but it reads as a section header: the attempts
/// recorded underneath it belong to this climb.
final class ClimbAttachment: NSTextAttachment, MarkerAttachment {
    let climbID: UUID
    var snapshotProvider: ((UUID) -> ClimbSnapshot?)?
    var onTap: ((UUID) -> Void)?
    /// The row currently on screen for this attachment, so a count change can reach it
    /// without rebuilding the document.
    weak var rowView: ClimbRowView?

    var markerID: UUID { climbID }
    var takesNotes: Bool { false }

    static let rowHeight: CGFloat = 52

    init(climbID: UUID) {
        self.climbID = climbID
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(for parentView: UIView?,
                               location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = ClimbRowViewProvider(textAttachment: self,
                                            parentView: parentView,
                                            textLayoutManager: textContainer?.textLayoutManager,
                                            location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class ClimbRowViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let row = ClimbRowView()
        if let attachment = textAttachment as? ClimbAttachment {
            let id = attachment.climbID
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
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let available = (textContainer?.size.width ?? proposedLineFragment.width) - padding
        let width = max(120, min(available, proposedLineFragment.width))
        return CGRect(x: 0, y: 0, width: width, height: ClimbAttachment.rowHeight)
    }
}

/// The heading itself: the name as a tinted tag on the left, the attempt count plain on
/// the right. Gym problems are named by hold colour — "Blue V4", "pink slab" — so the
/// tag picks that colour up, and the note becomes scannable by colour alone.
final class ClimbRowView: UIView {
    var onTap: (() -> Void)?

    private let nameTag = UIView()
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildHierarchy() {
        nameTag.layer.cornerCurve = .continuous
        nameTag.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameTag)

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameTag.addSubview(nameLabel)

        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.textAlignment = .right
        // The tag gets the room; the count is short and never truncates.
        summaryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        summaryLabel.setContentHuggingPriority(.required, for: .horizontal)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(summaryLabel)

        NSLayoutConstraint.activate([
            // Extra room above, little below: the heading belongs to what follows it.
            nameTag.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameTag.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            nameLabel.leadingAnchor.constraint(equalTo: nameTag.leadingAnchor, constant: 11),
            nameLabel.trailingAnchor.constraint(equalTo: nameTag.trailingAnchor, constant: -11),
            nameLabel.topAnchor.constraint(equalTo: nameTag.topAnchor, constant: 5),
            nameLabel.bottomAnchor.constraint(equalTo: nameTag.bottomAnchor, constant: -5),

            summaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameTag.trailingAnchor, constant: 10),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            summaryLabel.centerYAnchor.constraint(equalTo: nameTag.centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        nameTag.layer.cornerRadius = nameTag.bounds.height / 2
    }

    /// Only the tag itself is interactive. The rest of the row — the gap beside it, the
    /// count, the space above and below — falls through to the text view, so tapping
    /// around the heading puts the caret there instead of opening the climb.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard nameTag.frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    @objc private func handleTap() {
        onTap?()
    }

    func configure(with snapshot: ClimbSnapshot) {
        nameLabel.text = snapshot.name
        let count = snapshot.attemptCount
        summaryLabel.text = count == 1 ? "1 attempt" : "\(count) attempts"

        // Tinted fill, tinted text: a chip that carries the colour without shouting it.
        let tint = ClimbTint.color(for: snapshot.name)
        nameTag.backgroundColor = tint.withAlphaComponent(0.22)
        nameLabel.textColor = tint
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
