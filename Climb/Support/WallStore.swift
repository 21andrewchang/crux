import UIKit

/// Owns the on-disk wall photo and processed route render backing `Climb`.
enum WallStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Walls", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(for name: String?) -> URL? {
        name.map { directory.appendingPathComponent($0) }
    }

    /// Writes the normalized wall photo and its route render for a climb, replacing
    /// any previous pair. Names are stable per climb so re-detection with a different
    /// color overwrites in place instead of leaking files.
    static func save(photo: UIImage, route: UIImage, climbID: UUID) -> (photo: String, route: String)? {
        guard let jpeg = photo.jpegData(compressionQuality: 0.85),
              let png = route.pngData() else { return nil }
        let photoName = "\(climbID.uuidString)-wall.jpg"
        let routeName = "\(climbID.uuidString)-route.png"
        do {
            try jpeg.write(to: directory.appendingPathComponent(photoName), options: .atomic)
            try png.write(to: directory.appendingPathComponent(routeName), options: .atomic)
        } catch {
            return nil
        }
        return (photoName, routeName)
    }

    static func delete(_ climb: Climb) {
        for url in [climb.wallPhotoURL, climb.routeImageURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
