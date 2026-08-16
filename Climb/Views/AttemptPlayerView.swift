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
    /// Set when a timestamp was tapped in the note: the player opens parked there.
    var startAt: TimeInterval? = nil
    var autoplays = false
    var controller: AttemptPlayerController? = nil
    /// Extra controls under the playbar row — the review screen's Finish button.
    @ViewBuilder var footer: Footer

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    /// The notes field only exists while you're writing: the pencil button conjures it
    /// focused, and it leaves with the keyboard, committing what it held.
    @State private var isEditingNotes = false
    @State private var draft = ""
    /// Which line of `notes` the draft is editing; nil when it's a fresh note.
    @State private var editingLineIndex: Int?
    /// The moment the draft is about. Every note is a dot: a line whose clock the user
    /// deleted gets this one back on commit.
    @State private var draftStamp: TimeInterval = 0
    @State private var isConfirmingNoteDelete = false
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
                .onTapGesture { notesFocused = false }
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
        .interactiveDismissDisabled(notesFocused)
        .alert("Delete this note?", isPresented: $isConfirmingNoteDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: deleteShownNote)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                playbar

                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.smooth(duration: 0.3), value: isEditingNotes)
            // The pop-up rides the same morph as the editing row; animating on the
            // stamp (not the ticking clock) means one move per note, in and out.
            .animation(.smooth(duration: 0.3), value: passingNote?.stamp)
        }
        // Rides in the top bar's row, filling the empty trailing slot the bar leaves
        // opposite its ✕ — same size, same margins, so the two read as one row.
        .overlay(alignment: .topTrailing) {
            pencilButton
                .padding(.trailing, 20)
                .padding(.top, 14)
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
        // The keyboard leaving is what commits the note, and the row folds back
        // into the playbar with it.
        .onChange(of: notesFocused) { _, focused in
            if !focused, isEditingNotes {
                commitDraft()
                deselectNote()
            }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { isPlaying = $0 == .playing }
        .onAppear { controller?.onCommit = commitDraft }
        // The sheet can be flung away with the keyboard still up, skipping the focus
        // change that normally commits; this is the backstop.
        .onDisappear { commitDraft() }
        .task {
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
                // The row only exists while a note is open, so the linked note has
                // to be opened by hand — shown, but without raising the keyboard.
                openNote(at: startAt, focusing: false)
            }
            if autoplays { player.play() }
            let token = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                queue: .main
            ) { time in
                currentTime = time.seconds
            }
            defer { player.removeTimeObserver(token) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    // MARK: Playbar

    /// One circle, three moods: a checkmark to finish the note being typed, a trash
    /// can when the playhead sits exactly on a bookmark — that bookmark is the one
    /// pointed at, and deletable — and a pencil anywhere else. This button is the
    /// only way a new note starts; the playbar never invites one.
    private var pencilButton: some View {
        let onBookmark = !isEditingNotes && (currentNote
            .map { abs($0.stamp - NoteTimestamp.quantized(currentTime)) < 0.011 } ?? false)
        let symbol = isEditingNotes ? "checkmark" : (onBookmark ? "trash" : "square.and.pencil")

        return Button {
            if isEditingNotes {
                // Done — the commit rides on the focus change.
                notesFocused = false
            } else if onBookmark {
                isConfirmingNoteDelete = true
            } else {
                startNote()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: symbol == "square.and.pencil" ? 22 : 20, weight: .semibold))
                .foregroundStyle(symbol == "trash" ? .red : .white)
                // The pencil pokes above the glyph's square, so centring the whole
                // glyph leaves the square riding low; centre the square.
                .offset(y: symbol == "square.and.pencil" ? -2 : 0)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    /// A note about this exact moment — the clock carries centiseconds, so the stamp
    /// is the frame on screen, not the nearest second. One note per moment: if this
    /// exact moment already has one, this opens it instead of drafting a twin.
    private func startNote() {
        player.pause()
        let stamp = NoteTimestamp.quantized(min(max(currentTime, 0), duration))
        currentTime = stamp
        player.seek(to: CMTime(seconds: stamp, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)

        if NoteTimestamp.timestamps(in: notes).contains(stamp) {
            openNote(at: stamp)
            return
        }
        draftStamp = stamp
        draft = ""
        editingLineIndex = nil
        isEditingNotes = true
        notesFocused = true
    }

    /// The Photos bar: play/pause and a bare line — no thumb — in a rounded rectangle
    /// that stops short of a full capsule.
    ///
    /// One piece of glass. Opening a note stretches this same box upward and the
    /// input row — clock on the left, words beside it — slides in above the bar;
    /// closing one (scrubbing, playing, committing) collapses it back to just the
    /// bar. A single glass view resizing is what gets the native morph; a separate
    /// glass shape per piece would swap instead of growing.
    private var playbar: some View {
        VStack(spacing: 4) {
            if isEditingNotes {
                noteRow
                    .padding(.top, 12)
            } else if let passing = passingNote {
                passingNoteRow(passing)
                    .padding(.top, 12)
            }

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
    }

    /// The note playback is passing: pops up a beat before its moment and lingers a
    /// beat after, so the words are on screen while the moment happens. Playback only —
    /// scrubbing across bookmarks would make the row flap — and the editing row, when
    /// open, owns the slot.
    private var passingNote: (stamp: TimeInterval, words: String)? {
        guard isPlaying, !isEditingNotes else { return nil }
        var best: (stamp: TimeInterval, words: String)?
        for line in notes.components(separatedBy: "\n") {
            guard let stamp = NoteTimestamp.timestamps(in: line).first,
                  currentTime >= stamp - 1.0, currentTime <= stamp + 1.5 else { continue }
            // Windows can overlap when notes sit close; the upcoming note takes over
            // from the lingering one.
            if best == nil || stamp > best!.stamp {
                best = (stamp, strippingClock(line))
            }
        }
        return best
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

    /// The note the playhead is inside: the last bookmark at or before it.
    private var currentNote: (stamp: TimeInterval, words: String)? {
        var best: (stamp: TimeInterval, words: String)?
        for line in notes.components(separatedBy: "\n") {
            guard let stamp = NoteTimestamp.timestamps(in: line).first,
                  stamp <= currentTime + 0.011 else { continue }
            if best == nil || stamp > best!.stamp {
                best = (stamp, strippingClock(line))
            }
        }
        return best
    }

    /// A thin line, white up to the playhead and faint past it. Dragging anywhere on it
    /// pauses and seeks straight to that spot; the time observer echoes the same value
    /// back, so the line never fights the playhead.
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
                // gesture underneath. A fresh draft plants its bookmark the instant
                // the note opens — committed it stays, discarded it goes.
                let saved = NoteTimestamp.timestamps(in: notes)
                let stamps = isEditingNotes && !saved.contains(draftStamp)
                    ? saved + [draftStamp] : saved
                ForEach(Array(stamps.enumerated()), id: \.offset) { _, stamp in
                    // Centred exactly where the white bar ends at that stamp — same
                    // `progress * width` maths — nudged in just enough at the edges
                    // to stay whole.
                    let centre = min(max(min(max(stamp / span, 0), 1) * geo.size.width, 5.5),
                                     geo.size.width - 5.5)
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemYellow))
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .frame(width: 26, height: 34)
                        .contentShape(.rect)
                        .onTapGesture { openNote(at: stamp) }
                        .offset(x: centre - 13)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        player.pause()
                        let seconds = min(max(value.location.x / geo.size.width, 0), 1) * span
                        currentTime = seconds
                        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                                    toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    // Scrubbing moves on from the open note, but only once the finger
                    // lifts: collapsing mid-drag takes the keyboard with it and the
                    // bar slides down out from under the thumb. On release whatever
                    // was typed commits at its own moment, the row folds away, and
                    // the circle is a pencil again.
                    .onEnded { _ in
                        if isEditingNotes {
                            commitDraft()
                            deselectNote()
                            notesFocused = false
                        }
                    }
            )
        }
        .frame(height: 34)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            // Playing on is moving past the open note: it commits and deselects.
            if isEditingNotes {
                commitDraft()
                deselectNote()
                notesFocused = false
            }
            // Play at the end means watch it again.
            if currentTime >= duration - 0.05 {
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
    private func commitDraft() {
        let stampToken = NoteTimestamp.token(for: draftStamp)
        let noteLines = draft.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isBareClock($0) }
            .map { NoteTimestamp.timestamps(in: $0).isEmpty ? stampToken + " " + $0 : $0 }
        draft = ""

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
    }

    private func isBareClock(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return NoteTimestamp.regex.firstMatch(in: line, options: [], range: range)?.range == range
    }

    /// A tapped dot: park the video on that moment and put that note in the field.
    /// `focusing: false` shows the note without raising the keyboard — how the page
    /// opens when a timestamp link brought it here.
    private func openNote(at stamp: TimeInterval, focusing: Bool = true) {
        let lines = notes.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { NoteTimestamp.timestamps(in: $0).first == stamp })
        else { return }

        player.pause()
        currentTime = stamp
        player.seek(to: CMTime(seconds: stamp, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)

        draft = strippingClock(lines[index])
        editingLineIndex = index
        draftStamp = stamp
        isEditingNotes = true
        if focusing { notesFocused = true }
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
struct AttemptTopBar: View {
    let title: String
    var subtitle: String? = nil
    var onClose: () -> Void

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

                Color.clear.frame(width: controlHeight, height: controlHeight)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

/// A bare video layer — no system controls, the playbar above is the only chrome.
private struct PlayerSurface: UIViewRepresentable {
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
