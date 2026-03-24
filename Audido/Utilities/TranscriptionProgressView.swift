import SwiftUI

struct TranscriptionProgressView: View {
    let task: TranscriptionTask?
    @Environment(TranscriptionQueue.self) private var queue

    var body: some View {
        if let task {
            VStack(spacing: 16) {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text(task.statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Button(role: .destructive) {
                    queue.cancelTask(task)
                } label: {
                    Label("progress.cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
        } else {
            VStack(spacing: 16) {
                ProgressView()
                Text("progress.transcribing")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}
