import Foundation
import SwiftData

@Model final class StudySession {
    @Attribute(.unique) var id: UUID
    var mode: String
    var status: String
    var startedAt: Date
    var segmentStart: Date?
    var activeSeconds: Double
    var targetSeconds: Double
    var completedAt: Date?
    var awardedCredits: Int?
    @Attribute(.externalStorage) var proofPhoto: Data?
    init(mode: String, minutes: Int) {
        id = UUID(); self.mode = mode; status = "running"; startedAt = .now
        segmentStart = .now; activeSeconds = 0; targetSeconds = Double(minutes * 60)
    }
    func elapsed(at date: Date = .now) -> Double {
        let value = activeSeconds + max(0, segmentStart.map { date.timeIntervalSince($0) } ?? 0)
        return mode == "Timer" ? min(targetSeconds, value) : value
    }
}

@Model final class PixelCanvas {
    @Attribute(.unique) var id: UUID
    var title: String
    var resolution: Int
    var revealMode: String
    var createdAt: Date
    var completedAt: Date?
    var studySecondsAtCompletion: Double
    /// Original sampled sRGB colors. Revealing changes IDs, never these values.
    var pixels: [Int]
    var unlockedBlocks: [Int]
    // Defaults preserve existing personal canvases during lightweight migration.
    var kind: String = "personal"
    var splitLayout: String = "Half & Half"
    var creatorSeat: Int = 0
    var invitationCode: String?
    var friendJoined: Bool = false
    var senderSeat: Int = 0
    var swapStatus: String = "pending"
    var friendDemoCredits: Int = 0

    func pixelIndices(in block: Int) -> [Int] {
        PixelBlockLayout.pixelIndices(in: block, resolution: resolution)
    }

    func owner(of block: Int) -> Int {
        if kind == "swap" { return 1 - senderSeat }
        guard kind == "sync" else { return 0 }
        let row = block / 6, column = block % 6
        return splitLayout == "Puzzle Pieces" ? ((row / 3 + column / 3) % 2) : (column < 3 ? 0 : 1)
    }
    func canUnlock(_ block: Int, seat: Int) -> Bool {
        guard (0..<36).contains(block), (0...1).contains(seat), !unlockedBlocks.contains(block) else { return false }
        if kind == "sync" { return friendJoined && owner(of: block) == seat }
        if kind == "swap" { return swapStatus == "accepted" && owner(of: block) == seat }
        return seat == 0
    }
    init(title: String, resolution: Int, mode: String, pixels: [Int]) {
        id = UUID(); self.title = title; self.resolution = resolution
        revealMode = mode; createdAt = .now; studySecondsAtCompletion = 0
        self.pixels = pixels; unlockedBlocks = []
    }
}

@Model final class PixelSpend {
    @Attribute(.unique) var key: String
    var canvasID: UUID
    var block: Int
    var date: Date
    var contributor: String
    var isDemo: Bool = false
    init(canvasID: UUID, block: Int) {
        key = "\(canvasID)-\(block)"; self.canvasID = canvasID
        self.block = block; date = .now; contributor = "You"
    }
}
