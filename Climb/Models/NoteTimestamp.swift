import Foundation

/// A note line can open with the clock it was taken at — "0:12 fell here". The clock is
/// plain text, so it survives every trip through `bodyText` and the attempt's `notes`;
/// everything else about it — the tint, the tap that seeks the video — is derived from
/// the pattern wherever the text lands.
enum NoteTimestamp {
    /// A clock token opening a line, standing alone before a space or the line's end.
    /// The fraction is optional so plain "0:02" tokens from older notes still count.
    static let regex = try! NSRegularExpression(pattern: #"^\d{1,3}:[0-5]\d(?:\.\d{1,2})?(?=\s|$)"#,
                                                options: [.anchorsMatchLines])

    /// The clock speaks in centiseconds — within half a frame at 60fps — so a note
    /// marks the exact moment, and two notes moments apart never collide.
    static func quantized(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 100).rounded() / 100
    }

    /// "0:02.43" — what a quantized moment reads as, and parses back from exactly.
    static func token(for seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return String(format: "%d:%05.2f", minutes, seconds - Double(minutes * 60))
    }

    /// "0:02" — the token to the whole second, floored to match how the document
    /// shows a token with its fraction hidden.
    static func display(for seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// Every clock the note's lines open with, in order of appearance.
    static func timestamps(in notes: String) -> [TimeInterval] {
        let text = notes as NSString
        let matches = regex.matches(in: notes, options: [], range: NSRange(location: 0, length: text.length))
        return matches.map { seconds(from: text.substring(with: $0.range)) }
    }

    static func seconds(from token: String) -> TimeInterval {
        let parts = token.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return 0 }
        return minutes * 60 + seconds
    }

    /// The edit that turned `old` into `new`, stamped: typing at the start of a fresh
    /// line while the video sits paused at `time` opens the line with the clock.
    /// Anything else — edits mid-text, deletions, playback running — passes through nil.
    static func stamped(old: String, new: String, at time: TimeInterval?) -> String? {
        guard let time,
              new.count > old.count, new.hasPrefix(old),
              old.isEmpty || old.hasSuffix("\n")
        else { return nil }
        // A bare Return is a line with nothing on it yet; the clock arrives with the
        // first real character, so empty stamped lines never pile up.
        let added = new.dropFirst(old.count)
        guard !added.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return old + time.clockString + " " + added
    }
}
