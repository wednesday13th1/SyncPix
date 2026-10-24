import SwiftUI
import SwiftData
import PhotosUI

struct StudyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @State private var manager = StudySessionManager()
    @AppStorage("studyMode") private var mode = "Timer"
    @AppStorage("studyMinutes") private var minutes = 30
    @State private var error: String?
    @State private var discard = false
    @State private var photo: PhotosPickerItem?
    @State private var proof: Data?
    @State private var loading = false
    @State private var deleteHistory = false
    private var session: StudySession? { sessions.first { ["running", "paused", "awaitingPhoto"].contains($0.status) } }
    private var carry: Double { sessions.filter { $0.status == "confirmed" }.reduce(0) { $0 + $1.activeSeconds }.truncatingRemainder(dividingBy: 1800) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Study mode", selection: $mode) {
                        Text("Timer").tag("Timer"); Text("Stopwatch").tag("Stopwatch")
                    }.pickerStyle(.segmented).disabled(session != nil)
                    if session == nil && mode == "Timer" {
                        Picker("Focus minutes", selection: $minutes) {
                            ForEach([25, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let elapsed = session?.elapsed(at: timeline.date) ?? 0
                        let selectedMode = session?.mode ?? mode
                        let remaining = max(0, (session?.targetSeconds ?? Double(minutes * 60)) - elapsed)
                        let progress = selectedMode == "Timer" ? remaining / max(1, session?.targetSeconds ?? Double(minutes * 60)) : elapsed.truncatingRemainder(dividingBy: 1800) / 1800
                        ZStack {
                            Circle().stroke(.pink.opacity(0.15), lineWidth: 16)
                            Circle().trim(from: 0, to: progress).stroke(.pink, style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 10) {
                                Text(formatted(selectedMode == "Timer" ? ceil(remaining) : elapsed)).font(.system(.largeTitle, design: .monospaced).bold()).minimumScaleFactor(0.5).lineLimit(1)
                                Text(session?.status == "awaitingPhoto" ? "Ready for your photo" : session?.status.capitalized ?? "A moment for you").font(.subheadline)
                            }.padding(24)
                        }.frame(maxWidth: 300).aspectRatio(1, contentMode: .fit)
                            .accessibilityElement(children: .combine)
                            .onChange(of: timeline.date) { _, _ in perform { try manager.reconcile(session, context: context) } }
                    }
                    Text("30 active minutes = 1 Pixel Credit\nUnused minutes carry into your next session.").font(.subheadline).multilineTextAlignment(.center)
                    if let session {
                        if session.status == "awaitingPhoto" {
                            Text("\(Int((carry + session.activeSeconds) / 1800)) pending Pixel Credits").font(.headline)
                            Text("A photo is a personal study ritual, not proof of what you studied. Photos stay on this device.").font(.caption)
                            PhotosPicker(selection: $photo, matching: .images) { Label(proof == nil ? "Choose study photo" : "Change study photo", systemImage: "photo") }
                            if loading { ProgressView() }
                            if let proof, let image = UIImage(data: proof) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 12)) }
                            Button("Confirm session") {
                                guard let proof else { return }
                                perform { try PixelCreditManager.confirm(session, photo: proof, context: context); self.proof = nil; photo = nil }
                            }.buttonStyle(.borderedProminent).disabled(proof == nil || loading)
                        } else {
                            HStack {
                                Button(session.status == "running" ? "Pause" : "Resume") {
                                    perform { try manager.transition(session, to: session.status == "running" ? "paused" : "running", context: context) }
                                }.buttonStyle(.bordered)
                                Button("Finish") { perform { try manager.transition(session, to: "awaitingPhoto", context: context) } }.buttonStyle(.borderedProminent)
                            }
                        }
                        Button(session.mode == "Timer" && session.status != "awaitingPhoto" ? "Reset timer" : "Discard session", role: .destructive) { discard = true }
                    } else {
                        Button("Start \(mode)") { perform { try manager.start(mode: mode, minutes: minutes, context: context) } }.buttonStyle(.borderedProminent)
                        Text("\(Int(carry) / 60) min \(Int(carry) % 60) sec carried forward").font(.caption)
                    }
                    if let notice = manager.notice { Text(notice).font(.caption) }
                    if !sessions.filter({ $0.status == "confirmed" }).isEmpty {
                        DisclosureGroup("Study history · private on this device") {
                            ForEach(sessions.filter { $0.status == "confirmed" }) { entry in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        Text("\(entry.mode) · \(formatted(entry.activeSeconds)) · +\(entry.awardedCredits ?? 0) credits").font(.caption)
                                    }
                                    Spacer()
                                    if entry.proofPhoto != nil { Image(systemName: "photo.badge.checkmark").accessibilityLabel("Photo confirmed") }
                                }.padding(.vertical, 6)
                            }
                            Button("Delete saved study photos", role: .destructive) { deleteHistory = true }
                        }
                    }
                }.padding(24)
            }.background(Color(red: 1, green: 0.97, blue: 0.94)).navigationTitle("Study a little")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .task { if let session { mode = session.mode }; perform { try manager.reconcile(session, context: context) } }
                .onChange(of: scenePhase) { _, phase in if phase == .active { perform { try manager.reconcile(session, context: context) } } }
                .task(id: photo) {
                    proof = nil
                    guard let photo else { return }
                    loading = true; defer { loading = false }
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw AppFailure.image }
                        guard !Task.isCancelled else { return }
                        let scale = min(1, 1200 / max(image.size.width, image.size.height))
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let resized = UIGraphicsImageRenderer(size: CGSize(width: image.size.width * scale, height: image.size.height * scale), format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))) }
                        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw AppFailure.image }
                        proof = jpeg
                    } catch { self.error = error.localizedDescription }
                }
                .confirmationDialog("Discard this session and its study time?", isPresented: $discard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) {
                        guard let session else { return }
                        perform {
                            if session.status == "awaitingPhoto" {
                                session.status = "discarded"
                                do { try context.save() } catch { context.rollback(); throw error }
                            } else { try manager.transition(session, to: "discarded", context: context) }
                            proof = nil; photo = nil
                        }
                    }
                }
                .confirmationDialog("Delete all saved study photos? Your study time and credits will remain.", isPresented: $deleteHistory, titleVisibility: .visible) {
                    Button("Delete photos", role: .destructive) {
                        perform {
                            for session in sessions where session.status == "confirmed" { session.proofPhoto = nil }
                            do { try context.save() } catch { context.rollback(); throw error }
                        }
                    }
                }
                .alert("Study", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
    private func formatted(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
