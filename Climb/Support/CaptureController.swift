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

    /// Called with the finished recording, its LiDAR depth sidecar (nil when the
    /// device has no LiDAR), and the timestamp recording stopped.
    var onFinish: ((URL, URL?, Date) -> Void)?

    private let output = AVCaptureMovieFileOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.andrewchang.Climb.capture")
    /// Owns `depthRecorder`; depth frames and file writes never touch another queue.
    private let depthQueue = DispatchQueue(label: "com.andrewchang.Climb.depth")
    private var depthRecorder: DepthRecorder?
    /// Set during configuration when the LiDAR camera and depth output are live.
    private var capturesDepth = false
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
                    self.configureDepthIfAvailable(on: camera)

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

    /// Depth rides alongside the movie output as a best-effort extra: the LiDAR camera
    /// only exposes the wide lens, so this is a no-op on phones without LiDAR and the
    /// video path is identical either way.
    private func configureDepthIfAvailable(on camera: AVCaptureDevice) {
        guard camera.deviceType == .builtInLiDARDepthCamera,
              session.canAddOutput(depthOutput) else { return }
        session.addOutput(depthOutput)

        // Raw sensor readings — unreadable spots stay NaN rather than being smoothed
        // over. Flip to true for hole-filled, temporally filtered maps.
        depthOutput.isFilteringEnabled = false
        depthOutput.setDelegate(self, callbackQueue: depthQueue)

        // Densest Float16 depth the active video format can pair with (320×240 on
        // current hardware).
        let depthFormats = camera.activeFormat.supportedDepthDataFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
        }
        if let best = depthFormats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }), (try? camera.lockForConfiguration()) != nil {
            camera.activeDepthDataFormat = best
            camera.unlockForConfiguration()
        }
        capturesDepth = true
    }

    /// Prefers the LiDAR camera when the phone has one — it's the only device that can
    /// stream depth, at the price of losing the 0.5× ultra-wide stop. Otherwise the
    /// widest virtual device, so one camera can cover ultra-wide through telephoto.
    private static func bestBackCamera() -> AVCaptureDevice? {
        if let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
            return lidar
        }
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
        if capturesDepth {
            let depthURL = url.deletingPathExtension().appendingPathExtension("depth")
            depthQueue.async { self.depthRecorder = DepthRecorder(url: depthURL) }
        }
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
                    self.onFinish?(url, nil, stoppedAt)
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
        // Hop through the depth queue so the sidecar is sealed — and no late frame can
        // reopen it — before anyone hears the recording is done.
        depthQueue.async {
            let depthURL = self.depthRecorder?.finish()
            self.depthRecorder = nil
            DispatchQueue.main.async {
                self.status = .ready
                guard error == nil else { return }
                self.onFinish?(outputFileURL, depthURL, stoppedAt)
            }
        }
    }
}

extension CaptureController: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        // Runs on depthQueue; the recorder only exists between start and stop, so this
        // is a no-op while idle.
        depthRecorder?.append(depthData, at: timestamp)
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
