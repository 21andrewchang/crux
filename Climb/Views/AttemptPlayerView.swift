import AVKit
import Combine
import SwiftUI

/// Lets the screen that owns the notes force the half-written draft in before reading
/// them — finishing an attempt must not lose the line still sitting in the field.
final class AttemptPlayerController {
    fileprivate var onCommit: () -> Void = {}
    func commitDraft() { onCommit() }
}

/// The attempt screen both flows share — review right after recording, and replay from
/// the note: full-bleed muted video, the Photos-style playbar with a teal dot per note,
/// and a pencil-summoned field that writes stamped notes, one line per note.
///
/// The notes are a list — one line per note, every line opening with its clock — but
/// they live in one newline-joined string, which is what the note document renders as
/// the row's single quote block.
struct AttemptPlayerView<Footer: View>: View {
    let videoURL: URL?
    let duration: TimeInterval
    @Binding var notes: String
    /// Set when a note line was tapped in the note: the clip it marks plays, from its
    /// first frame to its last. The line is a link to a moment in the video, so what
    /// it opens is that moment running — not the note about it, waiting to be edited.
    var startAt: TimeInterval? = nil
    var autoplays = false
    var controller: AttemptPlayerController? = nil
    /// Extra controls under the playbar row — the review screen's Finish button.
    @ViewBuilder var footer: Footer

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    /// Set while either scrubber is being worked — a drag on the bar, or the strip
    /// still coasting. The player's own clock is ignored while it's set: the thumb is
    /// ahead of the picture on purpose.
    @State private var isScrubbing = false
    @State private var seeker = FrameSeeker()
    /// The notes field only exists while you're writing: the pencil button conjures it
    /// focused, and it leaves with the keyboard, committing what it held.
    @State private var isEditingNotes = false
    @State private var draft = ""
    /// Which line of `notes` the draft is editing; nil when it's a fresh note.
    @State private var editingLineIndex: Int?
    /// The moment the draft is about. Every note is a dot: a line whose clock the user
    /// deleted gets this one back on commit.
    @State private var draftStamp: TimeInterval = 0
    /// Where the open note's clip ends. Every note is a stretch of the video now, not
    /// a single moment — a fresh one gets `newClipLength` of it, laid around the
    /// playhead, and the strip's handles open it out from there.
    @State private var draftEnd: TimeInterval = 0
    /// Short on purpose: a new clip is a mark on the frame you stopped at, and pulling
    /// a handle outward is easier than hunting for where an over-long one should end.
    private let newClipLength: TimeInterval = 0.5
    @State private var isConfirmingNoteDelete = false
    /// Where the clip being watched ends. Set only while a tapped note line is
    /// playing itself out; the playhead stops there and it clears.
    @State private var watchedClipEnd: TimeInterval?
    /// One height, always — compact, and the box is cut to fit it. This box is the
    /// bottom safe-area inset, and every version of growing it, however the growth
    /// was paid for, ended up moving the bar row under the thumb.
    private let stripHeight: CGFloat = 32
    /// How far the keyboard reaches up the screen, less the home-indicator strip the
    /// box already clears. The bottom cluster is one piece — bar, clip button, rest
    /// clock — and SwiftUI's own avoidance lifts only as far as the field being typed
    /// in, leaving the row beneath it behind the keys. Tracked by hand so the whole
    /// box rides up together.
    @State private var keyboardLift: CGFloat = 0
    @FocusState private var notesFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Fills the whole modal, bars floating over it. A tap on the video puts
            // the keyboard away; a swipe is left alone on purpose — a SwiftUI drag
            // here would starve the sheet's own pan, and dragging the page around
            // belongs to the sheet.
            PlayerSurface(player: player)
                .ignoresSafeArea()
                // Two steps out of a note, because they are two different things:
                // the keyboard goes first, leaving the note open over a video you
                // can finally see, and the next tap lets the clip go.
                .onTapGesture(perform: stepOutOfNote)
                // While typing, a swipe on the video belongs to the keyboard, not
                // the sheet: claiming the pan here is what parks the sheet, and the
                // first movement just drops focus. Unfocused, the gesture switches
                // itself off and the sheet's own drag takes the swipe again.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in notesFocused = false },
                    including: notesFocused ? .all : .subviews
                )
        }
        // A scrub is a horizontal drag with a bit of wobble in it, and the sheet
        // reads the wobble as a dismiss and takes the whole modal with it.
        .interactiveDismissDisabled(notesFocused || isScrubbing)
        .alert("Delete this note?", isPresented: $isConfirmingNoteDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: deleteShownNote)
        }
        .safeAreaInset(edge: .bottom) { bottomBox }
        // The lift above is the one that counts; the automatic one would stack on top
        // of it, and it only ever moved half the box anyway.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }
            let height = max(0, UIScreen.main.bounds.maxY - frame.minY)
            // Ride the keyboard's own curve, so the box and the keys move as one.
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
            withAnimation(Self.keyboardRide(duration)) {
                keyboardLift = height > 0 ? max(0, height - bottomSafeInset) : 0
            }
        }
        // A break never goes into a note — one line per clock. The return key reads
        // as "done": whatever it rode in on is flattened to one line, and dropping
        // focus is what commits. Pasted breaks flatten the same way.
        .onChange(of: draft) { _, entered in
            guard entered.contains("\n") else { return }
            draft = entered.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            notesFocused = false
        }
        // The keyboard leaving writes the note down — but it does not close it. The
        // clip is still the one being worked on, its handles are still on the strip,
        // and the whole point of the keyboard going is that the video is visible
        // underneath it again.
        .onChange(of: notesFocused) { _, focused in
            if !focused, isEditingNotes { commitDraft(closing: false) }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { isPlaying = $0 == .playing }
        .onAppear { controller?.onCommit = { commitDraft() } }
        // The sheet can be flung away with the keyboard still up, skipping the focus
        // change that normally commits; this is the backstop.
        .onDisappear { commitDraft() }
        .task { await loadVideo() }
    }

    /// Everything under the video: the playbar, and the row of buttons beside the
    /// footer's own. Lifted out of `body` because the whole screen is one expression
    /// otherwise, and the type checker gives up on it.
    private var bottomBox: some View {
        VStack(spacing: 10) {
            playbar

            // The pencil rides the footer's leading edge — the corner opposite
            // the rest clock, which was standing empty — so the only two things
            // on this row are the one that writes notes and the one that counts.
            HStack(spacing: 12) {
                pencilButton

                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8 + keyboardLift)
        // The box grows on the same curve it rides up on: the row sliding in and
        // the lift are one movement, and a slower morph under a keyboard-paced
        // lift is what reads as the box arriving late.
        .animation(Self.keyboardRide(0.25), value: isEditingNotes)
        // The read-only pop-up answers to playback, not the keyboard, so it keeps
        // the softer morph; animating on the stamp (not the ticking clock) means
        // one move per note, in and out.
        .animation(.smooth(duration: 0.3), value: passingNote?.stamp)
    }

    /// Loading the video, and watching it play. Runs for as long as the screen is up:
    /// the time observer is torn down when the task is cancelled.
    private func loadVideo() async {
        guard let videoURL else { return }
        // Replays are silent, always — the video is beta, not a soundtrack.
        player.isMuted = true
        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        if let startAt {
            // Show the target on the bar right away, and hold the exact seek until
            // the item can actually honour it — a zero-tolerance seek fired while
            // the item is still loading quietly lands on frame zero.
            currentTime = startAt
            for _ in 0..<100 where item.status != .readyToPlay {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(30))
            }
            await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
            // Arriving on a link means watching what it points at: the clip runs
            // from here and stops at its far end, leaving the note itself alone.
            // One that names a moment rather than a stretch just plays on.
            watchedClipEnd = clipEndOfNote(at: startAt)
            player.play()
        }
        if autoplays { player.play() }
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            // Mid-scrub the strip leads and the player follows; letting its late
            // clock in here would drag the playhead back under the thumb.
            guard !isScrubbing else {
                // A hand on the thumb is somebody taking over: what was playing
                // stops being a clip and the video is just the video again.
                watchedClipEnd = nil
                return
            }
            currentTime = time.seconds
            // An open clip plays as a clip: it stops where it ends rather than
            // running on into the rest of the attempt.
            if isEditingNotes, draftEnd > draftStamp, currentTime >= draftEnd {
                player.pause()
            }
            // A clip arrived at through its link stops the same way, without a
            // note being open to hold its end.
            if let end = watchedClipEnd, currentTime >= end {
                watchedClipEnd = nil
                player.pause()
            }
        }
        defer { player.removeTimeObserver(token) }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    /// The curve UIKit actually raises the keyboard on — its own, unnamed one, far
    /// more front-loaded than any of the built-in easings: a sixth of the way through
    /// the keys are already better than half up, where `easeOut` is barely a third.
    /// Anything meant to move with them has to use it, or it reads as chasing them.
    private static func keyboardRide(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.38, 0.7, 0.125, 1, duration: duration)
    }

    /// The home-indicator strip. A keyboard's height is measured from the bottom of
    /// the screen and swallows it, and the box is already sitting above it.
    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    // MARK: Playbar

    /// One circle, four moods, in the order a note is worked through: a pencil to
    /// start one, a trash can when the playhead is sitting on a bookmark and nothing
    /// is open, then — with a clip open — *Edit* to put the keyboard up on it and a
    /// checkmark to take the keyboard away again. It sits in the bottom-left corner,
    /// in reach of the thumb that's already on the scrubber.
    ///
    /// *Edit* stays a word: beside a pencil, a glyph for it would be the same glyph
    /// twice. Finishing needs no such distinction — a checkmark over a keyboard is
    /// only ever the one thing.
    private var pencilButton: some View {
        let onBookmark = !isEditingNotes && currentNote != nil
        let word: String? = isEditingNotes && !notesFocused ? "Edit" : nil
        let symbol = notesFocused ? "checkmark" : (onBookmark ? "trash" : "square.and.pencil")

        return Button {
            if notesFocused {
                // Done — the commit rides on the focus change, and the note stays
                // open over the video it is about.
                notesFocused = false
            } else if isEditingNotes {
                notesFocused = true
            } else if onBookmark {
                isConfirmingNoteDelete = true
            } else {
                startNote()
            }
        } label: {
            ZStack {
                Text(word ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(word == nil ? 0 : 1)
                Image(systemName: symbol)
                    .font(.system(size: symbol == "square.and.pencil" ? 22 : 20, weight: .semibold))
                    .foregroundStyle(symbol == "trash" ? Color.red : Color.white)
                    // The pencil pokes above the glyph's square, so centring the
                    // whole glyph leaves the square riding low; centre the square.
                    .offset(y: symbol == "square.and.pencil" ? -2 : 0)
                    .opacity(word == nil ? 1 : 0)
            }
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    /// Where the clip a note marks ends, if that note marks a stretch at all.
    private func clipEndOfNote(at stamp: TimeInterval) -> TimeInterval? {
        for line in notes.components(separatedBy: "\n")
        where NoteTimestamp.timestamps(in: line).first == stamp {
            return clipEnd(of: line)
        }
        return nil
    }

    /// A tap on the video. Two steps out of a note, because they are two different
    /// things: the keyboard goes first, leaving the note open over a video you can
    /// finally see, and the next tap lets the clip go.
    private func stepOutOfNote() {
        if notesFocused {
            notesFocused = false
        } else if isEditingNotes {
            commitDraft()
            deselectNote()
        }
    }

    /// A note about this exact moment — the clock carries centiseconds, so the stamp
    /// is the frame on screen, not the nearest second. One note per moment: if this
    /// exact moment already has one, this opens it instead of drafting a twin.
    private func startNote() {
        player.pause()
        let moment = min(max(currentTime, 0), duration)
        // Laid around the frame you stopped on, not started from it: the moment worth
        // marking is usually in the middle of what you want to keep.
        let length = min(newClipLength, duration)
        let start = NoteTimestamp.quantized(
            min(max(moment - length / 2, 0), max(duration - length, 0)))
        let end = NoteTimestamp.quantized(min(start + length, duration))

        if NoteTimestamp.timestamps(in: notes).contains(start) {
            openNote(at: start)
            return
        }
        draftStamp = start
        draftEnd = end
        park(at: (start + end) / 2)
        draft = ""
        editingLineIndex = nil
        isEditingNotes = true
        notesFocused = true
    }

    /// Two scrubbers, both always out, because they're good at opposite things: the
    /// filmstrip across the top for landing on a frame, and under it the bare line —
    /// no thumb — for going anywhere in the clip at once. Play/pause keeps the line's
    /// row, the way it always had it.
    ///
    /// The strip rests as a sliver and stands up the moment either scrubber is
    /// The box is one size and stays it. Nothing in here resizes while a thumb is on
    /// it, so nothing in here can shove the bar row.
    ///
    /// One piece of glass. Opening a note stretches this same box upward and the
    /// input row — clock on the left, words beside it — slides in above the strip;
    /// closing one (playing, committing) collapses it back. A single glass view
    /// resizing is what gets the native morph; a separate glass shape per piece would
    /// swap instead of growing.
    private var playbar: some View {
        VStack(spacing: 8) {
            if isEditingNotes {
                noteRow
            } else if let passing = passingNote {
                passingNoteRow(passing)
            }

            filmstrip
                .frame(height: stripHeight)

            HStack(spacing: 12) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 24, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                scrubber
            }
            .frame(height: 48)
        }
        .foregroundStyle(.white)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    /// The row above the bar, there only while a note is open: the draft's clock on
    /// the left, the field beside it. Opening happens through the pencil or a
    /// bookmark, never the row itself. Centre-aligned, not baseline: the growable
    /// TextField reports a baseline that would split the row into what reads as two
    /// lines.
    private var noteRow: some View {
        HStack(spacing: 10) {
            Text(NoteTimestamp.display(for: draftStamp))
                .font(.body)
                .foregroundStyle(.secondary)
            TextField("Notes...", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($notesFocused)
        }
        // The clock and the empty end of the line raise the keyboard too: the row is
        // the note, and tapping a note is how you start writing in it.
        .contentShape(.rect)
        .onTapGesture { notesFocused = true }
    }

    /// The note playback is passing: a clip's words are on screen for exactly the
    /// stretch the clip covers, which is the whole point of having marked it out.
    /// Playback only — scrubbing across bookmarks would make the row flap — and the
    /// editing row, when open, owns the slot.
    private var passingNote: (stamp: TimeInterval, words: String)? {
        guard isPlaying, !isEditingNotes else { return nil }
        let spans = noteSpans
        // Windows can overlap when notes sit close; the later note takes over from the
        // one still lingering.
        if let active = spans.last(where: { currentTime >= $0.from && currentTime <= $0.to }) {
            return (active.stamp, active.words)
        }
        // Between two notes that all but touch, the row holds what it was saying
        // rather than folding away and opening again a few frames later. The words
        // change; the box doesn't move.
        guard let previous = spans.last(where: { $0.to < currentTime }),
              let next = spans.first(where: { $0.from > currentTime }),
              next.from - previous.to <= 0.5
        else { return nil }
        return (previous.stamp, previous.words)
    }

    /// Every note as a stretch of playback: what it says, and from when to when. A
    /// clip runs for exactly its own stretch; a note that names a single moment keeps
    /// the old window — up a beat before, lingering a beat after.
    private var noteSpans: [(from: TimeInterval, to: TimeInterval, stamp: TimeInterval, words: String)] {
        var spans: [(from: TimeInterval, to: TimeInterval, stamp: TimeInterval, words: String)] = []
        for line in notes.components(separatedBy: "\n") {
            guard let stamp = NoteTimestamp.timestamps(in: line).first else { continue }
            let words = strippingClock(line)
            if let end = clipEnd(of: line), end > stamp {
                spans.append((stamp, end, stamp, words))
            } else {
                spans.append((stamp - 1.0, stamp + 1.5, stamp, words))
            }
        }
        return spans.sorted { $0.from < $1.from }
    }

    /// The editing row's read-only twin — same clock, same seat above the bar — shown
    /// while playback passes the note. Not focusable: it's a caption, not a field.
    private func passingNoteRow(_ note: (stamp: TimeInterval, words: String)) -> some View {
        HStack(spacing: 10) {
            Text(NoteTimestamp.display(for: note.stamp))
                .font(.body)
                .foregroundStyle(.secondary)
            Text(note.words)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }

    /// The note the playhead is actually inside — the clip covering this frame, or a
    /// single-moment note sitting on it. The playhead parks in the middle of a clip
    /// now, so "on a bookmark" can't mean "on its first frame" any more.
    private var currentNote: (stamp: TimeInterval, words: String)? {
        var best: (stamp: TimeInterval, words: String)?
        for line in notes.components(separatedBy: "\n") {
            guard let stamp = NoteTimestamp.timestamps(in: line).first else { continue }
            let end = max(clipEnd(of: line) ?? stamp, stamp)
            guard currentTime >= stamp - 0.011, currentTime <= end + 0.011 else { continue }
            if best == nil || stamp > best!.stamp {
                best = (stamp, strippingClock(line))
            }
        }
        return best
    }

    /// Every note as the stretch it marks out — both ends on one frame for the notes
    /// written before clips existed. Both scrubbers draw from this: a bubble over the
    /// middle of each stretch, and a band across the ones that cover ground.
    ///
    /// The note being edited is left out — see `allMarks`.
    private var noteMarks: [ClipMark] {
        var marks: [ClipMark] = []
        for (index, line) in notes.components(separatedBy: "\n").enumerated() {
            guard let stamp = NoteTimestamp.timestamps(in: line).first else { continue }
            guard !(isEditingNotes && index == editingLineIndex) else { continue }
            marks.append(ClipMark(start: stamp, end: clipEnd(of: line) ?? stamp))
        }
        return marks
    }

    /// The same, plus the note being written. The strip keeps the open note out of
    /// this list and draws it from the draft instead, so its band tracks the handles
    /// live; the line has no handles and wants the whole set.
    private var allMarks: [ClipMark] {
        isEditingNotes ? noteMarks + [editingClip] : noteMarks
    }

    private var editingClip: ClipMark {
        ClipMark(start: draftStamp, end: max(draftEnd, draftStamp))
    }

    /// The clip a line marks out, if its clock is a range.
    private func clipEnd(of line: String) -> TimeInterval? {
        let text = line as NSString
        guard let match = NoteTimestamp.regex.firstMatch(
            in: line, options: [], range: NSRange(location: 0, length: text.length))
        else { return nil }
        return NoteTimestamp.end(from: text.substring(with: match.range))
    }

    /// The frame-accurate half: the video scrolling under a fixed playhead. A flick
    /// coasts across seconds, a creep walks single frames, and it's the same gesture
    /// either way.
    private var filmstrip: some View {
        FilmstripScrubber(
            videoURL: videoURL,
            duration: duration,
            time: currentTime,
            isPlaying: isPlaying,
            bookmarks: noteMarks,
            editing: isEditingNotes ? editingClip : nil,
            onClipChanged: { clip in
                draftStamp = clip.start
                draftEnd = clip.end
            },
            onScrubBegan: { player.pause() },
            onScrub: { seconds in
                currentTime = seconds
                seeker.seek(player, to: seconds)
            },
            // An open note survives a scrub — see the line's gesture for why.
            onScrubEnded: { },
            // A clip tapped on either scrubber opens as a clip: its note on screen,
            // its handles live, and no keyboard over the video. The word is one tap
            // further on — the row itself, or the button.
            onBookmarkTap: { openNote(at: $0, focusing: false) },
            onActiveChanged: { isScrubbing = $0 }
        )
    }

    /// A thin line, white up to the playhead and faint past it. Dragging anywhere on
    /// it pauses and seeks straight to that spot — thumb position is the moment, so
    /// the whole clip is one thumb width away. The strip above is where frames get
    /// picked; this is where you get near them.
    ///
    /// A note is one bubble here and nothing else. How long its clip runs is drawn on
    /// the strip, at a zoom where the answer means something — at this one a clip is a
    /// few points of yellow, which reads as clutter rather than as a length.
    private var scrubber: some View {
        GeometryReader { geo in
            let span = max(duration, 0.01)
            let progress = min(max(currentTime / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                    .frame(height: 8)
                Capsule().fill(.white)
                    .frame(width: max(8, progress * geo.size.width), height: 8)
                // A bookmark for every note. Tapping one opens that note; the padded
                // frame keeps it hittable, and a child gesture outranks the scrub
                // gesture underneath.
                ForEach(Array(allMarks.enumerated()), id: \.offset) { _, mark in
                    // Over the middle of the note's stretch — same `progress * width`
                    // maths as the line's own fill — nudged in just enough at the
                    // edges to stay whole.
                    let centre = min(max(min(max(mark.centre / span, 0), 1) * geo.size.width, 5.5),
                                     geo.size.width - 5.5)
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemYellow))
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .frame(width: 26, height: 34)
                        .contentShape(.rect)
                        .onTapGesture { openNote(at: mark.start) }
                        .offset(x: centre - 13)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.pause()
                        isScrubbing = true
                        let seconds = min(max(value.location.x / geo.size.width, 0), 1) * span
                        currentTime = seconds
                        seeker.seek(player, to: seconds)
                    }
                    // The open note stays open, keyboard and all: scrubbing while
                    // writing is the search for the moment the note is about, not a
                    // change of subject.
                    .onEnded { _ in isScrubbing = false }
            )
        }
        .frame(height: 34)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            // With a clip open, play means play the clip — from its start whenever
            // the playhead isn't already inside it.
            if isEditingNotes, draftEnd > draftStamp {
                if currentTime < draftStamp || currentTime >= draftEnd - 0.02 {
                    currentTime = draftStamp
                    player.seek(to: CMTime(seconds: draftStamp, preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero)
                }
            } else if currentTime >= duration - 0.05 {
                // Play at the end means watch it again.
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
        }
    }

    /// Clears the resting row without touching what was committed.
    private func deselectNote() {
        draft = ""
        editingLineIndex = nil
        isEditingNotes = false
    }

    /// The trash press: the bookmark the playhead sits on goes, line and all.
    private func deleteShownNote() {
        guard let note = currentNote else { return }
        var lines = notes.components(separatedBy: "\n")
        lines.removeAll { NoteTimestamp.timestamps(in: $0).first == note.stamp }
        notes = lines.joined(separator: "\n")
    }

    // MARK: Notes as a list

    /// Folds the draft back into the notes: a fresh note appends its own line, an
    /// opened one rewrites (or, emptied, removes) the line it came from. Every note is
    /// a dot — a line whose clock was deleted gets the field's stamp back, and a clock
    /// with nothing after it is not a note at all.
    private func commitDraft(closing: Bool = true) {
        let stampToken = NoteTimestamp.token(for: draftStamp, end: draftEnd)
        let noteLines = draft.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isBareClock($0) }
            .map { NoteTimestamp.timestamps(in: $0).isEmpty ? stampToken + " " + $0 : $0 }
        if closing { draft = "" }

        var lines = notes.isEmpty ? [] : notes.components(separatedBy: "\n")
        if let index = editingLineIndex, index < lines.count {
            lines.replaceSubrange(index...index, with: noteLines)
        } else {
            lines.append(contentsOf: noteLines)
        }
        editingLineIndex = nil

        // One note per moment: on a clash the later line — the one just committed —
        // is the note.
        var seen = Set<TimeInterval>()
        lines = Array(lines.reversed().filter { line in
            guard let stamp = NoteTimestamp.timestamps(in: line).first else { return true }
            return seen.insert(stamp).inserted
        }.reversed())

        // Nothing empty survives the trip. A blank line costs nothing here but comes
        // back as a real one in the document, and the note grows another every time a
        // clip is written.
        lines.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // The quote block reads top to bottom as the video plays: whatever order the
        // notes arrived in, they leave in time order. Ties (and any stray unstamped
        // line, sorted last) keep their relative order.
        let keyed = lines.enumerated().map {
            (index: $0.offset, line: $0.element, stamp: NoteTimestamp.timestamps(in: $0.element).first)
        }
        lines = keyed.sorted {
            let first = $0.stamp ?? .infinity
            let second = $1.stamp ?? .infinity
            return first == second ? $0.index < $1.index : first < second
        }.map(\.line)

        notes = lines.joined(separator: "\n")

        // Staying open: the row goes on showing the note just written, found again by
        // its clock now that the lines have been sorted around it. A note emptied out
        // is no longer there to stay open on.
        guard !closing else { return }
        let written = notes.components(separatedBy: "\n")
        if let index = written.firstIndex(where: {
            NoteTimestamp.timestamps(in: $0).first == draftStamp
        }) {
            editingLineIndex = index
            draft = strippingClock(written[index])
        } else {
            deselectNote()
        }
    }

    private func isBareClock(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return NoteTimestamp.regex.firstMatch(in: line, options: [], range: range)?.range == range
    }

    /// A tapped bookmark: park the video on the clip and put that note in the field.
    /// `focusing: false` shows the note without raising the keyboard — the clip open
    /// over a video you can still see, which is how tapping one on the strip lands.
    private func openNote(at stamp: TimeInterval, focusing: Bool = true,
                          parkingAtStart: Bool = false) {
        let lines = notes.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { NoteTimestamp.timestamps(in: $0).first == stamp })
        else { return }

        player.pause()
        draft = strippingClock(lines[index])
        editingLineIndex = index
        draftStamp = stamp
        // A note written before clips existed names one moment; opening it gives it a
        // stretch to trim, and committing is what writes that stretch down.
        draftEnd = min(max(clipEnd(of: lines[index]) ?? stamp + newClipLength, stamp), duration)
        // A clip opened for its own sake parks in the middle of what it is about. A
        // clip arrived at through a timestamp in the note parks on the moment that
        // timestamp names — the reader tapped a time, and that is where they meant.
        park(at: parkingAtStart ? draftStamp : (draftStamp + draftEnd) / 2)
        isEditingNotes = true
        if focusing { notesFocused = true }
    }

    /// Puts the picture — and both scrubbers with it — on one exact frame.
    private func park(at moment: TimeInterval) {
        let frame = NoteTimestamp.quantized(min(max(moment, 0), duration))
        currentTime = frame
        player.seek(to: CMTime(seconds: frame, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// The words of a note line, with its leading clock — which the field shows as
    /// chrome, not text — taken off.
    private func strippingClock(_ line: String) -> String {
        let text = line as NSString
        guard let match = NoteTimestamp.regex.firstMatch(in: line, options: [],
                                                         range: NSRange(location: 0, length: text.length)),
              match.range.location == 0
        else { return line }
        return text.substring(from: match.range.length).trimmingCharacters(in: .whitespaces)
    }
}

/// The floating header both attempt screens share: an ✕ in a glass disc, the name
/// capsule centred beside it at the same height.
struct AttemptTopBar<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var onClose: () -> Void
    /// What sits opposite the ✕. Sized to the same disc so the row stays balanced
    /// whether or not there's anything in it.
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let controlHeight: CGFloat = 48

        GlassEffectContainer(spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: controlHeight, height: controlHeight)
                        .glassEffect(.regular, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: controlHeight)
                .glassEffect(.regular, in: .capsule)

                Spacer()

                trailing
                    .frame(width: controlHeight, height: controlHeight)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

/// A bare video layer — no system controls, the playbar above is the only chrome.
/// Internal rather than file-private: the intro's clip slide is the same player, and
/// it has to be the same view rather than a second one that looks like it.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        // Fill, not fit: the video covers the whole modal instead of letterboxing,
        // trading a sliver of the frame's edges for no black bars.
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
