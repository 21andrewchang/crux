import AVKit
import SwiftUI

/// Opened by tapping an inline row: replay the attempt and refine the notes.
struct AttemptDetailView: View {
    @Bindable var attempt: Attempt
    let ordinal: Int
    var onDelete: () -> Void
    var onDone: () -> Void

    @State private var player = AVPlayer()
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if attempt.videoURL != nil {
                        VideoPlayer(player: player)
                            .aspectRatio(9 / 16, contentMode: .fit)
                            .frame(maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    HStack(spacing: 0) {
                        stat("Video", attempt.videoDuration.clockString, "video.fill")
                        stat("Rest", attempt.restSeconds.clockString, "timer")
                    }
                    .padding(.vertical, 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("What happened on this go?", text: $attempt.notes, axis: .vertical)
                            .lineLimit(3...10)
                            .padding(14)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Delete Attempt", role: .destructive) { isConfirmingDelete = true }
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Attempt \(ordinal)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone).fontWeight(.semibold)
                }
            }
            .alert("Delete this attempt?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: onDelete)
            } message: {
                Text("The video will not be deleted.")
            }
        }
        .task {
            guard let url = attempt.videoURL else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
    }

    private func stat(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}
