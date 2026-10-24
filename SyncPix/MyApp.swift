import SwiftUI
import SwiftData

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: [StudySession.self, PixelCanvas.self, PixelSpend.self])
    }
}
