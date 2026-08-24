import SwiftUI

/// What the search field turns the list into.
///
/// Not a shorter list of sessions — the things themselves. A climb, a clip, a line, in
/// that order, each said where it was written and each opening at exactly that place:
/// a climb opens the page it is named on, a clip opens its attempt parked at the
/// moment it marks. Sessions come last, because the field is far more often used to
/// find something inside a note than to find a note.
struct SearchResultsView: View {
    let terms: SearchTerms
    let results: [SearchResult]

    var body: some View {
        List {
            ForEach(SearchResult.Kind.allCases, id: \.self) { kind in
                let rows = results.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { result in
                            NavigationLink {
                                SessionDetailView(session: result.session, opening: result.opening)
                            } label: {
                                row(result)
                            }
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            // Zero leading lines the header up with the card's edge
                            // and the navigation title, as the week headers do.
                            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func row(_ result: SearchResult) -> some View {
        switch result.kind {
        case .climb, .session: nameRow(result)
        case .clip, .note: quoteRow(result)
        }
    }

    /// A thing with a name: the name is the answer, and what it belongs to is said
    /// under it. The climb's dot is the same mark it carries in the note.
    private func nameRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let name = result.climbName {
                    Circle()
                        .fill(Color(ClimbTint.color(for: name)).opacity(NoteDocument.headerTintAlpha))
                        .frame(width: 7, height: 7)
                        // Baseline-aligned text puts a dot on the cap line; this drops
                        // it to the middle of the word beside it.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                Text(marked(result.text, font: .headline))
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let trailing = result.trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.quaternary)
                }
            }
            Text(result.context)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    /// Something written: where it was written first, small, then the line itself with
    /// the words that were searched for marked in it. A clip carries the note's own
    /// bookmark before it and its clock at the trailing edge — the same shape the line
    /// has on the page it came from.
    private func quoteRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.context)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if result.kind == .clip {
                    Image(systemName: "bubble.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(marked(result.text, font: .body))
                    .font(.body)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if let trailing = result.trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The words that were typed, marked where they landed. A wash of the app's yellow
    /// rather than a bold run: the line has to still read as the line it is, with the
    /// query pointed at inside it.
    private func marked(_ text: String, font: Font) -> AttributedString {
        var attributed = AttributedString(text)
        for range in terms.ranges(in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].font = font.weight(.semibold)
            attributed[lower..<upper].foregroundColor = .paper
            attributed[lower..<upper].backgroundColor = Color.routeHold.opacity(0.24)
        }
        return attributed
    }
}

private extension SearchResult {
    /// Where the note this result came from should open — the page, the thing on it,
    /// and for a clip the attempt and moment it marks.
    var opening: SessionOpening {
        SessionOpening(tab: tab, reveal: reveal, attemptID: attemptID, start: start)
    }

    /// The place in the note this result stands for. A session found by its own name
    /// is the one result that is not a place inside a note: it opens as a note does.
    var reveal: NoteReveal? {
        switch kind {
        case .climb: climbName.map(NoteReveal.climb)
        case .clip: attemptID.map(NoteReveal.attempt)
        case .note: .line(text)
        case .session: nil
        }
    }
}
