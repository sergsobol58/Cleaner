import SwiftUI

/// Search, in the content area rather than the toolbar.
///
/// The guidelines put search in the toolbar, and that is where it belongs on
/// a Mac. It is not where it can go here: a search field changes the
/// toolbar's height, and `NavigationSplitView` does not re-inset the sidebar
/// when it does — the sidebar's first row rides up under the window
/// controls. Three screenshots agreed, and the one screen without a search
/// field was the one screen that looked right.
///
/// A guideline that visibly breaks the window loses to the window.
struct SearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: .capsule)
        .overlay {
            Capsule().strokeBorder(.tint.opacity(isFocused ? 0.6 : 0), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
