import SwiftUI

struct TagInputView: View {
    @Binding var tags: [String]
    let suggestions: [String]

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var filteredSuggestions: [String] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return suggestions
            .filter { $0.localizedCaseInsensitiveContains(trimmed) && !tags.contains($0) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tag chips
            if !tags.isEmpty {
                TagChipsView(tags: tags) { tag in
                    tags.removeAll { $0 == tag }
                }
            }

            // Input field + autocomplete
            ZStack(alignment: .topLeading) {
                TextField("Add tag...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit { commitCurrentInput() }

                // Suggestions overlay
                if !filteredSuggestions.isEmpty && isInputFocused {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "tag")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(suggestion)
                                        .font(.caption)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color.white)

                            if suggestion != filteredSuggestions.last {
                                Divider()
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .offset(y: 28)
                    .zIndex(10)
                }
            }
        }
    }

    private func commitCurrentInput() {
        addTag(inputText)
    }

    private func addTag(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            inputText = ""
            return
        }
        tags.append(trimmed)
        inputText = ""
    }
}

struct TagChipsView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        // Simple wrapping using ViewThatFits + LazyVStack fallback
        WrapLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                TagChip(label: tag) {
                    onRemove(tag)
                }
            }
        }
    }
}

struct TagChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}

/// Simple wrapping layout for tag chips
struct WrapLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
