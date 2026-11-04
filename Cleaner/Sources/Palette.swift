import SwiftUI

/// The app's own surface.
///
/// A gradient in the register the reference uses, in the blue the app icon
/// already is — not the reference's purple. Taking another product's exact
/// brand colour and illustrations is how an app ends up looking like a
/// counterfeit of the thing it was merely inspired by.
enum Palette {
    static func window(_ scheme: ColorScheme, plain: Bool) -> AnyShapeStyle {
        // Someone who asked the system for less translucency asked for a
        // readable background, and a gradient is the opposite of that.
        if plain {
            return AnyShapeStyle(scheme == .dark
                                 ? Color(red: 0.07, green: 0.09, blue: 0.16)
                                 : Color(red: 0.95, green: 0.96, blue: 0.99))
        }

        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.05, green: 0.07, blue: 0.16),
               Color(red: 0.08, green: 0.14, blue: 0.34),
               Color(red: 0.05, green: 0.08, blue: 0.19)]
            : [Color(red: 0.93, green: 0.95, blue: 1.00),
               Color(red: 0.86, green: 0.90, blue: 0.99),
               Color(red: 0.95, green: 0.96, blue: 1.00)]

        return AnyShapeStyle(LinearGradient(colors: colors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing))
    }

    /// Panels float on the window rather than being painted on it, so the
    /// gradient stays visible through them and the two read as one surface.
    static func panel(_ plain: Bool) -> AnyShapeStyle {
        plain ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.ultraThinMaterial)
    }
}

/// The mark on the overview: the app icon's own motif — a plate and a wand —
/// drawn large. Ours, so there is nothing borrowed about it.
struct HeroMark: View {
    var size: CGFloat = 148

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.36, green: 0.66, blue: 1.00),
                             Color(red: 0.04, green: 0.36, blue: 0.82)],
                    startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(-8))
                .shadow(color: Color(red: 0.10, green: 0.40, blue: 0.95).opacity(0.45),
                        radius: 24, y: 10)

            Image(systemName: "wand.and.sparkles")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .shadow(radius: 6, y: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
