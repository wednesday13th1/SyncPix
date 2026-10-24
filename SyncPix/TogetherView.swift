import SwiftUI
import SwiftData

struct TogetherView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PixelCanvas.createdAt, order: .reverse) private var canvases: [PixelCanvas]
    @AppStorage("localDemoSeat") private var seat = 0
    @State private var createSync = false
    @State private var createSwap = false
    @State private var code = ""
    @State private var error: String?
    @State private var deleting: PixelCanvas?
    @State private var joined: PixelCanvas?
    private var shared: [PixelCanvas] { canvases.filter { $0.kind == "sync" && ($0.creatorSeat == seat || $0.friendJoined) } }
    private var received: [PixelCanvas] { canvases.filter { $0.kind == "swap" && $0.senderSeat != seat } }
    private var sent: [PixelCanvas] { canvases.filter { $0.kind == "swap" && $0.senderSeat == seat } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Local collaboration demo", systemImage: "iphone").font(.headline)
                    Text(CollaborationService.status).font(.caption)
                    Picker("Demo participant", selection: $seat) {
                        Text("You").tag(0); Text("Friend (demo)").tag(1)
                    }.pickerStyle(.segmented)
                }
                Section("Sync Canvas · two people") {
                    Button("Create Sync Canvas", systemImage: "plus.square") { createSync = true }.frame(minHeight: 44)
                    HStack {
                        TextField("Local invite code", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Join") {
                            do { joined = try CollaborationService.join(code: code, seat: seat, context: context); code = "" }
                            catch { self.error = error.localizedDescription }
                        }.frame(minWidth: 44, minHeight: 44).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(shared) { canvas in
                        NavigationLink { detail(canvas) } label: { CanvasRow(canvas: canvas) }
                            .swipeActions { Button("Delete", role: .destructive) { deleting = canvas } }
                    }
                    if shared.isEmpty { Text("Create a photo canvas, then switch demo participant to join using its local code.").font(.caption) }
                }
                Section("Photo Swap inbox") {
                    Button("Send a photo (local demo)", systemImage: "photo.badge.plus") { createSwap = true }.frame(minHeight: 44)
                    ForEach(received) { canvas in
                        if canvas.swapStatus == "pending" {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("A hidden photo from \(canvas.senderSeat == 0 ? "You" : "Friend")", systemImage: "envelope")
                                Text("Accept to study and reveal it. You do not need to send a photo back.").font(.caption)
                                HStack {
                                    Button("Accept") {
                                        do { try CollaborationService.accept(canvas, seat: seat, context: context) }
                                        catch { self.error = error.localizedDescription }
                                    }.buttonStyle(.bordered).frame(minHeight: 44)
                                    Button("Decline", role: .destructive) { deleting = canvas }.frame(minHeight: 44)
                                }
                            }
                        } else {
                            NavigationLink { detail(canvas) } label: { CanvasRow(canvas: canvas) }
                                .swipeActions { Button("Delete", role: .destructive) { deleting = canvas } }
                        }
                    }
                    if received.isEmpty { Text("No received photos. Switch demo participant to try sending one to this inbox.").font(.caption) }
                }
                if !sent.isEmpty {
                    Section("Sent photos · local demo") {
                        ForEach(sent) { canvas in
                            VStack(alignment: .leading) {
                                Text(canvas.title)
                                Text(canvas.swapStatus == "pending" ? "Awaiting recipient" : "\(canvas.unlockedBlocks.count)/36 revealed by recipient").font(.caption)
                            }.swipeActions { Button("Delete", role: .destructive) { deleting = canvas } }
                        }
                    }
                }
            }.navigationTitle("Together")
                .sheet(isPresented: $createSync) { PhotoCanvasCreatorView(kind: "sync", seat: seat) }
                .sheet(isPresented: $createSwap) { PhotoCanvasCreatorView(kind: "swap", seat: seat) }
                .navigationDestination(item: $joined) { canvas in detail(canvas) }
                .confirmationDialog("Delete this local canvas and its image? Spent credits are not refunded.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete photo / canvas", role: .destructive) {
                        guard let deleting else { return }
                        do { try CanvasRepository.delete(deleting, context: context); self.deleting = nil }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .alert("Together", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func detail(_ canvas: PixelCanvas) -> some View {
        ScrollView { CanvasDetailView(canvas: canvas, seat: seat) }.navigationTitle("\(seat == 0 ? "You" : "Friend") · Demo")
    }
}

struct CanvasRow: View {
    let canvas: PixelCanvas
    var body: some View {
        HStack {
            PixelCanvasView(pixels: canvas.pixels, resolution: canvas.resolution, mode: canvas.revealMode, unlocked: canvas.unlockedBlocks)
                .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading) {
                Text(canvas.title).font(.headline)
                Text("\(canvas.unlockedBlocks.count)/36 restored · \(canvas.kind == "sync" ? canvas.splitLayout : "Mystery Reveal")").font(.caption)
            }
        }.padding(.vertical, 4)
    }
}
