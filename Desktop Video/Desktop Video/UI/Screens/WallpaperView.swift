import SwiftUI
import AppKit

/// 「墙纸」分区：仿 macOS「系统设置 > 墙纸」面板。
/// 顶部为标题与显示器选择器；中部为当前壁纸预览 + 控件检查器；
/// 底部为按内容类型分类的壁纸画廊（数据来自壁纸库，与历史记录分离）。
struct WallpaperView: View {
    @StateObject private var screenObserver = ScreenObserver()
    @State private var menuBarOnly = UserDefaults.standard.bool(forKey: "isMenuBarOnly")
    // 记住上次选择的屏幕，使用 BookmarkStore 持久化
    @State private var selectedScreenID: String = {
        BookmarkStore.get(prefix: "lastScreen", id: 0) ?? (NSScreen.main?.dv_displayUUID ?? "")
    }()
    // 当前选中屏幕正在显示的壁纸 URL，用于在画廊中高亮选中项
    @State private var currentURLString: String?

    private var resolvedScreen: NSScreen? {
        screenObserver.screens.first(where: { $0.dv_displayUUID == selectedScreenID })
            ?? screenObserver.screens.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(LocalizedStringKey(L("Wallpaper")))
                .font(.system(size: 22, weight: .bold))

            // 多显示器时显示显示器选择器
            if screenObserver.screens.count > 1 {
                Picker(LocalizedStringKey(L("Screen")), selection: $selectedScreenID) {
                    ForEach(screenObserver.screens, id: \.dv_displayUUID) { screen in
                        Text(screen.dv_localizedName).tag(screen.dv_displayUUID)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .leading)
            }

            if let screen = resolvedScreen {
                // 预览 + 控件
                SingleScreenView(screen: screen, isMultiScreen: screenObserver.screens.count > 1, menuBarOnly: $menuBarOnly)

                Divider().padding(.vertical, 8)

                // 壁纸画廊
                WallpaperGallery(screen: screen, currentURLString: currentURLString)
            } else {
                Text(LocalizedStringKey(L("No display detected")))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // 若上次保存的屏幕已断开，重选到当前有效屏幕，使选择器有正确选中项
            if !screenObserver.screens.contains(where: { $0.dv_displayUUID == selectedScreenID }) {
                selectedScreenID = resolvedScreen?.dv_displayUUID ?? ""
            }
            refreshCurrentURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WallpaperContentDidChange"))) { _ in
            refreshCurrentURL()
        }
        .onChange(of: selectedScreenID) { newID in
            BookmarkStore.set(newID, prefix: "lastScreen", id: 0)
            refreshCurrentURL()
            if let screen = screenObserver.screens.first(where: { $0.dv_displayUUID == newID }) {
                dlog("selected screen changed to \(screen.dv_localizedName)")
            } else {
                dlog("selected screen changed to \(newID)")
            }
        }
        .onChange(of: screenObserver.screens) { screens in
            if !screens.contains(where: { $0.dv_displayUUID == selectedScreenID }) {
                selectedScreenID = screens.first?.dv_displayUUID ?? ""
            }
        }
    }

    private func refreshCurrentURL() {
        let sid = resolvedScreen?.dv_displayUUID ?? selectedScreenID
        currentURLString = SharedWallpaperWindowManager.shared.screenContent[sid]?.url.absoluteString
    }
}
