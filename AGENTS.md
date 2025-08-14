# Contribution Guide

This repository contains **Desktop Video Wallpaper**, a lightweight dynamic wallpaper app for macOS. It runs entirely offline, ensuring your privacy and local control.

## Tech Stack

- Swift
- SwiftUI
- AVFoundation

## Project Structure

```
 desktop video/
├── desktop video/
│   ├── AppDelegate.swift
│   ├── ContentView.swift
│   ├── desktop_videoApp.swift
│   ├── LanguageManager.swift
│   ├── SharedWallpaperWindowManager.swift
│   ├── Utils.swift
│   ├── WallpaperWindow.swift
│   └── Localizable.xcstrings
├── ChangeLog.md
├── README-EN.md
├── README.md
├── SECURITY.md
├── releases/
├── statics/
└── demos/
```

## Development Guidelines

### Code Style

- Read through the entire repo.
- Use Xcode's default Swift formatting or swift-format.
- Keep code clean and readable.
- Reuse the methods that is already written.
- Check whethere there are previous logic and methods that are no longer effective.
- Add a clear, informative log statement for each new function to aid debugging.
- Provide Chinese comments when adding command-line scripts.
- For Change log, please write it in both English and Chinese; note that please put the later version on the top, above all previous methods
- For the date of the Change log, do NOT infer, Check the current date through Internet or through your system;
- For the version, do NOT infer, use "Version `<Previous-Version-number> `hot-fix `<index>`". There should be only one hot-fix each day.

### Naming Conventions

- Use PascalCase for class and struct names.
- Use camelCase for function and variable names.
- File names should match the main type they contain.

### Git Workflow

- Create feature branches from `main` with a short descriptive name.
- Commit messages should use the format `<type>: <summary>` (e.g., `feat: add HDR video support`).
- Open a pull request referencing related issues and ensure the build passes before requesting review.

## Required Checks

Please check the localizations and translations to find out whether there are changes or additions in code that needs to trasnlate.
If translate is needed, please translate and put the result in the Localizable.xcstrings file.

Run the following command to verify the project compiles:

```bash
xcodebuild \
  -project "desktop video/desktop video.xcodeproj" \
  -scheme "desktop video" \
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

PROJECT_NAME="desktop video"
SCHEME_NAME="desktop video"
DESTINATION="platform=macOS"

echo "📦 检查 xcodebuild 是否可用..."
which xcodebuild > /dev/null || { echo "请安装 Xcode 命令行工具"; exit 1; }

echo "📁 正在初始化项目环境..."

echo "🚧 正在构建项目..."
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -destination "$DESTINATION" \
  clean build

echo "🚀 正在启动 App..."
open "build/Release/${PROJECT_NAME}.app" || \
open "$HOME/Library/Developer/Xcode/DerivedData"/*/Build/Products/Debug/${PROJECT_NAME}.app

echo "✅ 启动完成"
```

## Testing Strategy

- Currently no automated tests are included.
- Ensure the project builds with `xcodebuild clean build` before merging.
- Update `ChangeLog.md` with a summary of your changes.

## Security Policy

See `SECURITY.md` for supported versions and how to report vulnerabilities.
