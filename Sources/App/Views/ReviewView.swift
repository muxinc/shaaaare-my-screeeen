import SwiftUI
import AVFoundation
import AppKit

// MARK: - NSViewRepresentable AVPlayer wrapper (avoids _AVKit_SwiftUI crash)

struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = AVPlayerContainerView(player: player)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class AVPlayerContainerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)

        // Layer-hosting view: set layer before wantsLayer
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        self.layer = rootLayer
        self.wantsLayer = true

        playerLayer.videoGravity = .resizeAspect
        rootLayer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Thin Scrubber Bar

private struct VideoScrubber: View {
    @Binding var currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    let onScrubStateChanged: (Bool) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var hoverProgress: CGFloat = 0

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 14
    private let expandedTrackHeight: CGFloat = 6

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let activeTrackHeight = (isHovering || isDragging) ? expandedTrackHeight : trackHeight

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: activeTrackHeight / 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: activeTrackHeight)

                // Hover preview (subtle lighter fill)
                if isHovering && !isDragging {
                    RoundedRectangle(cornerRadius: activeTrackHeight / 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: max(hoverProgress * width, 0), height: activeTrackHeight)
                }

                // Filled progress
                RoundedRectangle(cornerRadius: activeTrackHeight / 2)
                    .fill(MuxTheme.orange)
                    .frame(width: max(progress * width, 0), height: activeTrackHeight)

                // Thumb (visible on hover/drag)
                if isHovering || isDragging {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: progress * width - thumbSize / 2)
                }
            }
            .frame(height: max(thumbSize, activeTrackHeight))
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverProgress = max(0, min(location.x / width, 1))
                case .ended:
                    break
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubStateChanged(true)
                        }
                        let fraction = max(0, min(value.location.x / width, 1))
                        currentTime = Double(fraction) * duration
                    }
                    .onEnded { value in
                        let fraction = max(0, min(value.location.x / width, 1))
                        let target = Double(fraction) * duration
                        currentTime = target
                        onSeek(target)
                        isDragging = false
                        onScrubStateChanged(false)
                    }
            )
        }
        .frame(height: thumbSize)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Review View

struct ReviewView: View {
    @EnvironmentObject var appState: AppState
    let fileURL: URL
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var isScrubbing = false

    private var fileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return formatFileSize(size)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video player area
            ZStack {
                if let player {
                    NativeVideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            togglePlayback()
                        }
                        .overlay(alignment: .center) {
                            // Large centered play button when paused
                            if !isPlaying {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isPlaying)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black)
                        .overlay(
                            ProgressView()
                                .controlSize(.large)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Controls area
            VStack(spacing: 8) {
                // Scrubber
                VideoScrubber(
                    currentTime: $currentTime,
                    duration: duration,
                    onSeek: { seek(to: $0) },
                    onScrubStateChanged: { scrubbing in
                        isScrubbing = scrubbing
                        if scrubbing {
                            player?.pause()
                        }
                    }
                )

                // Time + Transport
                HStack(spacing: 0) {
                    // Current time / duration
                    Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(MuxTheme.textSecondary)
                        .frame(width: 90, alignment: .leading)

                    Spacer()

                    // Transport controls
                    HStack(spacing: 20) {
                        Button(action: { seek(by: -10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary.opacity(0.8))

                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 28, height: 28)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)

                        Button(action: { seek(by: 10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary.opacity(0.8))
                    }

                    Spacer()

                    // File size
                    if let fileSize {
                        Text(fileSize)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MuxTheme.textSecondary)
                            .frame(width: 90, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 90)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Spacer(minLength: 0)

            // Action buttons
            VStack(spacing: 0) {
                Divider()
                    .background(MuxTheme.border)

                HStack(spacing: 12) {
                    Button(action: {
                        tearDownPlayer()
                        appState.retake(fileURL: fileURL)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                            Text("Retake")
                        }
                    }
                    .buttonStyle(MuxSecondaryButtonStyle())

                    Button(action: {
                        tearDownPlayer()
                        Task { await appState.upload(fileURL: fileURL) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text("Upload to Mux")
                        }
                    }
                    .buttonStyle(MuxPrimaryButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func configurePlayer() {
        let player = AVPlayer(url: fileURL)
        self.player = player
        installObservers(for: player)

        // Play immediately — automaticallyWaitsToMinimizeStalling (default true)
        // handles buffering internally. Preroll was causing playback to never start
        // when it returned finished=false on large recordings.
        player.play()
    }

    private func tearDownPlayer() {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil

        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isScrubbing = false
    }

    private func installObservers(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            if !isScrubbing {
                currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
            }

            let itemDuration = player.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite && itemDuration > 0 {
                duration = itemDuration
            }

            isPlaying = player.rate > 0
        }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            currentTime = duration
        }
    }

    private func togglePlayback() {
        guard let player else { return }

        if player.rate > 0 {
            player.pause()
            isPlaying = false
            return
        }

        if duration > 0 && currentTime >= max(duration - 0.1, 0) {
            seek(to: 0)
        }

        player.play()
        isPlaying = true
    }

    private func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        let target = min(max(seconds, 0), max(duration, 0))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
