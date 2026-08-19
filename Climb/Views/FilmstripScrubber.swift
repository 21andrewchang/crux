import AVFoundation
import SwiftUI
import UIKit

/// The playbar's coarse scrubber's opposite number: the video itself as a filmstrip,
/// scrolling under a playhead nailed to the centre.
///
/// A second of video is a fixed, generous distance — about 140pt — so a single frame
/// is roughly 5pt of thumb travel rather than a fraction of one. Because it's a real
/// scroll view, a flick coasts: reaching across the clip and creeping a frame at a
/// time are the same gesture at different speeds. The white bar below stays the way
/// to jump anywhere at once; this is the way to land exactly.
/// A stretch of the video one note is about. A note that names a single moment is
/// one of these too, with both ends on the same frame.
struct ClipMark: Equatable {
    var start: TimeInterval
    var end: TimeInterval

    /// Where the note's bubble sits: over the middle of what the note is about.
    var centre: TimeInterval { (start + end) / 2 }
    var isClip: Bool { end > start + 0.005 }
}

struct FilmstripScrubber: UIViewRepresentable {
    let videoURL: URL?
    let duration: TimeInterval
    /// Where the player is. Pushed into the strip only when the strip isn't the one
    /// doing the moving.
    let time: TimeInterval
    let isPlaying: Bool
    /// Every note: a bubble over the middle of its stretch, and a band across the
    /// frames the stretch covers.
    let bookmarks: [ClipMark]
    /// The open note's stretch, the one with handles on it.
    var editing: ClipMark? = nil
    var onClipChanged: (ClipMark) -> Void = { _ in }
    var onScrubBegan: () -> Void = { }
    var onScrub: (TimeInterval) -> Void = { _ in }
    var onScrubEnded: () -> Void = { }
    var onBookmarkTap: (TimeInterval) -> Void = { _ in }
    /// True from the finger landing until the strip finally coasts to a stop — the
    /// window in which it's worth being big.
    var onActiveChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> FilmstripView { FilmstripView() }

    func updateUIView(_ view: FilmstripView, context: Context) {
        view.onScrubBegan = onScrubBegan
        view.onScrub = onScrub
        view.onScrubEnded = onScrubEnded
        view.onBookmarkTap = onBookmarkTap
        view.onActiveChanged = onActiveChanged
        view.onClipChanged = onClipChanged
        view.configure(videoURL: videoURL, duration: duration)
        view.setBookmarks(bookmarks, editing: editing)
        view.showTime(time, playing: isPlaying)
    }
}

/// The strip itself: a scroll view of stills with the playhead fixed at its centre.
final class FilmstripView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onScrubBegan: () -> Void = { }
    var onScrub: (TimeInterval) -> Void = { _ in }
    var onScrubEnded: () -> Void = { }
    var onBookmarkTap: (TimeInterval) -> Void = { _ in }
    var onActiveChanged: (Bool) -> Void = { _ in }
    var onClipChanged: (ClipMark) -> Void = { _ in }

    private let scrollView = UIScrollView()
    private let content = PassthroughView()
    /// Layers inside the content, in this order, because a view added later draws over
    /// one added earlier — and the tiles get rebuilt whenever the strip is resized.
    /// They span the whole strip, so they have to be the kind of view that doesn't
    /// answer for a touch that missed everything inside it.
    private let tileLayer = PassthroughView()
    private let bandLayer = PassthroughView()
    private let pinLayer = PassthroughView()
    private let handleLayer = PassthroughView()
    private let startHandle = UIView()
    private let endHandle = UIView()
    /// The open note's band and bubble are drawn from the local `editing` value rather
    /// than from `bookmarks`, so they follow a handle as it moves instead of catching
    /// up when the finger lifts.
    private let editingBand = UIView()
    private let editingPin = BookmarkPin()
    private let playhead = UIView()

    private var videoURL: URL?
    private var duration: TimeInterval = 0
    private var bookmarks: [ClipMark] = []
    private var tiles: [UIImageView] = []
    private var bookmarkViews: [BookmarkPin] = []
    private var bands: [ClipBand] = []
    /// The stretch the handles are on. Local while a handle is being dragged: the
    /// finger is the truth then, and the value coming back down from the note is a
    /// frame behind it.
    private var editing: ClipMark?
    private var draggingHandle: UIView?
    /// The last moment a drag actually reported. A finger crosses a frame every few
    /// points at this zoom, and every report costs a seek and a pass through SwiftUI;
    /// repeating one the picture is already on buys nothing.
    private var lastReported: TimeInterval?

    /// The moment the strip is showing. Kept so a resize can put the playhead back on
    /// the same moment instead of wherever the old offset now points.
    private var shownTime: TimeInterval = 0
    /// True from the moment a finger lands until the strip has fully coasted to a
    /// stop — a touch counts, not just a drag, so it grows the instant it's reached
    /// for. While it's set the player's own clock is ignored: the strip is ahead of
    /// it by design, and letting the echo in would fight the scroll.
    private var isActive = false
    /// A finger is on the strip. Tracked apart from the scroll view's own dragging,
    /// which only starts once the touch has actually moved.
    private var isTouched = false
    /// A frame at this video's rate. Every reported moment is snapped to one, so a
    /// scrub lands on a frame the picture can actually show.
    private var frameDuration: TimeInterval = 1.0 / 30
    private var lastHapticFrame = -1
    private var lastHapticAt: CFTimeInterval = 0
    private let haptics = UISelectionFeedbackGenerator()
    private var thumbnailTask: Task<Void, Never>?
    /// What the loaded stills are of. A relayout that doesn't change this leaves the
    /// strip alone rather than regenerating every tile.
    private var thumbnailKey: String?

    private let tileWidth: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.decelerationRate = .normal
        scrollView.clipsToBounds = true
        scrollView.layer.cornerRadius = 10
        scrollView.layer.cornerCurve = .continuous
        scrollView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        scrollView.delegate = self
        addSubview(scrollView)
        scrollView.addSubview(content)
        content.addSubview(tileLayer)
        content.addSubview(bandLayer)
        content.addSubview(pinLayer)
        content.addSubview(handleLayer)

        style(band: editingBand)
        bandLayer.addSubview(editingBand)
        editingPin.image = Self.pinGlyph
        editingPin.tintColor = .systemYellow
        editingPin.contentMode = .center
        style(shadowOn: editingPin.layer)
        editingPin.isHidden = true
        pinLayer.addSubview(editingPin)

        for (handle, chevron) in [(startHandle, "chevron.compact.left"),
                                  (endHandle, "chevron.compact.right")] {
            // A grip, the way every trimmer marks one: the chevron points at the way
            // the end travels.
            let grip = UIImageView(image: UIImage(
                systemName: chevron,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)))
            grip.tintColor = .black
            grip.contentMode = .center
            grip.tag = 1
            handle.addSubview(grip)

            // Solid, not a tint over the frames: a handle is a thing you grab, and a
            // see-through one reads as decoration on the video behind it.
            handle.backgroundColor = UIColor(red: 1, green: 0.84, blue: 0.16, alpha: 1)
            handle.layer.cornerRadius = 3
            handle.layer.cornerCurve = .continuous
            handle.layer.shadowColor = UIColor.black.cgColor
            handle.layer.shadowOpacity = 0.45
            handle.layer.shadowRadius = 3
            handle.layer.shadowOffset = CGSize(width: 0, height: 1)
            handle.isHidden = true
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                               action: #selector(handleDragged(_:))))
            handleLayer.addSubview(handle)
        }

        playhead.backgroundColor = .white
        playhead.layer.cornerRadius = 1.5
        playhead.layer.shadowColor = UIColor.black.cgColor
        playhead.layer.shadowOpacity = 0.55
        playhead.layer.shadowRadius = 3
        playhead.layer.shadowOffset = CGSize(width: 0, height: 1)
        playhead.isUserInteractionEnabled = false
        addSubview(playhead)

        // A press of no duration is just "a finger is here" — enough to wake the
        // strip up before the touch has moved far enough to count as a scroll.
        let touch = UILongPressGestureRecognizer(target: self, action: #selector(touchChanged(_:)))
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delaysTouchesBegan = false
        touch.delegate = self
        scrollView.addGestureRecognizer(touch)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let pinGlyph = UIImage(
        systemName: "text.bubble.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))

    private func style(band: UIView) {
        band.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.22)
        band.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.8).cgColor
        band.layer.borderWidth = 1.5
        band.layer.cornerRadius = 4
    }

    private func style(shadowOn layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    // MARK: Geometry

    /// How much thumb travel one second of video is worth. Fixed and generous for the
    /// short clips this is really for, eased off for long ones so the strip stays
    /// flickable end to end.
    private var pointsPerSecond: CGFloat {
        guard duration > 0 else { return 140 }
        return min(140, max(40, 6000 / CGFloat(duration)))
    }

    private var tileSeconds: TimeInterval { TimeInterval(tileWidth / pointsPerSecond) }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        playhead.frame = CGRect(x: (bounds.width / 2) - 1.5, y: 0, width: 3, height: bounds.height)
        layoutStrip()
    }

    private func layoutStrip() {
        guard bounds.width > 0 else { return }
        let contentWidth = CGFloat(duration) * pointsPerSecond
        content.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        for layer in [tileLayer, bandLayer, pinLayer, handleLayer] { layer.frame = content.bounds }
        scrollView.contentSize = content.frame.size
        // Half a screen of inset at each end is what lets the first and last frame
        // reach the centre playhead.
        let inset = bounds.width / 2
        scrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)

        rebuildTilesIfNeeded()
        for (index, tile) in tiles.enumerated() {
            let x = CGFloat(index) * tileWidth
            tile.frame = CGRect(x: x, y: 0, width: min(tileWidth, contentWidth - x), height: bounds.height)
        }
        layoutBookmarks()
        layoutClips()
        // The offset means nothing after a resize; the moment does.
        if !isActive { applyOffset(for: shownTime, animated: false, duration: 0) }
    }

    private func rebuildTilesIfNeeded() {
        guard duration > 0, tileSeconds > 0 else { return }
        // Long clips scroll slower per second, so the count stays bounded on its own;
        // the cap is only a backstop against a runaway duration.
        let wanted = min(240, max(1, Int(ceil(CGFloat(duration) * pointsPerSecond / tileWidth))))
        let key = "\(videoURL?.path ?? "")|\(wanted)"
        guard key != thumbnailKey else { return }
        thumbnailKey = key

        tiles.forEach { $0.removeFromSuperview() }
        tiles = (0..<wanted).map { _ in
            let tile = UIImageView()
            tile.contentMode = .scaleAspectFill
            tile.clipsToBounds = true
            tile.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            tileLayer.addSubview(tile)
            return tile
        }
        loadThumbnails()
    }

    private func layoutBookmarks() {
        for pin in bookmarkViews {
            // Over the middle of what the note is about, not its first frame. Full
            // height with the glyph centred: the strip is short enough that a
            // fixed-size marker would be clipped by the scroll view's own bounds.
            pin.frame = CGRect(x: CGFloat(pin.centre) * pointsPerSecond - 13, y: 0,
                               width: 26, height: bounds.height)
        }
    }

    /// A band per clip, and — on the open note's — a handle at each end. The handles
    /// are wider than they look: a 6pt bar with a 24pt grab area around it, or trimming
    /// a clip would need the same precision the strip exists to avoid needing.
    private func layoutClips() {
        let handleWidth: CGFloat = 24
        let clips = bookmarks.filter(\.isClip)

        while bands.count < clips.count {
            let band = ClipBand()
            style(band: band)
            // The whole stretch opens the note, not just the bubble over it.
            band.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                             action: #selector(bandTapped(_:))))
            bandLayer.addSubview(band)
            bands.append(band)
        }
        for (index, band) in bands.enumerated() {
            guard index < clips.count else {
                band.isHidden = true
                continue
            }
            let clip = clips[index]
            band.isHidden = false
            band.stamp = clip.start
            band.frame = frame(from: clip.start, to: clip.end)
        }

        guard let editing else {
            editingBand.isHidden = true
            editingPin.isHidden = true
            startHandle.isHidden = true
            endHandle.isHidden = true
            return
        }
        editingBand.isHidden = !editing.isClip
        editingBand.frame = frame(from: editing.start, to: editing.end)
        editingPin.isHidden = false
        editingPin.frame = CGRect(x: CGFloat(editing.centre) * pointsPerSecond - 13, y: 0,
                                  width: 26, height: bounds.height)
        startHandle.isHidden = false
        endHandle.isHidden = false
        for (handle, moment) in [(startHandle, editing.start), (endHandle, editing.end)] {
            handle.frame = CGRect(x: CGFloat(moment) * pointsPerSecond - handleWidth / 2, y: 0,
                                  width: handleWidth, height: bounds.height)
            handle.viewWithTag(1)?.frame = handle.bounds
        }
    }

    private func frame(from start: TimeInterval, to end: TimeInterval) -> CGRect {
        CGRect(x: CGFloat(start) * pointsPerSecond, y: 0,
               width: CGFloat(end - start) * pointsPerSecond, height: bounds.height)
    }

    @objc private func bandTapped(_ recognizer: UITapGestureRecognizer) {
        guard let band = recognizer.view as? ClipBand else { return }
        onBookmarkTap(band.stamp)
    }

    @objc private func handleDragged(_ recognizer: UIPanGestureRecognizer) {
        guard var editing, let handle = recognizer.view else { return }

        switch recognizer.state {
        case .began:
            // The strip must hold still while an end is being placed on it, or the
            // frames slide out from under the handle the finger is holding.
            draggingHandle = handle
            lastReported = nil
            scrollView.isScrollEnabled = false
            refreshActive()
        default:
            break
        }

        let shift = TimeInterval(recognizer.translation(in: self).x / pointsPerSecond)
        recognizer.setTranslation(.zero, in: self)

        // The handle itself tracks the finger exactly. Snapping where it is *drawn* to
        // whole frames is what made it catch: a frame is only a few points wide here,
        // so the bar jumped between them instead of following the thumb.
        if handle === startHandle {
            editing.start = min(max(editing.start + shift, 0), editing.end)
        } else {
            editing.end = min(max(editing.end + shift, editing.start), duration)
        }
        self.editing = editing
        layoutClips()

        // The moment that leaves here is on a frame, though, and it only leaves when
        // it changes — one seek and one pass through SwiftUI per frame crossed, not
        // per touch delivered.
        let dragged = handle === startHandle ? editing.start : editing.end
        let moment = quantizedToFrame(dragged)
        let settling = recognizer.state == .ended || recognizer.state == .cancelled

        if moment != lastReported || settling {
            lastReported = moment
            shownTime = moment
            var reported = editing
            if handle === startHandle { reported.start = moment } else { reported.end = moment }
            onClipChanged(reported)
            onScrub(moment)
        }

        switch recognizer.state {
        case .ended, .cancelled, .failed:
            // Off the finger and onto the frame it chose.
            if handle === startHandle { editing.start = moment } else { editing.end = moment }
            self.editing = editing
            layoutClips()
            draggingHandle = nil
            scrollView.isScrollEnabled = true
            refreshActive()
        default:
            break
        }
    }

    // MARK: Input from SwiftUI

    func configure(videoURL: URL?, duration: TimeInterval) {
        let changed = videoURL != self.videoURL || abs(duration - self.duration) > 0.001
        guard changed else { return }
        self.videoURL = videoURL
        self.duration = max(duration, 0)
        loadFrameRate()
        setNeedsLayout()
    }

    func setBookmarks(_ marks: [ClipMark], editing mark: ClipMark?) {
        // Mid-drag the handle is the truth; what comes back down from the note is a
        // frame behind the finger.
        guard draggingHandle == nil else { return }
        guard marks != bookmarks || mark != editing else { return }
        let sameMarks = marks == bookmarks
        bookmarks = marks
        editing = mark
        guard !sameMarks else {
            layoutClips()
            return
        }

        bookmarkViews.forEach { $0.removeFromSuperview() }
        bookmarkViews = marks.map { mark in
            let pin = BookmarkPin(image: Self.pinGlyph)
            pin.stamp = mark.start
            pin.centre = mark.centre
            pin.tintColor = .systemYellow
            pin.contentMode = .center
            pin.isUserInteractionEnabled = true
            // The same marker as the one on the line below, to the point: a bubble
            // that reads as a different object on each scrubber is two bookmarks, not
            // one moment seen twice.
            style(shadowOn: pin.layer)
            pin.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bookmarkTapped(_:))))
            pinLayer.addSubview(pin)
            return pin
        }
        layoutBookmarks()
        layoutClips()
    }

    /// Parks the strip on a moment reached elsewhere — playback, or a drag on the
    /// white bar. Playback arrives in ticks a twentieth of a second apart, which would
    /// march the strip in visible steps, so a forward step gets animated flat across
    /// the gap it covers.
    func showTime(_ time: TimeInterval, playing: Bool) {
        guard !isActive, bounds.width > 0, duration > 0 else { return }
        let step = time - shownTime
        guard abs(step) > 0.0005 else { return }
        shownTime = min(max(time, 0), duration)
        let smooth = playing && step > 0 && step < 0.5
        applyOffset(for: shownTime, animated: smooth, duration: step)
    }

    private func applyOffset(for time: TimeInterval, animated: Bool, duration step: TimeInterval) {
        let target = CGPoint(x: CGFloat(time) * pointsPerSecond - bounds.width / 2, y: 0)
        guard animated else {
            scrollView.layer.removeAllAnimations()
            scrollView.setContentOffset(target, animated: false)
            return
        }
        UIView.animate(withDuration: step, delay: 0,
                       options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
            self.scrollView.contentOffset = target
        }
    }

    @objc private func bookmarkTapped(_ recognizer: UITapGestureRecognizer) {
        guard let pin = recognizer.view as? BookmarkPin else { return }
        onBookmarkTap(pin.stamp)
    }

    // MARK: Scrolling is scrubbing

    @objc private func touchChanged(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed: isTouched = true
        default: isTouched = false
        }
        refreshActive()
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Playback's glide is mid-flight; take the strip back at wherever it visually
        // is, or the offset snaps to the animation's end the moment the finger lands.
        if let live = scrollView.layer.presentation()?.bounds.origin {
            scrollView.layer.removeAllAnimations()
            scrollView.contentOffset = live
        }
        refreshActive()
    }

    /// Awake for as long as the strip is anybody's business: a finger resting on it, a
    /// drag, or the coast afterwards. The finger lifting mid-flick doesn't end it —
    /// the strip is still moving, and shrinking out from under a moving picture is
    /// exactly what would read as a glitch.
    private func refreshActive() {
        let active = isTouched || draggingHandle != nil
            || scrollView.isDragging || scrollView.isDecelerating
        guard active != isActive else { return }
        isActive = active
        if active {
            haptics.prepare()
            lastHapticFrame = -1
            onScrubBegan()
        } else {
            onScrubEnded()
        }
        onActiveChanged(active)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard duration > 0, bounds.width > 0 else { return }
        // A programmatic offset — playback, or the white bar being dragged — comes
        // through here too, and it isn't a scrub.
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else { return }
        let raw = TimeInterval((scrollView.contentOffset.x + bounds.width / 2) / pointsPerSecond)
        let time = quantizedToFrame(min(max(raw, 0), duration))
        guard abs(time - shownTime) > 0.0001 else { return }
        shownTime = time
        tickHaptic(at: time)
        onScrub(time)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { refreshActive() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { refreshActive() }

    /// One click per frame crossed, so a slow drag can be counted by feel. Rate-limited
    /// because a fast flick crosses hundreds of frames and the taptic engine would
    /// either fall behind or buzz.
    private func tickHaptic(at time: TimeInterval) {
        let frame = Int((time / frameDuration).rounded())
        guard frame != lastHapticFrame else { return }
        lastHapticFrame = frame
        let now = CACurrentMediaTime()
        guard now - lastHapticAt > 0.035 else { return }
        lastHapticAt = now
        haptics.selectionChanged()
    }

    private func quantizedToFrame(_ time: TimeInterval) -> TimeInterval {
        guard frameDuration > 0 else { return time }
        return (time / frameDuration).rounded() * frameDuration
    }

    // MARK: Loading

    private func loadFrameRate() {
        guard let videoURL else { return }
        Task {
            let asset = AVURLAsset(url: videoURL)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let rate = try? await track.load(.nominalFrameRate), rate > 0
            else { return }
            frameDuration = TimeInterval(1.0 / rate)
        }
    }

    private func loadThumbnails() {
        thumbnailTask?.cancel()
        guard let videoURL, duration > 0 else { return }
        let count = tiles.count
        let seconds = tileSeconds
        thumbnailTask = Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)
            // These are context, not the frame the playhead is on — a frame either
            // side is free speed.
            let slack = CMTime(seconds: seconds / 2, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = slack
            generator.requestedTimeToleranceAfter = slack
            for index in 0..<count {
                guard !Task.isCancelled else { return }
                let at = CMTime(seconds: (Double(index) + 0.5) * seconds, preferredTimescale: 600)
                guard let frame = try? await generator.image(at: at) else { continue }
                guard !Task.isCancelled, let self, index < self.tiles.count else { return }
                self.tiles[index].image = UIImage(cgImage: frame.image)
            }
        }
    }
}

/// A note's marker on the strip, carrying the moment it stands for so a tap can open
/// that note.
final class BookmarkPin: UIImageView {
    /// The moment a tap opens — the note's start, not where the bubble is drawn.
    var stamp: TimeInterval = 0
    var centre: TimeInterval = 0
}

/// A clip's stretch on the strip, carrying the note it belongs to so a tap anywhere
/// along it opens that note.
final class ClipBand: UIView {
    var stamp: TimeInterval = 0
}

/// A container that is only ever its contents. A plain full-width `UIView` answers
/// `hitTest` for every point inside it even with nothing drawn there, so the topmost
/// of these layers would quietly swallow every tap meant for a band underneath it.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Zero-tolerance seeks are the only ones that land on the frame that was asked for,
/// but they queue: firing one per scroll callback leaves the picture running seconds
/// behind the thumb. This keeps a single seek in flight and always chases the newest
/// target, dropping every moment scrubbed past in between.
final class FrameSeeker {
    private var isSeeking = false
    private var pending: TimeInterval?

    func seek(_ player: AVPlayer, to time: TimeInterval) {
        pending = time
        guard !isSeeking else { return }
        drain(player)
    }

    private func drain(_ player: AVPlayer) {
        guard let target = pending else {
            isSeeking = false
            return
        }
        pending = nil
        isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.drain(player) }
        }
    }
}
