import SwiftUI
import SwiftData
import PhotosUI

private let rose = Color(red: 0.58, green: 0.23, blue: 0.37)
private let ivory = Color(red: 1, green: 0.97, blue: 0.94)

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var sessions: [StudySession]
    @State private var manager = StudySessionManager()
    @State private var recoveryError: String?
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house") }
            TogetherView().tabItem { Label("Together", systemImage: "person.2") }
        }.tint(rose)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do {
                        try manager.reconcile(sessions.first { $0.status == "running" }, context: context)
                        try await Task.sleep(for: .seconds(1))
                    } catch is CancellationError { return }
                    catch { recoveryError = error.localizedDescription; return }
                }
            }
            .alert("Could not restore session", isPresented: Binding(get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } })) {
                Button("OK") { recoveryError = nil }
            } message: { Text(recoveryError ?? "") }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PixelCanvas.createdAt, order: .reverse) private var canvases: [PixelCanvas]
    @Query private var sessions: [StudySession]
    @Query private var spends: [PixelSpend]
    @State private var study = false
    @State private var create = false
    @State private var startError: String?
    @State private var manager = StudySessionManager()
    @AppStorage("studyMode") private var studyMode = "Timer"
    @AppStorage("studyMinutes") private var studyMinutes = 30
    private var activeSession: StudySession? { sessions.first { ["running", "paused", "awaitingPhoto"].contains($0.status) } }
    private var seconds: Double { sessions.filter { $0.status == "confirmed" }.reduce(0) { $0 + $1.activeSeconds } }
    private var balance: Int { sessions.reduce(0) { $0 + ($1.awardedCredits ?? 0) } - spends.filter { !$0.isDemo }.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Two people. One picture.").font(.largeTitle.bold())
                    HStack {
                        Label("\(balance) Pixel Credits", systemImage: "sparkles").font(.headline)
                        Spacer()
                        Text("\(Int(seconds) / 60) min studied").font(.subheadline)
                    }
                    ProgressView(value: seconds.truncatingRemainder(dividingBy: 1800), total: 1800)
                    Text("\((1800 - Int(seconds) % 1800 + 59) / 60) more minutes toward your next pixel").font(.caption)
                    if activeSession == nil {
                        Picker("Study mode", selection: $studyMode) {
                            Text("Timer").tag("Timer"); Text("Stopwatch").tag("Stopwatch")
                        }.pickerStyle(.segmented)
                        if studyMode == "Timer" {
                            Picker("Focus duration", selection: $studyMinutes) {
                                ForEach([25, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                            }.pickerStyle(.menu)
                        }
                    }
                    Button {
                        do {
                            if activeSession == nil { try manager.start(mode: studyMode, minutes: studyMinutes, context: context) }
                            study = true
                        } catch { startError = error.localizedDescription }
                    } label: {
                        Label(sessions.contains { ["running", "paused", "awaitingPhoto"].contains($0.status) } ? "Continue study session" : "Start Studying", systemImage: "timer").frame(maxWidth: .infinity).padding()
                    }.buttonStyle(.borderedProminent)
                    HStack {
                        Button("Create Canvas", systemImage: "plus.square") { create = true }.buttonStyle(.bordered).frame(minHeight: 44)
                        Spacer()
                        NavigationLink("Gallery") { GalleryView() }.frame(minHeight: 44)
                    }
                    if let canvas = canvases.first(where: { $0.completedAt == nil && ($0.kind == "personal" || ($0.kind == "sync" && ($0.creatorSeat == 0 || $0.friendJoined)) || ($0.senderSeat == 1 && $0.swapStatus == "accepted")) }) {
                        Text("A little focus. A little color.").font(.title2.bold())
                        CanvasDetailView(canvas: canvas, embedded: true)
                    } else {
                        ContentUnavailableView("Make room for color", systemImage: "photo", description: Text("Create a canvas to turn a photo into your next study artwork."))
                    }
                }.padding()
            }.background(ivory).navigationTitle("SyncPix")
                .sheet(isPresented: $study) { StudyView() }
                .sheet(isPresented: $create) { PhotoCanvasCreatorView() }
                .alert("Could not start study", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) { Button("OK") { startError = nil } } message: { Text(startError ?? "") }
        }
    }
}
