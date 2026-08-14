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
    /// LiDAR depth sidecar (`DepthRecorder` format); nil when the phone couldn't capture depth.
    var depthFilename: String?

    var videoDuration: TimeInterval = 0
    var restSeconds: TimeInterval = 0
    var notes: String = ""

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

    var thumbnailURL: URL? {
        thumbnailFilename.map { VideoStore.directory.appendingPathComponent($0) }
    }

    var depthURL: URL? {
        depthFilename.map { VideoStore.directory.appendingPathComponent($0) }
    }
}

extension TimeInterval {
    /// `0:07` / `1:24` — the clock format used on rows, the timer, and the player.
    var clockString: String {
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
