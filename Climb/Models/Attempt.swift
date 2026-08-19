import Foundation
import SwiftData

/// One go on a climb: the video, how long you rested afterwards, and what you noticed.
@Model
final class Attempt {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Filenames are relative to `VideoStore.directory` so the record survives the
    /// container path changing between installs.
    var videoFilename: String?
    var thumbnailFilename: String?

    var videoDuration: TimeInterval = 0
    var restSeconds: TimeInterval = 0
    var notes: String = ""

    /// How hard it felt, as `Effort.rawValue` — `Effort.unrated` until it is answered
    /// on the attempt page. Stored as the raw number so an attempt written before the
    /// question existed reads as unrated rather than failing to load.
    var effortRaw: Int = Effort.unrated

    var session: ClimbSession?

    /// Stamped when the row was deleted from its note. The record and its video stay —
    /// a recording is the one thing here you cannot make again — but nothing links to
    /// it any more, so it counts towards nothing and shows up nowhere.
    var deletedAt: Date?

    /// Set when the attempt was recorded under a climb heading in the note.
    var climb: Climb?

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }

    var videoURL: URL? {
        videoFilename.map { VideoStore.directory.appendingPathComponent($0) }
    }

    /// The rating, as the four words it is asked in. Setting it to nothing clears it,
    /// which is how a mis-tap is taken back.
    var effort: Effort? {
        get { Effort.stored(effortRaw) }
        set { effortRaw = newValue?.rawValue ?? Effort.unrated }
    }

    var thumbnailURL: URL? {
        thumbnailFilename.map { VideoStore.directory.appendingPathComponent($0) }
    }
}

extension TimeInterval {
    /// `0:07` / `1:24` — the clock format used on rows, the timer, and the player.
    var clockString: String {
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
