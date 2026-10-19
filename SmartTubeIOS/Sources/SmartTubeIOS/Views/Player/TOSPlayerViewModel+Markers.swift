#if !os(tvOS)
import Foundation
import SmartTubeIOSCore

// MARK: - TOS marker navigation
//
// Native "previous/next chapter" and "previous/next SponsorBlock segment"
// actions. Navigation lives outside the embed's controls (ADR-0010): the
// marker layer is read-only, so all seeking is driven from SmartTube's own
// buttons and the segments list.
extension TOSPlayerViewModel {

    /// The chapter containing the current playhead, if chapters are available.
    var currentChapter: Chapter? {
        chapters.last(where: { $0.startTime <= currentTime })
    }

    var hasNextChapter: Bool {
        TOSPlayerMarkerSupport.nextChapterStart(in: chapters, after: currentTime) != nil
    }

    var hasPreviousChapter: Bool {
        TOSPlayerMarkerSupport.previousChapterStart(in: chapters, currentTime: currentTime) != nil
    }

    func skipToNextChapter() {
        guard
            let target = TOSPlayerMarkerSupport.nextChapterStart(
                in: chapters, after: currentTime)
        else { return }
        seekTo(target)
    }

    func skipToPreviousChapter() {
        guard
            let target = TOSPlayerMarkerSupport.previousChapterStart(
                in: chapters, currentTime: currentTime)
        else { return }
        seekTo(target)
    }

    var hasNextSponsorSegment: Bool {
        TOSPlayerMarkerSupport.nextSegmentStart(in: sponsorSegments, after: currentTime) != nil
    }

    var hasPreviousSponsorSegment: Bool {
        TOSPlayerMarkerSupport.previousSegmentStart(in: sponsorSegments, before: currentTime) != nil
    }

    func skipToNextSponsorSegment() {
        guard
            let target = TOSPlayerMarkerSupport.nextSegmentStart(
                in: sponsorSegments, after: currentTime)
        else { return }
        seekTo(target)
    }

    func skipToPreviousSponsorSegment() {
        guard
            let target = TOSPlayerMarkerSupport.previousSegmentStart(
                in: sponsorSegments, before: currentTime)
        else { return }
        seekTo(target)
    }
}
#endif
