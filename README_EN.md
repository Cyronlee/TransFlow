<div align="center">
  <img src="public/logo.png" alt="TransFlow Logo" width="128" height="128">
  <h1>TransFlow</h1>
  <p><strong>Real-time speech transcription & translation for macOS — fully offline, privacy-first</strong></p>

  [![GitHub release](https://img.shields.io/github/v/release/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/releases)
  [![License](https://img.shields.io/github/license/Cyronlee/TransFlow?style=flat-square)](LICENSE)
  [![Platform](https://img.shields.io/badge/platform-macOS%2015.0+-blue?style=flat-square&logo=apple)](https://github.com/Cyronlee/TransFlow)
  [![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)](https://swift.org)
  [![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-blue?style=flat-square&logo=swift)](https://developer.apple.com/swiftui/)
  [![GitHub stars](https://img.shields.io/github/stars/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/stargazers)
  [![GitHub issues](https://img.shields.io/github/issues/Cyronlee/TransFlow?style=flat-square)](https://github.com/Cyronlee/TransFlow/issues)
  [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/Cyronlee/TransFlow/pulls)

  **English** | [中文](README.md)

  <a href="https://github.com/Cyronlee/TransFlow/releases">
    <img src="https://img.shields.io/badge/Download-DMG%20Installer-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
</div>

---

<div align="center">
  <img src="public/demo-1-zh.png" alt="TransFlow Demo" width="800">
</div>

<div align="center">
  <img src="public/demo-2-zh.png" alt="TransFlow Video Transcription & Speaker Diarization" width="800">
</div>

## ✨ Features

- **🎙️ Real-time Speech Transcription** — Powered by Apple Speech framework with Neural Engine hardware acceleration, delivering high accuracy for long-form audio like meetings, lectures, and conversations
- **🌐 Real-time Translation** — Leverages Apple Translation framework to translate transcription results on the fly, supporting all languages built into macOS
- **🎬 Video Transcription & Speaker Diarization** — Import video files, automatically transcribe speech and identify different speakers, with each segment labeled by speaker and timestamp
- **🔊 App Audio Capture** — Capture audio from other applications via ScreenCaptureKit for transcription — easily transcribe online meetings and videos
- **🔒 Privacy First** — Speech recognition and translation run entirely on-device (offline)
- **📜 History Browser** — Sessions are saved automatically. Browse, preview, rename, and delete past transcription sessions
- **📤 Export Support** — Export sessions to SRT subtitle and Markdown formats
- **⚙️ Settings & Customization** — Configure language preferences, app appearance (light/dark/system), and global hotkeys
- **🪶 Lightweight** — Under 5MB app size — beautifully minimal, install and go

## 🛠️ Tech Stack

| Technology | Description |
|------------|-------------|
| **Swift 6.0** | Primary language with modern concurrency features |
| **SwiftUI** | Declarative UI framework for native macOS interface |
| **Speech Framework** | Apple's speech recognition with Neural Engine acceleration, fully offline |
| **Translation Framework** | Apple's on-device translation, supports all macOS built-in languages |
| **AVFoundation** | Audio capture and processing |
| **ScreenCaptureKit** | Capture audio streams from other applications |
| **MVVM Architecture** | Modern SwiftUI architecture with `@Observable` |

## 📦 Installation

### System Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon (arm64) or Intel (x86_64)

### Download

1. Go to the [Releases page](https://github.com/Cyronlee/TransFlow/releases) to download the latest DMG installer
2. Open the DMG file and drag TransFlow into your Applications folder
3. On first launch, if you see a security prompt, go to System Settings → Privacy & Security to allow the app

### Build from Source

```bash
git clone https://github.com/Cyronlee/TransFlow.git
cd TransFlow
open TransFlow/TransFlow.xcodeproj
```

Select the TransFlow target in Xcode and click Run.

## 🚀 Quick Start

1. Launch TransFlow and grant microphone permission
2. Select your audio source (microphone or app audio)
3. Choose the transcription language and translation target language
4. Click the start button to see real-time transcription and translation
5. Sessions are saved automatically and can be reviewed in History

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ K` | Clear current transcription |
| `⌘ ⇧ E` | Export as SRT subtitle |

## 🗺️ Roadmap

- [x] ~~Speaker diarization (video transcription)~~
- [x] ~~Custom keyboard shortcuts~~
- [ ] Real-time speaker identification (microphone / app audio)
- [ ] Custom vocabulary (professional terminology correction)
- [ ] Post-transcription refinement (edit and polish results)
- [ ] Global audio monitoring (system-level audio capture)
- [ ] Support third-party speech models (e.g., Whisper)
- [ ] Custom styles
- [ ] Welcome to contribute more

## 🤝 Contributing

Contributions are welcome! Feel free to submit Issues and Pull Requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Reporting Issues

If you find a bug or have a feature request, please [create an Issue](https://github.com/Cyronlee/TransFlow/issues/new).

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## ⭐ Star History

If you find TransFlow useful, please give us a Star ⭐ — it means a lot!

---

<div align="center">
  <sub>Built with ❤️ by <a href="https://github.com/Cyronlee">Cyronlee</a></sub>
</div>
