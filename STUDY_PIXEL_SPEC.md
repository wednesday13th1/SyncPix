# SyncPix — Collaborative Photo Canvas Specification

“Two people. One picture. Every study session brings it to life.”

## Platform and scope

SwiftUI, SwiftData, PhotosUI, Core Graphics, UserNotifications; iOS 17+. Reuse the existing study and reward implementation. Only Home and Together are main tabs. Gallery is accessed from Home. No rankings, streaks, avatars, coins, shops, feeds, missions, chat, reactions, or public sharing.

Home shows the current eligible canvas, study mode and preset, Pixel Credits, one-tap start, Create Canvas, and Gallery. Together shows Sync Canvases, create/join, and Photo Swap inbox. Keep the pastel pink/ivory visual identity, rounded surfaces, simple typography, VoiceOver, Dynamic Type, Reduce Motion, ownership symbols beyond color, and at least 44×44-point interactive targets.

## Photo canvas

Import a photo, drag/pinch to crop square with accessible zoom/position alternatives, normalize all eight UIImage orientations (including mirrored EXIF cases), then sample 24×24 sRGB colors locally with Core Graphics. Preserve existing saved resolutions. New canvases always use a 6×6 block grid with 4×4 pixels per block. Render an exact-size raster with nearest-neighbor enlargement. Fade only the newly restored block over its grayscale/neutral base; disable this animation for Reduce Motion. Persist the canvas and progress.

Color Restore begins grayscale; Mystery Reveal begins with neutral blocks. Each eligible locked block costs one credit to reveal its original colors. Already revealed blocks are immutable. Sync Canvas defaults to Color Restore, Photo Swap to Mystery Reveal, without separate mode-selection screens. Recipient thumbnails and previews must never show unrevealed full-color content. Sender crop editing can display the sender's own selected photo.

## Sync Canvas

Exactly two participants. Half & Half (default) assigns the three left block columns to You and three right columns to Friend. Puzzle Pieces assigns top-left/bottom-right quadrants to You and the opposite quadrants to Friend. Both assign 18 blocks per participant. Block ownership cannot change after creation.

Creation: photo → square crop → split → invitation code → other participant joins. Unlocks require membership and ownership. Show combined percentage, remaining blocks, You/Friend contribution counts, credit balance, one Unlock Pixel action, and contribution dates. Completed canvases appear in Gallery with study time and completion date. Deleting a canvas removes image/attribution while retaining anonymous debit accounting.

## Photo Swap

Each sent photo is independent, including one-way sends. A recipient may accept, decline, or delete a photo. Pending inbox entries have no photo preview. After acceptance only the recipient may unlock the Mystery Canvas. No chat or reciprocal-send requirement. UI concealment is not cryptographic protection if the full pixel data is delivered.

## Study and rewards

Preserve Timer presets 25/30/45/60 minutes with pause/resume/reset and local completion notifications. Preserve an unbounded hours/minutes/seconds stopwatch with start/pause/resume/finish. Count only active running segments, including background time; exclude pauses and discard canceled sessions entirely. Cap completed Focus Timers at the selected duration.

Persist timing transitions and reconcile on foreground/relaunch. Require a private local study-photo confirmation to finalize a completed session. This ritual does not verify study activity. Award exactly once, including zero-credit finalizations, using:

```swift
credits = floor((previousConfirmedSeconds + sessionActiveSeconds) / 1800)
        - floor(previousConfirmedSeconds / 1800)
```

Carry fractional study time forward across confirmed sessions. Save confirmation photo, award delta, and finalization together. Derive the local balance from finalized awards minus real debit receipts. Roll back failed saves. Never upload study-proof photos. Do not count or spend simulated Friend credits in the real study balance.

## Implemented fallback and remote boundary

Firebase is not configured in this repository. Implement a clearly labeled one-device collaboration demo. Codes only resolve local records. Role switching simulates both participants and is not authentication. Your credits remain study-earned; Friend can simulate study for explicitly separated per-canvas demo credits. Save ownership, join state, swap state, contribution attribution, and debit atomically in SwiftData. Never imply synchronization, private device-to-device transfer, or server validation exists.

Real sharing requires Firebase anonymous auth, Firestore and private Storage, real member IDs, server-generated expiring invitations, member-only rules, upload consent, realtime synchronization, offline/loading/error states, and server-authoritative study rewards. Use an authenticated server operation/transaction for reward validation and atomic spending/unlocking; local and remote stores cannot jointly guarantee atomicity. Keep the local personal canvas feature available offline.

## Acceptance checks

- Every layout has exactly 18 blocks per user; wrong-owner unlocks cannot debit.
- Only the second participant can consume a local invitation; a third join/reused code fails.
- Unlocking the same block twice charges once; insufficient funds change neither progress nor ledger.
- Friend demo receipts cannot reduce/inflate the real balance.
- A one-way Photo Swap works without a response; sender cannot accept or unlock the recipient's photo.
- Pending/locked Mystery UI has no full-color preview.
- Combined completion reaches 36 blocks across both owners and enters Gallery.
- Verify 24×24 dimensions and RGB preservation, all eight orientations, square-crop bounds, exactly 16 original pixels per block with no overlaps, nearest-neighbor rendered output, and restored source colors after reopening.
- Existing timing, carry, reward idempotency, restart persistence, and deletion/no-refund checks remain passing.
- Manual release validation covers device notifications, crop gestures, real saved-store migration, accessibility, creation time under one minute, and student usability.
