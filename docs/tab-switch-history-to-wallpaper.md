# 切换标签页时缩略图被全量重新生成的问题

> 场景：在主窗口里切换侧边栏页面（如「播放」/「设置」→「墙纸」，或「历史」→「墙纸」）时，
> 墙纸画廊里所有视频/图片缩略图会被重新生成，耗资源、耗时间。
> 核心诉求：能否用缓存（或其它手段）跳过这个重复生成过程。

## 一、切标签时实际发生了什么

切到「墙纸」页时，SwiftUI 销毁 `HistoryView`、重建 `WallpaperView`（大预览 + 画廊）：

1. **整个页面视图树被销毁重建**——SwiftUI 侧边栏导航离开页面就拆掉视图，回来时
   `WallpaperPreview` 和每个 `WallpaperTile` 的 `.task` 全部重新触发。
2. **每屏控件重新同步**——`refreshStateFromManager()` → `syncInitialState()` 从
   `SharedWallpaperWindowManager` 拉回当前屏状态（正常重连，非 bug）。
3. **画廊为每个条目重新请求缩略图**——`WallpaperTile.loadThumbnail()` →
   `ThumbnailGenerator.cached(...)`。命中缓存则瞬时返回；未命中则重新解码视频帧 / 图片。
4. **大预览重新请求缩略图**——`WallpaperPreview.reload()` 同理。

## 二、已有缓存为什么没能跳过重复生成

代码里已有一层内存缓存 `ThumbnailGenerator.cache`（`NSCache`，`countLimit=200`，
`totalCostLimit≈96MB`），命中即瞬时返回、不解码。但有几个漏点导致仍会大面积重算：

1. **三个界面请求的尺寸不同 → 缓存键不同 → 互不命中（最大元凶）**
   - 历史页 `128×96`（`HistoryItemRow.swift:88`）
   - 画廊磁贴 `264×168`（`WallpaperTile.swift:73`，132×84 ×2）
   - 大预览 `480×300`（`WallpaperPreview.swift:130`，240×150 ×2）

   `cacheKey` 把尺寸编进键里（`ThumbnailGenerator.swift:142`）。历史页解过的 `128×96`
   喂不到画廊的 `264×168`，**同一文件最多被解码 3 次**；从历史页切到墙纸等于全量重解。

2. **`NSCache` 会被系统主动驱逐**——purgeable，内存压力下（尤其装着 `NSImage`）会被提前
   清掉，且**重启 App 必然清空**。所以内存吃紧时「每次切都重做」是必然。

3. **失败结果从不缓存 → 每次切都重试**——`cached()` 取到 `nil` 直接返回、不写缓存
   （`ThumbnailGenerator.swift:125`）。不可访问的文件每次进墙纸页都重新敲 AVFoundation/ImageIO。

4. **网页大预览完全没缓存**——`WallpaperPreview` 网页分支每次重建都新建 `WKWebView`
   重载整页（`WallpaperPreview.swift:100` 的 `WebThumbnailView`），最重。

## 三、可选的修复方向（按性价比排序，尚未实施）

| 方案 | 作用 | 成本 | 状态 |
|------|------|------|------|
| **A. 一次解码到最大尺寸，显示时缩放** | 不再按 3 个尺寸分别缓存：统一生成 `480×300`，`.resizable()` 缩到磁贴/行用。直接消除跨页重解码，每文件只解一次 | 低 | ✅ 已实施（2026-06-15） |
| **B. 缩略图落盘持久化** | 沙盒 `Caches/Thumbnails` 按缓存键存 PNG，内存未命中先查磁盘。扛住 NSCache 驱逐 + 跨重启复用 | 中 | ✅ 已实施（2026-06-15） |
| **C. 缓存失败结果 + 先查可访问性** | 对不可读文件记「失败」标记，配合 `MediaAccess.isAccessible` 预检跳过解码，不再反复敲 AVFoundation/ImageIO | 低 | ✅ 已实施（2026-06-15） |
| **D. 画廊状态不随切页销毁** | 把已加载 `NSImage` 放进共享 `ObservableObject`，重建视图直接复用 | 中 | 待定 |
| **E. 网页预览截图缓存** | `WKWebView` 渲染一次后 `takeSnapshot` 存图，之后显示静态图而非重载整页 | 中 | 待定 |

**已完成 A + B + C**（均在 `ThumbnailGenerator.swift`）：
- **A**：引入 `canonicalSize=480×300`，公开入口去掉 `size` 参数、缓存键去掉尺寸维度，三个界面共用同一张缩略图。
- **B**：命中顺序改为 内存 → 磁盘 → 解码；磁盘按缓存键 SHA256 存 PNG 到沙盒 `Caches/Thumbnails`，128MB 上限按最旧优先清理，写入走后台串行队列。
- **C**：`cached()` 在缓存未命中时先 `MediaAccess.isAccessible` 预检，不可读 / 解码失败记入负缓存直接跳过；负缓存在 `WallpaperContentDidChange`（重新授权后必触发）时清空以便恢复重试。这同时修复了第四节「画廊绕过可访问性检查」导致的反复报错。

仍可后续做 D（画廊状态不随切页销毁）、E（网页预览截图缓存）。

## 四、附带发现：画廊绕过了「可访问性检查」（次要问题）

历史页与墙纸画廊取缩略图走了两条不一致的路径：

| 视图 | 调用 | 行为 |
|------|------|------|
| `HistoryItemRow`（历史页） | `ThumbnailGenerator.loadStatus()`（`HistoryItemRow.swift:85`） | 先 `MediaAccess.isAccessible`，不可读时不解码，显示 ⚠️ +「Re-authorize」 |
| `WallpaperTile`（墙纸画廊） | `ThumbnailGenerator.cached()`（`WallpaperTile.swift:69`） | 跳过可访问性检查，直接解码 → 失败才返回 `nil`，静默退回占位图标 |

后果（对应日志里 `IMG_7527.mov: ... couldn't be opened because you don't have permission`）：
画廊对不可访问文件**静默显示占位图、无重新授权提示**，且因失败不缓存而**每次切页都重试报错**。
方案 C 同时能解决这一点。

## 五、日志里那些「吓人」但无害的噪声

`FigFilePlayer err=-12860` / `VRP err=-12852`（AVFoundation 暂停/恢复 chatter，跟随
`pauseAll` 翻转）、`linkd.autoShortcut` / intents 框架错误、`os_unix.c DetachedSignatures`、
`AddInstanceForFactory: No factory registered`、`IIOScanner reached EOF` 等均为系统级噪声，
与本问题无关，可忽略。真正要管的只有缩略图解码失败（`IMG_7527.mov` 权限、`CMPhoto`/`IOSurface`
图片解码失败）。
