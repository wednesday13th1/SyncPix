import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PixelCanvas.createdAt, order: .reverse) private var canvases: [PixelCanvas]
    @State private var deleting: PixelCanvas?
    @State private var error: String?
    var body: some View {
        List {
            Section("Completed artwork") {
                if !canvases.contains(where: { $0.completedAt != nil }) {
                    Text("Complete all 36 blocks to add an artwork here.").foregroundStyle(.secondary)
                }
                ForEach(canvases.filter { $0.completedAt != nil }) { canvas in entry(canvas) }
            }
            if canvases.contains(where: { $0.kind == "personal" && $0.completedAt == nil }) {
                Section("Personal canvases in progress") {
                    ForEach(canvases.filter { $0.kind == "personal" && $0.completedAt == nil }) { canvas in entry(canvas) }
                }
            }
        }.navigationTitle("Gallery")
            .confirmationDialog("Delete this canvas? Spent credits are not refunded.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete canvas", role: .destructive) {
                    guard let deleting else { return }
                    do { try CanvasRepository.delete(deleting, context: context) } catch { self.error = error.localizedDescription }
                    self.deleting = nil
                }
            }
            .alert("Could not delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func entry(_ canvas: PixelCanvas) -> some View {
        NavigationLink {
            ScrollView {
                CanvasDetailView(canvas: canvas)
                if let date = canvas.completedAt { Text("Completed \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            }.navigationTitle(canvas.title)
        } label: { CanvasRow(canvas: canvas) }
        .swipeActions { Button("Delete", role: .destructive) { deleting = canvas } }
    }
}
