#if os(iOS)
import CoreFoundation
import CoreGraphics
import Foundation
import os
import WebKit

private let embedFsLog = Logger(subsystem: "com.void.smarttube.app", category: "EmbedFsSpike")

// MARK: - EmbedFullscreenSpikeViewModel
//
// Throwaway investigation harness. Question: what does pressing the fullscreen
// button in a YouTube embed actually do inside our WKWebView, and can a control
// outside the iframe reproduce it?
//
// Background (verified from WebKit headers, 2026-10):
//   - `WKPreferences.isElementFullscreenEnabled` defaults to NO, so the
//     Fullscreen API is unavailable in WKWebView unless explicitly enabled.
//   - `WKWebView.fullscreenState` (iOS 16+) is KVO-observable and WebKit swaps
//     the WKWebView into a fullscreen window while an element is fullscreen.
//   - Transient user activation is required for `requestFullscreen()` and
//     `video.webkitEnterFullscreen()`, so `evaluateJavaScript` cannot trigger
//     them; only a real tap inside web content can.
//
// The spike loads the same embed wrapper as `TOSPlayerViewModel.loadEmbed` in a
// matrix of four configurations, probes the iframe's document for available
// fullscreen APIs / YouTube's own fullscreen button, and logs every entry-point
// call (monkey-patched) plus every fullscreen transition. A real HTML button in
// the wrapper page (config C) exercises the parent -> iframe requestFullscreen
// path that a production implementation would use.
//
// DELETE this file (and its view + RootView wiring + UI test) once the results
// are recorded.
@MainActor
@Observable
final class EmbedFullscreenSpikeViewModel: NSObject {

    // MARK: - Configuration matrix

    enum Config: String, CaseIterable {
        /// Today's TOS configuration: inline, playsinline, YT controls, element
        /// fullscreen disabled. Baseline for "does YT even offer fullscreen?".
        case cfgA = "A"
        /// A + `isElementFullscreenEnabled = true`.
        case cfgB = "B"
        /// The replication candidate: element fullscreen enabled, YT controls
        /// off, a real HTML button in the wrapper page requesting fullscreen on
        /// the `<iframe>` from a genuine tap.
        case cfgC = "C"
        /// Non-inline playback + element fullscreen: expected to make YouTube's
        /// own button functional (it is reportedly disabled in inline WKWebView
        /// contexts) and reveal which API the button calls.
        case cfgD = "D"

        var allowsInlineMediaPlayback: Bool { self != .cfgD }
        var playsinline: String { self == .cfgD ? "0" : "1" }
        var controls: String { self == .cfgC ? "0" : "1" }
        var elementFullscreen: Bool { self != .cfgA }
    }

    // MARK: - Observable state (surfaced to the spike view + UI test)

    private(set) var config: Config = .cfgA
    private(set) var webView: WKWebView

    /// Most recent probe payload per frame ("parent" / "child").
    private var probeByFrame: [String: [String: Any]] = [:]
    /// Chronological, human-readable log of API calls, DOM events and native
    /// `fullscreenState` transitions. Trimmed to the last 12 entries.
    private(set) var events: [String] = []
    private(set) var probeCount = 0
    private(set) var isReady = false

    /// Single line surfaced via the spike status label (see the view).
    /// The UI test parses this; keep it stable and machine-readable.
    var statusText: String {
        "cfg=\(config.rawValue) ready=\(isReady ? 1 : 0) probes=\(probeCount)"
            + " | parent[\(summary(for: "parent"))]"
            + " | child[\(summary(for: "child"))]"
            + " | ev[\(events.joined(separator: ","))]"
    }

    /// Normalized (0-1) centre of YouTube's fullscreen button as reported by the
    /// iframe probe, or nil when no button was found. Lets the UI test tap it.
    var youtubeFullscreenButtonPoint: CGPoint? {
        guard let btn = probeByFrame["child"]?["btn"] as? [String: Any],
            let x = btn["x"] as? Double,
            let y = btn["y"] as? Double,
            (btn["visible"] as? Bool) == true
        else { return nil }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Internal

    private var proxyHandler: EmbedFsScriptMessageProxy?
    private var fullscreenObservation: NSKeyValueObservation?

    // MARK: - Init

    override init() {
        let made = Self.makeWebView(for: .cfgA)
        self.webView = made.webView
        self.proxyHandler = made.proxy
        super.init()
        made.proxy.target = self
        bind(webView: made.webView)
    }

    func start() {
        load(Self.launchConfig())
    }

    /// Launch-argument override, e.g. `--uitesting-embed-fs-spike=C`. Lets the UI
    /// test relaunch the app once per config instead of tapping the "Next cfg"
    /// button, which WebKit's fullscreen window can cover.
    private static func launchConfig() -> Config {
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix(overrideArg) {
            let value = String(arg.dropFirst(overrideArg.count)).uppercased()
            if let config = Config(rawValue: value) { return config }
        }
        return .cfgA
    }

    static let overrideArg = "--uitesting-embed-fs-spike="

    /// Switches to the next configuration in the matrix and reloads.
    func advanceConfig() {
        let all = Config.allCases
        let nextIndex = (all.firstIndex(of: config).map { $0 + 1 } ?? 0) % all.count
        load(all[nextIndex])
    }

    /// Calls `document.exitFullscreen()` in the wrapper page. Exiting does NOT
    /// require user activation, so this works from Swift — the asymmetry a
    /// production implementation would rely on.
    func exitFullscreen() {
        run(
            "exitFullscreen",
            in: nil,
            js: "(function(){var d=document;var f=d.exitFullscreen||d.webkitExitFullscreen;"
                + "if(f){f.call(d);return 'called';}return 'no-api';})();"
        )
    }

    /// Re-runs the probe in the wrapper frame (useful after YT's UI lazily loads).
    func reprobe() {
        run(
            "reprobe",
            in: nil,
            js: "(function(){if(window.__stProbe){window.__stProbe.postMessage(JSON.stringify("
                + "{type:'probe',top:true,note:'reprobe'}));}return 'ok';})();"
        )
    }

    // MARK: - Loading

    private func load(_ newConfig: Config) {
        embedFsLog.notice("[embedfs] switching to config \(newConfig.rawValue, privacy: .public)")
        fullscreenObservation?.invalidate()
        fullscreenObservation = nil

        config = newConfig
        probeByFrame = [:]
        events = []
        probeCount = 0
        isReady = false

        let made = Self.makeWebView(for: newConfig)
        proxyHandler = made.proxy
        made.proxy.target = self
        webView = made.webView
        bind(webView: made.webView)

        guard let url = Self.embedURL(videoId: Self.videoId, config: newConfig) else {
            embedFsLog.error("[embedfs] could not build embed URL for config \(newConfig.rawValue, privacy: .public)")
            return
        }
        let html = Self.wrapperHTML(embedURL: url, showProbeButton: newConfig == .cfgC)
        embedFsLog.notice("[embedfs] loading \(url.absoluteString, privacy: .public)")
        made.webView.loadHTMLString(html, baseURL: URL(string: "https://www.example.com")!)
    }

    private func bind(webView: WKWebView) {
        // Observe WebKit's own view of fullscreen. Entering fullscreen moves the
        // WKWebView out of our hierarchy into a fullscreen window (per WKWebView.h),
        // which is exactly the side effect a production implementation must handle.
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] _, change in
            let rawState = change.newValue ?? .notInFullscreen
            Task { @MainActor [weak self] in
                guard let self else { return }
                let name: String
                switch rawState {
                case .notInFullscreen: name = "notInFullscreen"
                case .enteringFullscreen: name = "entering"
                case .inFullscreen: name = "inFullscreen"
                case .exitingFullscreen: name = "exiting"
                @unknown default: name = "unknown"
                }
                self.appendEvent("native:\(name)")
                embedFsLog.notice("[embedfs] fullscreenState → \(name, privacy: .public)")
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.void.smarttube.embedfs.native.\(name)" as CFString),
                    nil, nil, true
                )
                if name == "inFullscreen" {
                    // Auto-exit after 3s: while WebKit owns the fullscreen window our
                    // SwiftUI "Exit FS" button is not reachable by the UI test, and
                    // exiting is activation-free, so do it from Swift. Also proves the
                    // exit half of the asymmetry.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        self?.exitFullscreen()
                    }
                }
            }
        }
    }

    // MARK: - JS bridge

    func handleProbe(_ body: String, frameInfo: WKFrameInfo) {
        guard let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else {
            embedFsLog.error("[embedfs] unparseable probe message")
            return
        }

        let frame = (json["top"] as? Bool) == true ? "parent" : "child"

        switch type {
        case "probe":
            probeCount += 1
            probeByFrame[frame] = json
            let probeSummary = summary(for: frame)
            appendEvent("probe:\(frame)")
            embedFsLog.notice(
                "[embedfs] probe \(frame, privacy: .public) \(probeSummary, privacy: .public)")
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.embedfs.probe" as CFString),
                nil, nil, true
            )

        case "call":
            let api = (json["api"] as? String) ?? "?"
            appendEvent("call:\(api)@\(frame)")
            embedFsLog.notice(
                "[embedfs] API CALL \(api, privacy: .public) frame=\(frame, privacy: .public) stack=\((json["stack"] as? String) ?? "", privacy: .public)"
            )

        case "event":
            let name = (json["name"] as? String) ?? "?"
            let active = (json["fsElement"] as? Bool) == true
            appendEvent("ev:\(name):\(active ? "in" : "out")@\(frame)")
            embedFsLog.notice(
                "[embedfs] DOM event \(name, privacy: .public) active=\(active, privacy: .public) frame=\(frame, privacy: .public)"
            )

        case "ready":
            isReady = true
            appendEvent("ready@\(frame)")
            embedFsLog.notice("[embedfs] video ready in \(frame, privacy: .public)")
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.void.smarttube.embedfs.ready" as CFString),
                nil, nil, true
            )

        default:
            break
        }
    }

    // MARK: - Helpers

    private func appendEvent(_ event: String) {
        events.append(event)
        if events.count > 12 { events.removeFirst(events.count - 12) }
    }

    private func summary(for frame: String) -> String {
        guard let probe = probeByFrame[frame] else { return "none" }
        let fs = (probe["fsEnabled"] as? Bool) == true ? 1 : 0
        let reqFS = (probe["reqFS"] as? Bool) == true ? 1 : 0
        let reqFSWebkit = (probe["reqFSWebkit"] as? Bool) == true ? 1 : 0
        let videoFS = (probe["videoFS"] as? Bool) == true ? 1 : 0
        let hasVideo = (probe["hasVideo"] as? Bool) == true ? 1 : 0

        var btn = "none"
        if let btnPayload = probe["btn"] as? [String: Any] {
            let disabled = (btnPayload["disabled"] as? Bool) == true ? "disabled" : "enabled"
            let visible = (btnPayload["visible"] as? Bool) == true ? "visible" : "hidden"
            let x = (btnPayload["x"] as? Double) ?? -1
            let y = (btnPayload["y"] as? Double) ?? -1
            btn = String(format: "%@/%@/%.2f,%.2f", disabled, visible, x, y)
        }
        return "fs=\(fs) req=\(reqFS) wk=\(reqFSWebkit) vfs=\(videoFS) vid=\(hasVideo) btn=\(btn)"
    }

    private func run(_ label: String, in frame: WKFrameInfo?, js: String) {
        webView.evaluateJavaScript(js, in: frame, in: .page) { result in
            switch result {
            case .success(let value):
                embedFsLog.notice(
                    "[embedfs-eval] \(label, privacy: .public) result: \(String(describing: value), privacy: .public)"
                )
            case .failure(let error):
                embedFsLog.error(
                    "[embedfs-eval] \(label, privacy: .public) ERROR: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

// MARK: - Web view / HTML construction + injected JS
//
// Split into an extension so the main type body stays within the SwiftLint
// body-length budget (these are large static templates).
extension EmbedFullscreenSpikeViewModel {
    // MARK: - Web view / HTML construction

    static let videoId = "dQw4w9WgXcQ"

    private static func makeWebView(for config: Config) -> (webView: WKWebView, proxy: EmbedFsScriptMessageProxy) {
        let wkConfig = WKWebViewConfiguration()
        wkConfig.mediaTypesRequiringUserActionForPlayback = []
        wkConfig.allowsInlineMediaPlayback = config.allowsInlineMediaPlayback
        wkConfig.allowsAirPlayForMediaPlayback = false
        // THE hypothesis under test: WKWebView disables the Fullscreen API by default.
        wkConfig.preferences.isElementFullscreenEnabled = config.elementFullscreen

        let controller = WKUserContentController()
        let proxy = EmbedFsScriptMessageProxy()
        controller.add(proxy, contentWorld: .page, name: "fsProbe")

        controller.addUserScript(
            WKUserScript(
                source: webkitHiderJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        controller.addUserScript(
            WKUserScript(
                source: probeJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: .page
            ))
        wkConfig.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: wkConfig)
        // Same TV UA as TOSPlayerViewModel — the probe is about the variant we
        // actually ship, not the desktop embed.
        webView.customUserAgent =
            "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) " + "AppleWebKit/537.36 (KHTML, like Gecko) "
            + "SamsungBrowser/2.1 Chrome/56.0.2924.0 TV Safari/537.36"
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return (webView, proxy)
    }

    private static func embedURL(videoId: String, config: Config) -> URL? {
        guard var comps = URLComponents(string: "https://www.youtube.com/embed/\(videoId)") else {
            preconditionFailure("embed URL is not valid")
        }
        comps.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: "1"),
            URLQueryItem(name: "controls", value: config.controls),
            URLQueryItem(name: "playsinline", value: config.playsinline),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "origin", value: "https://www.example.com"),
        ]
        return comps.url
    }

    private static func wrapperHTML(embedURL: URL, showProbeButton: Bool) -> String {
        let button =
            showProbeButton
            ? """
            <button id="st-fs" aria-label="stWebFullscreenButton">WEB
            FULLSCREEN</button>
            <style>
                #st-fs{position:fixed;left:50%;top:60%;transform:translate(-50%,-50%);
                    width:160px;height:64px;z-index:2147483647;border:0;border-radius:10px;
                    background:#ffd400;color:#000;font:600 15px/1.2 -apple-system;
                    white-space:pre-line;text-align:center}
            </style>
            """
            : ""
        return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width,initial-scale=1">
                <style>
                    html,body,iframe{margin:0;padding:0;border:0;width:100%;height:100%;background:#000}
                    iframe{position:absolute;top:0;left:0;z-index:0}
                </style>
            </head>
            <body>
                <iframe id="yt"
                    src="\(embedURL.absoluteString)"
                    frameborder="0"
                    allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
                    allowfullscreen>
                </iframe>
                \(button)
            </body>
            </html>
            """
    }

    // MARK: - Injected JS

    /// Hides `window.webkit` before the page scripts run (YouTube fires error 153
    /// when it detects WKWebView) but keeps the probe handler reachable as
    /// `window.__stProbe`. Mirrors `TOSPlayerViewModel.webkitHiderJS`.
    private static let webkitHiderJS: String = """
        (function() {
            try {
                var wk = window.webkit;
                if (!wk) return;
                var mh = wk.messageHandlers;
                window.__stProbe = (mh && mh.fsProbe) ? mh.fsProbe : null;
                Object.defineProperty(window, 'webkit', {
                    get: function() { return undefined; },
                    set: function() {},
                    configurable: true,
                    enumerable: false
                });
            } catch(e) {}
        })();
        """

    /// Probes available fullscreen APIs, locates YouTube's own fullscreen button,
    /// monkey-patches every fullscreen entry point to log its callers, relays DOM
    /// fullscreen events, and (in the wrapper frame) wires the real HTML button to
    /// `iframe.requestFullscreen()`.
    private static let probeJS: String = """
        (function() {
            var isTop = (window === window.top);

            function post(obj) {
                try {
                    var cb = window.__stProbe;
                    if (cb) cb.postMessage(JSON.stringify(obj));
                } catch(e) {}
            }

            function btnInfo() {
                var sel = '.ytp-fullscreen-button,button[aria-label*="ull screen" i],'
                    + 'button[title*="ull screen" i],[data-title*="ull screen" i],'
                    + '[aria-label*="ullscreen" i]';
                var b = document.querySelector(sel);
                if (!b) return null;
                var r = b.getBoundingClientRect();
                return {
                    label: (b.getAttribute('aria-label') || b.title || b.className || '').slice(0, 60),
                    disabled: (b.getAttribute('aria-disabled') === 'true') || b.disabled === true,
                    visible: !!(r.width > 4 && r.height > 4),
                    x: (r.x + r.width / 2) / (window.innerWidth || 1),
                    y: (r.y + r.height / 2) / (window.innerHeight || 1)
                };
            }

            function probe(note) {
                var v = document.querySelector('video');
                post({
                    type: 'probe',
                    top: isTop,
                    note: note || '',
                    href: location.href.slice(0, 90),
                    fsEnabled: !!document.fullscreenEnabled,
                    reqFS: !!(document.documentElement && Element.prototype.requestFullscreen),
                    reqFSWebkit: !!(Element.prototype.webkitRequestFullscreen),
                    videoFS: (typeof HTMLVideoElement !== 'undefined'
                        && !!HTMLVideoElement.prototype.webkitEnterFullscreen),
                    hasVideo: !!v,
                    btn: btnInfo()
                });
            }

            function patch(proto, name) {
                try {
                    if (!proto || !proto[name]) return;
                    var orig = proto[name];
                    proto[name] = function() {
                        var stack = '';
                        try {
                            stack = (new Error().stack || '').split('\\n').slice(1, 4)
                                .join(' <- ').slice(0, 300);
                        } catch(e) {}
                        post({ type: 'call', api: name, top: isTop, stack: stack });
                        return orig.apply(this, arguments);
                    };
                } catch(e) {}
            }

            patch(Element.prototype, 'requestFullscreen');
            patch(Element.prototype, 'webkitRequestFullscreen');
            patch(Element.prototype, 'webkitRequestFullScreen');
            if (typeof HTMLVideoElement !== 'undefined') {
                patch(HTMLVideoElement.prototype, 'webkitEnterFullscreen');
                patch(HTMLVideoElement.prototype, 'webkitExitFullscreen');
            }

            ['fullscreenchange', 'webkitfullscreenchange', 'webkitbeginfullscreen', 'webkitendfullscreen']
                .forEach(function(n) {
                    document.addEventListener(n, function() {
                        post({
                            type: 'event',
                            name: n,
                            top: isTop,
                            fsElement: !!(document.fullscreenElement || document.webkitFullscreenElement)
                        });
                    }, true);
                });

            if (isTop) {
                // Real user activation lives here: a genuine tap on this HTML
                // button (above the iframe in paint order) may request fullscreen
                // on the cross-origin iframe element. This is the exact mechanism a
                // production implementation would use.
                var wireButton = function() {
                    var b = document.getElementById('st-fs');
                    if (!b || b.__stWired) return;
                    b.__stWired = true;
                    b.addEventListener('click', function() {
                        var f = document.getElementById('yt');
                        var api = f && (f.requestFullscreen || f.webkitRequestFullscreen);
                        if (!api) {
                            post({ type: 'call', api: 'no-iframe-fs-api', top: true, stack: '' });
                            return;
                        }
                        post({ type: 'call', api: 'wrapper->iframe.requestFullscreen', top: true, stack: '' });
                        try {
                            var p = api.call(f);
                            if (p && p.catch) {
                                p.catch(function(err) {
                                    post({ type: 'call', api: 'rejected:' + (err && err.name), top: true, stack: '' });
                                });
                            }
                        } catch (err) {
                            post({ type: 'call', api: 'threw:' + (err && err.name), top: true, stack: '' });
                        }
                    });
                };
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', wireButton);
                } else {
                    wireButton();
                }
            }

            probe('initial');
            setTimeout(function() { probe('t1'); }, 1000);
            setTimeout(function() { probe('t3'); }, 3000);
            setTimeout(function() { probe('t8'); }, 8000);

            // Report "ready" once the video element exists and has a duration.
            var tries = 0;
            var timer = setInterval(function() {
                tries += 1;
                var v = document.querySelector('video');
                if (v && v.duration > 0) {
                    clearInterval(timer);
                    post({ type: 'ready', top: isTop, duration: v.duration });
                }
                if (tries > 120) clearInterval(timer);
            }, 250);
        })();
        """
}

// MARK: - EmbedFsScriptMessageProxy

/// Mirrors `ScriptMessageProxy` in `TOSPlayerViewModel`: `WKUserContentController`
/// retains its handlers, so the proxy holds the view model weakly.
private final class EmbedFsScriptMessageProxy: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    weak var target: EmbedFullscreenSpikeViewModel?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }
        let frameInfo = message.frameInfo
        MainActor.assumeIsolated { [weak target] in
            target?.handleProbe(body, frameInfo: frameInfo)
        }
    }
}
#endif
