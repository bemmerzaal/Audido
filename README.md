# Audido

> Local-first audio recording, transcription and AI summarisation for macOS.

Audido lets you record microphone audio, capture system audio from meetings (Teams, Zoom, etc.), import audio files and transcribe podcast episodes — all **on-device**, without sending audio to a server. Transcriptions can be summarised and turned into action items using **Apple Intelligence** (on supported Macs).

---

## Screenshots

<!-- Add screenshots here once available -->

---

## Features

| Feature | Details |
|---|---|
| 🎙 **Microphone recording** | Start, stop and manage recordings from any input device or iPhone via Continuity Camera |
| 🖥 **Meeting capture** | Capture system audio (entire system or one specific app) with optional microphone mix |
| 📄 **File import** | Import MP3, M4A, WAV, AIFF and other audio files for transcription |
| 🎧 **Podcast transcription** | Search for any podcast via the iTunes API, browse episodes and transcribe them |
| 🔤 **On-device transcription** | Powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML) — no audio ever leaves your Mac |
| 🧠 **AI summarisation** | Generate an AI summary and extract action items using Apple Intelligence (macOS 26+, Apple Silicon) |
| 🔖 **Tags & notes** | Add freeform notes and searchable tags to every recording |
| 🌐 **Localisation** | Full Dutch (NL) and English (EN) UI |

---

## Requirements

| | Minimum |
|---|---|
| **macOS** | 26.0 (Tahoe) |
| **Xcode** | 26+ |
| **Swift** | 5.0 |
| **Architecture** | Apple Silicon (M1 or later) — required for on-device AI features |
| **Apple Intelligence** | macOS 26, Apple Silicon, Apple Intelligence enabled in System Settings |

> [!NOTE]
> Recording and transcription work on any compatible Mac. Apple Intelligence features (summary, action items) require Apple Silicon and Apple Intelligence enabled in **System Settings → Apple Intelligence & Siri**.

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/your-username/Audido.git
cd Audido
```

### 2. Open in Xcode

```bash
open Audido.xcodeproj
```

Swift Package Manager will automatically resolve the [WhisperKit](https://github.com/argmaxinc/WhisperKit) dependency on first open.

### 3. Select a target and run

Select the **Audido** scheme and your Mac as the destination, then press **⌘R**.

### 4. Download a Whisper model

On first launch, open **Settings (⌘,)** and download one of the available Whisper models:

| Model | Size | Recommended use |
|---|---|---|
| Tiny | ~75 MB | Quick tests |
| Base | ~150 MB | Fast, reasonable accuracy |
| Small | ~500 MB | Good balance |
| Medium | ~800 MB | High accuracy |
| Large v3 | ~1.5 GB | Best accuracy |

Models are downloaded from Hugging Face via WhisperKit and stored in `~/Library/Application Support/WhisperModels/`.

---

## Required Permissions

The app requests these macOS permissions at runtime:

| Permission | Used for |
|---|---|
| **Microphone** | Recording audio |
| **Screen Recording** | Capturing system audio in Meeting Capture mode |

Grant permissions in **System Settings → Privacy & Security** if you dismiss the initial prompt.

---

## Architecture

```
Audido/
├── Models/
│   ├── Recording.swift          # SwiftData model for all audio items
│   └── Podcast.swift            # Podcast & episode value types
├── Services/
│   ├── AudioRecorderService     # AVAudioEngine-based microphone recorder
│   ├── MeetingCaptureService    # ScreenCaptureKit system-audio capture
│   ├── TranscriptionService     # WhisperKit inference wrapper
│   ├── TranscriptionQueue       # Serial async transcription queue
│   ├── ModelManager             # Download, select and manage Whisper models
│   ├── SummaryService           # Apple Foundation Models (summarisation)
│   ├── PodcastService           # iTunes Search API + episode download
│   └── AudioDeviceManager       # CoreAudio input device enumeration
├── Views/                       # SwiftUI screens
├── Utilities/                   # Shared UI helpers & style extensions
└── Localizable.xcstrings        # String Catalog (EN + NL)
```

**Key technology choices:**

- **SwiftData** for persistent storage of recordings, notes and tags.
- **SwiftUI** (NavigationSplitView, `@Observable`, `@Environment`) throughout — no UIKit/AppKit controllers.
- **WhisperKit** (CoreML) for fully on-device speech recognition.
- **FoundationModels** (`SystemLanguageModel`) for on-device AI summarisation on macOS 26+.
- **ScreenCaptureKit** for low-latency system-audio capture.

---

## Transcription languages

The following audio languages are supported for transcription (multilingual Whisper models):

Dutch · English · German · French · Spanish · Italian · Portuguese · Japanese · Chinese · Korean · Auto-detect

---

## Contributing

Pull requests are welcome. Please keep changes focused and follow the existing code style:

- **No force unwraps** outside of compile-time-safe contexts.
- **No UI changes** without updating `Localizable.xcstrings` for both `en` and `nl`.
- Run a **build** (`⌘B`) before opening a PR — there are no automated CI checks yet.

### Opening an issue

Please include:
- macOS version
- Mac model (chip)
- Steps to reproduce
- Relevant console output (Xcode → Debug → Console)

---

## Privacy

Audido processes all audio **locally on your device**. No audio, transcription text or summaries are transmitted to any server. The only external network calls are:

- Downloading Whisper models from **Hugging Face** (one-time, on demand).
- Searching for podcasts via the **iTunes Search API** (metadata only, no audio streaming through Audido servers).

---

## License

This project is currently unlicensed. Add a `LICENSE` file to specify usage terms before making the repository public.

---

## Acknowledgements

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax — CoreML Whisper inference on Apple Silicon.
- [OpenAI Whisper](https://github.com/openai/whisper) — the underlying speech recognition model.
- Apple FoundationModels framework for on-device language model access.
