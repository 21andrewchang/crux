import SwiftUI

/// The control that asks. Reads "Effort" until it has an answer, then wears the answer
/// in its own colour — so the page you land on after a go always says whether the
/// question has been dealt with.
struct EffortButton: View {
    let effort: Effort?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(effort?.color ?? Color.white.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(effort?.label ?? "Effort")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(effort?.color ?? .white)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: effort)
    }
}

/// The four words, in the middle of the screen.
///
/// Centred rather than hung off the button because this is the one question the page
/// asks, and it is asked with a video playing behind it — a menu in the corner reads as
/// a setting, and a sheet from the bottom is a whole screen for one tap.
struct EffortMenu: View {
    /// Whether the menu is up. The view stays in the hierarchy either way: the ground
    /// and the card answer to it separately, which is the only way each gets its own
    /// movement — one transition over the whole menu is one movement for both, and the
    /// ground ends up scaling in with the card.
    let isPresented: Bool
    let selection: Effort?
    /// Picking the answer already showing clears it: a rating tapped by mistake has to
    /// be takeable back, and there is nowhere else to take it back from.
    var onPick: (Effort?) -> Void
    var onDismiss: () -> Void

    /// How long the page takes to go down — slower than the card's arrival on purpose.
    private static let dim: TimeInterval = 0.1

    var body: some View {
        ZStack {
            // Always mounted, and animated by its own properties rather than by coming
            // and going: the page going dark is a change in the page itself, not a
            // sheet of black arriving over it.
            scrim

            // Over that ground, on its own beat — the card is what arrives.
            //
            // A real container, not a `Group`: a Group hands its modifiers to each
            // child rather than keeping them itself, so when the card is out there is
            // nothing left holding the animation and it snaps in.
            ZStack {
                if isPresented { card }
            }
            .animation(.bouncy(duration: 0.2), value: isPresented)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
    }

    /// Down to nearly black, but not all the way: the attempt stays visible behind the
    /// question being asked about it.
    private var scrim: some View {
        Color.black.opacity(isPresented ? 0.72 : 0)
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture(perform: onDismiss)
            .animation(.easeInOut(duration: Self.dim), value: isPresented)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Effort.allCases) { row($0) }
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: 360)
        // Not glass, on purpose. Glass is a lens: it takes its colour from whatever is
        // behind it, and behind this card is a blurred video, so it never settles into
        // one shade. The card the design copies is a plain dark panel with a hairline
        // of light around its edge — solid, so the words on it read the same over any
        // attempt — and the blur under it is what carries the depth.
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .padding(.horizontal, 28)
        // Grows into place from a tenth smaller, and nothing else — the card belongs
        // in the middle of the screen, so it arrives there rather than travelling.
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// What is being asked, and the way out of asking it. The ✕ is the same disc the
    /// player's own controls are drawn on, so closing this card feels like closing
    /// anything else on the page.
    private var header: some View {
        HStack {
            Text("Effort")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.14)))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 22)
        // Even with the card's top inset, so the disc sits square in the corner.
        .padding(.trailing, 18)
        .padding(.bottom, 12)
    }

    /// The colour on the left, the word beside it, and a tick when it is the answer —
    /// the words all read in white so the dot is the only thing carrying the scale.
    private func row(_ effort: Effort) -> some View {
        let picked = selection == effort

        return Button {
            Haptics.selection()
            onPick(picked ? nil : effort)
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(effort.color)
                    .frame(width: 20, height: 20)
                Text(effort.label)
                    .font(.system(size: 18, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .opacity(picked ? 1 : 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
