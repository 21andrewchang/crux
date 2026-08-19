import UIKit

/// The check-in card, pinned under a note's title: the score the session opened with,
/// and the four answers it was made of.
///
/// It does not ask anything. The questions live in `CheckInFlow`, which runs over the
/// whole screen before the note is ever on it — a form embedded in a document is a
/// form you scroll past, and this is the one thing a session should not begin without
/// having been offered. What is left here is the reading of it: a number you can see
/// across the room, and the four answers under it in case you want to know why it says
/// what it says. Tapping it opens the questions again.
///
/// Deliberately not a `MarkerAttachment`. Nothing about it is written into `bodyText`
/// and it carries no id — every session has exactly one, put into the document on the
/// way out of storage and taken off again on the way back in
/// (`NoteDocument.insertCheckIn` / `serialize`). That is what hands one to every note
/// written before the card existed, and what stops a note growing a stray marker
/// every time it is saved.
final class CheckInAttachment: NSTextAttachment {
    /// The card holds no state of its own: it reads the session through this, so a
    /// reload rebuilds it exactly as it stood.
    var answers: () -> [Int] = { [] }
    /// The card was tapped: put the questions back on screen.
    var onOpen: () -> Void = {}
    /// The card's height has changed under it, so the line it sits on has to be laid
    /// out again — something only the editor can ask for.
    var onResize: () -> Void = {}

    /// The card currently on screen, so an answer can be reflected in place rather
    /// than by rebuilding the document out from under the finger that just tapped.
    weak var cardView: CheckInCardView?

    /// Room above and below, so the card reads as a block set under the title rather
    /// than as another line of it.
    static let margin: CGFloat = 8

    override init(data: Data?, ofType uti: String?) {
        super.init(data: data, ofType: uti)
        allowsTextAttachmentView = true
    }

    convenience init() {
        self.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Measured off a card kept aside for the purpose rather than assumed from a
    /// table of constants: the rows are laid out by Auto Layout in the user's own
    /// text size, and this has to agree with what actually gets drawn or the line
    /// under the card is a few points out at every size but the default.
    private lazy var ruler: CheckInCardView = {
        let card = CheckInCardView()
        card.isUserInteractionEnabled = false
        return card
    }()

    /// `attachmentBounds` is asked on every pass over the line — and the caret maths
    /// asks again on every caret query — so the answer is kept rather than re-fitted.
    /// Keyed on whether the check-in is answered as well as on width: an unanswered
    /// card drops its summary, so the two are different heights at the same width.
    private var measured: (width: CGFloat, complete: Bool, height: CGFloat)?

    func height(forWidth width: CGFloat) -> CGFloat {
        let current = answers()
        let complete = CheckIn.readiness(current) != nil
        if let measured, measured.width == width, measured.complete == complete {
            return measured.height
        }
        ruler.configure(answers: current)
        ruler.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        let fitted = ruler.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let height = ceil(fitted.height)
        measured = (width, complete, height)
        return height
    }

    /// Throws the measurement away and asks the editor to lay the line out again —
    /// what a change in the text size needs, the card's height being measured off it.
    func invalidateHeight() {
        measured = nil
        onResize()
    }

    /// The width the card lays out in: the full text column, like an attempt row.
    ///
    /// Reads `proposedLineFragment.width` and never its height, and must keep doing
    /// so: `NoteTextView`'s caret maths asks for these bounds with a proposed fragment
    /// of (container width x .greatestFiniteMagnitude), so anything measured against
    /// the proposed *height* would be measured against infinity.
    static func width(in textContainer: NSTextContainer?, proposedLineFragment: CGRect) -> CGFloat {
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let available = (textContainer?.size.width ?? proposedLineFragment.width) - padding
        return max(120, min(available, proposedLineFragment.width))
    }

    /// The same height, answered through `NSTextAttachmentContainer` as well.
    ///
    /// TextKit 2 asks the view provider, which is the override further down. This is
    /// the older question, and `NSTextAttachment` answers it out of `bounds` — which
    /// nothing here ever sets, so left alone it reports a card of no height at all.
    /// `NoteTextView`'s caret maths asks this way when it wants a block line to answer
    /// for its own height rather than trusting the caret rect on it, and a silent zero
    /// there is worse than no answer: it reads as a real measurement.
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        let width = Self.width(in: textContainer, proposedLineFragment: lineFrag)
        return CGRect(x: 0, y: 0, width: width, height: height(forWidth: width))
    }

    override func viewProvider(for parentView: UIView?,
                               location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = CheckInViewProvider(textAttachment: self,
                                           parentView: parentView,
                                           textLayoutManager: textContainer?.textLayoutManager,
                                           location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class CheckInViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let card = CheckInCardView()
        if let attachment = textAttachment as? CheckInAttachment {
            card.configure(answers: attachment.answers())
            card.onOpen = { [weak attachment] in attachment?.onOpen() }
            attachment.cardView = card
        }
        view = card
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                   location: any NSTextLocation,
                                   textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect,
                                   position: CGPoint) -> CGRect {
        // The full text column, like an attempt row: the card is a block, not a glyph.
        let width = CheckInAttachment.width(in: textContainer, proposedLineFragment: proposedLineFragment)
        let height = (textAttachment as? CheckInAttachment)?.height(forWidth: width) ?? 0
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

/// The card itself: the score, what it came to, and the four answers behind it.
///
/// Drawn at a size that assumes it is the only thing on its page, because it is. The
/// number carries the colour and nothing else does — it is the one thing here you
/// should be able to read without reading it.
final class CheckInCardView: UIView {
    /// The card was tapped.
    var onOpen: (() -> Void)?

    private let column = UIStackView()
    private let scoreLabel = UILabel()
    private let verdictLabel = UILabel()
    private let adviceLabel = UILabel()
    private let summary = UIStackView()
    /// The answer beside each question's name, in `CheckIn.fields` order.
    private var values: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildHierarchy() {
        scoreLabel.font = .systemFont(ofSize: 84, weight: .bold)
        scoreLabel.textAlignment = .center

        verdictLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        verdictLabel.textColor = .label
        verdictLabel.textAlignment = .center

        adviceLabel.font = .systemFont(ofSize: 14)
        adviceLabel.textColor = .secondaryLabel
        adviceLabel.textAlignment = .center
        adviceLabel.numberOfLines = 0

        // What the number was made of, under it and smaller. The four answers are the
        // receipt for the score, and nobody reads a receipt first.
        summary.axis = .vertical
        summary.spacing = 7
        for field in CheckIn.fields {
            summary.addArrangedSubview(makeSummaryRow(field))
        }

        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(scoreLabel)
        column.addArrangedSubview(verdictLabel)
        column.addArrangedSubview(adviceLabel)
        column.addArrangedSubview(summary)
        column.setCustomSpacing(10, after: verdictLabel)
        column.setCustomSpacing(32, after: adviceLabel)
        addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: CheckInAttachment.margin),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CheckInAttachment.margin),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Opens the check-in."
    }

    private func makeSummaryRow(_ field: CheckIn.Field) -> UIView {
        let name = UILabel()
        name.text = field.title
        name.font = .systemFont(ofSize: 15)
        name.textColor = .tertiaryLabel

        let value = UILabel()
        value.font = .systemFont(ofSize: 15, weight: .medium)
        value.textColor = .secondaryLabel
        value.textAlignment = .right
        values.append(value)

        let row = UIStackView(arrangedSubviews: [name, value])
        row.axis = .horizontal
        row.spacing = 12
        return row
    }

    @objc private func tapped() {
        onOpen?()
    }

    func configure(answers: [Int]) {
        let verdict = CheckIn.verdict(for: answers)

        if let score = CheckIn.readiness(answers), let verdict {
            scoreLabel.text = "\(score)"
            scoreLabel.textColor = verdict.band.uiTint
            verdictLabel.text = verdict.headline
            adviceLabel.text = verdict.advice
            accessibilityLabel = "Readiness \(score). \(verdict.headline). \(verdict.advice)"
        } else {
            // Backed out of rather than answered. The card says what it is for and
            // nothing else — a number would have to be invented to sit there, and a
            // dash reads as a score of nothing rather than as a question never asked.
            scoreLabel.text = "—"
            scoreLabel.textColor = .quaternaryLabel
            verdictLabel.text = "Check in"
            adviceLabel.text = "Four questions, ten seconds — what this session should be."
            accessibilityLabel = "Check in. Four questions, ten seconds."
        }

        for (index, field) in CheckIn.fields.enumerated() {
            let answer = answers.indices.contains(index) ? answers[index] : CheckIn.unanswered
            values[index].text = field.options.indices.contains(answer) ? field.options[answer] : "—"
        }
        summary.isHidden = verdict == nil
    }
}
