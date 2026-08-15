import AVKit
import SwiftUI

/// What the flow hands back once the user finishes an attempt.
struct CapturedAttempt {
    var videoFilename: String
    var thumbnailFilename: String?
    var depthFilename: String?
    var duration: TimeInterval
    var restSeconds: TimeInterval
    var notes: String
}

/// Record → stop (rest timer starts) → review and annotate → finish.
struct AttemptFlowView: View {
    let attemptID: UUID
    let ordinal: Int
    /// The climb the attempt will belong to; nil when it lands outside any climb.
    var climbName: String? = nil
    var onFinish: (CapturedAttempt) -> Void
    var onCancel: () -> Void

    private enum Phase: Equatable {
        case capture
        case processing
        case review(video: String, thumbnail: String?, depth: String?, duration: TimeInterval, restStart: Date)
    }

    @StateObject private var capture = CaptureController()
    @State private var phase: Phase = .capture

    var body: some View {
        ZStack {
            switch phase {
            case .capture:
                captureScreen
            case .processing:
                Color.black.ignoresSafeArea()
                ProgressView().controlSize(.large).tint(.white)
            case let .review(video, thumbnail, depth, duration, restStart):
                AttemptReviewView(
                    ordinal: ordinal,
                    climbName: climbName,
                    videoFilename: video,
                    thumbnailFilename: thumbnail,
                    depthFilename: depth,
                    duration: duration,
                    restStart: restStart,
                    onFinish: onFinish,
                    onDiscard: onCancel
                )
            }
        }
        .animation(.smooth(duration: 0.3), value: phase)
        // Swiping the sheet away is fine while nothing is on the line — the idle
        // camera. Mid-recording, processing, or on review it would silently trash
        // the take, so there the ✕ (which confirms) is the only way out.
        .interactiveDismissDisabled(!(phase == .capture && capture.status != .recording))
        .task {
            capture.onFinish = { url, depthURL, stoppedAt in
                ingest(url: url, depthURL: depthURL, stoppedAt: stoppedAt)
            }
            await capture.prepare()
        }
        .onDisappear { capture.teardown() }
    }

    // MARK: Capture

    private var captureScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch capture.status {
            case .ready, .recording:
                CameraPreview(session: capture.session).ignoresSafeArea()
            case .simulated(let reason):
                simulatorStandIn(reason)
            case .denied:
                permissionMessage
            case .configuring:
                ProgressView().tint(.white)
            }

            VStack(spacing: 0) {
                captureTopBar
                Spacer()
                if !capture.zoomOptions.isEmpty {
                    zoomPicker
                        .padding(.bottom, 22)
                }
                recordButton
                    .padding(.bottom, 32)
            }
        }
    }

    private var captureTopBar: some View {
        // Same bones as AttemptTopBar — ✕ disc, centred capsule — so the capture page
        // is headed exactly like the review and replay pages. The capsule swaps to the
        // red clock while recording.
        let controlHeight: CGFloat = 48

        return GlassEffectContainer(spacing: 12) {
            HStack {
                Button {
                    capture.teardown()
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: controlHeight, height: controlHeight)
                        .glassEffect(.regular, in: .circle)
                        // Without this only the glyph is tappable, not the disc around it.
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)

                Spacer()

                Group {
                    if capture.status == .recording {
                        Text(capture.elapsed.clockString)
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    } else {
                        VStack(spacing: 1) {
                            Text(climbName ?? "Attempt \(ordinal)")
                                .font(.system(size: 17, weight: .semibold))
                            if climbName != nil {
                                Text("Attempt \(ordinal)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: controlHeight)
                .glassEffect(.regular.tint(capture.status == .recording ? .red.opacity(0.7) : nil),
                             in: .capsule)

                Spacer()

                Color.clear.frame(width: controlHeight, height: controlHeight)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// The Camera app's shutter: a full liquid-glass disc with a red disc on top that
    /// collapses into a rounded square while recording.
    private var recordButton: some View {
        let recording = capture.status == .recording
        let inner: CGFloat = recording ? 32 : 66

        return Button {
            if recording {
                phase = .processing
                capture.stopRecording()
            } else {
                capture.startRecording()
            }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular.tint(.white.opacity(0.25)), in: .circle)
                RoundedRectangle(cornerRadius: recording ? 8 : inner / 2, style: .continuous)
                    .fill(Color(red: 1, green: 0.23, blue: 0.19))
                    .frame(width: inner, height: inner)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(capture.status == .configuring || capture.status == .denied)
        .animation(.bouncy(duration: 0.28), value: capture.status)
    }

    /// Native-style lens stops: the selected one sits on a blurred disc with a yellow "×".
    /// The blur is a plain material *behind* the label — glass would sit over it and smear
    /// the digits.
    private var zoomPicker: some View {
        HStack(spacing: 0) {
            ForEach(capture.zoomOptions, id: \.self) { option in
                let selected = capture.zoom == option
                Button {
                    capture.setZoom(option)
                } label: {
                    Text(zoomLabel(option, selected: selected))
                        .font(.system(size: selected ? 17 : 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.yellow : .white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                        .frame(width: 46, height: 46)
                        .background {
                            if selected {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.2), value: capture.zoom)
        .sensoryFeedback(.selection, trigger: capture.zoom)
    }

    /// ".5" / "1" / "2" while idle; the selected stop picks up the "×" the way Camera does.
    private func zoomLabel(_ value: CGFloat, selected: Bool) -> String {
        let whole = value == value.rounded()
        var text = whole ? String(Int(value)) : String(format: "%.1f", value)
        if !whole, text.hasPrefix("0") { text.removeFirst() }
        return selected ? text + "×" : text
    }

    private func simulatorStandIn(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 44, weight: .light))
            Text(reason)
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .foregroundStyle(.white.opacity(0.65))
    }

    private var permissionMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 40, weight: .light))
            Text("Camera access is off.\nEnable it in Settings to record attempts.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    /// Moves the recording into permanent storage and flips to review. The rest timer
    /// runs from `stoppedAt` — the moment the user hit stop, not the moment ingest ends.
    private func ingest(url: URL, depthURL: URL?, stoppedAt: Date) {
        Task {
            let result = await VideoStore.ingest(recordingAt: url, depthAt: depthURL, attemptID: attemptID)
            await MainActor.run {
                phase = .review(video: result.video,
                                thumbnail: result.thumbnail,
                                depth: result.depth,
                                duration: result.duration,
                                restStart: stoppedAt)
            }
        }
    }
}

/// Dips on touch the way the Camera shutter does — no highlight, just a nudge in scale.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// The same attempt screen as the replay page, plus a Finish button. The rest clock
/// still runs from `restStart` — it's recorded on finish, just not shown for now.
private struct AttemptReviewView: View {
    let ordinal: Int
    let climbName: String?
    let videoFilename: String
    let thumbnailFilename: String?
    let depthFilename: String?
    let duration: TimeInterval
    let restStart: Date
    var onFinish: (CapturedAttempt) -> Void
    var onDiscard: () -> Void

    @State private var notes: String = ""
    @State private var isConfirmingDiscard = false
    @State private var controller = AttemptPlayerController()

    private var videoURL: URL { VideoStore.directory.appendingPathComponent(videoFilename) }

    var body: some View {
        AttemptPlayerView(
            videoURL: videoURL,
            duration: duration,
            notes: $notes,
            autoplays: true,
            controller: controller
        ) {
            Button {
                controller.commitDraft()
                onFinish(CapturedAttempt(
                    videoFilename: videoFilename,
                    thumbnailFilename: thumbnailFilename,
                    depthFilename: depthFilename,
                    duration: duration,
                    restSeconds: Date().timeIntervalSince(restStart),
                    notes: notes
                ))
            } label: {
                Text("Finish Attempt")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
        }
        .overlay(alignment: .top) {
            AttemptTopBar(
                title: climbName ?? "Attempt \(ordinal)",
                subtitle: climbName != nil ? "Attempt \(ordinal)" : nil
            ) { isConfirmingDiscard = true }
        }
        // Closing the review is discarding the take — the recording only becomes
        // an attempt through "Finish Attempt" — so the ✕ double-checks.
        .alert("Delete this attempt?", isPresented: $isConfirmingDiscard) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                try? FileManager.default.removeItem(at: videoURL)
                if let depthFilename {
                    try? FileManager.default.removeItem(
                        at: VideoStore.directory.appendingPathComponent(depthFilename))
                }
                onDiscard()
            }
        } message: {
            Text("The video will be deleted.")
        }
    }
}
