import UIKit

/// Spins a heading's fold chevron between down and right instead of flipping it
/// there in one frame.
///
/// The animation cannot live on the fragment that draws the chevron: a fold is a
/// restyle, and a restyle throws every fragment away and vends new ones. So it lives
/// here, keyed by the heading line's start offset, and each fragment reads its own
/// progress as it is vended. Folding never touches the text, so those offsets hold
/// still for the length of a spin.
final class FoldAnimator {
    private struct Spin {
        let from: CGFloat
        let to: CGFloat
        var elapsed: CFTimeInterval
    }

    private static let duration: CFTimeInterval = 0.24

    private var spins: [Int: Spin] = [:]
    private weak var textView: NoteTextView?
    private var link: CADisplayLink?

    deinit { link?.invalidate() }

    /// Where a heading's chevron points right now: mid-spin if it is spinning,
    /// otherwise wherever its fold state rests it.
    func progress(forLineAt location: Int, folded: Bool) -> CGFloat {
        spins[location].map(value(of:)) ?? (folded ? 1 : 0)
    }

    /// Starts the heading at `location` turning towards `folded`. Called once the
    /// fold itself has landed, so the chevron catches up with the group it describes.
    func spin(lineAt location: Int, to folded: Bool, in textView: NoteTextView) {
        let target: CGFloat = folded ? 1 : 0
        let current = spins[location].map(value(of:)) ?? 1 - target
        guard current != target else { return }
        spins[location] = Spin(from: current, to: target, elapsed: 0)
        self.textView = textView
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func value(of spin: Spin) -> CGFloat {
        let time = min(1, CGFloat(spin.elapsed / Self.duration))
        // Leaves fast and settles, the way the group under it drops away.
        let eased = 1 - pow(1 - time, 3)
        return spin.from + (spin.to - spin.from) * eased
    }

    @objc private func tick(_ link: CADisplayLink) {
        let step = link.targetTimestamp - link.timestamp
        for (location, spin) in spins {
            var spin = spin
            spin.elapsed += step
            // Dropped on the last frame, not held at 1: with no spin on file the
            // fragment falls back to its fold state, which says the same thing.
            spins[location] = spin.elapsed >= Self.duration ? nil : spin
            textView?.redrawFragment(onLineAt: location)
        }
        if spins.isEmpty || textView == nil { stop() }
    }

    /// Nothing left to turn — and a display link holds its target, so it has to go.
    private func stop() {
        link?.invalidate()
        link = nil
    }
}
