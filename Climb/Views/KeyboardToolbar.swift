import SwiftUI

/// The bar that rides above the keyboard, Notes-style. Name what you are on, then
/// record goes on it.
struct KeyboardToolbar: View {
    var onAddClimb: () -> Void
    var onStartAttempt: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onAddClimb) {
                    Label("Climb", systemImage: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                }
                .buttonStyle(.glass)
                // The climb button carries its own label; the attempt button takes the
                // rest of the bar so the primary action stays the big target.
                .fixedSize()

                Button(action: onStartAttempt) {
                    Label("Attempt", systemImage: "video.fill")
                        .font(.system(size: 17, weight: .semibold))
                        // The pill is white, so its label has to invert.
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    KeyboardToolbar(onAddClimb: {}, onStartAttempt: {})
        .background(.gray.opacity(0.2))
}
