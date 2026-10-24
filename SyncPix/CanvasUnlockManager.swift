import Foundation
import SwiftData

/// Local, serialized debit + reveal operation. Remote wallets require a server transaction.
@MainActor enum CanvasUnlockManager {
    static func unlock(_ block: Int, canvas: PixelCanvas, seat: Int = 0, context: ModelContext) throws {
        guard (0..<36).contains(block), !canvas.unlockedBlocks.contains(block) else { return }
        guard canvas.canUnlock(block, seat: seat) else { throw CollaborationError.notYourBlock }
        if seat == 0 {
            guard try PixelCreditManager.balance(context) > 0 else { throw AppFailure.noCredit }
        } else {
            guard canvas.friendDemoCredits > 0 else { throw AppFailure.noCredit }
        }
        do {
            canvas.unlockedBlocks.append(block)
            let spend = PixelSpend(canvasID: canvas.id, block: block)
            spend.contributor = seat == 0 ? "You" : "Friend (demo)"
            spend.isDemo = seat == 1
            context.insert(spend)
            if seat == 1 { canvas.friendDemoCredits -= 1 }
            if canvas.unlockedBlocks.count == 36 {
                canvas.completedAt = .now
                canvas.studySecondsAtCompletion = try PixelCreditManager.confirmedSeconds(context)
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
