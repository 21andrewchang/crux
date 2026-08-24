import AVFoundation
import UIKit

/// Owns the on-disk video and thumbnail files backing `Attempt`.
enum VideoStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Attempts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Moves a freshly captured recording into permanent storage and renders its poster
    /// frame, so inline rows can draw immediately without touching AVFoundation.
    ///
    /// The source extension is kept: recordings are always `.mov`, but a video picked
    /// out of Photos can just as easily be `.mp4`, and AVFoundation reads the container
    /// the name promises.
    static func ingest(recordingAt source: URL, attemptID: UUID) async
        -> (video: String, thumbnail: String?, duration: TimeInterval)
    {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let videoName = "\(attemptID.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(videoName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            try? FileManager.default.copyItem(at: source, to: destination)
        }

        excludeFromBackup(destination)

        let asset = AVURLAsset(url: destination)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let thumbnailName = await renderThumbnail(for: asset, attemptID: attemptID)
        return (videoName, thumbnailName, duration.isFinite ? duration : 0)
    }

    private static func renderThumbnail(for asset: AVURLAsset, attemptID: UUID) async -> String? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image,
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
        else { return nil }

        let name = "\(attemptID.uuidString).jpg"
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Keeps a recording out of the device's iCloud backup.
    ///
    /// Every take filmed here is already copied to the camera roll, so backing the
    /// app's copy up too would count the same footage against the user's iCloud twice
    /// — and a season of climbing is gigabytes, against a free tier of five. What is
    /// lost by skipping them is playback after a restore: the attempt, its rating, its
    /// notes and its thumbnail all come back, and only the video itself is missing.
    ///
    /// Thumbnails are deliberately left in the backup. They are tens of kilobytes each
    /// and they are what makes a restored note still look like the sessions it records.
    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Flags recordings written before the app started excluding them. Cheap enough to
    /// run at every launch — it only ever sets a flag that is already set — and doing
    /// it that way avoids keeping a "have I migrated yet" bit around to go stale.
    static func excludeExistingVideosFromBackup() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isExcludedFromBackupKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.pathExtension.lowercased() != "jpg" {
            let already = try? file.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup
            if already != true { excludeFromBackup(file) }
        }
    }

    static func delete(_ attempt: Attempt) {
        for url in [attempt.videoURL, attempt.thumbnailURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
