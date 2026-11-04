import SwiftUI

/// The row of actions along the bottom of a list.
///
/// Liquid Glass replaces the divider-and-strip this used to be: the list keeps
/// its full height and scrolls underneath, and the blur — not a hard line — is
/// what separates the two.
///
/// The bar is flush with the window edges rather than an inset floating pill.
/// A pill leaves a gap below it, and on macOS a `List` ignores
/// `scrollEdgeEffectStyle`, so nothing fades the row fragments that show
/// through that gap.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    /// Someone who has asked the system for less translucency has asked for
    /// a readable background, not a prettier one. Glass is the whole point
    /// of this bar, so the honest answer is to drop it rather than dilute it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                if reduceTransparency {
                    Rectangle().fill(.background)
                        .overlay(alignment: .top) { Divider() }
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: .rect)
    }
}
