import SwiftUI
import SwiftData

@main
struct WhisperTestApp: App {
    @State private var audioRecorder = AudioRecorderService()
    @State private var transcriptionService: TranscriptionService
    @State private var transcriptionQueue: TranscriptionQueue
    @State private var modelManager = ModelManager()
    @State private var podcastService = PodcastService()
    @State private var summaryService = SummaryService()
    @State private var audioDeviceManager = AudioDeviceManager()

    init() {
        let service = TranscriptionService()
        _transcriptionService = State(initialValue: service)
        _transcriptionQueue = State(initialValue: TranscriptionQueue(transcriptionService: service))
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed — delete old database and recreate
            print("ModelContainer migration failed, recreating: \(error)")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dbFiles = ["default.store", "default.store-shm", "default.store-wal"]
            for file in dbFiles {
                try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(file))
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioRecorder)
                .environment(transcriptionService)
                .environment(modelManager)
                .environment(podcastService)
                .environment(summaryService)
                .environment(audioDeviceManager)
                .environment(transcriptionQueue)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            ModelManagementView()
                .environment(modelManager)
                .environment(transcriptionService)
                .environment(audioDeviceManager)
        }
    }
}
