import SwiftUI

/// One row of coloured segments over a shared total, with the numbers spelled
/// out underneath. Used for memory, for the processor, and for the disk on the
/// overview, so the three read as the same kind of fact.
///
/// Deliberately chrome-less: it brings no background or padding of its own.
/// It used to, and placing it inside a card produced a container within a
/// container, with the card's own heading stranded outside the box it titled.
struct ResourceBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let color: Color
        let fraction: Double
        let caption: String
    }

    let headline: Text
    let warning: String?
    let segments: [Segment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                headline.font(.headline)
                Spacer()
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        Rectangle().fill(segment.color)
                            .frame(width: max(0, geometry.size.width * segment.fraction))
                    }
                    Rectangle().fill(.quinary)
                }
                .clipShape(.rect(cornerRadius: 4))
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.title).foregroundStyle(.secondary)
                        Text(segment.caption).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
    }
}

extension View {
    /// The one surface every panel in the app sits on, so panels in different
    /// sections cannot drift apart.
    func cardSurface(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}
