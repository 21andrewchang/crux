import PhotosUI
import SwiftUI
import UIKit

/// Opened by tapping a climb heading: rename it and look back at every go you have
/// taken on it, across every session.
struct ClimbDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var climb: Climb
    var onDone: () -> Void

    @State private var isConfirmingDelete = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var showsOriginal = false
    /// The freshly picked photo, shown under the spinner before any files exist.
    @State private var previewImage: UIImage?

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
                    if climb.routeImageName != nil || isProcessing {
                        wallCard.plainRow()
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Add a wall photo", systemImage: "photo.badge.plus")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .plainRow()
                    }
                } header: {
                    HStack {
                        Text("Wall")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if climb.routeImageName != nil, !isProcessing {
                            Text("\(climb.routeHoldCount) holds")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .confirmationDialog("Delete this climb?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Climb", role: .destructive, action: deleteClimb)
            } message: {
                Text("Attempts stay in their sessions; they just lose this climb.")
            }
            .presentationBackground(Color.black)
            .onChange(of: photoItem) { _, item in
                handlePickedPhoto(item)
            }
        }
    }

    private func deleteClimb() {
        WallStore.delete(climb)
        modelContext.delete(climb)
        try? modelContext.save()
        onDone()
    }

    // MARK: - Wall photo & hold detection

    /// The processed render, tap-toggling to the original photo underneath it. While a
    /// detection runs, whatever image is at hand sits dimmed under the spinner.
    private var wallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let image = displayedWallImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                if isProcessing {
                    Color.black.opacity(0.55)
                    ProgressView("Finding holds…")
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { showsOriginal.toggle() }

            HStack(spacing: 8) {
                colorChips
                Spacer()
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Replace Photo", systemImage: "photo")
                    }
                    Button("Remove Photo", systemImage: "trash", role: .destructive, action: removeWallPhoto)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var displayedWallImage: UIImage? {
        let url = showsOriginal ? climb.wallPhotoURL : climb.routeImageURL
        if let url, let image = UIImage(contentsOfFile: url.path) { return image }
        return previewImage
    }

    /// One dot per detectable color; tapping re-runs detection on the saved photo. The
    /// current route color is ringed, everything else sits dimmed.
    private var colorChips: some View {
        HStack(spacing: 8) {
            ForEach(HoldDetector.supportedColors, id: \.self) { name in
                let isSelected = name == climb.routeColorName
                Circle()
                    .fill(Self.chipColors[name] ?? .gray)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 2 : 0))
                    .opacity(isSelected ? 1 : 0.4)
                    .onTapGesture { redetect(with: name) }
            }
        }
    }

    private static let chipColors: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green,
        "blue": .blue, "purple": .purple, "pink": .pink,
    ]

    /// Detection color words map onto the same name convention the tag tint uses:
    /// "Blue V4" detects blue without asking. Off-palette words fold into the nearest
    /// detectable color; no color word at all defaults to yellow, one chip tap away.
    private var nameColor: String {
        let words: [String: String] = [
            "red": "red", "crimson": "red",
            "orange": "orange", "salmon": "orange",
            "yellow": "yellow", "gold": "yellow",
            "green": "green", "lime": "green", "mint": "green",
            "blue": "blue", "navy": "blue", "teal": "blue", "cyan": "blue",
            "aqua": "blue", "turquoise": "blue", "indigo": "blue",
            "purple": "purple", "violet": "purple",
            "pink": "pink", "magenta": "pink",
        ]
        for word in climb.name.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let color = words[String(word)] { return color }
        }
        return "yellow"
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoItem = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await detect(on: image, color: climb.routeColorName ?? nameColor)
        }
    }

    private func redetect(with color: String) {
        guard !isProcessing, color != climb.routeColorName,
              let url = climb.wallPhotoURL,
              let photo = UIImage(contentsOfFile: url.path) else { return }
        Task { await detect(on: photo, color: color) }
    }

    @MainActor
    private func detect(on photo: UIImage, color: String) async {
        isProcessing = true
        previewImage = photo
        showsOriginal = false
        let result = await Task.detached(priority: .userInitiated) {
            HoldDetector.detectRoute(in: photo, color: color)
        }.value
        if let result,
           let names = WallStore.save(photo: result.wallImage, route: result.routeImage, climbID: climb.id) {
            climb.wallPhotoName = names.photo
            climb.routeImageName = names.route
            climb.routeColorName = color
            climb.routeHoldCount = result.routeHoldCount
            try? modelContext.save()
        }
        previewImage = nil
        isProcessing = false
    }

    private func removeWallPhoto() {
        WallStore.delete(climb)
        climb.wallPhotoName = nil
        climb.routeImageName = nil
        climb.routeColorName = nil
        climb.routeHoldCount = 0
        try? modelContext.save()
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
