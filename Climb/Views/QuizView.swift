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
        /// How many of them at most. A list you can tick all the way down tells us
        /// nothing — asking for a few forces the ranking that makes the answer worth
        /// having. Once the count is reached the rows left over go quiet rather than
        /// swapping something out under the finger: what you picked stays picked until
        /// you take it back yourself.
        var limit: Int?
        /// Adds a row that opens a field, for the answer the list doesn't have.
        var allowsOther = false
        /// What a chosen row reads in. White for a question with one answer; a colour
        /// where the answers mean something against each other.
        var tint: Color = .white
        /// Another question over the same list whose answers stay on screen here, in
        /// their own colour and not for changing — so the second pass is read against
        /// the first rather than made blind to it.
        var carriesOver: String?
        /// Answered with a number instead of a list: the rows give way to a ruler, and
        /// `options` goes unread.
        var measure: BodyMeasure?
        /// A quiet line under the question, for the ones that need a word of
        /// explanation — what a term means, or that more than one answer is allowed.
        /// It sits inside the space the header already holds, so adding one to a
        /// question never moves that screen's answers.
        var note: String?
        /// Whether this question is worth asking at all, given what has been said so
        /// far. A question that isn't is stepped straight over in both directions, so
        /// nobody who has just told us they can't do a pull-up is asked how much weight
        /// they add to one.
        var asks: (([String: String]) -> Bool)?
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
    // rest already said. The three numbers open it, on a ruler rather than a list,
    // because the quickest thing to answer should be the thing that is already up.
    static let questions: [Question] = [
        .init(id: "height", title: "How tall are you?", options: [], measure: .height),
        .init(id: "weight", title: "What do you weigh?", options: [], measure: .weight),
        // Asked straight after height because that is what it is measured against, and
        // asked at all because it is the one body number climbers already know.
        .init(id: "apeIndex", title: "What's your ape index?", options: [],
              measure: .apeIndex, note: "Arm span minus height."),
        // Behind the numbers rather than in front of them: a ruler is answered with a
        // thumb and gets the quiz moving, where a list of age brackets is the sort of
        // form question that makes the first screen feel like a form.
        .init(id: "age", title: "How old are you?",
              options: ["Under 18", "18–24", "25–34", "35–44", "45+"]),
        // The two grades, both on the V scale itself rather than in three-wide buckets.
        // These are the answers a climber knows to the rung — nobody projects "V6 to
        // V8" — and bucketing them threw away the one thing the pair is asked for: the
        // gap. Under a banded ladder V5→V6 and V5→V8 were the same answer, and a goal
        // you have already met at the bottom of its own band is not a goal.
        //
        // The profile still reads *out* in bands, which is the right way round: what
        // you tell the app is a fact and comes in exact, what it tells you back is an
        // estimate and goes out as a range.
        .init(id: "grade", title: "What's your project grade?", options: [],
              measure: .grade, note: "The hardest climb you're working on."),
        // Straight after what you're on, on the same tape, and opening on whatever that
        // answer landed on — so the goal is however far it gets dragged from there, and
        // dragging it nowhere is the honest zero rather than a number the app picked.
        .init(id: "goalGrade", title: "What's your target grade?", options: [],
              measure: .goalGrade),
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
        .init(id: "weaknesses", title: "What holds you back?",
              options: attributes, allowsMultiple: true, limit: 3, tint: .red,
              note: "Pick up to three."),
        .init(id: "strengths", title: "What are you good at?",
              options: attributes, allowsMultiple: true, limit: 3, tint: .green,
              carriesOver: "weaknesses",
              note: "Up to three. Your weaknesses stay marked in red."),
        // The first questions with a right answer. They go here, after the two
        // screens of opinion, because they are the ones the profile is actually built
        // out of — and because a number is a harder thing to give than a tick, which
        // makes it the wrong way to open a quiz and the right way to close one.
        .init(id: "pullUps", title: "How many pull-ups can you do?", options: [],
              measure: .pullUps, note: "Rough estimate. Do not test your limit."),
        // Skipped for anyone who just said none: asking how much weight they add to a
        // pull-up they can't do is the quiz not listening.
        .init(id: "pullUpMax", title: "How much can you add for one rep?", options: [],
              measure: .pullUpMax, note: "Rough estimate. Do not test your limit.",
              asks: { ($0["pullUps"].flatMap { Int($0.prefix { $0.isNumber }) } ?? 0) > 0 }),
        // The one thing that predicts what you climb better than anything else, and the
        // one question here that fought hardest against being asked. A tape wanted a
        // number almost nobody has measured; every wording of the middle rungs was vague
        // about the thing that mattered. What works is a ladder whose top half is about
        // one arm and whose bottom half isn't: nobody has to estimate a percentage, and
        // the three rungs below one-arm are read off one word and a sign — under, on,
        // over — where a sentence took six words to hedge at what ">" says flat.
        //
        // The rows are the rings, in order, which is why the profile reads this answer
        // by its position in this list rather than by matching its words.
        .init(id: "hang", title: "How much can you hang on a 20 mm edge?",
              options: ["< Bodyweight",
                        "Bodyweight",
                        "> Bodyweight",
                        "One arm",
                        "One arm, easily"],
              note: "Rough estimate. Do not test your limit."),
        .init(id: "goal", title: "What are you here for?",
              options: ["Send a project", "Get stronger", "Fix my technique", "Track my sessions"]),
    ]

    /// Whether this question's rows need the screen to move: the two attribute lists
    /// are ten rows long and can't be seen at once, every other question fits.
    private var scrolls: Bool { rows.count > 6 }

    /// What the arrows and the home indicator take off the bottom of the screen, held
    /// clear at the end of a list so the last row can be reached.
    private static let arrowRoom: CGFloat = 120

    /// How black either end of the screen goes: dark enough to read the question and
    /// the arrows against, light enough that a row under it is still a row.
    private static let veil = Color.black.opacity(0.8)

    /// How far past the question the dark runs before it gives out.
    private static let fadeRun: CGFloat = 64

    /// The row that opens the field. Kept as a constant rather than a literal because
    /// it is both a label on screen and a key in `chosen`.
    private static let otherOption = "Something else"

    /// How a row arrives on a screen that has just come up: a spring out of slightly
    /// small, so the list lands rather than simply being there.
    private static let rowEntrance = Animation.spring(response: 0.48, dampingFraction: 0.78)

    /// The wait between one row starting and the next, top to bottom — enough to read
    /// as one after another, short enough that ten of them are still one gesture.
    private static let rowStagger = 0.075

    var onFinish: () -> Void

    /// Kept on `Onboarding` rather than here, so quitting mid-quiz comes back to the
    /// question that was on screen instead of to the first one.
    @State private var onboarding = Onboarding.shared
    /// What is ticked on the screen currently up — read back off the saved answer every
    /// time a question comes up, so stepping back through the quiz shows what you said
    /// rather than a blank screen.
    @State private var chosen: Set<String> = []
    @State private var other = ""
    /// The ruler's answer, in metric, whichever units it is being shown in.
    @State private var measureValue: Double = 0
    @FocusState private var otherFocused: Bool
    /// Two lines of question with a line of note under them, held whether or not a
    /// given screen fills it — and grown with the type rather than staying put while
    /// the words get bigger.
    @ScaledMetric(relativeTo: .title) private var headerBlock: CGFloat = 98
    /// How much of the screen the question takes, measured rather than assumed: its own
    /// height, for what lays out under it, and where its bottom edge falls on the glass,
    /// for the list that runs behind it.
    @State private var chromeHeight: CGFloat = 190
    @State private var chromeBottom: CGFloat = 250
    /// The height of the list's own window on the screen, which is the screen.
    @State private var listHeight: CGFloat = 800
    /// The strip of screen the home indicator sits in, which the arrow bar covers and
    /// so has to hold clear itself.
    @State private var safeBottom: CGFloat = 34
    /// Whether this screen's rows have come in yet. Dropped the moment the question
    /// changes and put back on the next pass, which is what makes them arrive at all.
    @State private var revealed = false
    @State private var picked = UIImpactFeedbackGenerator(style: .medium)
    @State private var unpicked = UIImpactFeedbackGenerator(style: .light)

    private var index: Int { min(max(onboarding.quizIndex, 0), Self.questions.count - 1) }
    private var question: Question { Self.questions[index] }

    /// Which questions this run is being asked, given what has been answered. Recomputed
    /// rather than stored: an answer changed on the way back through the quiz has to be
    /// able to open a question that was skipped the first time past.
    private var asked: [Int] {
        Self.questions.indices.filter { Self.questions[$0].asks?(onboarding.answers) ?? true }
    }

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

    /// Whether this screen has taken all the answers it will. Rows already ticked are
    /// still live — untick one and the list opens back up.
    private var atLimit: Bool {
        guard let limit = question.limit else { return false }
        return chosen.count >= limit
    }

    private var carriedTint: Color {
        Self.questions.first { $0.id == question.carriesOver }?.tint ?? .white
    }

    /// Forward is off until the question has been answered — and an empty "something
    /// else" is not an answer, so ticking that row alone doesn't open the door.
    private var canAdvance: Bool { question.measure != nil || !answerText.isEmpty }

    var body: some View {
        // The list is the whole screen, from the top of the glass to the bottom of it,
        // and the question sits over it rather than above it — so the rows run behind
        // the question and out under the arrows instead of stopping at a hard edge.
        ZStack(alignment: .top) {
            if let measure = question.measure {
                // The tape hangs off the bottom of the question, in the space the
                // question leaves it. The ladder doesn't: it owns the whole screen the
                // way the rows do, so the rung under the eye sits in the middle of the
                // glass rather than in the middle of the room left over — and the ones
                // above it run up behind the question instead of stopping under it.
                MeasurePicker(measure: measure, value: $measureValue)
                    .padding(.horizontal, 24)
                    .padding(.top, measure.isLadder ? 0 : chromeHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: measure.isLadder ? .center : .top)
            } else {
                optionList
            }

            chrome
        }
        .font(.body)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeBottom = $0 }
        // Over the list, at the two edges: back where a thumb reaches to undo, forward
        // where it reaches to go on — on a bar of their own that runs to the bottom of
        // the glass, home indicator and all.
        .overlay(alignment: .bottom) { arrowBar }
        // A new question is a new screen, not the same one re-lettered.
        .animation(.easeInOut(duration: 0.2), value: index)
        .animation(.easeInOut(duration: 0.15), value: chosen)
        .onAppear {
            loadAnswer()
            reveal()
            picked.prepare()
            unpicked.prepare()
        }
        .onChange(of: index) {
            loadAnswer()
            reveal()
        }
    }

    /// The progress bar and the question, floated over the list with nothing solid
    /// behind them: what passes under is dimmed into the top of the screen rather than
    /// hidden by a panel.
    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
            header
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        // Taller than the question itself, so the fade happens in the gap under the
        // words rather than across them.
        .background(alignment: .top) {
            topScrim
                .frame(height: chromeHeight + Self.fadeRun)
                .ignoresSafeArea(edges: .top)
        }
        // Both numbers are wanted: the height for the screens that lay out under the
        // question, and the bottom edge in screen terms for the list, which starts at
        // the top of the glass rather than at the top of the safe area.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            chromeHeight = $0.height
            chromeBottom = $0.maxY
        }
    }

    /// The dark the list runs into at either end of the screen. Not a fade to black but
    /// a pane over it: blurred and near-black at the edge, easing off to nothing by the
    /// time the rows are being read, so a row on its way out goes soft and dim rather
    /// than being cut off — and the question and the arrows always have something solid
    /// enough behind them to be read against.
    /// The dark the list runs into under the question: black across the words, then
    /// given up over the gap below them, so a row on its way up goes out before it
    /// reaches the writing. Black and nothing else — a frosted pane over a black screen
    /// only ever reads as grey.
    private var topScrim: some View {
        let solid = chromeHeight / (chromeHeight + Self.fadeRun)
        return LinearGradient(stops: [.init(color: .black, location: 0),
                                      .init(color: .black, location: solid),
                                      .init(color: .clear, location: 1)],
                              startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }

    /// The question, and under it whatever it needs saying about it. The block is the
    /// same height on every screen whether one line or three land in it: a long question
    /// wraps into the space instead of being cut off with an ellipsis, and a short one
    /// leaves it empty rather than pulling the answers up the screen.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.title)
                .font(.title.weight(.semibold))
                .lineLimit(2)
            if let note = question.note {
                Text(note)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: headerBlock, maxHeight: headerBlock,
               alignment: .topLeading)
        .padding(.top, 44)
        .padding(.bottom, 24)
    }

    /// The rows themselves, on a screen that answers with a tap rather than a number.
    /// The list owns the whole screen — it starts at the top of the glass and ends at
    /// the bottom of it, with the question's height and the arrows' room held open as
    /// padding, so scrolling carries rows up behind the question and down under the
    /// arrows rather than into a cut edge.
    private var optionList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.element) { position, option in
                    Button { tap(option) } label: { row(option) }
                        .buttonStyle(.plain)
                        .disabled(carried.contains(option) || spentOn(option))
                        .scaleEffect(revealed ? 1 : 0.88)
                        .opacity(revealed ? 1 : 0)
                        // Only the arrival is animated: going out is instant, so a new
                        // question starts from nothing instead of shrinking the old one
                        // away first.
                        .animation(revealed ? Self.rowEntrance.delay(Double(position) * Self.rowStagger) : nil,
                                   value: revealed)
                }
            }
            .padding(.horizontal, 24)
            // A short list sits in the middle of what the question and the arrows leave
            // it — which also puts it under the thumb. A list too long for that scrolls
            // from the top as usual.
            .frame(maxWidth: .infinity,
                   minHeight: max(0, listHeight - chromeBottom - Self.arrowRoom),
                   alignment: .center)
            .padding(.top, chromeBottom)
            .padding(.bottom, Self.arrowRoom)
        }
        .scrollIndicators(.hidden)
        // Only a list that doesn't fit scrolls. Everywhere else the rows are simply
        // where they are — no bounce, nothing to slide out from under the question.
        .scrollDisabled(!scrolls)
        // The list keeps the safe area rather than being inset out of it: the rows are
        // meant to run under the clock and the home indicator and be dimmed there.
        .ignoresSafeArea(.container, edges: .vertical)
        // Measured off the list itself rather than worked out from the screen, so the
        // middle of the list is the middle of what the list can actually see.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        // The band the arrows sit on, drawn by the list because the list is the thing
        // that reaches the bottom of the glass: clear where the rows are read, four
        // fifths black from the top of the buttons down through the home indicator.
        .overlay(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: Self.veil, location: 0.55),
                                   .init(color: Self.veil, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: safeBottom * 2 + 140)
                // Hung below the list's own edge by the height of the home indicator's
                // strip, which is the one bit of screen the list draws in but doesn't
                // count as its own.
                .padding(.bottom, -safeBottom)
                .allowsHitTesting(false)
        }

    }

    /// The arrows on their band of black: clear where the list is read, four fifths
    /// black from the top of the buttons down, so the rows behind them are still there
    /// to be seen but well behind.
    private var arrowBar: some View {
        ZStack(alignment: .bottom) {
            HStack {
                arrow("chevron.left", enabled: asked.contains { $0 < index }, action: back)
                Spacer()
                arrow("chevron.right", enabled: canAdvance) { advance() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, safeBottom + 8)
            // The band the arrows sit on takes the tap itself, so a row that has
            // scrolled behind it can't be picked through the dark: the arrows are in
            // front of this and still get their own taps.
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { }
            }
        }
        .ignoresSafeArea()
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
    /// A row the count has been used up on: not chosen, not carried, and there is no
    /// room left for it.
    private func spentOn(_ option: String) -> Bool {
        atLimit && !chosen.contains(option) && !carried.contains(option)
    }

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
        // A row already spoken for on the screen before is not for changing here, and
        // one there is no room left for goes further back than that — still readable,
        // plainly not tappable, and back to full the moment something is untaken.
        .opacity(isCarried ? 0.65 : (spentOn(option) ? 0.3 : 1))
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
    /// screen is already a step in rather than empty. Measured against the questions
    /// actually being asked, so skipping one moves the bar on rather than leaving a
    /// gap in it that never fills.
    private var filled: CGFloat {
        let asked = asked
        let place = asked.firstIndex(of: index).map { $0 + 1 } ?? asked.count
        return CGFloat(place) / CGFloat(max(asked.count, 1))
    }

    /// What this screen would be recorded as: the ticked rows in the order the list
    /// puts them, with "something else" standing for whatever was typed into it.
    private var answerText: String {
        // A ruler is never empty and never multiple: whatever is under the mark, in
        // metric, however the screen was reading it.
        if let measure = question.measure { return measure.answer(metric: measureValue) }
        // Never what the screen before claimed: a weakness cannot come back as a
        // strength, however the two screens were walked through.
        return rows.filter { chosen.contains($0) && !carried.contains($0) }
            .map { $0 == Self.otherOption ? other.trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Puts the saved answer back on screen. Anything in it that isn't one of the rows
    /// was typed into "something else", and goes back there.
    private func loadAnswer() {
        let saved = onboarding.answers[question.id] ?? ""
        if let measure = question.measure {
            measureValue = saved.isEmpty ? start(of: measure) : measure.value(from: saved)
            return
        }
        var picks: [String] = []
        var typed = ""
        for part in saved.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        where !part.isEmpty {
            if question.options.contains(part) {
                picks.append(part)
            } else if question.allowsOther {
                typed = part
                picks.append(Self.otherOption)
            }
        }
        var restored = picks.filter { !carried.contains($0) }
        // An answer saved before this question had a count — or before the count was
        // this one — comes back trimmed to what the screen would now let you tick,
        // keeping the first few rather than dropping the lot.
        if let limit = question.limit { restored = Array(restored.prefix(limit)) }
        chosen = Set(restored)
        other = typed
    }

    /// Where a ruler comes up on a question nothing has been said to yet. Its own
    /// starting point, except for the goal grade — which opens on whatever the grade
    /// before it landed on, so every rung of goal is a rung somebody deliberately
    /// dragged rather than one the tape was already sitting on.
    private func start(of measure: BodyMeasure) -> Double {
        guard measure == .goalGrade, let current = onboarding.answers["grade"] else {
            return measure.start
        }
        return BodyMeasure.grade.value(from: current)
    }

    /// Takes the rows off the screen and puts them back on the next pass, so the ones
    /// that were already there for the question before still come in for this one.
    private func reveal() {
        revealed = false
        DispatchQueue.main.async { revealed = true }
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
            // The rows are disabled at the limit, so this only catches a tap already
            // in flight — but the count is the answer's rule, not the button's.
            guard !atLimit else { return }
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
        // Read after the answer is written, not before: whether the next question is
        // asked at all can turn on the one just given.
        if let next = asked.first(where: { $0 > index }) {
            onboarding.quizIndex = next
        } else {
            onFinish()
        }
    }

    /// Back a question, keeping what was said on this one — stepping back to check an
    /// answer shouldn't cost the answer you were on.
    private func back() {
        otherFocused = false
        onboarding.answers[question.id] = answerText
        onboarding.quizIndex = asked.last { $0 < index } ?? 0
    }
}
