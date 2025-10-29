import SwiftUI

/// Compact meter used inside the menu bar.
struct StatusBarView: View {
    let progress: Double
    let menuLabel: String

    var body: some View {
        HStack(spacing: menuLabel.isEmpty ? 0 : Constants.labelSpacing) {
            if !menuLabel.isEmpty {
                Text(menuLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }

            MeterBody(progress: progress)
                .frame(width: Constants.barWidth, height: Constants.barHeight)
        }
        .animation(.easeInOut(duration: 0.25), value: progress)
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

                    Path { path in
                        path.addRoundedRect(
                            in: innerRect,
                            cornerSize: CGSize(width: innerRadius, height: innerRadius)
                        )
                    }
                    .fill(Color.white.opacity(Constants.emptyFillOpacity))

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
                        .fill(Color.white)
                    }
                }
            }
        }
    }
}
