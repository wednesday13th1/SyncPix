import SwiftUI
import UIKit

/// Read-only artwork layer. CanvasDetailView supplies the accessible 44-point block controls.
struct PixelCanvasView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pixels: [Int]
    let resolution: Int
    let mode: String
    let unlocked: [Int]

    var body: some View {
        ZStack {
            if let locked = try? PixelArtProcessor.image(from: PixelBlockLayout.lockedColors(pixels, mode: mode), resolution: resolution),
               let original = try? PixelArtProcessor.image(from: pixels, resolution: resolution) {
                raster(locked)
                raster(original).mask {
                    // For legacy non-divisible resolutions, match integer pixel boundaries exactly.
                    GeometryReader { geometry in
                        ForEach(0..<PixelBlockLayout.count, id: \.self) { block in
                            let rect = bounds(of: block)
                            Rectangle().fill(.white)
                                .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                                .position(x: rect.midX * geometry.size.width, y: rect.midY * geometry.size.height)
                                .opacity(unlocked.contains(block) ? 1 : 0)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: unlocked.contains(block))
                        }
                    }
                }
            } else {
                Color(red: 0.88, green: 0.83, blue: 0.82)
                    .overlay { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
    private func raster(_ image: UIImage) -> some View {
        Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
    }
    private func bounds(of block: Int) -> CGRect {
        let column = block % 6, row = block / 6
        let startX = (column * resolution + 5) / 6, endX = ((column + 1) * resolution + 5) / 6
        let startY = (row * resolution + 5) / 6, endY = ((row + 1) * resolution + 5) / 6
        return CGRect(x: Double(startX) / Double(resolution), y: Double(startY) / Double(resolution),
                      width: Double(endX - startX) / Double(resolution), height: Double(endY - startY) / Double(resolution))
    }
}
