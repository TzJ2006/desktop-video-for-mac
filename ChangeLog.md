# Desktop Video Wallpaper Change Log

**Desktop Video Wallpaper** is a lightweight dynamic wallpaper app for macOS. It runs entirely offline — no data is uploaded or synced to the cloud, ensuring your privacy and local control.

### Version 3.8 (2025-06-19)

- 注释所有与视频内存缓存相关的代码，回归 AVPlayer 播放实现
- Comment out memory caching for videos and revert to AVPlayer playback

### Version 3.7 (2025-06-18)

- 修复清理窗口时崩溃的问题，确保异步事件完成后移除引用
- Fix crash when clearing windows by removing references after async events

### Version 3.6 (2025-06-17)

- 修复视频内存缓存未释放导致的内存溢出，并统一视频播放逻辑
- Fix memory leaks from cached video data and consolidate playback code

### Version 3.5 (2025-06-16)

- 处理多屏共享临时视频时的引用，避免在其他屏幕仍在使用时删除文件
- Track usage of temp videos across displays to avoid deleting files still in use

### Version 3.4 (2025-06-15)

- 修复显示器插拔后临时视频文件未清理导致的内存错误
- Fix memory errors caused by temporary video files not being removed after display hot-plug

### Version 3.3 (2025-06-14)

- 新增在监测到新显示器时同步主控制器屏幕内容
- Auto-sync new displays with the primary controller screen

### Version 3.2 (2025-06-13)

- 将 Dock 与菜单栏图标管理逻辑移入 `AppAppearanceManager`
- 修复关闭壁纸后黑屏的问题，关闭窗口时一并销毁辅助窗口
- Moved dock/menu bar handling into `AppAppearanceManager`
- Fixed black screen when closing wallpaper by fully closing helper windows

### Version 3.1 (2025-06-12)

- 重构应用结构，将屏保及自动暂停逻辑移入独立管理器
- Refactor: move screensaver and idle pause code into separate managers
- 简化闲置暂停检测窗口，只使用一个可调边距的透明窗口
- Simplify idle-pause overlay to a single window with adjustable margin

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
- Users can choose video as Mac's wallpaper
