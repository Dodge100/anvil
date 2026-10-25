import SwiftUI

/// Searchable grid of SF Symbols.
/// Shared by every icon picker in the app so they all look and behave the same.
struct SymbolPickerView: View {
    /// Symbols to offer. Anything matching `query` is shown.
    let symbols: [String]
    @Binding var icon: String

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return symbols }
        return symbols.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                TextField("Search icons", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
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
            .padding(10)

            Divider()

            ScrollView {
                if filtered.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6),
                        spacing: 4
                    ) {
                        ForEach(filtered, id: \.self) { name in
                            Button {
                                icon = name
                                dismiss()
                            } label: {
                                Image(systemName: name)
                                    .font(.body)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        name == icon
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 264, height: 320)
        .onAppear { searchFocused = true }
    }
}
