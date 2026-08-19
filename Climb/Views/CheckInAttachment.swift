import UIKit

/// The check-in card: the grey block pinned under a note's title, holding the six
/// questions a readiness score is made of.
///
/// Deliberately not a `MarkerAttachment`. Nothing about it is written into `bodyText`
/// and it carries no id — every session has exactly one, put into the document on the
/// way out of storage and taken off again on the way back in
/// (`NoteDocument.insertCheckIn` / `serialize`). That is what hands one to every note
/// written before the card existed, and what stops a note growing a stray marker
/// every time it is saved.
final class CheckInAttachment: NSTextAttachment {
    /// The card holds no state of its own: it reads the session through these and
    /// writes back through them, so a reload rebuilds it exactly as it stood.
    var answers: () -> [Int] = { [] }
    var onAnswer: (_ field: Int, _ option: Int) -> Void = { _, _ in }
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
    /// asks again on every caret query, which is every keystroke — so the answer is
    /// kept rather than re-fitted. The width is the whole of the key: the advice line
    /// is held open at two lines whatever it says, so which answers are given cannot
    /// move it.
    private var measured: (width: CGFloat, height: CGFloat)?

    func height(forWidth width: CGFloat) -> CGFloat {
        if let measured, measured.width == width {
            return measured.height
        }
        ruler.configure(answers: answers())
        ruler.frame = CGRect(x: 0, y: 0, width: width, height: 0)
        let fitted = ruler.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let height = ceil(fitted.height)
        measured = (width, height)
        return height
    }

    /// Throws the measurement away and asks the editor to lay the line out again —
    /// what a change in the text size needs, the card's height being measured off it.
    func invalidateHeight() {
        measured = nil
        onResize()
    }

    /// The width the card lays out in: the full text column, like an attempt row.
    /// Shared, so the two questions below cannot answer at different widths.
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
            card.onAnswer = { [weak attachment] field, option in attachment?.onAnswer(field, option) }
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

/// The card itself: six rows of taps and the score they come to.
///
/// No header and no way to shut it. The page it opens is called Check-in and holds
/// nothing else, so a bar naming it again would be the same word twice — and a card
/// that is the whole point of its page has nothing to be collapsed out of the way of.
///
/// Everything is a tap and nothing is a drag. The coaching platforms ask these on
/// 0–10 sliders, but a slider living inside a scrolling text view spends its life
/// arguing with the scroll for the same gesture — and a five-point scale answered
/// honestly beats an eleven-point one answered by whichever pixel the thumb landed on.
final class CheckInCardView: UIView {
    var onAnswer: ((Int, Int) -> Void)?

    private let container = UIView()
    private let questions = UIStackView()
    private let divider = UIView()
    private let footer = UIStackView()
    private let scoreLabel = UILabel()
    private let verdictLabel = UILabel()
    private let adviceLabel = UILabel()
    /// The pills, by question then by option — the grid, kept so a configure can
    /// restyle it without rebuilding it.
    private var pills: [[UIButton]] = []

    private static let rowHeight: CGFloat = 30
    private static let labelWidth: CGFloat = 56
    private static let adviceFont = UIFont.systemFont(ofSize: 13)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildHierarchy() {
        // The one grey in the app: a few percent of white, no border. Everything that
        // has to read as its own block lifts off the black by exactly this much.
        container.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)

        questions.axis = .vertical
        questions.spacing = 6
        for (index, field) in CheckIn.fields.enumerated() {
            questions.addArrangedSubview(makeRow(index, field: field))
        }
        column.addArrangedSubview(questions)

        divider.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        column.addArrangedSubview(divider)

        buildFooter()
        column.addArrangedSubview(footer)

        // Tighter around the rule than between the blocks it separates — it is a
        // seam, not another block.
        column.setCustomSpacing(10, after: questions)
        column.setCustomSpacing(10, after: divider)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: CheckInAttachment.margin),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CheckInAttachment.margin),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),

            column.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
    }

    private func buildFooter() {
        scoreLabel.font = .systemFont(ofSize: 28, weight: .bold)
        scoreLabel.setContentHuggingPriority(.required, for: .horizontal)

        verdictLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        // Held open at two lines whatever it currently says, so answering a question
        // never reflows the note under the card.
        adviceLabel.font = Self.adviceFont
        adviceLabel.textColor = .secondaryLabel
        adviceLabel.numberOfLines = 2
        adviceLabel.translatesAutoresizingMaskIntoConstraints = false
        adviceLabel.heightAnchor.constraint(equalToConstant: ceil(Self.adviceFont.lineHeight * 2)).isActive = true

        let score = UIStackView(arrangedSubviews: [scoreLabel, verdictLabel])
        score.axis = .horizontal
        score.spacing = 8
        score.alignment = .firstBaseline

        footer.axis = .vertical
        footer.spacing = 3
        footer.addArrangedSubview(score)
        footer.addArrangedSubview(adviceLabel)
    }

    private func makeRow(_ index: Int, field: CheckIn.Field) -> UIView {
        let label = UILabel()
        label.text = field.title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true

        let options = UIStackView()
        options.axis = .horizontal
        options.spacing = 4
        options.distribution = .fillEqually

        var buttons: [UIButton] = []
        for (option, title) in field.options.enumerated() {
            let pill = makePill(title)
            pill.addAction(UIAction { [weak self] _ in self?.onAnswer?(index, option) },
                           for: .touchUpInside)
            options.addArrangedSubview(pill)
            buttons.append(pill)
        }
        pills.append(buttons)

        let row = UIStackView(arrangedSubviews: [label, options])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        return row
    }

    private func makePill(_ title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        config.background.cornerRadius = 8
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .medium)
            return outgoing
        }
        let pill = UIButton(type: .system)
        pill.configuration = config
        return pill
    }

    /// The answer given lifts further off the page rather than colouring in: the note
    /// is black and grey the whole way down, and the one place colour is allowed to
    /// carry meaning here is the score.
    private func style(_ pill: UIButton, selected: Bool) {
        guard var config = pill.configuration else { return }
        config.background.backgroundColor = UIColor.white.withAlphaComponent(selected ? 0.20 : 0.05)
        config.baseForegroundColor = selected ? .label : .secondaryLabel
        pill.configuration = config
    }

    func configure(answers: [Int]) {
        for (index, buttons) in pills.enumerated() {
            let answer = answers.indices.contains(index) ? answers[index] : CheckIn.unanswered
            for (option, pill) in buttons.enumerated() {
                style(pill, selected: option == answer)
            }
        }

        if let score = CheckIn.readiness(answers), let verdict = CheckIn.verdict(for: answers) {
            scoreLabel.text = "\(score)"
            scoreLabel.textColor = Self.tint(for: score)
            verdictLabel.text = verdict.headline
            verdictLabel.textColor = .label
            adviceLabel.text = verdict.advice
        } else {
            let done = CheckIn.answeredCount(answers)
            // No partial score: a number that climbed as the form was filled in would
            // teach you to fill the form in until it read the way you wanted.
            scoreLabel.text = "—"
            scoreLabel.textColor = .tertiaryLabel
            verdictLabel.text = "\(done) of \(CheckIn.fields.count)"
            verdictLabel.textColor = .secondaryLabel
            adviceLabel.text = "Answer all six for today's readiness — what this session should be, before you get on anything."
        }
    }

    /// Green through red by band. Meaning, not decoration — it is the one thing on
    /// the card you should be able to read without reading it.
    private static func tint(for score: Int) -> UIColor {
        switch score {
        case 80...: .systemGreen
        case 60..<80: UIColor(red: 0.66, green: 0.85, blue: 0.35, alpha: 1)
        case 40..<60: .systemYellow
        case 20..<40: .systemOrange
        default: .systemRed
        }
    }
}
