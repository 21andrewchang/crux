@preconcurrency import AVFoundation
import Combine
import SwiftUI

/// Drives video capture for one attempt.
///
/// Stopping the recording is the moment that matters: it hands back the file *and*
/// marks the instant the rest timer starts from.
/// `@unchecked Sendable`: published state is only ever mutated on the main actor, and
/// the capture session is only ever touched on `sessionQueue`.
final class CaptureController: NSObject, ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case configuring
        case ready
        case recording
        /// No usable camera — Simulator, or permission denied.
        case simulated(reason: String)
        case denied
    }

    @Published private(set) var status: Status = .configuring
    @Published private(set) var elapsed: TimeInterval = 0
    /// Zoom the way the user reads it — 1 means "1×", not the raw device factor.
    @Published private(set) var zoom: CGFloat = 1
    /// The stops offered by the zoom picker; empty when there's nothing to pick.
    @Published private(set) var zoomOptions: [CGFloat] = []

    let session = AVCaptureSession()

    /// Called with the finished recording and the timestamp recording stopped.
    var onFinish: ((URL, Date) -> Void)?

    private let output = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.andrewchang.Climb.capture")
    private var ticker: AnyCancellable?
    private var startedAt: Date?
    private var isSimulating = false
    private var device: AVCaptureDevice?
    /// Raw device factor that reads as "1×". On a phone with an ultra-wide lens the
    /// virtual device starts at the widest lens, so 1× sits at the first switch-over point.
    private var baseZoomFactor: CGFloat = 1

    // MARK: Setup

    func prepare() async {
        let authorized = await requestCameraAccess()
        guard authorized else {
            await MainActor.run { self.status = .denied }
            return
        }

        guard let camera = Self.bestBackCamera() else {
            await MainActor.run {
                self.status = .simulated(reason: "No camera on this device. Recording will be simulated.")
                // Stand-in stops so the picker still lays out while developing on the Simulator.
                self.zoomOptions = [0.5, 1, 2]
            }
            return
        }
        device = camera

        let configured = await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                defer { self.session.commitConfiguration() }

                do {
                    let videoInput = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(videoInput) else {
                        continuation.resume(returning: false); return
                    }
                    self.session.addInput(videoInput)

                    if let mic = AVCaptureDevice.default(for: .audio),
                       let audioInput = try? AVCaptureDeviceInput(device: mic),
                       self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }

                    guard self.session.canAddOutput(self.output) else {
                        continuation.resume(returning: false); return
                    }
                    self.session.addOutput(self.output)

                    self.baseZoomFactor = Self.baseZoomFactor(for: camera)
                    if (try? camera.lockForConfiguration()) != nil {
                        camera.videoZoomFactor = self.baseZoomFactor
                        camera.unlockForConfiguration()
                    }
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }

        guard configured else {
            await MainActor.run {
                self.status = .simulated(reason: "Camera unavailable. Recording will be simulated.")
            }
            return
        }

        sessionQueue.async { self.session.startRunning() }
        let stops = Self.zoomStops(for: camera, base: baseZoomFactor)
        await MainActor.run {
            self.zoomOptions = stops
            self.zoom = 1
            self.status = .ready
        }
    }

    // MARK: Zoom

    func setZoom(_ display: CGFloat) {
        zoom = display
        guard let device else { return }
        let target = min(max(display * baseZoomFactor, device.minAvailableVideoZoomFactor),
                         device.maxAvailableVideoZoomFactor)
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.ramp(toVideoZoomFactor: target, withRate: 24)
            device.unlockForConfiguration()
        }
    }

    /// The widest virtual device available, so one camera can cover ultra-wide
    /// through telephoto and the zoom picker gets every stop the phone has.
    private static func bestBackCamera() -> AVCaptureDevice? {
        let preference: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: preference,
                                                         mediaType: .video,
                                                         position: .back)
        for type in preference {
            if let match = discovery.devices.first(where: { $0.deviceType == type }) { return match }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Device factor that reads as 1×: the ultra-wide → wide switch-over, or 1 if there's no ultra-wide.
    private static func baseZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        guard hasUltraWide, let first = device.virtualDeviceSwitchOverVideoZoomFactors.first else { return 1 }
        return CGFloat(truncating: first)
    }

    /// The 0.5 / 1 / 2 / 5-style stops this camera can actually hit, in display units.
    private static func zoomStops(for device: AVCaptureDevice, base: CGFloat) -> [CGFloat] {
        let minimum = device.minAvailableVideoZoomFactor / base
        let maximum = device.maxAvailableVideoZoomFactor / base

        var stops: Set<CGFloat> = [1]
        if minimum <= 0.5 { stops.insert(0.5) }
        if maximum >= 2 { stops.insert(2) }

        // Telephoto lenses beyond 1× get their own stop, rounded to the nearest half.
        for factor in device.virtualDeviceSwitchOverVideoZoomFactors {
            let display = (CGFloat(truncating: factor) / base * 2).rounded() / 2
            if display > 1, display <= maximum { stops.insert(display) }
        }

        return stops.count > 1 ? stops.sorted() : []
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default:
            // The Simulator reports no device at all; treat that as "fall back", not "denied".
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil
        }
    }

    func teardown() {
        ticker?.cancel()
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Recording

    func startRecording() {
        guard status == .ready || isSimulatedStatus else { return }
        startedAt = Date()
        elapsed = 0
        status = .recording
        ticker = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }

        if isSimulatedStatus {
            isSimulating = true
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attempt-\(UUID().uuidString).mov")
        sessionQueue.async {
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        ticker?.cancel()
        let duration = elapsed

        if isSimulating {
            isSimulating = false
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("attempt-\(UUID().uuidString).mov")
            Task {
                try? await SampleMovieMaker.makeMovie(duration: max(duration, 0.5), at: url)
                let stoppedAt = Date()
                await MainActor.run {
                    self.status = .ready
                    self.onFinish?(url, stoppedAt)
                }
            }
            return
        }

        sessionQueue.async { self.output.stopRecording() }
    }

    private var isSimulatedStatus: Bool {
        if case .simulated = status { return true }
        return false
    }
}

extension CaptureController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: (any Error)?) {
        let stoppedAt = Date()
        DispatchQueue.main.async {
            self.status = .ready
            guard error == nil else { return }
            self.onFinish?(outputFileURL, stoppedAt)
        }
    }
}

/// Live camera feed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
