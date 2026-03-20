import SwiftUI

struct CountdownView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("\(count)")
                .font(MuxTheme.display(size: 120))
                .foregroundColor(MuxTheme.orange)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: count)

            Text("RECORDING STARTS IN...")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(MuxTheme.textSecondary)

            Spacer()
        }
    }
}
