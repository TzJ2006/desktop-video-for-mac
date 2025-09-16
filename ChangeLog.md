# Desktop Video Wallpaper Change Log

# Desktop Video 更新日志

**Desktop Video Wallpaper*- is a lightweight dynamic wallpaper app for macOS. It runs entirely offline — no data is uploaded or synced to the cloud, ensuring your privacy and local control.

### Version 4.0 (2025-09-16)

- 修改了UI设计，现在的UI设计更加好看
- 修复了因为UI修改带来的bug
- 添加了 macOS 26 Tahoe 支持
- 更多修改请见 Preview 版本
- Much Better UI
- Fix bug because of the new UI.
- Added support for macOS 26 Tahoe
- For more changes, please look at the Preview versions in the changelog.

### Version 4.0 Preview 0915 (2025-09-15)

- 统一窗口管理入口，确保每块屏幕仅创建一次壁纸窗口与菜单栏覆盖层
- Centralize window orchestration so each display keeps a single wallpaper and menu bar overlay window
- 提升菜单栏镜像面板层级并改为事件驱动刷新，移除 500 ms 轮询
- Raise the mirrored menu bar panel above the status bar and refresh it through space/screen/app events, removing the 500 ms polling timer
- 清理未使用代码并为后续保留项添加 periphery 标记
- Remove unused sources and annotate reserved declarations with periphery directives
- 修复应用启动时会弹出两个主窗口的问题，统一复用 SwiftUI 创建的主控制窗口
- Fix the duplicate main window shown at launch by reusing the SwiftUI-hosted controller window
- 移除菜单栏覆盖层实现与相关窗口调度逻辑，简化多屏幕管理
- Remove the menu bar overlay implementation and related window orchestration logic to simplify multi-display management
- 删除状态栏视频设置与界面组件，同时保留视频拉伸覆盖菜单栏的能力
- Delete the status bar video setting and UI components while keeping the video stretch-to-menu-bar capability intact

### Version 4.0 Preview 0914 (2025-09-14)

- 使用 `@MainActor` 注解 `SharedWallpaperWindowManager`，修复 `tearDownWindow` 并发编译错误
- Annotate `SharedWallpaperWindowManager` with `@MainActor` to fix `tearDownWindow` concurrency build errors
- 清理重复的覆盖层移除逻辑，防止窗口状态不一致
- Remove duplicate overlay cleanup to avoid inconsistent window state

### Version 4.0 Preview 0913 (2025-09-13)

- 在菜单栏显示视频并支持 Split 形状
- 强化 WallpaperWindow 生命周期管理，防止 Zombie 崩溃
- Show wallpaper video in menu bar with split shape overlay
- Stabilize WallpaperWindow lifetime to avoid zombie crashes

### Version 4.0 Preview 0912 (2025-09-12)

- 修复添加或移除视频时出现的死循环崩溃
- Fix crash caused by infinite loop when adding or removing videos
- 更新贡献指南以适配新的目录结构
- Update contribution guide to match new folder layout
- 移除跨屏视频自动同步，改为手动同步
- Remove automatic cross-screen video sync; synchronization is now manual
- 使用内存缓存视频数据以减少磁盘读取
- Use in-memory video data caching to reduce disk reads
- 修复内存播放视频缺少扩展名导致黑屏的问题
- Fix black screen when temporary video files missed extensions
- 修复恢复播放从头开始的问题
- Fix video restarting instead of resuming playback
- 修复恢复播放时的黑屏闪烁
- Fix black screen flash when resuming playback
- 修复移除视频时的内存错误崩溃
- Fix memory error crash when removing videos
- 修复更换视频时的内存峰值问题，适配多屏场景
- Fix memory spike when switching videos across multiple screens

### Version 4.0 Preview 0911 (2025-09-11)

- 改用内存映射加载视频以降低磁盘读写
- 移除临时文件写入与内存视频缓存
- Use memory-mapped video loading to reduce disk I/O
- Remove temporary file writes and in-memory video cache

### Version 4.0 Preview 0910 (2025-09-10)

- 新增在状态栏显示视频的开关
- 全屏时状态栏背景仅显示壁纸视频上缘且不遮挡菜单文字
- 修复无法清除视频的问题
- 修复状态栏不显示视频的问题
- 修复“拉伸以填充”设置无效的问题
- 将“在状态栏显示视频”选项移动至通用设置
- 在状态栏中按正确比例显示视频背景
- Added toggle to show video in status bar
- Status bar background crops to the top edge of the wallpaper video and stays behind menu text in full screen
- Fix issue where clearing video failed
- Fix issue where video did not appear in status bar
- Fix stretch-to-fill setting not applying
- Move “Show video in status bar” option to General settings
- Keep status bar video at correct aspect ratio

### Version 4.0 Preview 0909 (2025-09-09)

- 移除 GitHub 更新检查以避免沙盒环境下的网络错误
- 避免对壁纸窗口调用 makeKeyWindow 以消除系统警告
- 使用 OSLog 将调试输出标记为 Debug 级别
- 当仅连接外接显示器时自动恢复上次壁纸，避免黑屏
- Remove GitHub update check to prevent sandbox network errors
- Avoid calling makeKeyWindow on wallpaper window to eliminate system warnings
- Mark debug output using OSLog so it shows as Debug in console
- Automatically restore last wallpaper when only external displays are connected to avoid black screen

### Version 4.0 Preview 0905 (2025-09-05)

- 修复命名问题
- 修复重复加载或卸载视频导致无法播放的问题
- 修复同步视频到其他屏幕后崩溃并出现内存溢出的错误
- 限制 `windowScreenDidChange` 事件触发频率
- 视频切换后延迟 1 秒重新评估是否需要暂停
- Fix typo
- Fix failure when repeatedly loading or unloading videos
- Fix OOM crash when syncing video to additional screens
- Throttle `windowScreenDidChange` to avoid rapid triggering
- Reevaluate pause state one second after switching videos

### Version 4.0 Preview 0904 (2025-09-04)

- 修复屏幕保护程序计时器不启动的问题
- 修复同步屏幕时未正确移除旧视频的问题
- 修复切换显示器时“正在播放”未正确更新的问题
- 修复多屏幕相同视频时切换其中一屏视频导致的死循环
- 新增 Control+Command+H 快捷键以启动屏幕保护程序，并预留统一管理位置
- 在设置界面显示当前播放文件名
- 尝试修复屏保播放时偶尔出现黑屏闪烁的问题
- 新增同步按钮，将当前屏幕的视频同步到所有屏幕
- Fix issue where screensaver timer failed to start
- Add Control+Command+H shortcut to launch screensaver with centralized binding
- Show now playing file name in settings UI
  Fix intermittent black flashes during screensaver by reloading media without clearing
- Fix issue where the "Now Playing" label didn't update when switching screens
- Fix issue where synced screens kept the previous video when replacing it
- Prevent dead loop when changing video on one screen when both screens share the same video
- Add button to sync the current screen's video to all screens

### Version 4.0 Preview 0903 (2025-09-03)

- 在多屏幕环境中添加选择框以指定连接的显示器
- 下拉框中显示显示器名称
- 记住上次选择的显示器并在启动时恢复
- 屏保运行时保持系统唤醒，确保视频持续播放
- 所有视频均从内存加载，移除直接磁盘播放路径
- 使用 BookmarkStore 保存并恢复每个显示器的视频选择和音量
- 清除壁纸时同时移除相关书签
- 自动检查 GitHub 新版本并提示更新
- 主窗口尺寸增大时同步放大文本和图标
- Add a selection box to choose the display when multiple screens are available
- Show the display name inside the dropdown
- Remember the last chosen display and restore it on launch
- Keep system awake during screensaver so videos keep running
- Load all videos from memory and remove direct disk playback
- Persist video selections and volume per display using BookmarkStore
- Remove bookmark data when clearing wallpapers
- Automatically check GitHub releases for updates and prompt to upgrade
- Scale text and icons when enlarging main window

### Version 4.0 Preview 0902 hot-fix 1 (2025-09-02)

- 本地化单屏幕与设置页面字符串
- 恢复关于对话框原始内容
- Localize single-screen and settings page strings
- Restore original About dialog text

### Version 4.0 Preview 0902 (2025-09-02)

- 为主控制器侧边栏添加本地化支持
- 补全缺失的多语言翻译
- 在主界面调整通用设置时加入重启提示
- 将音量滑块与输入框结合为功率计样式
- 为播放模式提供详细说明
- 新增音量与空闲暂停灵敏度输入框并追加静音复选框
- Add localization support for main controller sidebar
- Complete missing translations in resource file
- Prompt restart when changing general settings in main interface
- Combine volume slider and input box into a power-meter control
- Add descriptions for playback modes
- Add input fields for volume and idle-pause sensitivity with a mute checkbox

### Version 4.0 Preview 0901 (2025-09-01)

- 改善多显示器列表更新逻辑
- 移除调试遮挡窗口以避免桌面切换闪烁
- 修复控制面板初始状态不同步的问题
- 修复“仅在菜单栏显示”选项未立即生效的问题
- 缩小偏好设置窗口尺寸以更好匹配字体大小
- 修复语言选择器未正确显示所选语言的问题
- 新增繁體中文、法语和西班牙语等语言选项
- Improve multi-display list refresh
- Remove debug overlay to prevent flashes when switching desktops
- Sync initial control values in the settings page
- Fix issue where "Show only in menu bar" didn't apply immediately
- Fix language picker not showing the selected language
- Add language options for Traditional Chinese, French, and Spanish

### Version 4.0 Preview 0814 (2025-08-14)

- 引入基于 SwiftUI的现代化窗口界面框架，
- 添加可扩展侧边栏与卡片式设置布局
- Added SwiftUI-based preference window framework
- Introduced extensible sidebar and card layout for settings
- 归档多余文件并整理目录结构
- 把 Desktop Video 项目文件集中到 `desktopVideo/`
- Archived non-Xcode files and organized directory structure
- Consolidated Desktop Video project files under `desktopVideo/`

### Version 3.1 hot-fix 1 (2025-07-01)

- 替换“自动暂停”开关为全新的播放模式选择
- 将播放模式选项移动到空闲暂停灵敏度之前
- 更新本地化字符串
- Replace *IdlePauseEnabled- toggle with a new playback mode picker
- Moved the picker above the idle pause sensitivity setting
- Updated localization strings
- 将空闲暂停灵敏度迁移到 AppState
- 修复沙盒环境下应用无法重启的问题
- Moved idle pause sensitivity into AppState
- Fixed restart logic for sandboxed environment
- 增强中文翻译并添加更多中文注释
- Improved Chinese localization and added detailed Chinese comments

### Version 3.1 (2025-06-28)

- 新增手动启动屏保菜单项
- 自动检测并重新分配被系统移到错误显示器的窗口
- 更稳定地恢复黑屏窗口
- Added menu option to start the screensaver manually
- Automatically reassign windows that macOS moves to the wrong display
- More robust recovery when wallpaper windows disappear

### Version 3.0 hot-fix 1 (2025-06-27)

- 强绑定显示器 UUID，避免 PID 变化导致错绑
- 修复新增或移除显示器后壁纸黑屏的问题
- 修复新增或移除显示器后壁纸不显示的问题
- 检测黑屏并自动从书签恢复
- 当视频名称超过 30 个字符时，自动截取前后两半以保证正确显示
- Use stable screen UUID to prevent window misalignment
- Fix bug when screens do not exist when displays are added or removed
- Fix rare black screen when displays are added or removed
- Detect black screens and reload from bookmarks
- Better Appearence when the name of the video is longer than 30 characters

### Version 3.0 (2025-06-25)

- 更新闲置暂停逻辑，更智能，更节能
- 修复闲置暂停开关无法生效的问题
- 改进显示器热插拔处理，移除黑屏窗口
- 新连接显示器时同步当前视频并保持时间戳
- 优化视频读取逻辑，优先从内存加载
- 添加屏保功能
- 为单桌面控制预留了接口 (currently unavailable because of Apple's settings)
- 修复了一些 bug
- Update idle-pause; smarter and more energy-efficient
- Fix the issue where the idle-pause toggle
- Improve hot-plug handling for displays and eliminate black-screen windows
- Sync the current video and preserve its timestamp when a new display is connected
- Optimize video loading to prioritize in-memory playback
- Add screen-saver
- Add potential code for single space wallpaper control (currently unavailable because of Apple's settings)
- Fix some bugs

### Version 3.0 Beta hot-fix 3 (2025-06-20)

- 优化 dlog 日志，新增日志级别
- 添加中文注释并改进本地化
- Improve dlog logging with level support
- Add Chinese comments and localization updates

### Version 3.0 Beta hot-fix 2 (2025-06-18)

- 添加全屏遮挡检测窗口，完全被遮挡时不进入屏保
- Add full-screen overlay windows; cancel screensaver if fully covered

### Version 3.0 Beta hot-fix 1 (2025-06-15)

- 修复插拔显示器造成的黑屏/内存异常
- 修复屏保启动时视频被误暂停的问题
- 改进遮挡检测，避免随机暂停和恢复
- Fix black screen and memory error
- Fix issue where videos paused when screensaver started
- Improve occlusion handling to prevent random pauses

### Version 3.0 Beta (2025-06-11)

- 更新闲置暂停逻辑，更智能，更节能
- 修复闲置暂停开关无法生效的问题
- 改进显示器热插拔处理，移除黑屏窗口
- 新连接显示器时同步当前视频并保持时间戳
- 优化视频读取逻辑，优先从内存加载
- 添加屏保功能
- Update idle-pause; smarter and more energy-efficient
- Fix the issue where the idle-pause toggle
- Improve hot-plug handling for displays and eliminate black-screen windows
- Sync the current video and preserve its timestamp when a new display is connected
- Optimize video loading to prioritize in-memory playback
- Add screen-saver

### Version 2.5 生日特辑 (2025-05-30)

- 增加了更多语言支持
- 支持了自动暂停以降低能耗
- 改进自动暂停逻辑，使用检测窗口判断遮挡
- 使用四个检测窗口进一步优化暂停触发判断
- 屏保模式下隐藏检测窗口，保持播放并降低资源占用
- 清理未使用的函数和属性，精简代码
- 增加了彩蛋
- 移除了HIM
- More Language
- Auto Pause to lower energe consumpsion
- Improve auto pause logic with overlay windows
- Further refine pause triggers using four overlay windows
- Happy Birthday to myself!
- /kill HIM

### Version 2.4 (2025-05-28)

- 新增了 Preference 页面
- 支持了最新系统 Sequoia 15.5
- Add Preference Page
- Support Sequoia 15.5

### Version 2.3.2 (2025-05-28)

- 添加了多语言支持
- Support Multiple Language (Currently Chinese-Simplified and English)

### Version 2.3.1 (2025-05-13)

- 修改了一个更好看的 menubar icon
- Better menubar icon

### Version 2.3 (2025-05-10)

- 新增了静音按钮
- 现在视频可以通过拖拽的方式添加
- 修复了一些 bug
- Add a mute button
- Now you can drag and drop media
- Fix some bugs
- 注：全局设置只在打开软件的时候会更新，所以要更改全局设置请重启软件

### Version 2.2 (2025-05-05)

- 新增了开机自启动
- 新增了视频恢复功能
- 修复了一些 bug
- add start at launch
- able to recover videos
- bugs fixed

### Version 2.1 (2025-05-03)

- 优化单显示器体验
- 修复多显示器下的显示异常问题
- 新增显示器热插拔支持
- 新增显示器同步及自动同步新显示器功能
- 优化磁盘空间占用
- 修复了一些 bug
- Improved single-display experience
- Fixed display issues in multi-display setups
- Added support for hot-plugging monitors
- Added display synchronization and automatic sync for new monitors
- Optimized disk space usage
- Bug fixed

### Version 2.0 (2025-04-26)

- 支持多显示屏
- 支持菜单栏图标显示
- 修复了一些 bug
- Multiple screen support
- Menubar Item support
- Fix bugs

### Version 1.0 (2025-03-26)

- 支持图片壁纸
- 修复了一些 bug
- You can now add images as wall papers
- Fix some bugs

### alpha 0.2 (2025-03-25)

- 新增了音量控件
- 新增了更改视频按钮
- 修复了一些错误
- Choose your volume! Now you can set the volume of your video
- Close video and change video! Now you can close video or change video
- Fixed some bugs

### alpha 0.1 (2025-03-21)

- 梦开始的地方
- 可以让视频作为 Mac 动态壁纸
- The first version of desktop video
- Users can choose a video as Mac's wallpaper
