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
- Update `ChangeLog.md` in both English and Chinese, placing the newest version at the top.
- Use the actual current date for change-log entries.
- Use `Version <previous-version-number> hot-fix <index>` for versioning. Only one hot-fix is allowed per day.

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

## Security Policy

See `SECURITY.md` for supported versions and how to report vulnerabilities.
