# Desktop Video App

macOS 上的动态壁纸应用，使用 Swift 和 SwiftUI 构建。支持用户为每个屏幕设置不同的视频或图片作为桌面背景。具备多屏幕支持、媒体访问持久化和用户设置保存等功能。

A macOS dynamic wallpaper app built with Swift and SwiftUI that allows users to set custom videos or images as wallpapers on individual screens. The app supports multi-screen setups and persistent media access with Security-Scoped Bookmarks.

---

## 🌟 功能 Features

- 🎥 将视频或图片设置为桌面壁纸 Set videos or images as wallpapers
- 🖥 多屏幕独立设置（即使只有一个屏幕）Per-screen customization, even with a single display
- 💾 支持重启后恢复媒体访问权限 Persistent access with Security-Scoped Bookmarks
- 🔊 记住音量和拉伸模式 Remembers video settings like volume and stretch
- 🖱 自动识别屏幕并提供选择菜单 Detects screens and lets user choose which to control
- 🧠 减少磁盘读写，优化性能 Loads videos into memory to reduce disk I/O

---

## 🛠️ 构建方法 How to Build

1. 使用 Xcode 打开项目 Open the project in Xcode
2. 确保目标启用了以下设置 Ensure the target includes:
   - ✅ 启用 App Sandbox App Sandbox enabled
   - ✅ 启用 Security-Scoped Bookmarks 权限 Security-Scoped Bookmarks capability
3. 运行于 macOS 12.0 或以上版本 Run on macOS 12.0+
4. 支持 Intel & Apple 芯片 Support Intel & Apple Sillicon

---

## 🔮 未来改进 Future Improvements

- 🔄 定时自动更换壁纸 Auto-switch wallpapers on schedule
- 🧱 视频格式兼容性或自动转码 Fallback or conversion for unsupported formats
- 🌄 接入在线壁纸库 Online wallpaper gallery
- 🪟 更好窗口缩放体验 Improved window resizing UX
- 🐞 多视频流性能优化 Performance optimization for multi-video setup

---

## 📄 许可证 License

MIT License © 2025 Zijia Tang
