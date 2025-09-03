# Desktop Video Wallpaper Change Log

# Desktop Video 更新日志

**Desktop Video Wallpaper** is a lightweight dynamic wallpaper app for macOS. It runs entirely offline — no data is uploaded or synced to the cloud, ensuring your privacy and local control.

### Version 4.0 Preview 0903 hot-fix 1 (2025-09-03)

- 同步偏好设置到通用设置界面
- Copy preference settings into general UI

### Version 4.0 Preview 0903 (2025-09-03)

- 在多屏幕环境中添加选择框以指定连接的显示器
- 下拉框中显示显示器名称
- 记住上次选择的显示器并在启动时恢复
- 屏保运行时保持系统唤醒，确保视频持续播放
- 所有视频均从内存加载，移除直接磁盘播放路径
- 使用 BookmarkStore 保存并恢复每个显示器的视频选择和音量
- 清除壁纸时同时移除相关书签
- 自动检查 GitHub 新版本并提示更新
- Add a selection box to choose the display when multiple screens are available
- Show the display name inside the dropdown
- Remember the last chosen display and restore it on launch
- Keep system awake during screensaver so videos keep running
- Load all videos from memory and remove direct disk playback
- Persist video selections and volume per display using BookmarkStore
- Remove bookmark data when clearing wallpapers
- Automatically check GitHub releases for updates and prompt to upgrade

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
- Replace *IdlePauseEnabled* toggle with a new playback mode picker
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

* 更新闲置暂停逻辑，更智能，更节能
* 修复闲置暂停开关无法生效的问题
* 改进显示器热插拔处理，移除黑屏窗口
* 新连接显示器时同步当前视频并保持时间戳
* 优化视频读取逻辑，优先从内存加载
* 添加屏保功能
* 为单桌面控制预留了接口 (currently unavailable because of Apple's settings)
* 修复了一些 bug
* Update idle-pause; smarter and more energy-efficient
* Fix the issue where the idle-pause toggle
* Improve hot-plug handling for displays and eliminate black-screen windows
* Sync the current video and preserve its timestamp when a new display is connected
* Optimize video loading to prioritize in-memory playback
* Add screen-saver
* Add potential code for single space wallpaper control (currently unavailable because of Apple's settings)
* Fix some bugs

### Version 3.0 Beta hot-fix 4 (2025-06-20)

- 优化 dlog 日志，新增日志级别
- 添加中文注释并改进本地化
- Improve dlog logging with level support
- Add Chinese comments and localization updates

### Version 3.0 Beta hot-fix 3 (2025-06-18)

- 添加全屏遮挡检测窗口，完全被遮挡时不进入屏保
- Add full-screen overlay windows; cancel screensaver if fully covered

### Version 3.0 Beta hot-fix 2 (2025-06-15)

- 修复屏保启动时视频被误暂停的问题
- 改进遮挡检测，避免随机暂停和恢复
- Fix issue where videos paused when screensaver started
- Improve occlusion handling to prevent random pauses

### Version 3.0 Beta hot-fix 1 (2025-06-15)

- 修复插拔显示器造成的黑屏/内存异常
- Fix black screen and memory error

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
- 增加了彩蛋
- 移除了HIM
- More Language
- Auto Pause to lower energe consumpsion
- Special bonus hidden
- /kill HIM
- 改进自动暂停逻辑，使用检测窗口判断遮挡
- Improve auto pause logic with overlay windows
- 使用四个检测窗口进一步优化暂停触发判断
- Further refine pause triggers using four overlay windows
- 屏保模式下隐藏检测窗口，保持播放并降低资源占用
- 清理未使用的函数和属性，精简代码

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

* 新增了静音按钮
* 现在视频可以通过拖拽的方式添加
* 修复了一些 bug
* Add a mute button
* Now you can drag and drop media
* Fix some bugs
* 注：全局设置只在打开软件的时候会更新，所以要更改全局设置请重启软件

### Version 2.2 (2025-05-05)

* 新增了开机自启动
* 新增了视频恢复功能
* 修复了一些 bug
* add start at launch
* able to recover videos
* bugs fixed

### Version 2.1 (2025-05-03)

* 优化单显示器体验
* 修复多显示器下的显示异常问题
* 新增显示器热插拔支持
* 新增显示器同步及自动同步新显示器功能
* 优化磁盘空间占用
* 修复了一些 bug
* Improved single-display experience
* Fixed display issues in multi-display setups
* Added support for hot-plugging monitors
* Added display synchronization and automatic sync for new monitors
* Optimized disk space usage
* Bug fixed

### Version 2.0 (2025-04-26)

* 支持多显示屏
* 支持菜单栏图标显示
* 修复了一些 bug
* Multiple screen support
* Menubar Item support
* Fix bugs

### Version 1.0 (2025-03-26)

* 支持图片壁纸
* 修复了一些 bug
* You can now add images as wall papers
* Fix some bugs

### alpha 0.2 (2025-03-25)

* 新增了音量控件
* 新增了更改视频按钮
* 修复了一些错误
* Choose your volume! Now you can set the volume of your video
* Close video and change video! Now you can close video or change video
* Fixed some bugs

### alpha 0.1 (2025-03-21)

- 梦开始的地方
- 可以让视频作为 Mac 动态壁纸
- The first version of desktop video
- Users can choose a video as Mac's wallpaper
