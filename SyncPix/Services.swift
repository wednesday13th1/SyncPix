import SwiftUI
import SwiftData
import UIKit
import UserNotifications

enum AppFailure: LocalizedError {
    case image, noCredit, unavailable
    var errorDescription: String? {
        switch self {
        case .image: return "The photo could not be processed. Please choose another photo."
        case .noCredit: return "Study and confirm a photo to earn a Pixel Credit first."
        case .unavailable: return "This session has already changed. Please try again."
        }
    }
}

@MainActor struct PixelCreditManager {
    static func confirmedSeconds(_ context: ModelContext) throws -> Double {
        try context.fetch(FetchDescriptor<StudySession>()).filter { $0.status == "confirmed" }.reduce(0) { $0 + $1.activeSeconds }
    }
    static func balance(_ context: ModelContext) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        return sessions.reduce(0) { $0 + ($1.awardedCredits ?? 0) } - (try context.fetch(FetchDescriptor<PixelSpend>()).filter { !$0.isDemo }.count)
    }
    static func confirm(_ session: StudySession, photo: Data, context: ModelContext) throws {
        guard session.status == "awaitingPhoto", session.awardedCredits == nil else { return }
        guard UIImage(data: photo) != nil else { throw AppFailure.image }
        let before = try confirmedSeconds(context)
        session.proofPhoto = photo
        session.awardedCredits = Int((before + session.activeSeconds) / 1800) - Int(before / 1800)
        session.status = "confirmed"
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

@MainActor struct CanvasRepository {
    static func delete(_ canvas: PixelCanvas, context: ModelContext) throws {
        // Anonymize debit receipts: keep the balance without retaining canvas attribution.
        for receipt in try context.fetch(FetchDescriptor<PixelSpend>()) where receipt.canvasID == canvas.id {
            receipt.canvasID = UUID(); receipt.key = UUID().uuidString; receipt.block = -1
            receipt.contributor = ""; receipt.date = Date(timeIntervalSince1970: 0)
        }
        context.delete(canvas)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

@MainActor @Observable final class StudySessionManager {
    var notice: String?
    func start(mode: String, minutes: Int, context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        guard !sessions.contains(where: { ["running", "paused", "awaitingPhoto"].contains($0.status) }) else { throw AppFailure.unavailable }
        let session = StudySession(mode: mode, minutes: minutes)
        context.insert(session)
        do { try context.save() } catch { context.rollback(); throw error }
        schedule(session)
    }
    func transition(_ session: StudySession, to status: String, context: ModelContext) throws {
        guard ["running", "paused"].contains(session.status) else { return }
        let oldNotificationID = notificationID(session)
        let elapsed = session.elapsed()
        let nextStatus = session.mode == "Timer" && elapsed >= session.targetSeconds && status != "discarded" ? "awaitingPhoto" : status
        let deadline = session.segmentStart.map { $0.addingTimeInterval(max(0, session.targetSeconds - session.activeSeconds)) }
        session.activeSeconds = elapsed
        session.segmentStart = nextStatus == "running" ? .now : nil
        session.status = nextStatus
        if nextStatus == "awaitingPhoto" {
            session.completedAt = session.mode == "Timer" && elapsed >= session.targetSeconds ? deadline ?? .now : .now
        }
        do { try context.save() } catch { context.rollback(); throw error }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [oldNotificationID])
        if nextStatus == "running" { schedule(session) }
    }
    func reconcile(_ session: StudySession?, context: ModelContext) throws {
        if let session, session.status == "running", session.mode == "Timer", session.elapsed() >= session.targetSeconds {
            try transition(session, to: "awaitingPhoto", context: context)
        }
    }
    private func notificationID(_ session: StudySession) -> String {
        "\(session.id.uuidString)-\(session.segmentStart?.timeIntervalSince1970 ?? 0)"
    }
    private func schedule(_ session: StudySession) {
        guard session.mode == "Timer", session.status == "running" else { return }
        let id = notificationID(session)
        let segment = session.segmentStart
        let deadline = Date.now.addingTimeInterval(max(1, session.targetSeconds - session.elapsed()))
        Task { @MainActor in
            do {
                let center = UNUserNotificationCenter.current()
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed, session.status == "running", session.segmentStart == segment else { return }
                let content = UNMutableNotificationContent()
                content.title = "A little study, a little color"
                content.body = "Your focus timer is complete. Confirm your study photo in SyncPix."
                content.sound = .default
                try await center.add(UNNotificationRequest(identifier: id, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
                if session.status != "running" || session.segmentStart != segment {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                }
            } catch { notice = "Timer alerts are unavailable: \(error.localizedDescription)" }
        }
    }
}

enum CollaborationError: LocalizedError {
    case notYourBlock, invitation, recipientOnly
    var errorDescription: String? {
        switch self {
        case .notYourBlock: return "Choose one of your locked blocks. Both demo participants must join a Sync Canvas first."
        case .invitation: return "Code not found on this device, already joined, or belongs to the selected participant. Switch demo participant to join."
        case .recipientOnly: return "Only the recipient can accept this photo."
        }
    }
}

@MainActor struct CollaborationService {
    static let status = "Local collaboration demo · one device only. Codes do not connect devices. Switch between You and Friend to try both roles. Your credits come from study; Friend credits are simulated separately."
    static func create(title: String, pixels: [Int], kind: String, layout: String, seat: Int, context: ModelContext) throws {
        guard pixels.count == 576, ["sync", "swap"].contains(kind), (0...1).contains(seat), ["Half & Half", "Puzzle Pieces"].contains(layout) else { throw AppFailure.image }
        let canvas = PixelCanvas(title: title, resolution: 24, mode: kind == "swap" ? "Mystery Reveal" : "Color Restore", pixels: pixels)
        canvas.kind = kind; canvas.splitLayout = layout; canvas.creatorSeat = seat; canvas.senderSeat = seat
        if kind == "sync" { canvas.invitationCode = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased() }
        context.insert(canvas)
        do { try context.save() } catch { context.rollback(); throw error }
    }
    static func join(code: String, seat: Int, context: ModelContext) throws -> PixelCanvas {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (0...1).contains(seat), let canvas = try context.fetch(FetchDescriptor<PixelCanvas>()).first(where: {
            $0.kind == "sync" && $0.invitationCode == normalized && !$0.friendJoined && $0.creatorSeat != seat
        }) else { throw CollaborationError.invitation }
        canvas.friendJoined = true; canvas.invitationCode = nil
        do { try context.save() } catch { context.rollback(); throw error }
        return canvas
    }
    static func accept(_ canvas: PixelCanvas, seat: Int, context: ModelContext) throws {
        guard canvas.kind == "swap", (0...1).contains(seat), canvas.senderSeat == 1 - seat, canvas.swapStatus == "pending" else { throw CollaborationError.recipientOnly }
        canvas.swapStatus = "accepted"
        do { try context.save() } catch { context.rollback(); throw error }
    }
    static func simulateFriendStudy(_ canvas: PixelCanvas, context: ModelContext) throws {
        guard canvas.kind != "personal" else { throw CollaborationError.notYourBlock }
        canvas.friendDemoCredits += 1
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

@MainActor @Observable final class CanvasViewModel {
    var error: String?
    func unlock(_ block: Int, canvas: PixelCanvas, seat: Int = 0, context: ModelContext) {
        do { try CanvasUnlockManager.unlock(block, canvas: canvas, seat: seat, context: context) }
        catch { self.error = error.localizedDescription }
    }
}
