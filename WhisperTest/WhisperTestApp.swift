import SwiftUI
import SwiftData

@main
struct WhisperTestApp: App {
    @State private var audioRecorder = AudioRecorderService()
    @State private var transcriptionService = TranscriptionService()
    @State private var modelManager = ModelManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioRecorder)
                .environment(transcriptionService)
                .environment(modelManager)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            ModelManagementView()
                .environment(modelManager)
                .environment(transcriptionService)
        }
    }
}
