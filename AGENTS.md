# Contribution Guide

This repository contains **Desktop Video Wallpaper**, a lightweight dynamic wallpaper app for macOS. It runs entirely offline, ensuring your privacy and local control.

## Tech Stack

- Swift
- SwiftUI
- AVFoundation

## Project Structure

```
Desktop Video/
├── Desktop Video/
│   ├── AppDelegate.swift
│   ├── Assets.xcassets/
│   ├── ContentView.swift
│   ├── Core/
│   │   └── WindowManager.swift
│   ├── Desktop_Video.entitlements
│   ├── Desktop_VideoApp.swift
│   ├── KeyBindings.swift
│   ├── LanguageManager.swift
│   ├── Localizable.xcstrings
│   ├── SharedWallpaperWindowManager.swift
│   ├── SpaceWallPaperManager.swift
│   ├── UI/
│   │   ├── AppMainWindow.swift
│   │   ├── Components/
│   │   ├── Screens/
│   │   └── Sidebar/
│   ├── Utils.swift
│   ├── ViewModels/
│   │   ├── AppState.swift
│   │   ├── AppViewModel.swift
│   │   └── ScreenObserver.swift
│   ├── WallpaperWindow.swift
│   └── WallpaperWindowController.swift
├── Desktop Video.xcodeproj/
├── Desktop VideoTests/
├── Desktop VideoUITests/
├── DesktopVideoforMACTempleate.dmg
├── ChangeLog.md
├── README-EN.md
├── README.md
├── SECURITY.md
├── archive/
├── statics/
└── demos/
```

## Development Guidelines

### Code Style

- Read through the entire repo.
- Use Xcode's default Swift formatting or swift-format.
- Keep code clean and readable.
- Reuse existing methods where possible.
- Remove any obsolete logic or unused methods.
- Add a clear, informative log statement for each new function to aid debugging.
- Provide Chinese comments when adding command-line scripts.
- **Every change must be logged in `ChangeLog.md`** — see the [ChangeLog Requirements](#changelog-requirements) section below for details.

### Naming Conventions

- Use PascalCase for class and struct names.
- Use camelCase for function and variable names.
- File names should match the main type they contain.

### Git Workflow

- Create feature branches from `main` with a short descriptive name.
- Commit messages should use the format `<type>: <summary>` (e.g., `feat: add HDR video support`).
- Open a pull request referencing related issues and ensure the build passes before requesting review.

## Required Checks

Check the localizations to see if code changes require translation.
If translation is needed, update `Localizable.xcstrings` accordingly.

Run the following command to verify the project compiles:

```bash
xcodebuild \
  -project "Desktop Video/Desktop Video.xcodeproj" \
  -scheme "Desktop Video" \
  -destination "platform=macOS" \
  clean build
```

Because this repository is compiled with Xcode, the command above should be attempted before merging. If Xcode is unavailable, note the failure in your pull request.

## Environment Setup

### Development Requirements

- macOS with Xcode installed.
- No additional Node.js dependencies.

### Installation Steps

```bash
#!/bin/bash
set -e  # 出错就退出

git clone https://github.com/TzJ2006/desktop-video-for-mac.git

PROJECT_DIR="Desktop Video"
SCHEME_NAME="Desktop Video"
DESTINATION="platform=macOS"

echo "📦 检查 xcodebuild 是否可用..."
which xcodebuild > /dev/null || { echo "请安装 Xcode 命令行工具"; exit 1; }

echo "📁 正在初始化项目环境..."

echo "🚧 正在构建项目..."
xcodebuild \
  -project "${PROJECT_DIR}/${SCHEME_NAME}.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -destination "$DESTINATION" \
  clean build

echo "🚀 正在启动 App..."
open "build/Release/${SCHEME_NAME}.app" || \
open "$HOME/Library/Developer/Xcode/DerivedData"/*/Build/Products/Debug/${SCHEME_NAME}.app

echo "✅ 启动完成"
```

## Testing Strategy

- Currently no automated tests are included.
- Ensure the project builds with `xcodebuild clean build` before merging.
- Update `ChangeLog.md` with a summary of your changes.

## ChangeLog Requirements

Every code change **must** have a corresponding entry in `ChangeLog.md`. No exceptions.

### Format

- Entries are grouped under version headers: `### Version X.Y hot-fix Z (YYYY-MM-DD)`
- Each entry is a bullet point with **Chinese first, then English**, in pairs
- Newest entries go at the **top** of the file (below the file header)
- Use the **actual current date**, not a placeholder

### When to Add an Entry

- Any bug fix, feature addition, refactor, or behavioral change
- UI changes, localization updates, build configuration changes
- Do **not** skip logging just because a change seems minor

### How to Write Entries

- Keep descriptions concise (one line each for Chinese and English)
- Chinese line describes the change for Chinese-speaking users
- English line describes the same change for English-speaking users
- Use active voice: "修复…" / "Fix…", "新增…" / "Add…", "移除…" / "Remove…"

### Version Bumping

- If today already has a hot-fix entry, append to that section
- If today has no entry yet, create a new hot-fix section (max one hot-fix bump per day)
- Follow the pattern: `Version X.Y hot-fix Z` where Z increments from the last hot-fix

### Example

```markdown
### Version 4.0 hot-fix 3 (2025-10-15)

- 新增 HDR 视频支持
- Add HDR video support
- 修复多屏幕下音量不同步的问题
- Fix volume not syncing across multiple screens
```

## Security Policy

See `SECURITY.md` for supported versions and how to report vulnerabilities.
