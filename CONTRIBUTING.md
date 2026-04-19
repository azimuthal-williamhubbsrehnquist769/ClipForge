# Contributing to ClipForge

Thanks for your interest in contributing! ClipForge is a small, focused open-source project.
Contributions of all kinds are welcome — bug fixes, features from the roadmap, documentation improvements, and test coverage.

---

## Getting Started

1. **Fork** the repository and clone your fork.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have it:
   ```bash
   brew install xcodegen
   ```
3. Generate the Xcode project:
   ```bash
   cd ClipForge
   xcodegen generate
   ```
4. Open `ClipForge.xcodeproj` in Xcode 15+.
5. Build and run on macOS 14+.

---

## Project Structure

```
ClipForge/
├── ClipForge/
│   ├── App/             # @main App, AppDelegate
│   ├── Models/          # Clip, RecordingSettings, CaptureSource
│   ├── Managers/        # One file per concern: Capture, Buffer, Export, Library, Hotkeys…
│   ├── ViewModels/      # CaptureViewModel, LibraryViewModel
│   ├── Views/
│   │   ├── Library/     # LibraryView, ClipDetailView, TrimView
│   │   ├── Settings/    # Settings tabs
│   │   ├── Onboarding/  # PermissionsOnboardingView
│   │   ├── MenuBar/     # MenuBarController (MenuBarExtra content)
│   │   └── Shared/      # Reusable components (ThumbnailView, EmptyStateView)
│   └── Resources/       # Entitlements, Info.plist, Assets
└── ClipForgeTests/      # XCTest unit tests
```

---

## Architecture

ClipForge follows **MVVM**:

- **Model** — plain Swift structs/enums (`Clip`, `RecordingSettings`, `CaptureSource`)
- **Manager / Service** — `actor` or `@MainActor final class` that owns external resources (capture stream, disk I/O, etc.)
- **ViewModel** — `@MainActor ObservableObject` that composes managers and drives SwiftUI state
- **View** — SwiftUI structs; no business logic

### Key data flow

```
ScreenCaptureKit
    └─► CaptureManager.stream(_:didOutputSampleBuffer:)
            └─► VideoEncoder (VTCompressionSession)
                    └─► ReplayBuffer (actor, in-memory ring buffer)
                            └─► [Save hotkey] ──► ClipExportManager ──► .mp4 file
                                                         └─► LibraryManager (metadata + thumbnail)
                                                                  └─► LibraryView
```

---

## Coding Guidelines

- **Swift 5.9+** — use `async/await`, `actor`, and structured concurrency.
- **No third-party dependencies** — if you want to add one, open an issue first and explain why no native API solves the problem.
- **Comments** — only where the *why* isn't obvious from the code. No doc-comment boilerplate on trivial getters.
- **Test non-UI logic** — managers (ReplayBuffer, LibraryManager, ClipExportManager) should have test coverage. Skip testing pure SwiftUI views.
- **One class/struct per file** — keep the module graph navigable.
- **Error handling** — use typed `Error` enums with `LocalizedError`; surface errors to the user via `@Published var lastError: String?` in the view model.

---

## Pull Requests

1. **Keep PRs small and focused.** One feature or fix per PR.
2. **Match the existing code style** — 4-space indent, no trailing whitespace, Swift naming conventions.
3. **Update `ROADMAP.md`** if your PR completes a roadmap item.
4. **Add tests** for any new manager logic.
5. **Run `xcodegen generate` and verify the project builds** before opening a PR.

### PR Title Format

```
[fix] ReplayBuffer trimming off-by-one on exact duration boundary
[feat] Add GIF export via CGImageDestination
[docs] Clarify screen recording permission setup in README
[refactor] Extract VTCompressionSession into VideoEncoder
```

---

## Reporting Bugs

Open a GitHub Issue with:
- macOS version and chip (e.g., macOS 14.4, Apple M2)
- Steps to reproduce
- What you expected vs. what happened
- Console log output if relevant (from Console.app or `log stream`)

---

## Questions

Open a GitHub Discussion. Prefer discussions over issues for "how do I…" or "what's the design intent of…" questions.

---

## Code of Conduct

Be kind, be constructive. This is a hobbyist / indie project — everyone contributing is doing so voluntarily.
