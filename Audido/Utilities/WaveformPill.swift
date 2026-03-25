import SwiftUI

// MARK: - Pill container

struct WaveformPill: View {
    let level: Float
    let duration: TimeInterval

    private let barCount = 36
    @State private var history: [Float] = Array(repeating: 0, count: 36)

    var body: some View {
        HStack(spacing: 16) {
            PulsingDot()

            WaveformBars(history: history, barCount: barCount)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)

            Text(formatDuration(duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .capsule)
        .onChange(of: level) { _, newLevel in
            // Apply a power curve (0.55) so soft speech is already visually prominent
            let boosted = newLevel > 0 ? pow(newLevel, 0.55) : 0
            history.removeFirst()
            history.append(boosted)
        }
    }
}

// MARK: - Pulsing recording dot

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0.65 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Waveform bars

/// Draws a scrolling level-history waveform.
/// Each bar represents one audio sample from the past (left = oldest, right = newest).
/// A tiny per-bar sine variation adds organic feel without overriding the real audio signal.
private struct WaveformBars: View {
    let history: [Float]
    let barCount: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                guard history.count == barCount else { return }

                let t = timeline.date.timeIntervalSinceReferenceDate
                let barW: CGFloat = 3.5
                let gap: CGFloat  = 2.0
                let totalW = CGFloat(barCount) * (barW + gap) - gap
                let startX = (size.width - totalW) / 2
                let midY   = size.height / 2
                let maxH   = size.height / 2   // max half-height (grows up and down)

                for i in 0..<barCount {
                    let raw = CGFloat(history[i])

                    // Subtle organic jitter (±12%) that scales with the signal — silent bars stay flat
                    let jitter = 1.0 + sin(t * 7.0 + Double(i) * 0.45) * 0.12 * Double(raw > 0.02 ? 1 : 0)
                    let effective = raw * CGFloat(jitter)

                    let minH: CGFloat = 2.5                          // idle stub height
                    let halfH = effective > 0.02
                        ? max(minH, maxH * effective)
                        : minH

                    let x    = startX + CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: midY - halfH, width: barW, height: halfH * 2)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    let alpha: Double = effective > 0.02 ? 1.0 : 0.25
                    context.fill(path, with: .color(Color.accentColor.opacity(alpha)))
                }
            }
        }
    }
}
