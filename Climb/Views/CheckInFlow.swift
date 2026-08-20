import PostHog
import SwiftUI

/// The check-in, asked the way the onboarding quiz asks things: one question to a
/// screen, answered with a tap, and a score at the end of it.
///
/// It was a card inside the note before this, six rows deep on the session's first
/// page, and the trouble with that was never the card — it was that a form embedded in
/// a document is a form you scroll past. A session begins with this or it does not
/// begin, so it gets the screen: nothing else on it, one thing to answer, and the
/// number arriving as a result rather than as a field that quietly filled in.
///
/// The advice at the end is the point of the whole thing. The number is what makes the
/// advice comparable to last week's.
struct CheckInFlow: View {
    /// Where the answers go, and what running off the end of the questions does.
    let onFinish: ([Int]) -> Void
    /// Backing out of the first question — the session still opens, unchecked.
    let onSkip: () -> Void

    /// What is already stored, so reopening this to change one answer starts from what
    /// was said rather than from nothing.
    @State private var answers: [Int]
    /// Whether this question's rows have come in yet. Taken down and put straight back
    /// up on every question, so the rows that were already on screen for the last one
    /// still arrive for this one rather than sitting there through the change.
    @State private var revealed = false
    /// Which question is on screen, or `CheckIn.fields.count` for the score.
    @State private var index: Int

    private let picked = UISelectionFeedbackGenerator()

    /// The quiz's own entrance, to the number: a row comes in from 88% and clear, one
    /// after another down the list. The check-in is the same screen asked again later,
    /// so it moves the same way.
    private static let rowEntrance = Animation.spring(response: 0.48, dampingFraction: 0.78)
    private static let rowStagger = 0.075

    /// The column the summary's symbols sit in, kept in step with the text size the
    /// rows are set at.
    @ScaledMetric(relativeTo: .subheadline) private var iconColumn: CGFloat = 18
    @ScaledMetric(relativeTo: .subheadline) private var iconGlyph: CGFloat = 13

    init(answers: [Int] = [], onFinish: @escaping ([Int]) -> Void, onSkip: @escaping () -> Void) {
        let start = CheckIn.migrating(answers)
        _answers = State(initialValue: start)
        // Reopened on a check-in already answered, this opens on its score rather than
        // walking the four again: the usual reason to come back is to read it.
        _index = State(initialValue: CheckIn.readiness(start) == nil ? 0 : CheckIn.fields.count)
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    private var isScoring: Bool { index >= CheckIn.fields.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress

            if isScoring {
                score
            } else {
                questionScreen(CheckIn.fields[index])
            }
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .safeAreaInset(edge: .bottom) { footer }
        .animation(.easeInOut(duration: 0.2), value: index)
        .onAppear {
            picked.prepare()
            reveal()
        }
        .onChange(of: index) { _, _ in reveal() }
    }

    // MARK: - Questions

    private func questionScreen(_ field: CheckIn.Field) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(field.prompt)
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 48)
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                ForEach(Array(field.options.enumerated()), id: \.offset) { option, title in
                    Button { answer(option) } label: { row(title, chosen: answers[index] == option) }
                        .buttonStyle(.plain)
                        .scaleEffect(revealed ? 1 : 0.88)
                        .opacity(revealed ? 1 : 0)
                        // Only the arrival is animated: going out is instant, so a new
                        // question starts from nothing instead of shrinking the old one
                        // away first.
                        .animation(revealed ? Self.rowEntrance.delay(Double(option) * Self.rowStagger) : nil,
                                   value: revealed)
                }
            }
            // The rows sit in the middle of whatever the question and the footer leave
            // them, which is also where the thumb is — lifted, because the middle of
            // the leftovers is not the middle of the screen. The question pushes the
            // gap down by its own height, so half of that comes back off the bottom
            // and the rows land where the eye was already looking.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 72)
        }
    }

    /// The same row the quiz uses, so a choice looks like a choice everywhere in the
    /// app: flat on the surface unticked, outlined in white once it counts.
    private func row(_ title: String, chosen: Bool) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(Color.surface, in: .rect(cornerRadius: 14))
            .background(Color.white.opacity(chosen ? 0.16 : 0), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(.white, lineWidth: chosen ? 1.5 : 0))
            .contentShape(.rect)
    }

    /// Takes the rows off the screen and puts them back on the next pass.
    private func reveal() {
        revealed = false
        DispatchQueue.main.async { revealed = true }
    }

    /// Answering moves on by itself. There is one answer to a question here and no
    /// reason to confirm it — a tap and then a tap on an arrow is the same decision
    /// charged twice, and the back arrow is what a mis-tap is for.
    private func answer(_ option: Int) {
        answers[index] = option
        picked.selectionChanged()
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
    }

    // MARK: - Score

    private var score: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            if let value = CheckIn.readiness(answers), let verdict = CheckIn.verdict(for: answers) {
                Text("\(value)")
                    .font(.system(size: 96, weight: .heavy))
                    .tracking(-2)
                    .foregroundStyle(verdict.band.tint)
                    .contentTransition(.numericText())

                Text(verdict.headline)
                    .font(.title2.weight(.semibold))
                    .padding(.top, 4)

                Text(verdict.advice)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 10)

                answerSummary
                    .padding(.top, 32)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the number was made of, under it. Small on purpose: the four answers are
    /// the receipt for the score, and nobody reads a receipt first.
    ///
    /// Each answer is drawn in the colour of how good it was, on the same ladder the
    /// number itself is drawn on. It is what turns the receipt into a reading: a 62
    /// made of four fair answers and a 62 made of two good ones and a red one are the
    /// same score and completely different days, and the second one is legible here
    /// without reading a word of it.
    private var answerSummary: some View {
        VStack(spacing: 10) {
            ForEach(Array(CheckIn.fields.enumerated()), id: \.offset) { field, question in
                if question.options.indices.contains(answers[field]) {
                    HStack(spacing: 10) {
                        // A square box each, at one point size: symbols are drawn to
                        // wildly different widths, and left to themselves they sit at
                        // four different sizes down four different margins.
                        Image(systemName: question.icon)
                            .font(.system(size: iconGlyph))
                            .frame(width: iconColumn, height: iconColumn)
                        Text(question.title)
                        Spacer(minLength: 12)
                        Text(question.options[answers[field]])
                            .foregroundStyle(question.score(for: answers[field])
                                .map(CheckIn.tint(forQuality:)) ?? .white.opacity(0.8))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    // MARK: - Chrome

    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * filled)
            }
        }
        .frame(height: 3)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: filled)
    }

    private var filled: CGFloat {
        CGFloat(min(index, CheckIn.fields.count)) / CGFloat(CheckIn.fields.count)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            arrow("chevron.left", enabled: true, action: back)
            Spacer()
            if isScoring {
                Button(action: finish) {
                    Text("Start session")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 26)
                        .frame(height: 56)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
    }

    /// Back off the first question and the session opens anyway, unchecked. A check-in
    /// you cannot decline is one that gets answered dishonestly to get past it, which
    /// is worse than not having it — the questions only mean anything volunteered.
    private func back() {
        if index == 0 {
            // PostHog: track check-in skip (backed out on the first question)
            PostHogSDK.shared.capture("check_in_skipped")
            onSkip()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { index -= 1 }
        }
    }

    private func finish() {
        // PostHog: track check-in completion with the readiness score
        let readiness = CheckIn.readiness(answers)
        PostHogSDK.shared.capture("check_in_completed", properties: [
            "readiness_score": readiness as Any,
        ])
        onFinish(answers)
    }
}

extension CheckIn {
    /// How good an answer was, as one of five: blue, green, yellow, orange, red, taken
    /// straight out of the hold table a climb tag is tinted from rather than picked
    /// again here. A green that only appeared on this card would be a colour the app
    /// has to explain; the same green a green climb is tagged in is one it already has.
    ///
    /// Blue sits past green, which is not how a risk scale works — nothing is safer
    /// than safe — but is exactly how a rank works, and the app has already taught this
    /// one: `GradeTier` runs bronze, silver, gold, platinum, diamond blue, elite purple,
    /// so blue already means the tier above around here. It is worth the exception
    /// because five answers on four colours wastes the top step: green covering both
    /// the best answer and the merely good one is the card declining to tell you the
    /// difference between a full night and nearly enough.
    ///
    /// Five steps rather than a blend between them. A ramp put every answer on its own
    /// slightly different colour, and the ones that landed between yellow and green
    /// came out lime — a colour that reads as its own verdict rather than as a point on
    /// the way to one.
    static func tint(forQuality quality: Double) -> Color {
        Color(uiColor: uiTint(forQuality: quality))
    }

    static func uiTint(forQuality quality: Double) -> UIColor {
        ClimbTint.color(for: hold(forQuality: quality))
    }

    private static func hold(forQuality quality: Double) -> String {
        switch quality {
        // Blue only at the top, and only exactly at it: it is a rank rather than a
        // reading, so it has to be the answer nothing beats and not merely a good one.
        case 0.99...: "blue"
        case 0.75..<0.99: "green"
        case 0.50..<0.75: "yellow"
        case 0.25..<0.50: "orange"
        default: "red"
        }
    }
}

extension CheckIn.Band {
    /// The same five colours the answers are drawn in, off the same hold table: the
    /// number and the rows under it are one scale, so a card of blue answers adds up
    /// to a blue number and you can see that it does without reading either.
    ///
    /// Meaning, not decoration — it is the one thing on the screen you should be able
    /// to read without reading it.
    var tint: Color {
        Color(uiColor: ClimbTint.color(for: hold))
    }

    private var hold: String {
        switch self {
        case .send: "blue"
        case .good: "green"
        case .easy: "yellow"
        case .light: "orange"
        case .rest: "red"
        }
    }

    var uiTint: UIColor { UIColor(tint) }
}
