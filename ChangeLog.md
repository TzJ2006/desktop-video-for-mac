# Desktop Video Wallpaper Change Log

# Desktop Video 更新日志

**Desktop Video Wallpaper*- is a lightweight dynamic wallpaper app for macOS. It runs entirely offline — no data is uploaded or synced to the cloud, ensuring your privacy and local control.

### Version 5.0 Preview 0615 (2026-06-15)

- 「通用」页把「外观」从分段控件改为可点开的下拉菜单，与下方「壁纸库排序」「语言」一致；三者改用统一的自绘下拉组件 `CenteredMenuPicker`：框内文字居中（原生 Picker(.menu) 只能左对齐）、统一宽度（200pt，容纳最长的本地化选项）、右对齐，菜单项仍用内联 Picker 保留「选中打勾」语义
- General: change "Appearance" from a segmented control to a pop-up menu, matching the "Library sort order" and "Language" rows below it; all three now use one custom dropdown component (`CenteredMenuPicker`) with the selected text centered in the box (the native Picker(.menu) only left-aligns it), a shared width (200pt, sized for the longest localized option) and right alignment, while the menu items still use an inline Picker to keep the native "checkmark on selected" behavior
- 修复上一条改动经审查发现的回归：(1) 灵敏度默认值此前只改了 `AppState` 与「恢复默认」两处，遗漏了 `AppDelegate.applicationDidFinishLaunching` 里的 `register(defaults:)`（仍为 40），导致全新安装时新默认 50% 不生效——现统一为 50%（同时把旧偏好窗口 `PreferencesView` 里的 40 残留也对齐为 50）。(2) 修复「屏保 / 视频缓存」并排为半宽卡片后，在最小窗口宽度（620）下多语言文本被截断的问题：屏保卡改用短标题 `ScreenSaverTitle`（「屏幕保护」），卡片标题与拨动开关标题改为缩放而非截断（`minimumScaleFactor`），设置行长标题改为换行而非截断
- Fix regressions found by review of the previous entry: (1) the sensitivity default was changed only in `AppState` and "Restore Defaults" but the `register(defaults:)` call in `AppDelegate.applicationDidFinishLaunching` was missed (still 40), so the new 50% default never took effect on fresh installs — all three sources are now 50% (the stale 40 literals in the legacy `PreferencesView` were reconciled to 50 too). (2) Fix multi-locale text truncation at the minimum window width (620) after the Screen Saver / video-cache cards became half-width side-by-side: the screensaver card uses a short title (`ScreenSaverTitle`, "Screen Saver"), card titles and toggle labels now scale down instead of truncating (`minimumScaleFactor`), and long setting-row titles wrap instead of truncating
- 优化「自动暂停灵敏度」滑块与「通用」页布局：把灵敏度默认值由 40% 改为 50%；将原生 Slider 换成自绘的磁吸滑块（`SnappingSlider`），在 0% / 25% / 50% / 75% / 100% 设置磁吸档位，拖动到档位附近会自动吸附，并修复原生 Slider 因拇指内缩量未知导致「值为 50% 时拇指与 50% 标签对不齐」的问题——新滑块自绘轨道 / 拇指 / 刻度 / 标签，档位标签与拇指中心严格对齐。「通用」页把「全局静音」与「登录时启动」并排为一排两个；把「将壁纸设为屏保」与「视频缓存上限」并排为左右两张卡片（屏保开关移至卡片头部、缓存卡只保留右对齐输入框，避免半宽并排时标题重复）
- Refine the "Idle pause sensitivity" slider and the General page layout: change the sensitivity default from 40% to 50%; replace the native Slider with a custom magnetic-snap slider (`SnappingSlider`) that traps at 0% / 25% / 50% / 75% / 100% — dragging near a tick snaps to it — and fix the native Slider's "thumb doesn't line up with the 50% label at value 50%" caused by its undisclosed knob inset (the new slider draws its own track/thumb/ticks/labels so the tick labels align exactly with the thumb center). On General, "Global Mute" and "Launch at Login" are placed side by side (two per row), and "Set Wallpaper as Screen Saver" and "Max video cache" become two side-by-side cards (the screensaver toggle moved into the card header, and the cache card keeps only a right-aligned field to avoid repeating the title at half width)
- 将外观系统重构为统一的 liquid glass 设计：把当天早先的「经典 / 玻璃深色」两套主题预设合并为同一套半透明玻璃界面，仅由「外观」开关（跟随系统 / 浅色 / 深色）驱动明暗，在「通用」设置里以分段控件实时切换、无需重启（旧的 `selectedTheme` 值自动迁移：classic→跟随系统、glassDark→深色）。主窗口改为整窗半透明 + 透明标题栏，底层用 behind-window 的 `NSVisualEffectView`（`WindowBlur`）模糊透出桌面 / 壁纸，卡片叠 within-window 磨砂材质形成层次；颜色仍以系统语义色为主、随 `.preferredColorScheme` 自动适配，外观切换对全部页面（壁纸 / 播放 / 历史 / 通用）生效（真正的系统级 Liquid Glass API 需 macOS 26，此处用材质模拟同等观感）
- Rework the appearance system into one unified liquid-glass design: the two earlier theme presets ("Classic" / "Glass Dark") shipped the same day are merged into a single translucent-glass UI driven only by an Appearance switch (System / Light / Dark), toggled live via a segmented control in General settings with no restart (the legacy `selectedTheme` value is migrated automatically: classic→System, glassDark→Dark). The main window becomes fully translucent with a transparent title bar, backed by a behind-window `NSVisualEffectView` (`WindowBlur`) that blurs the desktop/wallpaper through, with within-window frosted materials layered on the cards; colors remain system-semantic and adapt via `.preferredColorScheme`, and the appearance applies to every page (Wallpaper / Playback / History / General). (The real system-level Liquid Glass API requires macOS 26; this simulates the same look with materials.)
- 重新设计「播放」与「通用」页面：左对齐大标题 + 副标题 + 右上角动作区（`PageHeader`）。播放页保留全部 5 个播放模式（新的分段式 `PlaybackModeSelector`）、带百分比读数的遮挡阈值滑块，并把「自动连播」与「播放列表」拆为左右两张玻璃卡片，新增「恢复默认设置」一键重置播放与连播相关项（实时生效）。`CardSection` 重做为「图标徽章 + 左对齐标题 + 可选配件槽」的玻璃卡片，使全 App 卡片观感统一；通用页的开关改用拨动开关样式
- Redesign the Playback and General pages: a left-aligned large title + subtitle + top-right actions (`PageHeader`). Playback keeps all 5 playback modes (the new segmented `PlaybackModeSelector`), a threshold slider with a percentage readout, and splits "Auto-advance" and "Playlist" into two side-by-side glass cards, plus a "Restore Defaults" action that resets the playback/slideshow preferences live. `CardSection` is rebuilt as a glass card with an "icon badge + left-aligned title + optional accessory slot" so all cards across the app look consistent; General's toggles now use the switch style
- 新增可切换的应用主题系统：把颜色、材质、强调色、内容类型色、圆角、边框/选中色抽象为一组「设计 token」（`ThemeTokens`），界面组件通过 SwiftUI 环境 `@Environment(\.theme)` 读取，与具体配色彻底解耦。内置两套主题——「经典」（当前外观，跟随系统明暗）与「玻璃深色」（半透明玻璃卡片 + 发光蓝 + 更圆的卡片，强制深色），在「通用」设置里下拉选择即可**实时切换、无需重启**。架构上复用 `LanguageManager` / `AppState` 的单例 + `@Published` + UserDefaults 持久化模式（`ThemeManager`），新增主题只需在 `AppTheme` 注册表中加一个 case 与对应 token 预设。多数语义色（`.primary`/`.secondary`/系统背景色/材质）仍交由 `.preferredColorScheme` 自动适配明暗，token 只承载非自适应的差异部分
- Add a switchable app theme system: colors, materials, accent, content-type colors, corner radii and border/selection colors are abstracted into a set of design tokens (`ThemeTokens`) that UI components read via the SwiftUI environment (`@Environment(\.theme)`), fully decoupling the views from any specific palette. Two built-in themes ship — "Classic" (the current look, follows the system light/dark) and "Glass Dark" (translucent glass cards + a glowing blue accent + rounder corners, forced dark) — selectable from a dropdown in General settings and **applied live, no restart required**. It reuses the singleton + `@Published` + UserDefaults pattern of `LanguageManager` / `AppState` (`ThemeManager`); adding a new theme is just one more case in the `AppTheme` registry plus its token preset. Most semantic colors (`.primary`/`.secondary`/system backgrounds/materials) still adapt to light/dark automatically via `.preferredColorScheme`, so tokens only carry the non-adaptive deltas
- 缩略图增加磁盘持久化缓存：内存 `NSCache` 会被系统驱逐、重启即清，导致切回「墙纸」页仍可能全量重解。现在缩略图生成后以 PNG 落盘到沙盒 `Caches/Thumbnails`（文件名为缓存键的 SHA256），命中顺序为内存 → 磁盘 → 解码生成，扛住内存驱逐并跨重启复用；磁盘缓存设 128MB 上限，超限时按修改时间从旧到新清理，写入在后台串行队列以免阻塞主线程
- Add a persistent on-disk thumbnail cache: the in-memory `NSCache` gets evicted under pressure and is cleared on relaunch, so returning to the Wallpaper page could still re-decode everything. Thumbnails are now written as PNG to the sandbox `Caches/Thumbnails` (filename = SHA256 of the cache key); lookup order is memory → disk → decode, surviving eviction and reuse across launches. The disk cache is capped at 128MB and pruned oldest-first when exceeded, with writes on a background serial queue to avoid blocking the main thread
- 缩略图增加负缓存与可访问性预检：画廊磁贴此前直接调缩略图生成，对无权限/已移动的文件每次切页都重复触发 AVFoundation/ImageIO 并刷出权限错误日志。现在缓存未命中时先做 `MediaAccess.isAccessible` 预检，不可读则记入负缓存直接跳过（解码失败同样记入），避免反复昂贵调用与日志刷屏；负缓存在 `WallpaperContentDidChange`（重新授权后必触发）时清空，使恢复可读的文件能重新生成
- Add a negative cache and accessibility pre-check for thumbnails: gallery tiles previously called thumbnail generation directly, so inaccessible/moved files re-triggered AVFoundation/ImageIO on every page switch and spammed permission errors in the log. On a cache miss it now runs a `MediaAccess.isAccessible` pre-check and, if unreadable, records the key in a negative cache and skips (decode failures are recorded too), avoiding repeated expensive calls and log spam; the negative cache is cleared on `WallpaperContentDidChange` (always fired after re-authorization) so files that become readable again get regenerated
- 优化缩略图缓存：此前历史行、墙纸画廊磁贴、墙纸大预览各自按不同尺寸（128×96 / 264×168 / 480×300）请求缩略图，缓存键含尺寸维度，导致同一文件被解码并缓存最多 3 次，切换侧边栏页面（如「设置/播放」→「墙纸」）时缩略图全量重新生成、耗资源耗时。现统一为单一 `canonicalSize`（480×300，各界面最大需求）解码一次、各界面显示时用 `.resizable()` 缩放，缓存键去掉尺寸维度，同一文件全程只解码一张并复用；NSImage 逻辑尺寸改用 CGImage 实际像素尺寸以保留真实宽高比、避免拉伸变形
- Optimize thumbnail caching: previously the history row, gallery tile and large preview each requested thumbnails at different sizes (128×96 / 264×168 / 480×300) and the cache key included the size, so the same file was decoded and cached up to 3 times and switching sidebar pages (e.g. Settings/Playback → Wallpaper) regenerated all thumbnails — costly and slow. Unified to a single `canonicalSize` (480×300, the largest need) decoded once and scaled per view via `.resizable()`, with the size dimension dropped from the cache key so each file is decoded once and reused everywhere; the NSImage logical size now uses the CGImage's actual pixel dimensions to preserve the true aspect ratio and avoid stretching
- 自动清理网页壁纸遗留的 WebKit 缓存：此前网页壁纸的 WKWebView 使用默认持久化数据存储，HTTP 网络缓存会无限堆积在 `~/Library/Containers/<bundle>/Data/Library/Caches/WebKit/NetworkCache`（实测已达约 98MB）且从不清理。现新增 `clearWebCache()`，在 App 启动时（清理历史/上次会话遗留）以及最后一个网页壁纸被移除时自动清掉网络/磁盘/离线缓存，保留 cookies 与 localStorage 使浏览模式登录态可跨启动保留，把缓存增长限制在网页壁纸活跃期间
- Auto-clear leftover WebKit cache from web wallpapers: web-wallpaper WKWebViews previously used the default persistent data store, so the HTTP network cache grew without bound in `~/Library/Containers/<bundle>/Data/Library/Caches/WebKit/NetworkCache` (~98MB observed) and was never cleared. Added `clearWebCache()`, invoked on app launch (purging legacy/previous-session leftovers) and when the last web wallpaper is removed, clearing network/disk/offline caches while preserving cookies and localStorage so browse-mode logins persist across launches — bounding cache growth to the period a web wallpaper is active

### Version 5.0 Preview 0614 (2026-06-14)

- 历史记录改为按屏幕区分：每块屏幕各自保留自己的使用历史，切换「历史记录」界面的显示器选择器即切换对应历史列表；「清除历史」只清当前所选屏幕。升级时把旧历史（无屏幕归属）一次性归入当前主显示器，使按屏切换可见生效
- Make history per-screen: each display keeps its own usage history, switching the display selector in the History view now switches the corresponding list, and "Clear History" clears only the selected screen. On upgrade, legacy history (no screen attribution) is migrated once to the current main display so per-screen switching takes visible effect
- 修复「墙纸」大预览的重复加载/闪烁：切换侧边栏页面（墙纸/历史/通用）来回时预览会重建并重新解码缩略图；现在视图重建时同步复用内存缓存中的缩略图（首帧即显示），且遮挡、空闲暂停、静音等高频刷新只要内容未变就不再清空重解码
- Fix the Wallpaper large preview reloading/flickering: switching sidebar pages (Wallpaper/History/General) and back rebuilt the preview and re-decoded the thumbnail; the preview now synchronously reuses the in-memory cached thumbnail on view recreation (shown on the first frame), and frequent refreshes (occlusion, idle pause, mute) no longer clear and re-decode while the content is unchanged
- 修复「墙纸」画廊视频/图片缩略图变空白（只显示占位图标）的问题：缩略图取数书签解析此前仅尝试安全作用域、失败即退回不可读的原始 URL，现改为与可访问性判定一致的双分支解析（安全作用域 + 非安全作用域回退），并在失败路径补充诊断日志
- Fix Wallpaper gallery video/image thumbnails rendering blank (placeholder only): the thumbnail bookmark resolution previously tried security-scope only and fell back to an unreadable raw URL on failure; it now uses the same dual-branch resolution as the accessibility check (security-scoped + non-scoped fallback), with diagnostic logging on the failure paths
- 将「墙纸」控件中的「播放」「暂停」两个按钮合并为单一的播放/暂停切换按钮（播放中显示暂停、暂停中显示播放）
- Merge the separate "Play" and "Pause" buttons in the Wallpaper controls into a single play/pause toggle (shows pause while playing, play while paused)
- 修复「墙纸」画廊与「历史记录」混用同一数据源的问题：画廊仅显示壁纸库快捷入口（inLibrary），历史仅显示真正使用过的壁纸（played）；使用后库中条目仍保留
- Fix Wallpaper gallery and History sharing the same data source: the gallery now shows only library shortcuts (inLibrary), History shows only wallpapers actually used (played); library items remain after use
- 壁纸库按 URL 去重，并在「通用」设置中新增排序选项：名称 A–Z / Z–A、最近添加、最近使用
- Deduplicate library items by URL and add sort options in General settings: name A–Z / Z–A, recently added, recently used
- 进一步优化墙纸分区 UI，将控件整合至独立的圆角区域，以完美匹配 macOS 系统偏好设置
- Refine Wallpaper UI by grouping controls into a standalone rounded box to perfectly match macOS System Settings
- 将“添加文件”和“输入网址”磁贴重新设计并内嵌到各个分类的首位
- Redesign "Choose File" and "Input Web URL" tiles and embed them at the beginning of each category grid
- 优化屏保时钟标签的尺寸计算：改为用离屏 host 仅在日期变化时测量并缓存复用，不再每秒在已加入窗口的 NSHostingView 上读取 fittingSize，规避潜在的 AppKit 布局递归告警（_NSDetectedLayoutRecursion）
- Optimize screensaver clock label sizing: measure on an off-window host only when the date changes and reuse the cached size, instead of reading fittingSize on the on-window NSHostingView every second — avoids a potential AppKit layout-recursion warning (_NSDetectedLayoutRecursion)
- 增强内存视频管线健壮性：AVDataAsset 写临时文件失败时记录并向上抛出（不再静默吞错），showVideo 增加空数据防御，并观察 AVPlayerItem 播放状态以在失败时记录错误
- Harden the in-memory video pipeline: AVDataAsset now logs and propagates temp-file write failures (no longer silently swallowed), showVideo guards against empty data, and AVPlayerItem playback status is observed to log errors on failure
- 新增网页壁纸 WKWebView 数量的调试日志，便于核对各屏网页视图与 WebKit 辅助进程的对应关系
- Add a debug log of the active WKWebView count for web wallpapers, to help correlate per-screen web views with WebKit helper processes

#### 自动连播、文件夹、网页预览与重新授权 Slideshow, Folders, Web Preview & Re-authorization

- 新增「自动连播」：在「播放」分区维护一个播放列表（可加入单个文件或整个文件夹），支持顺序/随机、循环开关、图片切换间隔；视频播完自动切下一项、图片按间隔切换，**每块屏幕各自独立**遍历列表
- Add "Slideshow": a playlist in the Playback section (single files or whole folders) with sequential/random order, a loop toggle and an image interval; videos advance when finished, images switch on the interval, and **each screen advances independently**
- 网页壁纸大预览改为用实时 WKWebView 渲染：按屏幕宽高比离屏渲染整页再整体缩放铺进预览框（桌面级窗口的 takeSnapshot 常返回空白，故弃用截图方案），并在画廊/历史中显示正确网址（host），不再因 lastPathComponent 为「/」而显示不出网址
- Render the web wallpaper large preview with a live WKWebView (off-screen full-page render at the screen aspect ratio, scaled to fit), replacing the snapshot approach that often returned blank for desktop-level windows; the correct URL (host) is shown in the gallery/history instead of failing because lastPathComponent is "/"
- 「添加」区将「选择文件」与「选择文件夹」合并为单一入口「选择文件或文件夹…」：同一面板中选中文件即作为壁纸应用，选中文件夹则把其中所有图片/视频批量加入壁纸库（自动保存 per-URL 书签）
- Merge "Choose File" and "Choose Folder" into a single "Choose File or Folder…" entry: in one panel, picking a file applies it as the wallpaper, while picking a folder bulk-imports all its images/videos into the wallpaper library (saving per-URL bookmarks)
- 区分「壁纸库」与「历史记录」：批量添加（如文件夹）的条目只出现在「壁纸」画廊供挑选，不再立刻进入「历史记录」；只有真正被设为壁纸的内容才计入历史。历史与库分别限量（各 100 / 1000 条），避免一次性添加大文件夹把真实历史挤出上限；「清除历史」只清历史、保留库；画廊右键菜单对库存项显示「从壁纸库移除」而非「从历史移除」
- Separate the "wallpaper library" from "History": bulk-added items (e.g. folders) now appear only in the Wallpaper gallery for picking and no longer land in History immediately — only items actually set as wallpaper count as history. History and library are capped independently (100 / 1000) so adding a large folder won't evict real history, "Clear History" clears history only, keeping the library, and the gallery context menu shows "Remove from Library" (not "Remove from history") for library items
- 当视频/图片因被移动、删除或权限丢失而无法显示时，仅在历史记录界面叠加灰色警告标志并显示「请重新授权」；墙纸界面不再叠加该提示，仅回退到占位图标
- When a video/image can't be displayed (moved, deleted, or access lost), show a gray warning icon with "Re-authorize" only in the History view; the Wallpaper view no longer overlays this hint and simply falls back to a placeholder icon
- 应用历史/画廊条目前若文件不可访问，先弹窗请求重新授权，**授权成功后再切换壁纸**；用户取消则保留当前壁纸
- Before applying a history/gallery item, if the file is inaccessible, prompt re-authorization first and **switch the wallpaper only after access is granted**; keep the current wallpaper if cancelled
- 去掉「墙纸」主界面的「屏幕保护程序…」按钮（屏保仍可在偏好设置与菜单栏中启动）
- Remove the "Screen Saver…" button from the Wallpaper main view (the screensaver is still available from Preferences and the menu bar)
- 新增相关多语言文案（中/英/法/西/繁体中文）
- Add localized strings for the new features (zh-Hans/en/fr/es/zh-Hant)

### Version 5.0 Preview 0613 (2026-06-13)

#### 壁纸界面重做为 Apple「墙纸」风格 Redesign Wallpaper UI to Match Apple Wallpaper

- 将「墙纸」分区重做为 macOS「系统设置 > 墙纸」面板样式：顶部为当前壁纸大预览 + 控件检查器（填充模式、播放/暂停/清除、音量与静音、网页浏览），下方为按内容类型分类的缩略图画廊
- Redesign the Wallpaper section to mirror the macOS System Settings > Wallpaper pane: a large current-wallpaper preview with an inspector (display mode, play/pause/clear, volume & mute, web browse) above a categorized thumbnail gallery
- 画廊提供「选择文件…」「输入网址…」添加磁贴，并从历史记录按类型派生「视频 / 图片 / 网页」三行，支持「显示全部」展开为网格
- The gallery offers "Choose File…" and "Input Web URL" add tiles, plus "Videos / Images / Web" rows derived from history by content type, with "Show All" expanding into a grid
- 沿用双击应用壁纸 + 1 秒冷却防抖的既有约定，当前壁纸显示强调色选中描边
- Keep the existing double-click-to-apply convention with a 1-second cooldown; the active wallpaper shows an accent-colored selection ring
- 保留应用侧边栏导航（壁纸 / 播放 / 历史 / 通用），仅重做「墙纸」分区
- Preserve the app's sidebar navigation (Wallpaper / Playback / History / General); only the Wallpaper section is restyled
- 多显示器时在预览上方提供显示器选择器，沿用 dv_displayUUID 与断开自动重选逻辑
- For multi-display setups, a display selector sits above the preview, reusing dv_displayUUID and reselect-on-disconnect logic
- 为 ThumbnailGenerator 增加内存缓存，避免画廊滚动时反复解码视频帧
- Add an in-memory cache to ThumbnailGenerator to avoid re-decoding video frames while scrolling the gallery
- 适当增大主窗口最小尺寸以容纳预览与画廊
- Increase the main window's minimum size to fit the preview and gallery
- 新增相关多语言文案（中/英/法/西/繁体中文）
- Add localized strings for the new UI (zh-Hans/en/fr/es/zh-Hant)

#### 重构评审修复 Redesign Review Fixes

- 修复从画廊「选择文件…」新建视频时未沿用每屏本地静音与当前音量（双层静音回归），及网址应用丢失每屏网页音量
- Fix "Choose File…" not honoring per-screen local mute / current volume when starting a new video, and web-URL apply losing per-screen web volume
- 修复视频缩略图按 4 倍分辨率解码（调用方与生成器重复放大）；为缩略图缓存增加按字节的内存上限并修复同路径文件替换后返回旧图的问题
- Fix video thumbnails decoding at 4× resolution (caller + generator double-scaling); add a byte-based memory cap to the thumbnail cache and invalidate stale entries when a file at the same path is replaced
- 修复切换屏幕/壁纸时预览短暂残留上一张缩略图；修复多屏选择器在保存的屏幕断开后无选中项
- Fix the preview briefly showing the previous thumbnail when switching screen/wallpaper; fix the multi-display picker having no selection when the saved display is disconnected
- 修复分类展开后条目减少仍无法收起；修复音量滑块在内容刷新后触发冗余写入；修复网址输入弹窗重开时残留旧错误
- Fix an expanded category not collapsing after entries drop below the limit; avoid a redundant volume write on content refresh; clear stale error text when reopening the web-URL popover

### Version 4.2 Preview 0312 (2026-03-12)

#### 修复历史记录无法打开旧视频 Fix History Unable to Open Old Videos

- 启用 App Sandbox，使 security-scoped bookmark 能正常创建和解析，修复权限错误 (Code 257)
- Enable App Sandbox so security-scoped bookmarks work correctly, fixing permission errors (Code 257)
- 修复 per-URL 书签解析仅尝试 security-scoped 模式的问题，增加 non-scoped 回退兼容旧书签
- Fix per-URL bookmark resolution only attempting security-scoped mode; add non-scoped fallback for legacy bookmarks
- 视频和图片加载因权限不足失败时，自动弹出 NSOpenPanel 让用户重新授权
- When video or image loading fails due to insufficient permissions, automatically show NSOpenPanel for user re-authorization
- 添加重新授权提示的多语言翻译（中/英/法/西/繁体中文）
- Add localized strings for re-authorization prompt (zh-Hans/en/fr/es/zh-Hant)

### Version 4.2 Preview 0307 (2026-03-07)

#### 运行时日志改善 Runtime Logging Improvements

- 为所有 `evaluateJavaScript` 调用添加错误处理，JS 执行失败时输出 `errorLog` 日志
- Add error handling to all `evaluateJavaScript` calls, logging failures via `errorLog`
- 为私有 API `allowFileAccessFromFileURLs` 添加注释说明
- Add comment noting `allowFileAccessFromFileURLs` as a private API

#### 网页壁纸 Web Wallpaper

- 新增网页壁纸功能：支持通过 URL 加载任意网页作为桌面壁纸，可播放 YouTube、Bilibili 等平台视频
- Add web wallpaper support: load any web page as desktop wallpaper via URL, enabling playback of YouTube, Bilibili and other platform videos
- 使用 WKWebView 渲染网页，支持自动播放媒体内容
- Use WKWebView to render web pages with automatic media playback support
- 网页壁纸支持持久化：退出并重启应用后自动恢复网页壁纸
- Web wallpaper persistence: automatically restore web wallpapers after app restart
- 历史记录支持网页条目，使用紫色标签和地球图标区分
- History supports web entries with purple badge and globe icon
- 遮挡暂停支持网页中的视频和音频元素
- Occlusion-based pause/resume works with video and audio elements in web pages
- 网页壁纸现在显示完整的音量、静音、缩放控件，与本地视频一致
- Web wallpaper now shows full volume, mute, and stretch controls, consistent with local video
- 网页壁纸音量和缩放设置支持持久化，重启后自动恢复
- Web wallpaper volume and stretch settings are persisted and restored after restart

#### 浏览模式 Browse Mode

- 新增浏览模式：可直接与网页壁纸交互（点击链接、滚动、输入等）
- Add browse mode: interact directly with web wallpaper (click links, scroll, type, etc.)
- 按 ESC 键或点击控制面板按钮退出浏览模式
- Press ESC or click the control panel button to exit browse mode
- 修复浏览模式无法交互的问题：进入浏览模式时窗口提升至 normal 层级以接收鼠标/键盘事件，退出时恢复桌面层级
- Fix browse mode interaction: elevate window to normal level for mouse/keyboard input on enter, restore desktop level on exit
- 进入浏览模式时窗口置于其他窗口之下，不再遮挡已打开的应用
- Browse mode window now stays behind other windows, no longer covering open apps
- 进入浏览模式时显示 "已进入浏览模式" 提示，3 秒后自动消失
- Show "Entering Browse Mode" toast for 3 seconds on activation

#### 修复 Bug Fixes

- 移除网页壁纸的拉伸功能（本地视频/图片拉伸不受影响）
- Remove stretch feature for web wallpaper (local video/image stretch is unaffected)
- 修复控制面板滑块输入框透明的问题
- Fix transparent slider input field in control panel
- 修复部分网站提示浏览器版本过低的问题（设置现代 Chrome User-Agent）
- Fix websites reporting outdated browser (set modern Chrome User-Agent)
- 修复网页壁纸滚动条透明的问题，添加可见的滚动条轨道背景
- Fix transparent scrollbar in web wallpaper by adding visible scrollbar track
- 修复切换网页/视频壁纸时音量设置未正确应用的问题
- Fix volume settings not applied when switching between web and video wallpaper

### Version 4.1 (2026-03-02)

#### 屏保 Screensaver

- 屏保时钟改为 Liquid Glass 风格：文字本身即毛玻璃，可透视背后视频内容，贴近 macOS Tahoe 锁屏设计
- Screensaver clock now uses Liquid Glass style with frosted-glass text showing video behind, matching macOS Tahoe lock screen
- 无视频时屏保显示黑屏+时钟，不再依赖媒体内容作为启动前置条件
- Screensaver now works without video: shows black background with white clock on screens without wallpaper
- 提升时钟可读性：增强文字不透明度和阴影层，确保在亮色视频背景下清晰可见
- Improve clock readability: increase text opacity and strengthen shadows for visibility on bright backgrounds
- 改进日期格式为区域感知模板，自动适配不同语言
- Use locale-aware date format template for proper internationalization

#### 壁纸历史记录 Wallpaper History

- 新增壁纸历史记录功能，自动记录每次壁纸选择并支持按屏幕查看
- Add wallpaper history feature with per-screen viewing and automatic logging
- 新增历史记录界面，支持缩略图预览、双击快速应用壁纸
- Add history UI with thumbnail previews and double-click to reapply wallpaper
- 新增视频和图片缩略图自动生成器
- Add automatic thumbnail generator for videos and images

#### 书签与权限 Bookmarks & Permissions

- 全面修复沙盒环境下安全作用域书签的创建、解析和访问，修复视频/图片恢复时的权限错误 (Code 257)
- Comprehensive fix for security-scoped bookmark creation, resolution, and access under sandbox, fixing permission errors (Code 257)
- 新增 ensureFileAccess 机制与 per-URL 书签存储，历史视频不再因屏幕书签被覆盖而丢失权限
- Add ensureFileAccess mechanism and per-URL bookmark storage so history videos retain sandbox access
- 检测到过期书签时自动刷新，防止书签逐渐失效
- Automatically refresh stale bookmarks to prevent gradual degradation

#### 播放模式 Playback Modes

- 修复省电/省电+模式的遮挡检测，修复两种省电模式完全无效的问题
- Fix powerSave/powerSavePlus occlusion detection — both modes were previously non-functional
- 自动模式新增低电量模式检测：正常电量→省电模式，低电量→省电+模式
- Add Low Power Mode detection to automatic mode: normal power → PowerSave, low power → PowerSave+

#### 性能与稳定性 Performance & Stability

- 降低 CPU 占用：移除恢复播放时多余的精确帧 seek，仅在播放状态真正变化时发送通知
- Reduce CPU usage: remove unnecessary precise-frame seek on resume, only post notifications when pause state changes
- 修复切换视频后仍播放旧视频、启动时主窗口打开两次、日志并发写入丢失等问题
- Fix video not switching after selection, main window opening twice at launch, and concurrent log write losses
- 消除 VKCImageAnalyzerRequest 报错（macOS 14+）
- Fix VKCImageAnalyzerRequest errors on macOS 14+

#### 窗口管理与代码质量 Window Management & Code Quality

- 实现窗口重新分配逻辑，修复唤醒/屏幕变更后窗口停留在错误显示器的问题
- Implement window reassignment so windows return to correct displays after wake/screen changes
- 清除壁纸时同时移除回退数据，防止壁纸意外恢复
- Purge fallback data when clearing wallpaper to prevent unintended restoration
- 重构 AppDelegate 中的重复代码，提取可复用工具方法
- Refactor duplicated code in AppDelegate into reusable utilities
- 构建时自动将 Build Number 更新为当前日期
- Automatically update build number to current date on every build

### Version 4.0 hot-fix 2 (2025-10-03)

- 修复显示器唤醒后未重新评估遮挡状态导致视频在被遮挡时仍继续播放的问题
- Ensure playback modes re-evaluate occlusion after a display wakes so covered videos stay paused

### Version 4.0 hot-fix 1 (2025-09-17)

- 修复播放设置中切换全局静音会造成死循环的问题
- 恢复原有的屏保窗口与轮询逻辑，继续在检测到全屏窗口时暂停轮询
- 保留屏保日期标签，改为在创建时立即填充文本避免首秒空白
- 当没有视频播放时，禁用菜单栏的“启动屏幕保护程序”按钮并阻止快捷键误触发
- 提升屏保日期/时间标签的显示层级并增加半透明背景，保证在播放视频时清晰可见
- Fix the infinite loop triggered by toggling global mute from the playback settings card
- Restore the original screensaver window flow and periodic checks, still pausing when a full-screen app is detected
- Keep the screensaver date label but populate its text immediately so it appears as soon as the overlay shows
- Raise the screensaver date/time overlays above the player and add translucent backgrounds so they remain legible over video playback

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
