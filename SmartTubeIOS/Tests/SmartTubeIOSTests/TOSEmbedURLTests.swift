import Foundation
import Testing

@testable import SmartTubeIOS

// MARK: - TOSEmbedURLTests
//
// Compliance regression guard for ADR-0010. The TOS player must load the
// YouTube embed with its own controls and branding enabled. An earlier
// iteration passed `controls=0` and hid the in-embed chrome, which is the
// exact behaviour App Review flagged under guideline 5.2.3.
//
// If someone reintroduces `controls=0` (or forces captions off/on via
// `cc_load_policy`), these tests fail before the change reaches review.

@Suite("TOS embed keeps YouTube's native player chrome")
struct TOSEmbedURLTests {

    private func queryItems(_ url: URL) -> [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private func value(_ name: String, in url: URL) -> String? {
        queryItems(url).first(where: { $0.name == name })?.value
    }

    @Test("controls is always 1 — never 0")
    func controlsAlwaysOn() {
        let url = TOSEmbedURL.make(videoId: "dQw4w9WgXcQ", startTime: 0)
        #expect(value("controls", in: url) == "1")
    }

    @Test("no caption policy override")
    func noForcedCaptions() {
        let url = TOSEmbedURL.make(videoId: "dQw4w9WgXcQ", startTime: 0)
        #expect(value("cc_load_policy", in: url) == nil)
        #expect(value("cc_lang_pref", in: url) == nil)
    }

    @Test("origin matches the cross-origin wrapper page")
    func originMatchesWrapper() {
        let url = TOSEmbedURL.make(videoId: "dQw4w9WgXcQ", startTime: 0)
        #expect(value("origin", in: url) == TOSEmbedURL.origin)
        #expect(TOSEmbedURL.origin != "https://www.youtube.com")
    }

    @Test("start time is preserved as whole seconds")
    func startTimeIsPreserved() {
        let url = TOSEmbedURL.make(videoId: "dQw4w9WgXcQ", startTime: 91.7)
        #expect(value("start", in: url) == "91")
    }

    @Test("embed path still points at the YouTube embed endpoint")
    func embedPath() {
        let url = TOSEmbedURL.make(videoId: "dQw4w9WgXcQ", startTime: 0)
        #expect(url.host == "www.youtube.com")
        #expect(url.path == "/embed/dQw4w9WgXcQ")
    }
}
