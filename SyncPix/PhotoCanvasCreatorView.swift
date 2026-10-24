import SwiftUI
import SwiftData
import PhotosUI

struct PhotoCanvasCreatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var kind = "personal"
    var seat = 0
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var pixels: [Int] = []
    @State private var mode = "Color Restore"
    @State private var layout = "Half & Half"
    @State private var title = "Our little world"
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var zoomStart: CGFloat = 1
    @State private var error: String?
    @State private var loading = false
    @State private var revision = UUID()
    private var reveal: String { kind == "swap" ? "Mystery Reveal" : kind == "sync" ? "Color Restore" : mode }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Canvas name", text: $title)
                    PhotosPicker(selection: $item, matching: .images) { Label("Choose photo", systemImage: "photo.badge.plus").frame(minHeight: 44) }
                    if loading { ProgressView("Loading photo…") }
                    if kind == "sync" {
                        Picker("Split layout", selection: $layout) {
                            Text("Half & Half").tag("Half & Half")
                            Text("Puzzle Pieces").tag("Puzzle Pieces")
                        }
                        Text("18 blocks each · circles for You, diamonds for Friend").font(.caption)
                    } else if kind == "personal" {
                        Picker("Reveal", selection: $mode) {
                            Text("Color Restore").tag("Color Restore")
                            Text("Mystery Reveal").tag("Mystery Reveal")
                        }
                    }
                    if kind != "personal" {
                        Label("Local demo · no uploads or device sync", systemImage: "iphone").font(.caption)
                    }
                }
                if let image {
                    Section("Square crop") {
                        Text("Drag to position. Pinch or use the slider to zoom.").font(.caption)
                        GeometryReader { geometry in
                            let side = geometry.size.width
                            let scale = max(side / image.size.width, side / image.size.height) * zoom
                            Image(uiImage: image).resizable()
                                .frame(width: image.size.width * scale, height: image.size.height * scale)
                                .position(x: side / 2 + offset.width * side, y: side / 2 + offset.height * side)
                                .frame(width: side, height: side).clipped().contentShape(Rectangle())
                                .gesture(DragGesture().onChanged { value in
                                    offset = clamped(CGSize(width: dragStart.width + value.translation.width / side, height: dragStart.height + value.translation.height / side), image: image)
                                }.onEnded { _ in dragStart = offset; refresh() })
                                .simultaneousGesture(MagnificationGesture().onChanged { value in
                                    zoom = min(3, max(1, zoomStart * value)); offset = clamped(offset, image: image)
                                }.onEnded { _ in zoomStart = zoom; dragStart = offset; refresh() })
                                .accessibilityLabel("Square photo crop")
                        }.aspectRatio(1, contentMode: .fit)
                        Slider(value: Binding(get: { zoom }, set: { zoom = $0; zoomStart = $0; offset = clamped(offset, image: image); dragStart = offset }), in: 1...3) { Text("Crop zoom") }.onChange(of: zoom) { _, _ in
                            offset = clamped(offset, image: image); refresh()
                        }
                        // Accessible alternatives to dragging remain available in a compact disclosure.
                        DisclosureGroup("Adjust crop position") {
                            Slider(value: Binding(get: { offset.width }, set: { offset = clamped(CGSize(width: $0, height: offset.height), image: image); dragStart = offset; refresh() }), in: -1...1) { Text("Horizontal position") }
                            Slider(value: Binding(get: { offset.height }, set: { offset = clamped(CGSize(width: offset.width, height: $0), image: image); dragStart = offset; refresh() }), in: -1...1) { Text("Vertical position") }
                        }
                    }
                    Section("Canvas preview · 24 × 24") {
                        PixelCanvasView(pixels: pixels, resolution: 24, mode: reveal, unlocked: [])
                        Text("36 blocks · 4 × 4 pixels each").font(.caption)
                        if kind == "swap" {
                            Text("The recipient gets a hidden Mystery Canvas. Nothing is sent to another device in this demo.").font(.caption)
                        }
                        Button(kind == "sync" ? "Create & get local invite" : kind == "swap" ? "Send to \(seat == 0 ? "Friend" : "You") (local demo)" : "Save canvas") { save() }
                            .frame(minHeight: 44).disabled(pixels.count != 576 || loading)
                    }
                }
            }.navigationTitle(kind == "sync" ? "Sync Canvas" : kind == "swap" ? "Photo Swap" : "Create Canvas")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .task(id: item) {
                    let token = UUID(); revision = token; loading = true
                    defer { if revision == token { loading = false } }
                    guard let item else { return }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let imported = UIImage(data: data) else { throw AppFailure.image }
                        guard !Task.isCancelled, revision == token else { return }
                        image = try PixelArtProcessor.normalizeOrientation(imported); zoom = 1; zoomStart = 1; offset = .zero; dragStart = .zero; refresh()
                    } catch { self.error = error.localizedDescription }
                }
                .alert("Photo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func clamped(_ value: CGSize, image: UIImage) -> CGSize {
        let side = min(image.size.width, image.size.height)
        let x = (image.size.width / side * zoom - 1) / 2
        let y = (image.size.height / side * zoom - 1) / 2
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    private func refresh() {
        guard let image else { return }
        do { pixels = try PixelArtProcessor.process(image, zoom: zoom, offset: offset) }
        catch { self.error = error.localizedDescription; pixels = [] }
    }
    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if kind == "personal" {
                context.insert(PixelCanvas(title: name.isEmpty ? "My little world" : name, resolution: 24, mode: reveal, pixels: pixels))
                try context.save()
            } else {
                try CollaborationService.create(title: name.isEmpty ? "Our little world" : name, pixels: pixels, kind: kind, layout: layout, seat: seat, context: context)
            }
            dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
