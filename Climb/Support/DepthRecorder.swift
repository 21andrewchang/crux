import AVFoundation

/// Writes the LiDAR depth stream for one recording into a sidecar file next to the video.
///
/// File format (`.depth`, all values little-endian):
/// - Header: `"CLDP"` magic, `UInt32` version (1), `UInt32` width, `UInt32` height.
/// - Then one record per frame: `Float64` seconds since the first depth frame,
///   `UInt32` compressed byte count, zlib-compressed pixels.
/// - Pixels are row-major `Float16` metres (`kCVPixelFormatType_DepthFloat16`),
///   `width * 2` bytes per row with no padding. Holes the sensor couldn't read are NaN.
///
/// Roughly 265 MB/min raw at 320×240 @ 30 fps; zlib brings a typical indoor scene
/// down to ~70–130 MB/min. If that's too heavy, thin frames in `append` before writing.
///
/// Not thread-safe by itself — every call must come from the capture controller's
/// depth queue.
final class DepthRecorder {
    private let url: URL
    private var handle: FileHandle?
    private var firstTimestamp: CMTime?
    private var frameCount = 0

    init(url: URL) {
        self.url = url
    }

    func append(_ depthData: AVDepthData, at timestamp: CMTime) {
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat16
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        let map = depth.depthDataMap

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)
        let rowBytes = width * MemoryLayout<Float16>.size

        // Copy row by row: the buffer's rows can carry alignment padding the file must not.
        var pixels = Data(capacity: rowBytes * height)
        for row in 0..<height {
            pixels.append(Data(bytes: base + row * bytesPerRow, count: rowBytes))
        }

        guard let compressed = try? (pixels as NSData).compressed(using: .zlib) as Data else { return }
        if handle == nil, !open(width: width, height: height) { return }

        let reference = firstTimestamp ?? timestamp
        firstTimestamp = reference
        let offset = CMTimeSubtract(timestamp, reference).seconds

        var record = Data()
        withUnsafeBytes(of: offset.bitPattern.littleEndian) { record.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(compressed.count).littleEndian) { record.append(contentsOf: $0) }
        record.append(compressed)
        do {
            try handle?.write(contentsOf: record)
            frameCount += 1
        } catch {
            try? handle?.close()
            handle = nil
        }
    }

    private func open(width: Int, height: Int) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let opened = try? FileHandle(forWritingTo: url) else { return false }
        var header = Data("CLDP".utf8)
        for value in [UInt32(1), UInt32(width), UInt32(height)] {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        guard (try? opened.write(contentsOf: header)) != nil else { return false }
        handle = opened
        return true
    }

    /// Closes the file and hands back its URL, or nil if no depth ever arrived.
    func finish() -> URL? {
        try? handle?.close()
        handle = nil
        if frameCount == 0 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}
