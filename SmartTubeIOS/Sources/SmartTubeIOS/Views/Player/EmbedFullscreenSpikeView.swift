#if os(iOS)
import SwiftUI
import WebKit

/// File-local identifiers for the spike, mirroring `TOSFloatingPlayerView`'s
/// `TOSMiniPlayerAccessibilityID` — the shared `AccessibilityID` migration has not
/// covered this throwaway harness (and will not, since it is deleted afterwards).
private enum EmbedFsSpikeAccessibilityID {
    static let status = "embedFsSpike.statusLabel"
    static let nextConfig = "embedFsSpike.nextConfigButton"
    static let exitFullscreen = "embedFsSpike.exitFullscreenButton"
    static let reprobe = "embedFsSpike.reprobeButton"
}

/// SwiftUI host for the embed-fullscreen spike. Presented as a full-screen cover
/// from `RootView` when launched with `--uitesting-embed-fs-spike`.
///
/// The status label is the primary output: it carries the config letter, the
/// per-frame API probe and the last 12 fullscreen events as one machine-readable
/// string, so the UI test (and a human) can read the verdict without extracting
/// device logs. Simulator-only investigation harness — delete after the results
/// are recorded.
struct EmbedFullscreenSpikeView: View {
    @State private var vm = EmbedFullscreenSpikeViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            SpikeWebHost(webView: vm.webView)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text(vm.statusText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(6)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(EmbedFsSpikeAccessibilityID.status)

                HStack(spacing: 10) {
                    Button("Next cfg") { vm.advanceConfig() }
                        .accessibilityIdentifier(EmbedFsSpikeAccessibilityID.nextConfig)
                    Button("Exit FS") { vm.exitFullscreen() }
                        .accessibilityIdentifier(EmbedFsSpikeAccessibilityID.exitFullscreen)
                    Button("Probe") { vm.reprobe() }
                        .accessibilityIdentifier(EmbedFsSpikeAccessibilityID.reprobe)
                }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
        }
        .onAppear { vm.start() }
    }
}

/// Hosts the spike's WKWebView and swaps it when the config changes.
/// Mirrors `ShortsEmbedSrcSwapSpikeView.SpikeWebView`, with one addition: the
/// previous web view is removed, because each config builds a fresh WKWebView.
private struct SpikeWebHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if uiView.subviews.first !== webView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = true
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
#endif
