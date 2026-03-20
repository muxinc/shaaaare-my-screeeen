import SwiftUI

struct UploadProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Circular progress
            ZStack {
                Circle()
                    .stroke(MuxTheme.border, lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(MuxTheme.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(MuxTheme.mono(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
            }

            VStack(spacing: 8) {
                Text("Uploading to Mux")
                    .font(MuxTheme.display(size: 22))

                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundColor(MuxTheme.textSecondary)
            }

            Spacer()
        }
        .padding(32)
    }

    private var statusText: String {
        if progress < 0.5 {
            return "Uploading file..."
        } else if progress < 0.7 {
            return "Processing upload..."
        } else {
            return "Preparing for playback..."
        }
    }
}
