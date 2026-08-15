import SwiftData
import SwiftUI

/// Type the climb's name. Anything you have already saved filters as you go; if the
/// name is new, the last row makes it. One field, no form.
struct ClimbPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var climbs: [Climb]

    var onPick: (Climb) -> Void

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [Climb] {
        let sorted = Climb.recencySorted(climbs)
        guard !trimmedQuery.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Typing the exact name of a saved climb should offer that climb, not a duplicate.
    private var exactMatch: Climb? {
        climbs.first { $0.name.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    private var canCreate: Bool {
        !trimmedQuery.isEmpty && exactMatch == nil
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches) { climb in
                    Button { pick(climb) } label: { row(for: climb) }
                        .buttonStyle(.plain)
                        .plainRow()
                }
                .onDelete(perform: delete)

                if canCreate {
                    Button(action: create) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                            Text("Create new climb \"\(trimmedQuery)\"")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .contentShape(.rect)
                        .padding(.vertical, 6)
                        // Line the plus up under the search field's magnifying glass
                        // (16 outer + 14 capsule padding).
                        .padding(.leading, 30)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                }
            }
            .listStyle(.plain)
            .blackBackground()
            .overlay {
                if matches.isEmpty && !canCreate {
                    ContentUnavailableView {
                        Label("No Climbs Yet", systemImage: "figure.climbing")
                    } description: {
                        Text("Type a name to save the one you're on.")
                    }
                }
            }
            .safeAreaInset(edge: .top) { searchField }
            .navigationTitle("Climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationBackground(Color.black)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Name of the climb", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($fieldFocused)
                .onSubmit(submit)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.surface, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color.black)
        .task { fieldFocused = true }
    }

    private func row(for climb: Climb) -> some View {
        HStack {
            Text(climb.name)
                .font(.body.weight(.medium))
            Spacer()
            Text(climb.attempts.isEmpty
                 ? "No attempts"
                 : "\(climb.attempts.count) attempt\(climb.attempts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
    }

    /// Return picks the obvious thing: the exact name if it exists, the top match if
    /// there is only one, otherwise a new climb.
    private func submit() {
        guard !trimmedQuery.isEmpty else { return }
        if let exactMatch {
            pick(exactMatch)
        } else if matches.count == 1, let only = matches.first {
            pick(only)
        } else {
            create()
        }
    }

    private func create() {
        let climb = Climb(name: trimmedQuery)
        modelContext.insert(climb)
        try? modelContext.save()
        pick(climb)
    }

    private func pick(_ climb: Climb) {
        onPick(climb)
        dismiss()
    }

    private func delete(_ offsets: IndexSet) {
        let rows = matches
        for index in offsets {
            modelContext.delete(rows[index])
        }
        try? modelContext.save()
    }
}
