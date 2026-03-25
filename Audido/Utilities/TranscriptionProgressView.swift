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

                Button {
                    queue.cancelTask(task)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("progress.cancel")
                    }
                    .audidoToolbarNeutralCapsule()
                }
                .buttonStyle(.plain)
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
