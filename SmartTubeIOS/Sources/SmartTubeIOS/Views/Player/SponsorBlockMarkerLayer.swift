#if !os(tvOS)
import SwiftUI
import SmartTubeIOSCore

// MARK: - SponsorBlockMarkerLayer
//
// Additive, non-interactive markers drawn over YouTube's own progress bar.
// YouTube keeps its controls, thumb and hit area; this layer only reads the
// bar's geometry (reported by stateDetectionJS) and paints SponsorBlock
// segments and chapter ticks on top. It is hidden while the control bar is
// auto-hidden and while an ad is playing (ADR-0010).
//
// The layer is `allowsHitTesting(false)`, so every drag/tap on the scrubber
// still reaches YouTube unchanged.
struct SponsorBlockMarkerLayer: View {
    let rect: TOSProgressBarRect
    let duration: Double
    let sponsorSegments: [SponsorSegment]
    let chapters: [Chapter]

    var body: some View {
        GeometryReader { geo in
            let bar = CGRect(
                x: rect.x * geo.size.width,
                y: rect.y * geo.size.height,
                width: rect.width * geo.size.width,
                height: max(rect.height * geo.size.height, 4)
            )

            Canvas { context, _ in
                // SponsorBlock segments — a 4 pt strip centred on YouTube's
                // own scrub track.
                for segment in sponsorSegments {
                    let start = TOSPlayerMarkerSupport.fraction(of: segment.start, duration: duration)
                    let end = TOSPlayerMarkerSupport.fraction(of: segment.end, duration: duration)
                    guard end > start else { continue }
                    let width = max(bar.width * (end - start), 2)
                    let marker = CGRect(
                        x: bar.minX + bar.width * start,
                        y: bar.midY - 2,
                        width: width,
                        height: 4
                    )
                    context.fill(
                        Path(roundedRect: marker, cornerRadius: 2),
                        with: .color(segment.category.color.opacity(0.9))
                    )
                }

                // Chapter ticks — taller, so they remain distinguishable from
                // SponsorBlock segments.
                for chapter in chapters {
                    let position = TOSPlayerMarkerSupport.fraction(
                        of: chapter.startTime, duration: duration)
                    let tick = CGRect(
                        x: bar.minX + bar.width * position - 1,
                        y: bar.midY - 6,
                        width: 2,
                        height: 12
                    )
                    context.fill(Path(tick), with: .color(.white.opacity(0.9)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
