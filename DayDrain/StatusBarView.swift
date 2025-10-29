import SwiftUI

/// Compact meter used inside the menu bar.
struct StatusBarView: View {
    let progress: Double
    let menuLabel: String
    let pulseToken: Int
    let isDimmed: Bool

    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: menuLabel.isEmpty ? 0 : Constants.labelSpacing) {
            if !menuLabel.isEmpty {
                Text(menuLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }

            MeterBody(progress: progress, isDimmed: isDimmed)
                .frame(width: Constants.barWidth, height: Constants.barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .stroke(Color.white.opacity(isPulsing ? 0.9 : 0), lineWidth: 2)
                        .shadow(color: Color.white.opacity(isPulsing ? 0.65 : 0), radius: isPulsing ? 6 : 0)
                        .animation(.easeOut(duration: 0.4), value: isPulsing)
                )
        }
        .animation(.easeInOut(duration: 0.25), value: progress)
        .onChange(of: pulseToken) { _ in
            triggerPulse()
        }
    }
}

extension StatusBarView {
    enum Constants {
        static let barWidth: CGFloat = 70
        static let barHeight: CGFloat = 12
        static let cornerRadius: CGFloat = 2
        static let borderWidth: CGFloat = 1
        static let borderInset: CGFloat = 1
        static let borderOpacity: Double = 0.65
        static let emptyFillOpacity: Double = 0.12
        static let labelSpacing: CGFloat = 6
    }

    private struct MeterBody: View {
        let progress: Double
        let isDimmed: Bool

        var body: some View {
            GeometryReader { geometry in
                let clamped = max(0, min(1, progress))
                let outerRect = CGRect(origin: .zero, size: geometry.size)
                let inset = Constants.borderInset
                let innerRect = outerRect.insetBy(dx: inset, dy: inset)
                let fillWidth = innerRect.width * CGFloat(clamped)
                let cornerRadius = min(Constants.cornerRadius, min(outerRect.width, outerRect.height) / 2)
                let innerRadius = max(0, cornerRadius - inset)

                ZStack(alignment: .leading) {
                    Path { path in
                        path.addRoundedRect(
                            in: outerRect,
                            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                        )
                    }
                    .stroke(Color.white.opacity(Constants.borderOpacity), lineWidth: Constants.borderWidth)
                    .opacity(isDimmed ? 0.35 : 1)

                    Path { path in
                        path.addRoundedRect(
                            in: innerRect,
                            cornerSize: CGSize(width: innerRadius, height: innerRadius)
                        )
                    }
                    .fill(Color.white.opacity(Constants.emptyFillOpacity))
                    .opacity(isDimmed ? 0.4 : 1)

                    if fillWidth > 0 {
                        let fillRect = CGRect(
                            x: innerRect.maxX - fillWidth,
                            y: innerRect.minY,
                            width: fillWidth,
                            height: innerRect.height
                        )
                        let fillCornerRadius = min(innerRadius, fillRect.width / 2)

                        Path { path in
                            path.addRoundedRect(
                                in: fillRect,
                                cornerSize: CGSize(width: fillCornerRadius, height: fillCornerRadius)
                            )
                        }
                        .fill(Color.white.opacity(isDimmed ? 0.4 : 1))
                    }
                }
            }
        }
    }
}

extension StatusBarView {
    private func triggerPulse() {
        guard pulseToken > 0 else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            isPulsing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeOut(duration: 0.35)) {
                isPulsing = false
            }
        }
    }
}
