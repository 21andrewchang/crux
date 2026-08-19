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
    /// Which question is on screen, or `CheckIn.fields.count` for the score.
    @State private var index: Int

    private let picked = UISelectionFeedbackGenerator()

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
        .onAppear { picked.prepare() }
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
                }
            }
            Spacer(minLength: 0)
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
                    .font(.system(size: 96, weight: .bold, design: .rounded))
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
    private var answerSummary: some View {
        VStack(spacing: 10) {
            ForEach(Array(CheckIn.fields.enumerated()), id: \.offset) { field, question in
                if question.options.indices.contains(answers[field]) {
                    HStack {
                        Text(question.title)
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text(question.options[answers[field]])
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .font(.subheadline)
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
            onSkip()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { index -= 1 }
        }
    }

    private func finish() {
        onFinish(answers)
    }
}

extension CheckIn.Band {
    /// Green through red. Meaning, not decoration — it is the one thing on the screen
    /// you should be able to read without reading it.
    var tint: Color {
        switch self {
        case .send: .green
        case .good: Color(red: 0.66, green: 0.85, blue: 0.35)
        case .easy: .yellow
        case .light: .orange
        case .rest: .red
        }
    }

    var uiTint: UIColor { UIColor(tint) }
}
