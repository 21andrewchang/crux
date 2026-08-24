import Photos

/// Copies finished recordings out to the camera roll.
///
/// Attempts live in the app's own storage — this is the second copy, so a video shot
/// here shows up in Photos like anything else filmed on the phone. Add-only access is
/// all it asks for: nothing here ever reads the library back.
enum PhotoLibraryExport {
    /// Saves a copy of `url` to Photos, if the user allows it. Quietly does nothing
    /// when access is refused — a missing camera-roll copy is never worth interrupting
    /// the flow between an attempt and its review.
    static func save(videoAt url: URL) async {
        guard await requestAddAccess() else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            // The app keeps its own copy in Application Support, so Photos takes a copy
            // rather than moving the file out from under the attempt.
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }

    private static func requestAddAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default: return false
        }
    }
}
