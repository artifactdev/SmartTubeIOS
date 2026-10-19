#if !os(tvOS)
import Foundation
import SmartTubeIOSCore

// MARK: - TOSProgressBarRect
//
// Geometry of YouTube's own progress bar, expressed as fractions of the embed
// viewport (0...1). Normalised so the native marker layer can map it onto a
// full-bleed SwiftUI overlay without depending on CSS-pixel scale factors.
struct TOSProgressBarRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// False while YouTube's control bar auto-hides. The marker layer is only
    /// drawn while the real scrubber is on screen.
    let isVisible: Bool
}

// MARK: - TOSPlayerMarkerSupport
//
// Pure next/previous marker maths for the TOS player's SponsorBlock and
// chapter navigation. Kept free of SwiftUI/WKWebView so it can be unit-tested.

enum TOSPlayerMarkerSupport {

    // MARK: SponsorBlock

    /// Start of the first SponsorBlock segment strictly after `time`. A segment
    /// that is already under the playhead is not "next".
    static func nextSegmentStart(in segments: [SponsorSegment], after time: Double) -> Double? {
        segments
            .filter { $0.start > time + 0.5 }
            .min(by: { $0.start < $1.start })?
            .start
    }

    /// Start of the most recent SponsorBlock segment that began at least a
    /// second before `time`, so tapping "previous" right after a segment starts
    /// does not seek to where the playhead already is.
    static func previousSegmentStart(in segments: [SponsorSegment], before time: Double) -> Double? {
        segments
            .filter { $0.start < time - 1.0 }
            .max(by: { $0.start < $1.start })?
            .start
    }

    // MARK: Chapters

    /// Start time of the first chapter strictly after `time`.
    static func nextChapterStart(in chapters: [Chapter], after time: Double) -> Double? {
        chapters.first(where: { $0.startTime > time })?.startTime
    }

    /// Mirrors the direct player: when more than 3 s into the current chapter,
    /// restart it; otherwise jump to the previous chapter.
    static func previousChapterStart(in chapters: [Chapter], currentTime: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        guard let current = chapters.last(where: { $0.startTime <= currentTime }) else { return nil }
        if currentTime - current.startTime > 3 { return current.startTime }
        return chapters.last(where: { $0.startTime < current.startTime })?.startTime
    }

    // MARK: Timeline mapping

    /// Position of `time` on a `duration`-long timeline, clamped to 0...1. The
    /// marker layer uses this for both SponsorBlock segments and chapter ticks.
    static func fraction(of time: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}
#endif
