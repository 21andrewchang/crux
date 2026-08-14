import SwiftUI
import UIKit

/// Opened by tapping a climb heading: rename it and look back at every go you have
/// taken on it, across every session.
struct ClimbDetailView: View {
    @Bindable var climb: Climb
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: $climb.name)
                            .font(.largeTitle.weight(.bold))
                            .textInputAutocapitalization(.words)
                        if !climb.tags.isEmpty {
                            tagPills
                                .padding(.top, 6)
                        }
                    }
                    .plainRow()
                }

                Section {
                    if climb.attempts.isEmpty {
                        Text("No attempts recorded yet.")
                            .foregroundStyle(.secondary)
                            .plainRow()
                    } else {
                        ForEach(climb.orderedAttempts) { attempt in
                            historyRow(attempt).plainRow()
                        }
                    }
                } header: {
                    HStack {
                        Text("History")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(climb.summary)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .plainRow()
                }
            }
            .listStyle(.plain)
            .blackBackground()
            // No nav title: the climb's own name is the heading right below it.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone).fontWeight(.semibold)
                }
            }
            .presentationBackground(Color.black)
        }
    }

    /// Gray pills, one per tag. A plain HStack is fine while tags are a single
    /// placeholder; revisit with a wrapping layout when climbs carry more of them.
    private var tagPills: some View {
        HStack(spacing: 6) {
            ForEach(climb.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.25), in: Capsule())
            }
        }
    }

    private func historyRow(_ attempt: Attempt) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: attempt)
            VStack(alignment: .leading, spacing: 2) {
                Text(attempt.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text(detail(for: attempt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func thumbnail(for attempt: Attempt) -> some View {
        let image = attempt.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .frame(width: 46, height: 46)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "video.slash")
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detail(for attempt: Attempt) -> String {
        var parts = ["\(attempt.videoDuration.clockString) video"]
        if attempt.restSeconds > 0 { parts.append("rested \(attempt.restSeconds.clockString)") }
        let notes = attempt.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }
}
