import SwiftUI

/// Simple SwiftUI view that renders the draining bar inside the status bar.
struct StatusBarView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: geometry.size.height / 2)
                    .fill(Color.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: geometry.size.height / 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(progress))
                RoundedRectangle(cornerRadius: geometry.size.height / 2)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: 70, height: 12)
    }
}
