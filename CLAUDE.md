# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Desktop Video Wallpaper is a lightweight, privacy-focused dynamic wallpaper app for macOS. It sets videos, images, and web pages as desktop wallpapers with multi-display support, playback modes, screensaver functionality, and power management. Runs entirely offline with no cloud syncing.

**Tech Stack**: Swift, SwiftUI, AVFoundation, WebKit | **Target**: macOS 26.0+

## Build & Verify

```bash
xcodebuild \
  -project "Desktop Video/Desktop Video.xcodeproj" \
  -scheme "Desktop Video" \
  -destination "platform=macOS" \
  clean build
```

There are no automated tests. The build command above is the primary verification step before merging.

**Dead code detection** is configured via two `.periphery.yml` files. The root one sets `retain_public: true` only. The one inside `Desktop Video/` is stricter — it adds `targets`, `retain_assign_only_properties`, `analyze_spm`, and `strict: true`. Note `periphery:ignore` comments are used in source to park unused code (e.g. `SpaceWallPaperManager.swift`).

**Localization check**: When making code changes, verify if translations are needed and update `Localizable.xcstrings` accordingly.

## Architecture

### Core Pattern: MVVM with Centralized State

- **AppState** (`ViewModels/AppState.swift`): Singleton `ObservableObject` holding global state — playback mode, mute, idle sensitivity, manual screen selections. Syncs with UserDefaults.
- **AppViewModel** (`ViewModels/AppViewModel.swift`): Lightweight `ObservableObject` holding only UI navigation state (`SidebarSelection`). Distinct from AppState — keep wallpaper/playback state in AppState, sidebar/view state here.
- **SharedWallpaperWindowManager** (`SharedWallpaperWindowManager.swift`): Central coordinator (largest file) mapping screen UUIDs to window controllers, AVQueuePlayers, media content, overlay windows, web views, and screensaver windows. Handles in-memory video caching (`NSCache<NSURL, NSData>`), security-scoped bookmark persistence, and occlusion-based pausing.
- **AppDelegate** (`AppDelegate.swift`): App lifecycle, main window management, screensaver overlay, menu bar integration, occlusion debouncing.
- **Desktop_VideoApp** (`Desktop_VideoApp.swift`): `@main` entry point, menu setup, settings/preferences window.
- **WindowManager** (`Core/WindowManager.swift`): Creates/tracks `WallpaperWindowController` instances (one per screen), syncs with active screens.

### Wallpaper Window System

**Window hierarchy per screen:**
- `WallpaperWindow` (NSWindow): level=desktop, `canBecomeKey=false`, `ignoresMouseEvents=true`, `collectionBehavior=[.canJoinAllSpaces, .stationary]`
- Content layer: `AVPlayerLayer` (video), `NSImageView` (image), or `WKWebView` (web)
- Overlay windows: Small windows for occlusion detection (if all occluded → pause playback)
- Screensaver overlay windows: Full-screen overlays triggered during screensaver

**Creation flow**: `WindowManager.startForAllScreens()` → `syncScreens()` → `ensureWallpaper(on:)` → `SharedWallpaperWindowManager.ensureWallpaperController(for:)` → creates `WallpaperWindowController` + `WallpaperWindow` per screen.

**Content types**: Video (AVQueuePlayer with AVPlayerLooper), Image (NSImageView), Web (WKWebView with `WebNavigationHandler` delegate and JavaScript injection for pause control). Cached in-memory video bytes (`NSCache<NSURL, NSData>`) are played back via `AVDataAsset` (`Core/AVDataAsset.swift`), which writes the data to a temp file with the correct extension and cleans it up on deinit.

### Security-Scoped Bookmark System

`BookmarkStore` in Utils.swift manages file access persistence. UserDefaults keys use prefixes: `bookmark`, `stretch`, `volume`, `savedAt`, `lastURL`, `lastType`, `urlBookmark`. Resolution fallback chain: per-screen-scoped → per-screen-nonscoped → per-URL-scoped → per-URL-nonscoped → original URL. When all fail, `NSOpenPanel` prompts for re-authorization.

### Key Conventions

- **Screen identity**: All per-screen state uses `screen.dv_displayUUID` (CGDirectDisplayID-based UUID, fallback to "name-resolution" hash) as dictionary keys. Lookup via `NSScreen.screen(forUUID:)`.
- **Notification-driven**: Heavy use of NotificationCenter — `WallpaperContentDidChange`, `didChangeScreenParametersNotification`, `screensDidWake/Sleep`, `didChangeOcclusionStateNotification`, `didWakeNotification`.
- **Logging**: `dlog()` for debug logging (DEBUG builds only), `errorLog()` always writes to `~/Library/Logs/desktop-video.log`. Both use `LogFile` singleton with serial DispatchQueue.
- **Localization**: `L("key")` shorthand function via `LanguageManager`. Supports: system, en, zh-Hans, zh-Hant, fr, es. Update `Localizable.xcstrings` when adding UI text.
- **Global mute**: `AppState.isGlobalMuted` triggers `muteAllScreens()`/`restoreAllScreens()` with per-screen volume saved/restored via `savedVolumes` dict.
- **Video sync**: `syncSameNamedVideos()` aligns playback position across screens playing the same file.
- **Web JS helpers**: Use `WKWebView.dv_evaluateJS(_:)` (in Utils.swift) for all JavaScript evaluation — it handles error logging. Use `WKWebView.jsPauseAll`, `.jsPlayAll`, `.jsSetVolume(_:muted:)` constants instead of raw JS strings.

### Playback Modes

1. **Always Play** (`alwaysPlay`): Continuous playback on all screens
2. **Automatic** (`automatic`): Auto-degrades based on idle pause sensitivity
3. **Power Save** (`powerSave`): Pause if all screens occluded
4. **Power Save Plus** (`powerSavePlus`): Pause if any screen occluded
5. **Stationary** (`stationary`): Always paused

### State Binding Patterns

- `@AppStorage` for system-level preferences (launch at login, language)
- `@ObservedObject` for shared AppState
- `@Published` properties with `didSet` handlers for side effects

### UI Structure

Sidebar navigation (`SidebarView`, 220pt) + scrollable card-based content (`CardSection` components) with four sections: Wallpaper, Playback, History, General. Layout constants defined in `AppMainWindow` (used by both `ContentView` and `AppDelegate`).

**History system**: `WallpaperHistoryStore` (singleton) stores up to 100 `WallpaperHistoryEntry` records (Codable, JSON in UserDefaults) tracking URL, content type, timestamp, and filename. Per-URL bookmarks enable re-opening history items without re-prompting. `ThumbnailGenerator` (`ViewModels/ThumbnailGenerator.swift`) renders preview thumbnails for video/image entries, activating per-URL security-scoped bookmarks before reading.

### App Sandbox Entitlements

`app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `network.client` — files accessed only via NSOpenPanel or stored bookmarks.

## Code Style & Conventions

- PascalCase for types, camelCase for functions/variables
- File names match the main type they contain
- Provide Chinese comments when adding command-line scripts
- **Every change must be logged in `ChangeLog.md`** — see `AGENTS.md` for detailed requirements
  - Format: Bilingual entries (Chinese first, then English) under version headers
  - Newest entries go at the top of the file
  - Use actual current date in format `YYYY-MM-DD`
- Versioning: `Version X.Y hot-fix Z` (one hot-fix per day max)
- **ChangeLog grouping rule**: If changes are made on the same day as an existing version entry, append to that entry. Only create a new `hot-fix` version if the changes are on a different day.

## Git Workflow

- Feature branches from `main` with short descriptive names
- Commit format: `<type>: <summary>` (e.g., `feat: add HDR video support`)
- Ensure build passes before requesting review
