# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Desktop Video Wallpaper is a lightweight, privacy-focused dynamic wallpaper app for macOS. It sets videos and images as desktop wallpapers with multi-display support, playback modes, screensaver functionality, and power management. Runs entirely offline with no cloud syncing.

**Tech Stack**: Swift, SwiftUI, AVFoundation | **Target**: macOS 12.0+

## Build & Verify

```bash
xcodebuild \
  -project "Desktop Video/Desktop Video.xcodeproj" \
  -scheme "Desktop Video" \
  -destination "platform=macOS" \
  clean build
```

There are no automated tests. The build command above is the primary verification step before merging.

**Dead code detection** is configured via `.periphery.yml` (retain_public=true, strict=true).

## Architecture

### Core Pattern: MVVM with Centralized State

- **AppState** (`ViewModels/AppState.swift`): Singleton `ObservableObject` holding global state — playback mode, mute, idle sensitivity, manual screen selections. Syncs with UserDefaults.
- **SharedWallpaperWindowManager** (`SharedWallpaperWindowManager.swift`): Central coordinator mapping screen UUIDs to window controllers, AVQueuePlayers, media content, and overlay windows. Handles in-memory video caching, security-scoped bookmark persistence, and occlusion-based pausing.
- **AppDelegate** (`AppDelegate.swift`): App lifecycle, main window management, screensaver overlay, menu bar integration.
- **Desktop_VideoApp** (`Desktop_VideoApp.swift`): `@main` entry point, settings/preferences window.

### Key Conventions

- **Screen identity**: All per-screen state uses `screen.dv_displayUUID` (CGDirectDisplayID-based) as dictionary keys.
- **Notification-driven**: Heavy use of NotificationCenter for cross-component communication (power state changes, screen connect/disconnect, screensaver triggers).
- **Persistence**: `BookmarkStore` in Utils.swift wraps UserDefaults for per-screen security-scoped bookmarks with raw URL fallback.
- **Logging**: Use `dlog()` for debug logging, `errorLog()` for errors — both are wrappers around os.Logger.
- **Localization**: `L("key")` shorthand function. Supports English, Simplified/Traditional Chinese, French, Spanish. Update `Localizable.xcstrings` when adding UI text.

### Playback Modes

1. **Always Play**: Continuous playback on all screens
2. **Intelligent**: Auto-degrades based on CPU/thermal/power state (multi-screen → single-screen → paused)
3. **Manual**: User selects specific screens

### State Binding Patterns

- `@AppStorage` for system-level preferences (launch at login, language)
- `@ObservedObject` for shared AppState
- `@Published` properties with `didSet` handlers for side effects

### UI Structure

Sidebar navigation (`SidebarView`, 220pt) + scrollable card-based content (`CardSection` components) with three main sections: Wallpaper, Playback, General.

## Code Style & Conventions

- PascalCase for types, camelCase for functions/variables
- File names match the main type they contain
- Provide Chinese comments when adding command-line scripts
- Update `ChangeLog.md` (English + Chinese, newest first) with actual current date
- Versioning: `Version X.Y hot-fix Z` (one hot-fix per day max)

## Git Workflow

- Feature branches from `main` with short descriptive names
- Commit format: `<type>: <summary>` (e.g., `feat: add HDR video support`)
- Ensure build passes before requesting review
