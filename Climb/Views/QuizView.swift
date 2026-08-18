import SwiftUI
import UIKit

/// The first thing a new user sees: a handful of questions, one per screen. Most take
/// a single tap and move straight on; the ones that ask for a list wait at the arrow.
/// Nothing here is required by the app yet — it exists to set the frame before the
/// tutorial hands over the real thing.
struct QuizView: View {
    struct Question: Identifiable {
        let id: String
        let title: String
        let options: [String]
        /// Several answers rather than one — which also means the screen no longer
        /// advances on a tap, since a tap is now "and this too".
        var allowsMultiple = false
        /// Adds a row that opens a field, for the answer the list doesn't have.
        var allowsOther = false
        /// What a chosen row reads in. White for a question with one answer; a colour
        /// where the answers mean something against each other.
        var tint: Color = .white
        /// Another question over the same list whose answers stay on screen here, in
        /// their own colour and not for changing — so the second pass is read against
        /// the first rather than made blind to it.
        var carriesOver: String?
    }

    /// The vocabulary strengths and weaknesses share, so that "good at" and "held back
    /// by" line up as the same axes read in two directions rather than two lists that
    /// have to be reconciled later. Footwork and route reading are pulled out of
    /// technique — they are what people actually name — which leaves movement for
    /// everything else about how you climb.
    private static let attributes = ["Finger strength", "Power", "Endurance",
                                     "Body tension", "Footwork", "Movement",
                                     "Route reading", "Flexibility", "Mentality",
                                     "Recovery"]

    // Ordered by how much thinking each one costs, cheapest first: facts about you,
    // then facts about your climbing, then a judgement about yourself, and only at the
    // end what you want out of the app — the one question worth arriving at with the
    // rest already said. Weight, height and ape index belong in the first stretch too,
    // but they need a screen that takes a number rather than a tap.
    static let questions: [Question] = [
        .init(id: "age", title: "How old are you?",
              options: ["Under 18", "18–24", "25–34", "35–44", "45+"]),
        .init(id: "gender", title: "What's your gender?",
              options: ["Man", "Woman", "Prefer not to say"]),
        .init(id: "grade", title: "What are you projecting?",
              options: ["V0–V2", "V3–V5", "V6–V8", "V9+"]),
        // Straight after what you're on, in the same buckets, so the two together are
        // the gap the app is for.
        .init(id: "dreamGrade", title: "What's your dream grade?",
              options: ["V3–V5", "V6–V8", "V9–V11", "V12+"]),
        .init(id: "experience", title: "How long have you been climbing?",
              options: ["Just started", "Under a year", "1–3 years", "3+ years"]),
        .init(id: "frequency", title: "How often do you climb?",
              options: ["Once a week", "Twice a week", "3–4 times", "Almost daily"]),
        .init(id: "competes", title: "Do you compete?",
              options: ["No", "I'd like to", "Local comps", "Regionals or higher"]),
        // Weaknesses first: easier to name than strengths, and naming them makes the
        // strengths screen a relief rather than a boast. The same ten rows twice over,
        // marked red then green — the second screen keeps the red so it reads as one
        // list being sorted rather than the same question asked again.
        .init(id: "weaknesses", title: "Your weaknesses",
              options: attributes, allowsMultiple: true, tint: .red),
        .init(id: "strengths", title: "Your strengths",
              options: attributes, allowsMultiple: true, tint: .green,
              carriesOver: "weaknesses"),
        .init(id: "goal", title: "What are you here for?",
              options: ["Send a project", "Get stronger", "Fix my technique", "Track my sessions"]),
    ]

    /// The row that opens the field. Kept as a constant rather than a literal because
    /// it is both a label on screen and a key in `chosen`.
    private static let otherOption = "Something else"

    var onFinish: () -> Void

    /// Kept on `Onboarding` rather than here, so quitting mid-quiz comes back to the
    /// question that was on screen instead of to the first one.
    @State private var onboarding = Onboarding.shared
    /// What is ticked on the screen currently up — read back off the saved answer every
    /// time a question comes up, so stepping back through the quiz shows what you said
    /// rather than a blank screen.
    @State private var chosen: Set<String> = []
    @State private var other = ""
    @FocusState private var otherFocused: Bool
    @State private var picked = UIImpactFeedbackGenerator(style: .medium)
    @State private var unpicked = UIImpactFeedbackGenerator(style: .light)

    private var index: Int { min(max(onboarding.quizIndex, 0), Self.questions.count - 1) }
    private var question: Question { Self.questions[index] }

    private var rows: [String] {
        question.allowsOther ? question.options + [Self.otherOption] : question.options
    }

    /// What the screen before marked, still marked here: the weaknesses showing in red
    /// under the strengths being picked in green.
    private var carried: Set<String> {
        guard let id = question.carriesOver, let saved = onboarding.answers[id] else { return [] }
        return Set(saved.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    private var carriedTint: Color {
        Self.questions.first { $0.id == question.carriesOver }?.tint ?? .white
    }

    /// Forward is off until the question has been answered — and an empty "something
    /// else" is not an answer, so ticking that row alone doesn't open the door.
    private var canAdvance: Bool { !answerText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress

            Text(question.title)
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 48)
                .padding(.bottom, 28)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.self) { option in
                        Button { tap(option) } label: { row(option) }
                            .buttonStyle(.plain)
                            .disabled(carried.contains(option))
                    }
                    // Room under the last row for the arrows to float over, so nothing
                    // is stuck behind them at the end of a long list.
                    Color.clear.frame(height: 96)
                }
            }
            .scrollIndicators(.hidden)
            // The list runs off the bottom of the screen rather than stopping at an
            // edge: what is under the arrows fades out instead of being cut.
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.78),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        // Over the list, at the two edges: back where a thumb reaches to undo, forward
        // where it reaches to go on.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack {
                    arrow("chevron.left", enabled: index > 0, action: back)
                    Spacer()
                    arrow("chevron.right", enabled: canAdvance) { advance() }
                }
                // Why any of this is being asked, said once at the foot of every screen
                // rather than on a screen of its own.
                Text("Answers used for proper goal-setting")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        // A new question is a new screen, not the same one re-lettered.
        .animation(.easeInOut(duration: 0.2), value: index)
        .animation(.easeInOut(duration: 0.15), value: chosen)
        .onAppear {
            loadAnswer()
            picked.prepare()
            unpicked.prepare()
        }
        .onChange(of: index) { loadAnswer() }
    }

    /// The two ways through the quiz, as glass over the list rather than a slab under
    /// it — the list keeps the full height of the screen and these sit on top of it.
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
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    /// A row is a tap target first: flat on the surface unticked, outlined in white
    /// once it counts — the same selected state the paywall's plans use, so a choice
    /// looks like a choice everywhere in the app. The "something else" row grows a
    /// field under its label rather than becoming one, so the list keeps its shape.
    @ViewBuilder
    private func row(_ option: String) -> some View {
        let isCarried = carried.contains(option)
        let isChosen = chosen.contains(option) && !isCarried
        let tint = isCarried ? carriedTint : question.tint
        let isMarked = isChosen || isCarried
        VStack(alignment: .leading, spacing: 8) {
            Text(option)
                .frame(maxWidth: .infinity, alignment: .leading)
            if option == Self.otherOption, isChosen {
                TextField("", text: $other, prompt: Text("In your words").foregroundStyle(.white.opacity(0.35)))
                    .textInputAutocapitalization(.sentences)
                    .focused($otherFocused)
                    .submitLabel(.done)
                    .onSubmit { otherFocused = false }
                    .foregroundStyle(.white)
            }
        }
        .foregroundStyle(isMarked ? tint : .white)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.surface, in: .rect(cornerRadius: 14))
        // The colour sits under the row as well as around it, faintly — enough that a
        // marked row reads at a glance down the list, not enough to shout at ten of them.
        .background(tint.opacity(isMarked ? 0.16 : 0), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(tint, lineWidth: isMarked ? 1.5 : 0))
        .contentShape(.rect)
        // A row already spoken for on the screen before is not for changing here.
        .opacity(isCarried ? 0.65 : 1)
    }

    /// One bar filling across the quiz — how much is left, without a number. The same
    /// fraction the ticks used to step through, read continuously: answering slides it
    /// on rather than switching a segment.
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
        // Enough spring to read as a slide, not enough to overshoot the end of the bar.
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: filled)
    }

    /// How much of the bar is behind you: the question you are on counts, so the first
    /// screen is already a step in rather than empty.
    private var filled: CGFloat {
        CGFloat(index + 1) / CGFloat(Self.questions.count)
    }

    /// What this screen would be recorded as: the ticked rows in the order the list
    /// puts them, with "something else" standing for whatever was typed into it.
    private var answerText: String {
        // Never what the screen before claimed: a weakness cannot come back as a
        // strength, however the two screens were walked through.
        rows.filter { chosen.contains($0) && !carried.contains($0) }
            .map { $0 == Self.otherOption ? other.trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Puts the saved answer back on screen. Anything in it that isn't one of the rows
    /// was typed into "something else", and goes back there.
    private func loadAnswer() {
        let saved = onboarding.answers[question.id] ?? ""
        var picks: Set<String> = []
        var typed = ""
        for part in saved.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        where !part.isEmpty {
            if question.options.contains(part) {
                picks.insert(part)
            } else if question.allowsOther {
                typed = part
                picks.insert(Self.otherOption)
            }
        }
        chosen = picks.subtracting(carried)
        other = typed
    }

    private func tap(_ option: String) {
        guard question.allowsMultiple else {
            felt(picking: true)
            // Recorded from the tap itself rather than from `chosen`: state written
            // this pass is not guaranteed to read back before the next one.
            chosen = [option]
            advance(recording: option)
            return
        }
        if chosen.contains(option) {
            felt(picking: false)
            chosen.remove(option)
            if option == Self.otherOption { other = "" }
        } else {
            felt(picking: true)
            chosen.insert(option)
            if option == Self.otherOption { otherFocused = true }
        }
    }

    /// A tap under the finger for every answer given, and a lighter one for an answer
    /// taken back — the same feel the loading route sets its holds with, so choosing
    /// something is one thing throughout onboarding.
    private func felt(picking: Bool) {
        let feedback = picking ? picked : unpicked
        feedback.impactOccurred()
        feedback.prepare()
    }

    /// `text` for a screen that answers itself on a tap; without it, whatever is ticked.
    private func advance(recording text: String? = nil) {
        otherFocused = false
        onboarding.answers[question.id] = text ?? answerText
        if index + 1 < Self.questions.count {
            onboarding.quizIndex = index + 1
        } else {
            onFinish()
        }
    }

    /// Back a question, keeping what was said on this one — stepping back to check an
    /// answer shouldn't cost the answer you were on.
    private func back() {
        otherFocused = false
        onboarding.answers[question.id] = answerText
        onboarding.quizIndex = max(0, index - 1)
    }
}
