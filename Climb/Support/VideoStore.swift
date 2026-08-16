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
    static func ingest(recordingAt source: URL, attemptID: UUID) async
        -> (video: String, thumbnail: String?, duration: TimeInterval)
    {
        let videoName = "\(attemptID.uuidString).mov"
        let destination = directory.appendingPathComponent(videoName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            try? FileManager.default.copyItem(at: source, to: destination)
        }

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

    static func delete(_ attempt: Attempt) {
        for url in [attempt.videoURL, attempt.thumbnailURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
