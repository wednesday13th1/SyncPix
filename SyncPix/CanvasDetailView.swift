import SwiftUI
import SwiftData

struct CanvasDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var spends: [PixelSpend]
    @Query private var sessions: [StudySession]
    let canvas: PixelCanvas
    var embedded = false
    var seat = 0
    @State private var selected: Int?
    @State private var model = CanvasViewModel()
    private var balance: Int {
        seat == 1 ? canvas.friendDemoCredits : sessions.reduce(0) { $0 + ($1.awardedCredits ?? 0) } - spends.filter { !$0.isDemo }.count
    }
    private var available: [Int] { (0..<36).filter { canvas.canUnlock($0, seat: seat) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(canvas.title).font(.title2.bold())
            if canvas.kind != "personal" { Label("Local demo · no device sync", systemImage: "iphone").font(.caption) }
            GeometryReader { geometry in
                ZStack {
                    PixelCanvasView(pixels: canvas.pixels, resolution: canvas.resolution, mode: canvas.revealMode, unlocked: canvas.unlockedBlocks)
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<6, id: \.self) { column in
                                    blockButton(row * 6 + column)
                                        .frame(width: geometry.size.width / 6, height: geometry.size.width / 6)
                                }
                            }
                        }
                    }
                }
            }.frame(minWidth: 264).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
            ProgressView(value: Double(canvas.unlockedBlocks.count), total: 36)
            Text("\(Int(Double(canvas.unlockedBlocks.count) / 36 * 100))% complete · \(36 - canvas.unlockedBlocks.count) blocks remaining").font(.subheadline)
            if canvas.kind == "sync" {
                ViewThatFits(in: .horizontal) {
                    HStack { contribution(0); Spacer(); contribution(1) }
                    VStack(alignment: .leading) { contribution(0); contribution(1) }
                }
                if !canvas.friendJoined {
                    Text("Waiting for the other demo participant to join.").font(.caption)
                    if seat == canvas.creatorSeat, let code = canvas.invitationCode {
                        Text("Local invite: \(code)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Text("In Together, switch demo participant and enter this code on this device.").font(.caption)
                    }
                }
            }
            if canvas.completedAt == nil {
                Text("\(balance) \(seat == 1 ? "Friend demo credits" : "Pixel Credits")").font(.headline)
                Button {
                    guard let block = selected.flatMap({ available.contains($0) ? $0 : nil }) ?? available.first else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        model.unlock(block, canvas: canvas, seat: seat, context: context)
                    }
                    selected = nil
                } label: { Label("Unlock Pixel", systemImage: "square.grid.3x3.fill").frame(maxWidth: .infinity).frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent).disabled(available.isEmpty || balance <= 0)
                if seat == 1 && canvas.kind != "personal" {
                    Button("Simulate Friend studying 30 min (+1 demo credit)") {
                        do { try CollaborationService.simulateFriendStudy(canvas, context: context) }
                        catch { model.error = error.localizedDescription }
                    }.font(.caption).frame(minHeight: 44)
                    Text("Demo credits apply only to this canvas and never enter your study balance.").font(.caption)
                }
            } else {
                Label("Together, you brought it to life.", systemImage: "sparkles").font(.headline)
                Text("Saved in Gallery · \(Int(canvas.studySecondsAtCompletion) / 60) study minutes at completion").font(.caption)
            }
            if let receipt = spends.filter({ $0.canvasID == canvas.id }).max(by: { $0.date < $1.date }) {
                Text("Last block: \(receipt.contributor) · \(receipt.date.formatted(date: .abbreviated, time: .shortened))").font(.caption)
            }
        }.padding(embedded ? 0 : 16)
            .alert("Pixel Credit", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func contribution(_ owner: Int) -> some View {
        let count = canvas.unlockedBlocks.filter { canvas.owner(of: $0) == owner }.count
        return Label("\(owner == 0 ? "You" : "Friend") · \(count)/18", systemImage: owner == 0 ? "circle" : "diamond")
            .font(.caption).accessibilityLabel("\(owner == 0 ? "You" : "Friend"), \(count) of 18 blocks restored")
    }
    private func blockButton(_ block: Int) -> some View {
        let open = canvas.unlockedBlocks.contains(block)
        let allowed = canvas.canUnlock(block, seat: seat)
        let owner = canvas.owner(of: block)
        return Button { selected = block } label: {
            Rectangle().fill(.clear)
                .overlay { Image(systemName: open ? "checkmark" : (canvas.kind == "sync" ? (owner == 0 ? "circle" : "diamond") : "plus")).font(.caption2.bold()).foregroundStyle(.black).padding(3).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 4)) }
                .overlay { Rectangle().stroke(selected == block ? .pink : .white.opacity(0.4), lineWidth: selected == block ? 3 : 0.5) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!allowed)
            .accessibilityLabel("Block \(block + 1), \(canvas.kind == "sync" ? (owner == 0 ? "You" : "Friend") : "photo"), \(open ? "restored" : "locked")")
            .accessibilityHint(allowed ? "Select, then use Unlock Pixel to spend one credit" : "")
            .accessibilityAddTraits(selected == block ? .isSelected : [])
    }
}
