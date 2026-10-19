import SmartTubeIOSCore
import SwiftUI

// MARK: - SponsorSegmentsOverlayView
//
// Dim-backdrop bottom sheet listing the video's SponsorBlock segments. Tapping
// a row seeks to the segment start. This is the discoverable counterpart to
// the timeline marker layer: the markers themselves stay non-interactive so
// YouTube's scrubber keeps every touch (ADR-0010).
struct SponsorSegmentsOverlayView: View {
    let segments: [SponsorSegment]
    let onSelect: (SponsorSegment) -> Void
    let onDismiss: () -> Void
    var accessibilityId: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("SponsorBlock Segments")
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 4)
                Divider()
                if segments.isEmpty {
                    Text("No SponsorBlock segments for this video.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(segments) { segment in
                                Button {
                                    onSelect(segment)
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(segment.category.color)
                                            .frame(width: 10, height: 10)
                                        Text(segment.category.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(
                                            "\(formatDuration(segment.start))–\(formatDuration(segment.end))"
                                        )
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "tosPlayer.segmentsOverlay.segment.\(segment.id)")
                                if segment.id != segments.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier(accessibilityId)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifier(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}
