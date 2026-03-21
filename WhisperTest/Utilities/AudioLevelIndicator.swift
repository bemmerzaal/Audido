import SwiftUI

struct AudioLevelIndicator: View {
    var level: Float
    var barCount: Int = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(for: index))
                    .frame(width: 3, height: 16)
                    .opacity(Float(index) / Float(barCount) <= level ? 1.0 : 0.2)
            }
        }
        .animation(.easeOut(duration: 0.05), value: level)
    }

    private func color(for index: Int) -> Color {
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.6 {
            return .green
        } else if ratio < 0.85 {
            return .yellow
        } else {
            return .red
        }
    }
}
