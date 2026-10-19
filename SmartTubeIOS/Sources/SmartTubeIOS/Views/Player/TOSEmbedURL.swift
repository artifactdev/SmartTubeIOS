#if !os(tvOS)
import Foundation

// MARK: - TOSEmbedURL
//
// Builds the YouTube embed URL for the TOS player.
//
// Compliance boundary (ADR-0010): the embed is always loaded with YouTube's
// own player chrome enabled (`controls=1`). Do not pass `controls=0`, do not
// force captions (`cc_load_policy=1`), and do not remove parameters YouTube
// documents for third-party embeds. The TOS player must not hide, replace or
// obscure YouTube's controls or branding.
//
// Kept as a pure function so the regression test can assert the URL without
// instantiating a WKWebView-owning view model.
enum TOSEmbedURL {

    /// Origin declared to YouTube. Matches the wrapper page's `baseURL` so the
    /// iframe request looks like a normal third-party embed (`Sec-Fetch-Site:
    /// cross-site`); must not be `youtube.com` or YouTube detects a self-embed
    /// and fires error 153.
    static let origin = "https://www.example.com"

    static func make(videoId: String, startTime: Double) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.youtube.com"
        comps.path = "/embed/\(videoId)"
        comps.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: "1"),
            // YouTube's native player chrome. Never override this with "0":
            // replacing the embed's controls is outside the TOS boundary.
            URLQueryItem(name: "controls", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "iv_load_policy", value: "3"),
            URLQueryItem(name: "start", value: "\(Int(startTime))"),
            URLQueryItem(name: "origin", value: origin),
        ]
        guard let url = comps.url else {
            // A scheme + host + path always produces a URL; this is a
            // programmer error, not a runtime condition.
            preconditionFailure("TOSEmbedURL produced an invalid YouTube embed URL")
        }
        return url
    }
}
#endif
