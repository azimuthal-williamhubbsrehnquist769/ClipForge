# ClipForge Roadmap

This document captures planned features and long-term ideas. Items are grouped by phase, not by a fixed timeline. Contributions toward any of these are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## MVP (v1.0) - Done ✓

- [x] ScreenCaptureKit-based display + window capture
- [x] VTCompressionSession ring buffer for instant replay
- [x] Configurable replay duration (15s / 30s / 60s / 90s / 2m)
- [x] System audio capture via ScreenCaptureKit
- [x] Optional microphone capture via AVCaptureSession
- [x] Global hotkeys (Carbon API, no Accessibility permission required)
- [x] Local clip library with thumbnails
- [x] Rename, favorite, delete, reveal in Finder
- [x] Basic trim editor (in/out points → export new clip)
- [x] Menu bar quick actions
- [x] First-run permissions onboarding
- [x] Settings: resolution, FPS, codec, bitrate, library path
- [x] MIT license, README, CONTRIBUTING guide

---

## v1.1 - Quality & Polish

- [ ] **Waveform preview in trim view** - visualise audio so users find the best cut point
- [ ] **Better hotkey recorder** - full virtual key code mapping via NSEvent monitor so any key (F-keys, numpad, etc.) can be bound
- [ ] **Clip tags** - tag clips with game names, sessions, or custom labels; filter by tag in library
- [ ] **Drag-and-drop clips** - drag a clip from the library to Finder or another app
- [ ] **Countdown overlay** - show 3-2-1 on screen when saving a replay clip so you know it worked
- [ ] **Auto-name by active app** - use NSWorkspace + AppleScript to name clips after the frontmost game
- [ ] **Multi-display support** - capture a secondary display, or capture all displays simultaneously

---

## v1.2 - Sharing & Export

- [ ] **Share sheet integration** - macOS share sheet (AirDrop, Messages, Mail) for any clip
- [ ] **Copy video to clipboard** - paste directly into Discord, Slack, etc. (via `NSPasteboard` with file URL + movie data)
- [ ] **GIF export** - short GIF for quick sharing (via FFmpeg subprocess or CGImageDestination)
- [ ] **Configurable output directory per source** - auto-sort clips into `~/Movies/ClipForge/CS2/`, `~/Movies/ClipForge/Minecraft/`, etc.
- [ ] **Quick-share URL** - generate a temporary public URL via Cloudflare Workers / R2 (opt-in, privacy-respecting)

---

## v1.3 - Editing

- [ ] **Clip markers** - drop a marker mid-clip and jump to it in the trim view
- [ ] **Simple subtitle / caption overlay** - add a text overlay that burns in during export
- [ ] **Clip stitching** - select multiple clips and export them back-to-back as a single file
- [ ] **Speed ramp** - slow-motion or 2× speed for a section (AVMutableVideoComposition)
- [ ] **Picture-in-picture** - embed webcam feed over gameplay (if webcam track is captured)

---

## v1.4 - Integrations

- [ ] **Discord Rich Presence** - show "Clipping on ClipForge" in Discord status while recording
- [ ] **Discord webhook** - optionally post a clip to a channel after saving (with user opt-in per server)
- [ ] **Twitch clip sync** - import Twitch clips you created on-stream back into your local library
- [ ] **iCloud Drive sync** - opt-in sync of metadata (not video files) so library state is shared across Macs
- [ ] **Shortcuts app actions** - `Start Recording`, `Save Clip`, `Open Library` as Shortcuts actions

---

## Long-term / Speculative

- [ ] **Apple Silicon hardware encoder** - use `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder` more aggressively and expose hardware encoder selection in settings
- [ ] **Segment-file ring buffer** - write 5-second HLS-style segment files to temp disk instead of holding CMSampleBuffers in RAM; reclaim memory for very long durations
- [ ] **iOS / iPadOS companion** - stream clips to iPhone for quick mobile sharing (via Bonjour + local network)
- [ ] **Plugin API** - allow third-party Swift packages to add export destinations (YouTube, Streamable, etc.)
- [ ] **Ghost mode** - fully invisible recording: no menu bar icon, no Dock icon, no window; activate and save clips entirely via hotkeys
- [ ] **Accessibility / VoiceOver audit** - full VoiceOver support and keyboard-only navigation

---

## Philosophy

ClipForge is intentionally **not** trying to be:

- A social platform (no feed, no follows, no cloud accounts)
- An analytics dashboard (no telemetry, no engagement metrics)
- A subscription product (MIT-licensed, always free to self-host)

The goal is to be the **`mpv` of clip tools** - fast, native, scriptable, trusted, and out of your way.
