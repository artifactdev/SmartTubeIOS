#if !os(tvOS)
import Foundation
import Testing

@testable import SmartTubeIOS

// MARK: - TOSPlayerTransportSupportTests
//
// Pure-logic coverage for the TOS native transport/media-option helpers. No
// WKWebView is involved, so these run in the SwiftPM test target.

@Suite("TOSPlayerTransportSupport.parseRanges")
struct TOSPlayerTransportParseRangesTests {

    @Test("decodes NSNumber pairs into closed ranges")
    func decodesNumberPairs() {
        let raw: [[Any]] = [[NSNumber(value: 0), NSNumber(value: 12.5)], [NSNumber(value: 30), NSNumber(value: 40)]]
        let ranges = TOSPlayerTransportSupport.parseRanges(raw)
        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == 0)
        #expect(ranges[0].upperBound == 12.5)
        #expect(ranges[1].lowerBound == 30)
        #expect(ranges[1].upperBound == 40)
    }

    @Test("rejects non-finite, inverted and malformed entries")
    func rejectsInvalidEntries() {
        let raw: [[Any]] = [
            [NSNumber(value: Double.infinity), NSNumber(value: 10)],
            [NSNumber(value: 20), NSNumber(value: 10)],
            [NSNumber(value: 5)],
        ]
        #expect(TOSPlayerTransportSupport.parseRanges(raw).isEmpty)
    }

    @Test("non-array payload returns no ranges")
    func ignoresNonArray() {
        #expect(TOSPlayerTransportSupport.parseRanges("nope").isEmpty)
        #expect(TOSPlayerTransportSupport.parseRanges(nil).isEmpty)
    }
}

@Suite("TOSPlayerTransportSupport.clampedScrubTime")
struct TOSPlayerTransportClampTests {

    @Test("within the window is unchanged")
    func withinWindow() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(42, duration: 100) == 42)
    }

    @Test("above the window clamps to duration")
    func aboveWindow() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(140, duration: 100) == 100)
    }

    @Test("below zero clamps to zero")
    func belowZero() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(-5, duration: 100) == 0)
    }

    @Test("unknown duration still clamps the lower bound")
    func unknownDuration() {
        #expect(TOSPlayerTransportSupport.clampedScrubTime(-5, duration: 0) == 0)
        #expect(TOSPlayerTransportSupport.clampedScrubTime(30, duration: 0) == 30)
    }
}

@Suite("TOSPlayerTransportSupport quality + language helpers")
struct TOSPlayerTransportQualityTests {

    @Test("prettyQuality maps YouTube identifiers")
    func prettyQualityMapping() {
        #expect(TOSPlayerTransportSupport.prettyQuality("hd1080") == "1080p")
        #expect(TOSPlayerTransportSupport.prettyQuality("large") == "480p")
        #expect(TOSPlayerTransportSupport.prettyQuality("mystery") == "mystery")
    }

    @Test("bestQualityID picks the highest at or below the cap")
    func bestQualityAtOrBelow() {
        let qualities = [
            TOSQualityOption(id: "hd1080", label: "1080p", height: 1080),
            TOSQualityOption(id: "hd720", label: "720p", height: 720),
            TOSQualityOption(id: "medium", label: "360p", height: 360),
        ]
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 720, in: qualities) == "hd720")
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 1080, in: qualities) == "hd1080")
    }

    @Test("bestQualityID falls back to the lowest when every option exceeds the cap")
    func bestQualityFallback() {
        let qualities = [
            TOSQualityOption(id: "hd1080", label: "1080p", height: 1080),
            TOSQualityOption(id: "hd720", label: "720p", height: 720),
        ]
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 400, in: qualities) == "hd720")
        #expect(TOSPlayerTransportSupport.bestQualityID(forMaxHeight: 400, in: []) == nil)
    }

    @Test("matchLanguage prefers an exact code, then a prefix")
    func languageMatching() {
        let tracks: [(String, Int)] = [("en-US", 0), ("es", 1), ("fr", 2)]
        #expect(TOSPlayerTransportSupport.matchLanguage("es", in: tracks) == 1)
        #expect(TOSPlayerTransportSupport.matchLanguage("en-GB", in: tracks) == 0)
        #expect(TOSPlayerTransportSupport.matchLanguage("de", in: tracks) == nil)
    }

    @Test("audio display name derives a language name from the track id")
    func audioDisplayNameFromTrackID() {
        let name = TOSPlayerTransportSupport.audioTrackDisplayName(
            provided: "", languageCode: "", identifier: "en.4", index: 0)
        if let localized = TOSPlayerTransportSupport.localizedLanguageName("en") {
            #expect(name == localized)
        } else {
            #expect(name == "Audio 1")
        }
    }

    @Test("audio display name falls back to Audio N for opaque ids")
    func audioDisplayNameFallback() {
        let name = TOSPlayerTransportSupport.audioTrackDisplayName(
            provided: "", languageCode: "", identifier: "opaque-content-id", index: 1)
        #expect(name == "Audio 2")
    }

    @Test("audio language code is derived from the langcode.number track id")
    func audioLanguageCodeFromLangcodeNumberID() {
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "en.4") == "en")
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "de-DE.2") == "de-DE")
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "", identifier: "opaque-content-id") == nil)
    }

    @Test("audio language code prefers an explicit provided code")
    func audioLanguageCodePrefersProvided() {
        #expect(TOSPlayerTransportSupport.audioLanguageCode(provided: "fr", identifier: "opaque") == "fr")
    }

    @Test("audio display name prefers the embed's localized name")
    func audioDisplayNamePrefersProvidedName() {
        #expect(
            TOSPlayerTransportSupport.audioTrackDisplayName(
                provided: "English original", languageCode: "en", identifier: "en.4", index: 0)
                == "English original")
        // A three-letter-plus localized name is passed through unchanged.
        #expect(
            TOSPlayerTransportSupport.audioTrackDisplayName(
                provided: "Deutsch", languageCode: "de", identifier: "de.2", index: 1)
                == "Deutsch")
    }
}
#endif
