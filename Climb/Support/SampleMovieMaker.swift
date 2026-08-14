import AVFoundation
import CoreImage
import UIKit

/// Writes a synthetic movie file.
///
/// The Simulator has no capture device, so without this the record → rest-timer →
/// review → inline-row flow could only ever be exercised on hardware.
enum SampleMovieMaker {
    static func makeMovie(duration: TimeInterval, at url: URL) async throws {
        let size = CGSize(width: 720, height: 1280)
        let fps: Int32 = 24
        let frameCount = max(1, Int(duration * Double(fps)))

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let renderer = UIGraphicsImageRenderer(size: size)
        for frame in 0..<frameCount {
            let progress = Double(frame) / Double(frameCount)
            let image = renderer.image { context in
                UIColor(hue: 0.58, saturation: 0.45, brightness: 0.22, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))

                // A climber-ish blob tracking up the frame, so successive attempts are
                // visually distinguishable in the review player and thumbnails.
                let y = size.height * (0.85 - 0.6 * progress)
                UIColor(hue: 0.08, saturation: 0.75, brightness: 0.95, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: size.width / 2 - 60, y: y - 60, width: 120, height: 120))

                let text = "SIMULATED \(String(format: "%.1f", progress * duration))s"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: 80), withAttributes: attributes)
            }

            guard let buffer = pixelBuffer(from: image, size: size, pool: adaptor.pixelBufferPool) else { continue }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &buffer)
        }
        guard let buffer, let cgImage = image.cgImage else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
