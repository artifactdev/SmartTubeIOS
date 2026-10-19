---
status: accepted
date: 2026-10-19
deciders: maintainer
---
# 0010. TOS player keeps YouTube's native player chrome

## Context and problem statement

SmartTube ships through the App Store/TestFlight. App Review has already rejected a build
for YouTube-related content handling (guideline 5.2.3), which led to compiling out all
download code. The TOS player (ADR-0006) exists as the lower-risk path: YouTube's own IFrame
player handles streams, controls and branding inside a WKWebView.

A prototype replaced that chrome (`controls=0` + an injected visibility hider + a native
transport overlay), fetched caption tracks from InnerTube's private `/player` endpoint, and
read `movie_player` internals (`__stPlayerAPI`) for quality/audio/player-response data. That
moves the TOS path towards the exact behaviour App Review flags. Embedded-player policy does
not allow hiding, obscuring or replacing the player and its controls/branding, and ads must
never be hidden, skipped or covered.

## Decision

- Load the embed with its native chrome (`controls=1`; no `controls=0`, no caption-policy
  override). Never inject CSS/DOM changes that hide, dim, resize, disable or replace
  YouTube's player, controls, branding or ad surface. Reading DOM state (the `<video>`
  element, the `ad-showing` class, error text) is allowed.
- Native SwiftUI on top of the embed is limited to things YouTube does not provide: app
  navigation (back/minimize, speed, more menu), SponsorBlock skip/undo UI, and a
  non-interactive SponsorBlock/chapter marker layer aligned to YouTube's own timeline.
  No native transport bar, scrubber, play/pause or media pickers.
- Quality, captions and audio tracks use YouTube's own settings menu. No
  `movie_player` option APIs, no `getPlayerResponse`/`adaptiveFormats`, and no InnerTube
  `/player` caption fetch from the TOS path (`fetchCaptionTracks` removed).
- Ads: the app hides nothing, so no ad frame can be hidden. Native chrome, the marker layer
  and SponsorBlock toasts are suppressed while the embed reports `ad-showing`, and
  SponsorBlock never seeks or shows a toast during an ad.
- Do not migrate to the IFrame Player API now: the TV-UA embed (required for the TV OAuth
  session cookies) does not reliably expose it, migration risks the error-153 class this
  player avoids, and it does not provide buffered ranges, audio tracks or ad state.
- No hybrid AVPlayer handoff (ADR-0007).

## Consequences

- Good: removes the highest ToS/compliance risk from the default iOS player; ads are
  untouched by construction; no private endpoints or undocumented player APIs.
- Bad: TOS controls no longer match the direct player; quality/caption/audio selection is
  YouTube's UI; the app must not draw its own transport timeline.
- Risk: the remaining DOM polling is best-effort; failures degrade to stale native state,
  never to a crash or a hidden player.

## Alternatives considered

- **Hide YouTube's chrome + native overlay**: rejected — the behaviour the review flagged.
- **Documented IFrame Player API**: deferred for the reasons above.
- **InnerTube caption tracks**: rejected — private `/player` request from the compliant path.
- **Hide or skip ads**: rejected — the player exists to stay TOS-compliant.
