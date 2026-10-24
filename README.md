# SyncPix

“Two people. One picture. Every study session brings it to life.”

SwiftUI + SwiftData, iOS 17+, iPhone/iPad. Open `SyncPix.xcodeproj`, select the shared **SyncPix** scheme, and choose a simulator or your signing team for a physical device.

## Current scope

Only **Home** and **Together** are main tabs. Home contains the current canvas, study mode/preset, available Pixel Credits, a one-tap Start Studying action, Create Canvas, and a Gallery link. Personal canvases remain available offline. Gallery shows completed artworks and retains access to older unfinished personal canvases.

New canvases use 24×24 pixel colors, divided into 36 blocks of 4×4 pixels. Existing 16×16/32×32 canvases remain readable. Import through PhotosPicker, drag/pinch to crop a square, and use the zoom/position controls as accessible alternatives. Core Graphics samples the source photo; the pixel view draws flat, non-antialiased cells with no interpolation between colors, equivalent to nearest-neighbor enlargement. Color Restore starts grayscale, Mystery Reveal starts neutral.

Timer/stopwatch, photo confirmation, carried study seconds, idempotent awards, local notifications, saved history, and study-photo deletion are preserved. Home starts the selected study mode directly; ongoing sessions reopen without starting another one. Study-proof photos stay local and are never uploaded. Canceled sessions yield no time or credits.

## Local collaboration demo — no Firebase or device synchronization

This repository has no Firebase configuration or SDK dependencies. **Together is explicitly a one-device demo.** There is no real invitation, authentication, private transfer, cloud upload, server wallet, or realtime synchronization. Switching demo participant is a development simulation, not an identity boundary.

### Sync Canvas

1. In Together, select **You**, create a Sync Canvas, choose a photo/crop and a split layout, then save.
2. Open the canvas and copy its **local** code.
3. Return to Together, switch to **Friend (demo)**, and enter that code on the same device. The code is consumed once joined; the creator cannot join their own invite. There are exactly two seats.
4. Switch roles to try each side. Half & Half assigns three columns each. Puzzle Pieces assigns two diagonal 3×3-block quadrants each. Both layouts assign exactly 18 blocks per participant.
5. Tap an owned block to select it, then **Unlock Pixel**. Ownership uses circle/diamond symbols and accessible labels, beyond color alone. If no block is selected, the action chooses the first eligible block. See combined completion, individual contributions, remaining blocks, and the latest contribution date.
6. **You** spends credits from confirmed study sessions. **Friend** can use the explicitly labeled “Simulate Friend studying 30 min” action; those demo credits belong only to this canvas and never enter the actual study balance. Simulated friend spending has separate receipts.

The local model context serializes unlocks, debits, and contribution attribution in one save, rolling back failures. Unlocked blocks cannot be charged twice; wrong-owner attempts cannot spend credits. Complete all 36 blocks to appear in Gallery. Artwork deletion anonymizes debit receipts and does not refund spent credits.

### Photo Swap

Send a photo in Together, then switch demo roles to see the recipient inbox. A pending received photo displays no image preview and can be accepted or declined. Acceptance creates no reciprocal sending obligation. The recipient receives a Mystery Canvas, spends their own applicable credits, and can delete it. Sending a photo back is a separate independent action. In this local demo, deleting a received canvas also removes the corresponding local sent record.

Mystery colors are hidden in recipient previews and thumbnails until blocks are unlocked. **This is UI concealment, not cryptographic protection**: all pixel colors exist in the local store. The photo picker/crop editor shows the sender's own selected image. Do not interpret this demo as secure private sharing.

## Files and architecture

| File | Responsibility |
| --- | --- |
| `Models.swift` | StudySession, PixelCanvas with defaulted collaboration metadata, PixelSpend with separate demo receipts, ownership policy |
| `Services.swift` | PixelProcessor, StudySessionManager, PixelCreditManager, CanvasRepository, CanvasViewModel, local CollaborationService |
| `ContentView.swift` | Two-tab shell, Home, pixel renderer, foreground timer reconciliation |
| `CreateCanvasView.swift` | Photo import, bounded drag/zoom crop, fixed-resolution preview and save |
| `CanvasDetailView.swift` | Ownership selection, one unlock action, contribution/progress labels |
| `TogetherView.swift` | Demo role selection, create/join, Photo Swap inbox and sent records |
| `GalleryView.swift` | Home-accessible gallery and deletion |
| `StudyView.swift` | Existing timer/stopwatch, confirmation and private history; shared mode/preset preferences |
| `MyApp.swift` | Shared SwiftData container |
| `SyncPixTests/SyncPixTests.swift` | Timing/reward persistence, image processing, ownership, invite, swap, spending and completion tests |

Collaboration fields have defaults so existing personal canvases and debit receipts retain their original interpretation. Local serial execution protects this device's accounting only; it is not a security model for distributed clients. Device-clock manipulation is not prevented by the offline study timer.

## Validation and manual setup

Use Product → Test or:

```sh
xcodebuild -project SyncPix.xcodeproj -scheme SyncPix \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Choose your signing team/bundle identifier for physical-device installation. No Firebase keys are needed for the demo. Notification permission is requested contextually on Timer start. Validate notification delivery on a physical device, including denial and background expiration.

Before release, test iOS 17 runtime behavior, large/rotated photos, drag/pinch crops, migration with real saved artworks, VoiceOver, Dynamic Type, Reduce Motion, and 44-point hit areas on small screens. Test process termination in running/paused/pending-photo states and actual persistence failures. Have students assess 24×24 recognition, creation speed, unlock satisfaction, and shared motivation; no user-study outcomes are claimed.

## Real collaboration requires a separate configured backend

To replace the demo, configure Firebase Authentication (anonymous sign-in), Firestore, and private Storage with the project's GoogleService-Info.plist. Add SDK dependencies only when implementing that integration. Use real member UIDs, exactly two members, expiring server-issued invitations, member-scoped Firestore/Storage rules, realtime listeners, consent before photo upload, and explicit offline/loading/error states. Never upload study-proof photos.

A local SwiftData balance cannot atomically participate in a Firestore transaction. Use a server-authoritative award ledger and authenticated server operation to validate earned time, assigned ownership, balance, and the still-locked block before atomically charging/unlocking. Do not trust client-awarded balances or claim that a selected study photo verifies study activity. Server session timing/idempotency and anti-replay need an explicit protocol. Mystery delivery must document its privacy limits; access-controlled full-image delivery still allows a determined authorized recipient to inspect the bytes.

### Verification — 2026-10-25

The app and tests built with Xcode 27.1, and all **13 XCTest cases passed** on iPhone 18 Pro / iOS 27.0 Simulator. Coverage includes both ownership layouts, consumed invites, owner-only atomic local spending, isolated Friend demo credits, one-way Photo Swap, shared completion, collaboration progress restored from disk, and the existing timing/reward/image tests. `git diff --check` passed. This round did not verify gesture interactions, screen layouts, real device notifications, iOS 17 runtime behavior, or multi-device operation; real multi-device collaboration is not implemented.
# SyncPix
