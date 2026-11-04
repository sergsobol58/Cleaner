import SwiftUI

/// One row of coloured segments over a shared total, with the numbers
/// spelled out underneath. Used for memory, for the processor, and for the
/// disk on the overview, so the three read as the same kind of fact.
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
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
