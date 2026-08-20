import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// What the flow hands back the moment a recording lands — the attempt is saved
/// there and then, not on a button.
struct CapturedAttempt {
    var videoFilename: String
    var thumbnailFilename: String?
    var duration: TimeInterval
    /// When the recording stopped: what the rest clock — and the rest written onto
    /// the attempt when the page closes — counts from.
    var stoppedAt: Date
}

/// Record → stop (the attempt saves itself, the rest timer starts) → the ordinary
/// attempt page, where it can be annotated, retaken, or deleted.
struct AttemptFlowView: View {
    let attemptID: UUID
    let ordinal: Int
    /// The climb the attempt will belong to; nil when it lands outside any climb.
    var climbName: String? = nil
    /// The app's one rest clock, started here the moment the recording stops and
    /// shown counting down on the page that follows.
    var stopwatch: StopwatchModel
    /// The saved attempt, looked up once the recording has been ingested.
    var attempt: () -> Attempt?
    /// Saves the recording as an attempt. Called straight off the camera.
    var onCapture: (CapturedAttempt) -> Void
    /// Unwinds that save — row, record and video — for both Retake and Delete.
    var onDiscard: () -> Void
    /// Closes the sheet, keeping whatever is saved.
    var onClose: () -> Void

    private enum Phase: Equatable {
        case capture
        case processing
        case review
    }

    @StateObject private var capture = CaptureController()
    @State private var phase: Phase = .capture
    @State private var showingLibrary = false
    /// How far the Photos import has got, nil when nothing is being imported.
    /// It is the honest number: an iCloud download reports through it too.
    @State private var importProgress: Double?
    /// The import in flight, kept so Cancel can actually stop it.
    @State private var importJob: Progress?

    var body: some View {
        ZStack {
            switch phase {
            case .capture:
                captureScreen
            case .processing:
                Color.black.ignoresSafeArea()
                processingScreen
            case .review:
                // The same page an attempt opens to from the note, over the attempt
                // that was just saved — plus the controls that only a fresh take has.
                if let attempt = attempt() {
                    AttemptDetailView(
                        attempt: attempt,
                        ordinal: ordinal,
                        climbName: climbName,
                        autoplays: true,
                        stopwatch: stopwatch,
                        actions: AttemptActions(
                            onRetake: {
                                onDiscard()
                                phase = .capture
                            },
                            onDelete: {
                                onDiscard()
                                onClose()
                            },
                            isFreshTake: true
                        ),
                        onDone: onClose
                    )
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: phase)
        // Swiping the sheet away is fine wherever nothing is on the line: the idle
        // camera, and the review page, where the attempt is already saved. Only a
        // recording in flight — or the ingest right after it — holds the sheet.
        .interactiveDismissDisabled(phase == .processing || capture.status == .recording)
        .task {
            capture.onFinish = { url, stoppedAt in
                ingest(url: url, stoppedAt: stoppedAt)
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
                bottomControls
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
                    onClose()
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
        // Matches AttemptTopBar's top padding so capture, review, and replay all
        // hang the bar at the same height.
        .padding(.top, 14)
    }

    /// The shutter, with the Photos import sitting where Camera keeps its library
    /// thumbnail. The trailing spacer is the picker's mirror image, so the shutter
    /// stays centred on the screen rather than on what's left of the row.
    private var bottomControls: some View {
        HStack {
            libraryButton
            Spacer()
            recordButton
            Spacer()
            Color.clear.frame(width: libraryButtonSize, height: libraryButtonSize)
        }
        .padding(.horizontal, 32)
    }

    private var libraryButtonSize: CGFloat { 54 }

    /// Pulls an attempt in from Photos for climbs someone else filmed, or that were
    /// shot before the app was open. It lands in exactly the same place a recording
    /// does: ingested, saved, and opened on its own page.
    private var libraryButton: some View {
        Button {
            showingLibrary = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: libraryButtonSize, height: libraryButtonSize)
                .glassEffect(.regular, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        // Nothing to import onto mid-take; the shutter owns the screen while it runs.
        .opacity(capture.status == .recording ? 0 : 1)
        .disabled(capture.status == .recording)
        .animation(.smooth(duration: 0.2), value: capture.status)
        .sheet(isPresented: $showingLibrary) {
            VideoLibraryPicker { provider in
                showingLibrary = false
                importVideo(provider)
            } onCancel: {
                showingLibrary = false
            }
            .ignoresSafeArea()
        }
    }

    /// What sits over the black between picking a video and the attempt page. A
    /// recording is ingested in a moment and gets the bare spinner; a Photos import
    /// can mean an iCloud download, so it gets the bar it is actually filling and a
    /// way out.
    private var processingScreen: some View {
        VStack(spacing: 18) {
            if let importProgress {
                ProgressView(value: importProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 200)
                Text("Importing from Photos")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Cancel") {
                    importJob?.cancel()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 4)
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .animation(.smooth(duration: 0.2), value: importProgress == nil)
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

    /// Pulls the picked video out of Photos and hands it to the same ingest the camera
    /// uses. Cancelling — or a failed load — drops straight back to the camera; there
    /// is nothing half-saved to clean up.
    private func importVideo(_ provider: NSItemProvider) {
        phase = .processing
        importProgress = 0
        Task {
            let url = await copyOutOfLibrary(provider)
            importProgress = nil
            importJob = nil
            guard let url else {
                phase = .capture
                return
            }
            ingest(url: url, stoppedAt: Date())
        }
    }

    /// The file Photos hands back lives only until the completion handler returns, so
    /// it gets moved somewhere we own — a rename, not a second copy of the video.
    @MainActor
    private func copyOutOfLibrary(_ provider: NSItemProvider) async -> URL? {
        var observation: NSKeyValueObservation?
        let url: URL? = await withCheckedContinuation { continuation in
            let job = provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let mine = FileManager.default.temporaryDirectory
                    .appendingPathComponent("picked-\(UUID().uuidString).\(ext)")
                try? FileManager.default.removeItem(at: mine)
                do {
                    try FileManager.default.moveItem(at: url, to: mine)
                } catch {
                    guard (try? FileManager.default.copyItem(at: url, to: mine)) != nil else {
                        continuation.resume(returning: nil); return
                    }
                }
                continuation.resume(returning: mine)
            }
            observation = job.observe(\.fractionCompleted) { job, _ in
                Task { @MainActor in importProgress = job.fractionCompleted }
            }
            importJob = job
        }
        observation?.invalidate()
        return url
    }

    /// Moves the recording into permanent storage, saves it as an attempt, and shows
    /// the attempt's own page over it. The rest timer runs from `stoppedAt` — the
    /// moment the user hit stop, not the moment ingest ends — so the countdown the
    /// page opens on is already the real one.
    private func ingest(url: URL, stoppedAt: Date) {
        Task {
            let result = await VideoStore.ingest(recordingAt: url, attemptID: attemptID)
            await MainActor.run {
                onCapture(CapturedAttempt(
                    videoFilename: result.video,
                    thumbnailFilename: result.thumbnail,
                    duration: result.duration,
                    stoppedAt: stoppedAt
                ))
                withAnimation(.smooth(duration: 0.35)) {
                    stopwatch.start(120, from: stoppedAt)
                }
                phase = .review
            }
        }
    }
}

/// PHPicker rather than SwiftUI's `PhotosPicker`, for the one setting that decides how
/// long the wait is: `.current` hands over the file as it already sits on disk, where
/// the default re-encodes every video on its way out of the library.
private struct VideoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (NSItemProvider) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: VideoLibraryPicker

        init(_ parent: VideoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onCancel(); return
            }
            parent.onPick(provider)
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
