import Foundation
import Testing

@testable import SmartTubeIOS
@testable import SmartTubeIOSCore

// MARK: - TOSPlayerMarkerSupportTests
//
// Pure marker navigation maths for the TOS player: SponsorBlock segments and
// chapters are rendered on a non-interactive layer over YouTube's own
// scrubber, so previous/next navigation comes from SmartTube's buttons.

@Suite("TOS marker navigation")
struct TOSPlayerMarkerSupportTests {

    private func segment(_ start: Double, _ end: Double) -> SponsorSegment {
        SponsorSegment(start: start, end: end, category: .sponsor)
    }

    private func chapter(_ start: Double) -> Chapter {
        Chapter(title: "Chapter \(start)", startTime: start)
    }

    @Test("next segment skips the one currently under the playhead")
    func nextSegmentSkipsCurrent() {
        let segments = [segment(10, 20), segment(40, 50)]
        #expect(TOSPlayerMarkerSupport.nextSegmentStart(in: segments, after: 15) == 40)
    }

    @Test("next segment is nil after the last segment")
    func nextSegmentNilAtEnd() {
        let segments = [segment(10, 20)]
        #expect(TOSPlayerMarkerSupport.nextSegmentStart(in: segments, after: 25) == nil)
    }

    @Test("previous segment picks the most recent start before the playhead")
    func previousSegment() {
        let segments = [segment(10, 20), segment(40, 50)]
        #expect(TOSPlayerMarkerSupport.previousSegmentStart(in: segments, before: 45) == 40)
        #expect(TOSPlayerMarkerSupport.previousSegmentStart(in: segments, before: 30) == 10)
    }

    @Test("previous segment ignores a segment that just started")
    func previousSegmentIgnoresJustStarted() {
        let segments = [segment(40, 50)]
        #expect(TOSPlayerMarkerSupport.previousSegmentStart(in: segments, before: 40.5) == nil)
    }

    @Test("next chapter is the first boundary after the playhead")
    func nextChapter() {
        let chapters = [chapter(0), chapter(60), chapter(120)]
        #expect(TOSPlayerMarkerSupport.nextChapterStart(in: chapters, after: 30) == 60)
        #expect(TOSPlayerMarkerSupport.nextChapterStart(in: chapters, after: 130) == nil)
    }

    @Test("previous chapter restarts the current chapter when >3s in")
    func previousChapterRestarts() {
        let chapters = [chapter(0), chapter(60), chapter(120)]
        #expect(TOSPlayerMarkerSupport.previousChapterStart(in: chapters, currentTime: 100) == 60)
    }

    @Test("previous chapter jumps back when within the first 3s")
    func previousChapterJumpsBack() {
        let chapters = [chapter(0), chapter(60), chapter(120)]
        #expect(TOSPlayerMarkerSupport.previousChapterStart(in: chapters, currentTime: 61) == 0)
        #expect(TOSPlayerMarkerSupport.previousChapterStart(in: chapters, currentTime: 1) == nil)
    }

    @Test("timeline fraction clamps to 0...1 and handles unknown duration")
    func timelineFraction() {
        #expect(TOSPlayerMarkerSupport.fraction(of: 50, duration: 100) == 0.5)
        #expect(TOSPlayerMarkerSupport.fraction(of: -5, duration: 100) == 0)
        #expect(TOSPlayerMarkerSupport.fraction(of: 150, duration: 100) == 1)
        #expect(TOSPlayerMarkerSupport.fraction(of: 50, duration: 0) == 0)
    }
}
