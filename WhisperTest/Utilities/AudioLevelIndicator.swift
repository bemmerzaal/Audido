import SwiftUI

struct AudioLevelIndicator: View {
    var level: Float
    var barCount: Int = 20

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 2
            let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let barHeight = size.height

            for index in 0..<barCount {
                let x = CGFloat(index) * (barWidth + spacing)
                let ratio = Float(index) / Float(barCount)
                let isActive = ratio <= level
                let color: Color = ratio < 0.6 ? .green : (ratio < 0.85 ? .yellow : .red)

                let rect = CGRect(x: x, y: 0, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                context.fill(path, with: .color(color.opacity(isActive ? 1.0 : 0.2)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
