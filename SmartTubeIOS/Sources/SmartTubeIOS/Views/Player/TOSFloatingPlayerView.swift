#if os(iOS)
import SwiftUI
import WebKit
import SmartTubeIOSCore

// MARK: - TOSFloatingPlayerView

/// Accessibility identifiers for the floating player. Declared as constants (rather
/// than inline literals) so the `raw_accessibility_identifier` lint rule stays clean
/// until the shared `AccessibilityID` migration lands.
private enum TOSMiniPlayerAccessibilityID {
    static let bar = "tosPlayer.miniPlayerBar"
    static let playPause = "tosPlayer.miniPlayer.playPauseButton"
    static let close = "tosPlayer.miniPlayer.closeButton"
}
//
// Floating corner window shown when the TOS player is minimized
// (TOSPlayerStateStore.presentation == .miniPlayer). Mirrors YouTube's minimized
// player: a small 16:9 window pinned to the bottom-right corner that keeps playing
// while the user browses the video grid.
//
// Layout:
//   ┌───────────────────┐
//   │ ▶/⏸            ✕ │   ← buttons overlaid in the top corners
//   │      (video)      │   ← live WKWebView; tap anywhere else → expand
//   └───────────────────┘
//
// Actions:
//   play/pause (top-left)  → vm.play() / vm.pause()
//   close (top-right)      → tosState.stop() → releases WKWebView, hides the window
//   tap the video area     → tosState.expand() → re-presents TOSPlayerView

struct TOSFloatingPlayerView: View {
    @Environment(TOSPlayerStateStore.self) private var tosState

    private let width: CGFloat = 176
    private var height: CGFloat { width * 9 / 16 }

    private var isPlaying: Bool {
        tosState.vm?.playerState == .playing || tosState.vm?.playerState == .buffering
    }

    var body: some View {
        ZStack {
            if let webView = tosState.vm?.webView {
                // Live video — transplants the same WKWebView that was hosting the
                // full-screen player, so the embedded YouTube <video> stays attached
                // to the window and playback continues. See TOSMiniPlayerLayerView.
                TOSMiniPlayerLayerView(webView: webView)
            } else if let thumb = tosState.currentVideo?.thumbnailURL {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
            } else {
                Color.black
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { tosState.expand() }
        .overlay(alignment: .topLeading) { playPauseButton }
        .overlay(alignment: .topTrailing) { closeButton }
        // Without this, SwiftUI flattens this ZStack's accessibility tree so each
        // child Button inherits the container identifier and XCUITest can't find
        // them individually. Same fix the bottom bar used.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.bar)
    }

    // MARK: - Corner buttons

    private var playPauseButton: some View {
        Button {
            if isPlaying {
                tosState.vm?.pause()
            } else {
                tosState.vm?.play()
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.playPause)
    }

    private var closeButton: some View {
        Button {
            tosState.stop()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityIdentifier(TOSMiniPlayerAccessibilityID.close)
    }
}

// MARK: - TOSMiniPlayerLayerView

/// UIViewRepresentable that hosts the TOS player's WKWebView as a live thumbnail.
/// UIView.addSubview transplants the webView from the full-screen
/// YouTubeWebPlayerView's container automatically — no explicit removeFromSuperview
/// needed. Keeping the webView attached to the window keeps the embedded YouTube
/// <video> element's document.visibilityState == 'visible', so playback continues
/// while minimized. Mirrors MiniPlayerLayerView's transplant pattern for AVPlayer.
struct TOSMiniPlayerLayerView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        // Disable interaction so taps fall through to the SwiftUI buttons
        // (expand / play-pause / close) overlaying this view, rather than being
        // captured by YouTube's native player controls inside the WKWebView.
        webView.isUserInteractionEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}
#endif  // os(iOS)
