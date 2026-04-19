# ClipForge

**ClipForge** is a lightweight, open-source macOS gameplay clipping app.
Save the last N seconds of your gameplay with a single hotkey - no account, no cloud, no bloat.

![ClipForge Screenshot](docs/screenshot.png)

---

## Why ClipForge?

Most gameplay clippers are heavy Electron apps bolted onto cloud platforms. They run background services, want your social accounts, and eat RAM. ClipForge takes the opposite approach:

| | ClipForge | Medal / Outplayed |
|---|---|---|
| Account required | No | Yes |
| Cloud upload | Never (opt-in roadmap) | Always |
| Background CPU | ~0 when idle | Constant |
| Electron / web tech | No - native Swift + SwiftUI | Often yes |
| Open source | MIT | No |
| Apple Silicon optimised | Yes | Partial |
| Local-first | Yes | Cloud-first |

ClipForge is the **`mpv` of clip tools** - fast, native, local, and completely out of your way.

---

## Features

- **Instant Replay** - rolling ring buffer captures the last 15s / 30s / 60s / 90s / 2m of gameplay
- **Hotkey save** - press `⌘⇧C` (configurable) to save the last N seconds as an MP4
- **Manual record** - start and stop a full recording session with a hotkey
- **Display or window capture** - capture a whole display or just one game window
- **System audio** - captures system sound via ScreenCaptureKit
- **Optional mic** - overlay your voice on the clip
- **Clip library** - local grid view with thumbnails, rename, favorite, delete
- **Lightweight trim** - drag in/out points and export a trimmed version
- **Menu bar app** - quick access without opening the main window
- **No telemetry** - zero analytics, zero network requests

---

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac (both supported)
- Xcode 15+ (to build from source)

---

## Building from Source

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Clone and generate the project

```bash
git clone https://github.com/yourusername/ClipForge.git
cd ClipForge
xcodegen generate
```

### 3. Open and build

```bash
open ClipForge.xcodeproj
```

Select the `ClipForge` scheme, choose **My Mac** as the destination, and press `⌘R`.

> **Code signing:** Set your Apple developer team in project settings, or change *Signing Certificate* to *Sign to Run Locally* for local development without a paid account.

---

## Permissions

ClipForge requires two permissions:

| Permission | Why | How to grant |
|---|---|---|
| **Screen Recording** | Captures your display or window | System Settings → Privacy & Security → Screen Recording → enable ClipForge |
| **Microphone** (optional) | Records your voice alongside gameplay | Prompted on first mic use |

ClipForge is **not sandboxed** so it can write clips to any user-chosen folder. No entitlement exceptions or private APIs are used.

---

## Architecture

```
ClipForge/
├── App/
│   ├── ClipForgeApp.swift      - @main, WindowGroup + MenuBarExtra + Settings scenes
│   └── AppDelegate.swift       - lifecycle, single-instance guard
│
├── Models/
│   ├── Clip.swift              - Value type representing a saved clip
│   ├── RecordingSettings.swift - Enums for FPS, resolution, codec, bitrate, replay duration
│   └── CaptureSource.swift     - Display or window capture target
│
├── Managers/                   - Single-responsibility services (no UI dependencies)
│   ├── SettingsStore.swift     - UserDefaults-backed @Published settings
│   ├── PermissionsManager.swift- Check + request screen recording & microphone
│   ├── ReplayBuffer.swift      - actor: thread-safe CMSampleBuffer ring buffer
│   ├── VideoEncoder.swift      - VTCompressionSession wrapper (CVPixelBuffer → H.264/HEVC)
│   ├── CaptureManager.swift    - SCStream setup, delegate, feeds VideoEncoder → ReplayBuffer
│   ├── AudioManager.swift      - AVCaptureSession microphone capture
│   ├── ClipExportManager.swift - AVAssetWriter assembles buffer → .mp4; generates thumbnails
│   ├── LibraryManager.swift    - Clip metadata, search, CRUD, JSON persistence
│   └── HotkeyManager.swift     - Carbon RegisterEventHotKey (no Accessibility permission needed)
│
├── ViewModels/
│   ├── CaptureViewModel.swift  - Orchestrates capture + save; bridges managers → SwiftUI
│   └── LibraryViewModel.swift  - Search, sort, trim export, selection state
│
└── Views/
    ├── ContentView.swift        - Root NavigationSplitView
    ├── Library/                 - LibraryView, ClipDetailView, TrimView
    ├── Settings/                - Tabbed settings window (General, Capture, Hotkeys, Library)
    ├── Onboarding/              - PermissionsOnboardingView (first run)
    ├── MenuBar/                 - MenuBarController (MenuBarExtra popover)
    └── Shared/                  - ThumbnailView, EmptyStateView
```

### Capture pipeline

```
ScreenCaptureKit (SCStream)
    │  raw CVPixelBuffer + system audio PCM
    ▼
VideoEncoder (VTCompressionSession)
    │  compressed H.264/HEVC CMSampleBuffer
    ▼
ReplayBuffer (actor)         ◄─── AudioManager (AVCaptureSession, optional mic)
    │  rolling N-second window
    ▼  [on hotkey / manual save]
ClipExportManager (AVAssetWriter)
    │  normalised .mp4 file
    ▼
LibraryManager
    │  metadata JSON + thumbnail JPEG
    ▼
LibraryView + ClipDetailView
```

### Ring buffer memory model

- **Raw frames are never stored.** ScreenCaptureKit delivers `CVPixelBuffer` (raw) → `VideoEncoder` compresses immediately → only the tiny H.264 bitstream is stored in the `ReplayBuffer` actor.
- A 60-second 1080p@30fps H.264 buffer at 8 Mbps ≈ **60 MB** peak.
- Compressed `CMSampleBuffer` objects are retained by value in a Swift `Array`; old samples are dropped when `PTS < (latest PTS − maxDuration)`.
- On save, the buffer is snapshotted (O(n) copy), trimmed to the first keyframe, then written by `AVAssetWriter`.

---

## Default Hotkeys

| Action | Default |
|---|---|
| Save replay clip | `⌘⇧C` |
| Start / stop recording | `⌘⇧R` |
| Mute / unmute mic | `⌘⇧M` |
| Open ClipForge | `⌘⇧J` |

All hotkeys are configurable in **Settings → Hotkeys**.

---

## Frequently Asked Questions

**Does it work on Intel Macs?**
Yes. VTCompressionSession and ScreenCaptureKit work on Intel. Performance is best on Apple Silicon due to the hardware H.264/HEVC encoder.

**How do I capture system audio?**
Enable "Capture system audio" in Settings → General. This uses ScreenCaptureKit's built-in audio tap (macOS 13+) - no virtual audio driver required.

**The clip is missing the first second.**
The ring buffer trims to the first keyframe (IDR frame) for valid H.264 streams. If the configured FPS is low, keyframes are spaced further apart. Increase FPS or enable B-frame support in a future release (see ROADMAP).

**Why is there no NVENC / AMD VCN support?**
VideoToolbox (`VTCompressionSession`) automatically selects the best available hardware encoder on your Mac, including the Apple Neural Engine's video encoder on M-series chips. No manual selection is needed.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, architecture notes, and PR guidelines.

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features: GIF export, clip stitching, Discord integration, AI highlight detection, and more.

---

## License

MIT - see [LICENSE](LICENSE).
