import XCTest
import SwiftData
import UIKit
import SwiftUI
@testable import SyncPix

@MainActor final class SyncPixTests: XCTestCase {
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([StudySession.self, PixelCanvas.self, PixelSpend.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
    private var photo: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }.pngData()!
    }
    private func pending(_ seconds: Double, context: ModelContext) -> StudySession {
        let session = StudySession(mode: "Stopwatch", minutes: 30)
        session.status = "awaitingPhoto"; session.segmentStart = nil; session.activeSeconds = seconds
        context.insert(session); return session
    }
    func testRewardBoundariesAndDuplicateConfirmation() throws {
        for (seconds, expected) in [(1799.0, 0), (1800, 1), (3599, 1), (3600, 2)] {
            let store = try container(); let context = store.mainContext
            let session = pending(seconds, context: context)
            try PixelCreditManager.confirm(session, photo: photo, context: context)
            try PixelCreditManager.confirm(session, photo: photo, context: context)
            XCTAssertEqual(try PixelCreditManager.balance(context), expected)
        }
    }
    func testCarryAndPausedTime() throws {
        let store = try container(); let context = store.mainContext
        let first = pending(1500, context: context)
        try PixelCreditManager.confirm(first, photo: photo, context: context)
        XCTAssertEqual(first.awardedCredits, 0)
        let second = pending(300, context: context)
        XCTAssertEqual(second.elapsed(at: .now.addingTimeInterval(600)), 300)
        try PixelCreditManager.confirm(second, photo: photo, context: context)
        XCTAssertEqual(second.awardedCredits, 1)
        XCTAssertEqual(try PixelCreditManager.balance(context), 1)
    }
    func testTimerRecoveryAndUnboundedStopwatch() throws {
        let store = try container(); let context = store.mainContext
        let timer = StudySession(mode: "Timer", minutes: 30)
        timer.segmentStart = .now.addingTimeInterval(-4000); context.insert(timer)
        let expectedDate = timer.segmentStart!.addingTimeInterval(1800)
        try StudySessionManager().reconcile(timer, context: context)
        XCTAssertEqual(timer.status, "awaitingPhoto")
        XCTAssertEqual(timer.activeSeconds, 1800)
        XCTAssertEqual(timer.completedAt!.timeIntervalSince(expectedDate), 0, accuracy: 0.01)
        let expired = StudySession(mode: "Timer", minutes: 25)
        expired.segmentStart = .now.addingTimeInterval(-1800); context.insert(expired)
        try StudySessionManager().transition(expired, to: "paused", context: context)
        XCTAssertEqual(expired.status, "awaitingPhoto")
        let stopwatch = StudySession(mode: "Stopwatch", minutes: 30)
        stopwatch.segmentStart = .now.addingTimeInterval(-100000)
        XCTAssertGreaterThanOrEqual(stopwatch.elapsed(), 100000)
    }
    func testAtomicUnlockAndDeletionNoRefund() throws {
        let store = try container(); let context = store.mainContext
        try PixelCreditManager.confirm(pending(1800, context: context), photo: photo, context: context)
        let canvas = PixelCanvas(title: "Test", resolution: 16, mode: "Mystery Reveal", pixels: Array(repeating: 0xFF0000, count: 256))
        context.insert(canvas)
        try CanvasUnlockManager.unlock(0, canvas: canvas, context: context)
        try CanvasUnlockManager.unlock(0, canvas: canvas, context: context)
        XCTAssertEqual(canvas.unlockedBlocks, [0])
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
        XCTAssertThrowsError(try CanvasUnlockManager.unlock(1, canvas: canvas, context: context))
        XCTAssertEqual(canvas.unlockedBlocks, [0])
        try CanvasRepository.delete(canvas, context: context)
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PixelCanvas>()).isEmpty)
    }
    func testPixelArtProcessorResolutionsAndColor() throws {
        let image = UIImage(data: photo)!
        for size in [16, 24, 32] {
            let result = try PixelArtProcessor.process(image, resolution: size, zoom: 1, offset: .zero)
            XCTAssertEqual(result.count, size * size)
            XCTAssertTrue(result.allSatisfy { $0 == 0xFF0000 })
        }
    }
    func testPixelOrientation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 8, width: 16, height: 8))
        }
        let pixels = try PixelArtProcessor.process(image, resolution: 16, zoom: 1, offset: .zero)
        XCTAssertEqual(pixels.first, 0xFF0000)
        XCTAssertEqual(pixels.last, 0x0000FF)
    }
    func testPersistenceAndAwardAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Study.store")
        var id = UUID()
        do {
            let store = try container(url: url); let context = store.mainContext
            let session = pending(1800, context: context); id = session.id
            try PixelCreditManager.confirm(session, photo: photo, context: context)
        }
        do {
            let store = try container(url: url); let context = store.mainContext
            let restored = try XCTUnwrap(context.fetch(FetchDescriptor<StudySession>()).first { $0.id == id })
            try PixelCreditManager.confirm(restored, photo: photo, context: context)
            XCTAssertEqual(try PixelCreditManager.balance(context), 1)
            XCTAssertNotNil(restored.proofPhoto)
        }
    }
    private func sync(_ context: ModelContext, layout: String = "Half & Half") throws -> PixelCanvas {
        try CollaborationService.create(title: "Together", pixels: Array(repeating: 0xAABBCC, count: 576), kind: "sync", layout: layout, seat: 0, context: context)
        return try XCTUnwrap(context.fetch(FetchDescriptor<PixelCanvas>()).first)
    }
    func testOwnershipLayoutsHaveEighteenBlocksPerPerson() throws {
        let store = try container()
        for layout in ["Half & Half", "Puzzle Pieces"] {
            let canvas = PixelCanvas(title: "Ownership", resolution: 24, mode: "Color Restore", pixels: [])
            canvas.kind = "sync"; canvas.splitLayout = layout; canvas.friendJoined = true
            XCTAssertEqual((0..<36).filter { canvas.owner(of: $0) == 0 }.count, 18)
            XCTAssertEqual((0..<36).filter { canvas.owner(of: $0) == 1 }.count, 18)
            for block in 0..<36 {
                XCTAssertTrue(canvas.canUnlock(block, seat: canvas.owner(of: block)))
                XCTAssertFalse(canvas.canUnlock(block, seat: 1 - canvas.owner(of: block)))
            }
        }
        let canvas = try sync(store.mainContext)
        XCTAssertEqual(canvas.owner(of: 0), 0)
        XCTAssertEqual(canvas.owner(of: 3), 1)
        canvas.splitLayout = "Puzzle Pieces"
        XCTAssertEqual(canvas.owner(of: 0), 0)
        XCTAssertEqual(canvas.owner(of: 3), 1)
        XCTAssertEqual(canvas.owner(of: 18), 1)
        XCTAssertEqual(canvas.owner(of: 21), 0)
    }
    func testLocalInviteRequiresSecondParticipantAndIsSingleUse() throws {
        let store = try container(); let context = store.mainContext
        let canvas = try sync(context)
        let code = try XCTUnwrap(canvas.invitationCode)
        XCTAssertFalse(canvas.canUnlock(0, seat: 0))
        XCTAssertThrowsError(try CollaborationService.join(code: code, seat: 0, context: context))
        XCTAssertThrowsError(try CollaborationService.join(code: "INVALID", seat: 1, context: context))
        let joined = try CollaborationService.join(code: " \(code.lowercased()) ", seat: 1, context: context)
        XCTAssertEqual(joined.id, canvas.id)
        XCTAssertNil(canvas.invitationCode)
        XCTAssertThrowsError(try CollaborationService.join(code: code, seat: 1, context: context))
        XCTAssertTrue(canvas.canUnlock(0, seat: 0))
    }
    func testSharedUnlockEnforcesOwnershipAndIsolatesFriendCredits() throws {
        let store = try container(); let context = store.mainContext
        try PixelCreditManager.confirm(pending(1800, context: context), photo: photo, context: context)
        let canvas = try sync(context); canvas.friendJoined = true
        XCTAssertThrowsError(try CanvasUnlockManager.unlock(3, canvas: canvas, seat: 0, context: context))
        XCTAssertEqual(try PixelCreditManager.balance(context), 1)
        try CanvasUnlockManager.unlock(0, canvas: canvas, seat: 0, context: context)
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
        try CollaborationService.simulateFriendStudy(canvas, context: context)
        XCTAssertThrowsError(try CanvasUnlockManager.unlock(1, canvas: canvas, seat: 1, context: context))
        try CanvasUnlockManager.unlock(3, canvas: canvas, seat: 1, context: context)
        try CanvasUnlockManager.unlock(3, canvas: canvas, seat: 1, context: context)
        XCTAssertEqual(canvas.friendDemoCredits, 0)
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
        XCTAssertEqual(canvas.unlockedBlocks.sorted(), [0, 3])
        let receipts = try context.fetch(FetchDescriptor<PixelSpend>())
        XCTAssertEqual(receipts.count, 2)
        XCTAssertEqual(receipts.filter { $0.isDemo }.count, 1)
    }
    func testOneWayPhotoSwapRequiresRecipientAcceptance() throws {
        let store = try container(); let context = store.mainContext
        try CollaborationService.create(title: "Secret", pixels: Array(repeating: 0x123456, count: 576), kind: "swap", layout: "Half & Half", seat: 0, context: context)
        let canvas = try XCTUnwrap(context.fetch(FetchDescriptor<PixelCanvas>()).first)
        XCTAssertEqual(canvas.revealMode, "Mystery Reveal")
        XCTAssertTrue(canvas.unlockedBlocks.isEmpty)
        XCTAssertFalse(canvas.canUnlock(0, seat: 1))
        XCTAssertThrowsError(try CollaborationService.accept(canvas, seat: 0, context: context))
        try CollaborationService.accept(canvas, seat: 1, context: context)
        XCTAssertFalse(canvas.canUnlock(0, seat: 0))
        XCTAssertTrue(canvas.canUnlock(0, seat: 1))
        try CollaborationService.simulateFriendStudy(canvas, context: context)
        try CanvasUnlockManager.unlock(0, canvas: canvas, seat: 1, context: context)
        XCTAssertEqual(canvas.unlockedBlocks, [0])
        try CanvasRepository.delete(canvas, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PixelCanvas>()).isEmpty)
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
    }
    func testSharedCompletionAcrossBothParticipants() throws {
        let store = try container(); let context = store.mainContext
        try PixelCreditManager.confirm(pending(18 * 1800, context: context), photo: photo, context: context)
        let canvas = try sync(context, layout: "Puzzle Pieces"); canvas.friendJoined = true
        for block in 0..<36 {
            let seat = canvas.owner(of: block)
            if seat == 1 { try CollaborationService.simulateFriendStudy(canvas, context: context) }
            try CanvasUnlockManager.unlock(block, canvas: canvas, seat: seat, context: context)
        }
        XCTAssertEqual(canvas.unlockedBlocks.count, 36)
        XCTAssertNotNil(canvas.completedAt)
        XCTAssertEqual(try PixelCreditManager.balance(context), 0)
        XCTAssertEqual(canvas.friendDemoCredits, 0)
    }

    func testCollaborationStateSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Together.store")
        do {
            let store = try container(url: url); let context = store.mainContext
            try PixelCreditManager.confirm(pending(1800, context: context), photo: photo, context: context)
            let canvas = try sync(context)
            _ = try CollaborationService.join(code: XCTUnwrap(canvas.invitationCode), seat: 1, context: context)
            try CanvasUnlockManager.unlock(0, canvas: canvas, context: context)
            try CollaborationService.simulateFriendStudy(canvas, context: context)
            try CanvasUnlockManager.unlock(3, canvas: canvas, seat: 1, context: context)
        }
        do {
            let store = try container(url: url); let context = store.mainContext
            let canvas = try XCTUnwrap(context.fetch(FetchDescriptor<PixelCanvas>()).first)
            XCTAssertEqual(canvas.kind, "sync")
            XCTAssertEqual(canvas.resolution, 24)
            XCTAssertEqual(canvas.splitLayout, "Half & Half")
            XCTAssertTrue(canvas.friendJoined)
            XCTAssertNil(canvas.invitationCode)
            XCTAssertEqual(canvas.unlockedBlocks.sorted(), [0, 3])
            XCTAssertEqual(canvas.pixels, Array(repeating: 0xAABBCC, count: 576))
            XCTAssertEqual(canvas.pixelIndices(in: 0).count, 16)
            let visible = PixelBlockLayout.displayColors(canvas.pixels, mode: canvas.revealMode, unlocked: canvas.unlockedBlocks)
            XCTAssertEqual(visible.filter { $0 == 0xAABBCC }.count, 32)
            XCTAssertEqual(canvas.friendDemoCredits, 0)
            try CanvasUnlockManager.unlock(0, canvas: canvas, context: context)
            XCTAssertEqual(try PixelCreditManager.balance(context), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PixelSpend>()), 2)
        }
    }

    func testExact24RasterAndRGBRoundTrip() throws {
        let colors = (0..<576).map { ($0 * 23119) & 0xFFFFFF }
        let raster = try PixelArtProcessor.image(from: colors)
        XCTAssertEqual(raster.cgImage?.width, 24)
        XCTAssertEqual(raster.cgImage?.height, 24)
        XCTAssertEqual(raster.imageOrientation, .up)
        XCTAssertEqual(try PixelArtProcessor.process(raster), colors)
        let retina = UIImage(cgImage: try XCTUnwrap(raster.cgImage), scale: 2, orientation: .up)
        XCTAssertEqual(try PixelArtProcessor.process(retina), colors)
        XCTAssertThrowsError(try PixelArtProcessor.image(from: [0]))
        XCTAssertThrowsError(try PixelArtProcessor.process(raster, resolution: 0))
        XCTAssertThrowsError(try PixelArtProcessor.process(raster, zoom: .nan))
    }
    func testEveryBlockMapsToSixteenPixelsWithoutOverlap() {
        var covered = Set<Int>()
        for block in 0..<36 {
            let indices = PixelBlockLayout.pixelIndices(in: block)
            XCTAssertEqual(indices.count, 16)
            XCTAssertTrue(covered.isDisjoint(with: indices))
            covered.formUnion(indices)
            for index in indices {
                XCTAssertEqual(PixelBlockLayout.blockID(x: index % 24, y: index / 24), block)
            }
        }
        XCTAssertEqual(covered, Set(0..<576))
        XCTAssertEqual(PixelBlockLayout.pixelIndices(in: 0), [0, 1, 2, 3, 24, 25, 26, 27, 48, 49, 50, 51, 72, 73, 74, 75])
        XCTAssertTrue(PixelBlockLayout.pixelIndices(in: 36).isEmpty)
        XCTAssertNil(PixelBlockLayout.blockID(x: -1, y: 0))
    }
    func testRevealRestoresOnlyTheSelectedSixteenOriginalColors() {
        let colors = (0..<576).map { ($0 * 23119) & 0xFFFFFF }
        for mode in ["Color Restore", "Mystery Reveal"] {
            let locked = PixelBlockLayout.lockedColors(colors, mode: mode)
            for block in 0..<36 {
                let indices = Set(PixelBlockLayout.pixelIndices(in: block))
                let restored = PixelBlockLayout.displayColors(colors, mode: mode, unlocked: [block])
                for index in colors.indices {
                    XCTAssertEqual(restored[index], indices.contains(index) ? colors[index] : locked[index])
                }
            }
            XCTAssertEqual(PixelBlockLayout.displayColors(colors, mode: mode, unlocked: Array(0..<36)), colors)
        }
        let gray = PixelBlockLayout.lockedColors([0xFF0000], mode: "Color Restore")[0]
        XCTAssertEqual((gray >> 16) & 255, gray & 255)
        XCTAssertEqual((gray >> 8) & 255, gray & 255)
        XCTAssertEqual(Set(PixelBlockLayout.lockedColors(colors, mode: "Mystery Reveal")).count, 1)
    }
    func testAllUIImageOrientationsNormalize() throws {
        let colors = (0..<576).map { $0 / 24 < 12 ? ($0 % 24 < 12 ? 0xFF0000 : 0x00FF00) : ($0 % 24 < 12 ? 0x0000FF : 0xFFFF00) }
        let cg = try XCTUnwrap(PixelArtProcessor.image(from: colors).cgImage)
        // Expected top-left, top-right, bottom-left, bottom-right after UIImage's transform.
        let expectations: [(UIImage.Orientation, [Int])] = [
            (.up, [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00]),
            (.down, [0xFFFF00, 0x0000FF, 0x00FF00, 0xFF0000]),
            (.upMirrored, [0x00FF00, 0xFF0000, 0xFFFF00, 0x0000FF]),
            (.downMirrored, [0x0000FF, 0xFFFF00, 0xFF0000, 0x00FF00]),
            (.left, [0x00FF00, 0xFFFF00, 0xFF0000, 0x0000FF]),
            (.right, [0x0000FF, 0xFF0000, 0xFFFF00, 0x00FF00]),
            (.leftMirrored, [0xFF0000, 0x0000FF, 0x00FF00, 0xFFFF00]),
            (.rightMirrored, [0xFFFF00, 0x00FF00, 0x0000FF, 0xFF0000])
        ]
        for (orientation, corners) in expectations {
            let source = UIImage(cgImage: cg, scale: 1, orientation: orientation)
            XCTAssertEqual(try PixelArtProcessor.normalizeOrientation(source).imageOrientation, .up)
            let output = try PixelArtProcessor.process(source)
            XCTAssertEqual([output[0], output[23], output[552], output[575]], corners, "orientation \(orientation.rawValue)")
        }
    }
    func testSquareCropAndOutOfBoundsOffsetClamping() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 24), format: format).image { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 24))
            UIColor.red.setFill(); ctx.fill(CGRect(x: 12, y: 0, width: 24, height: 24))
        }
        XCTAssertTrue(try PixelArtProcessor.process(source).allSatisfy { $0 == 0xFF0000 })
        let rotated = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .left)
        let normalized = try PixelArtProcessor.normalizeOrientation(rotated)
        XCTAssertEqual(normalized.cgImage?.width, 24)
        XCTAssertEqual(normalized.cgImage?.height, 48)
        XCTAssertTrue(try PixelArtProcessor.process(rotated).allSatisfy { $0 == 0xFF0000 })
        let edge = try PixelArtProcessor.process(source, offset: CGSize(width: 100, height: 100))
        XCTAssertFalse(edge.contains(0xFFFFFF), "Crop must not expose unpainted borders")
        XCTAssertEqual(edge.count, 576)
    }
    func testPixelCanvasRendersNearestNeighborAndMasksMystery() throws {
        let colors = (0..<576).map { $0 % 24 % 2 == 0 ? 0xFF0000 : 0x0000FF }
        let renderer = ImageRenderer(content: PixelCanvasView(pixels: colors, resolution: 24, mode: "Mystery Reveal", unlocked: [0]).frame(width: 240, height: 240))
        renderer.scale = 1
        let snapshot = try XCTUnwrap(renderer.uiImage)
        let sampled = try PixelArtProcessor.process(snapshot, resolution: 240)
        for y in 0..<240 {
            for x in 0..<240 {
                let expected = x < 40 && y < 40 ? (x / 10 % 2 == 0 ? 0xFF0000 : 0x0000FF) : 0xE0D4D1
                if sampled[y * 240 + x] != expected {
                    XCTFail("Unexpected rendered color at \(x),\(y): \(sampled[y * 240 + x]) instead of \(expected)")
                    return
                }
            }
        }
    }

}
