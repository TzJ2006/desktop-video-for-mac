import ScreenSaver
import AVFoundation
import UniformTypeIdentifiers

class DesktopVideoSaverView: ScreenSaverView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var imageView: NSImageView?
    
    // 如果你想在跑屏保时实时监控文件变动，可以在这里保存一个文件监视器
    private var fileMonitor: DispatchSourceFileSystemObject?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupFileMonitor()   // 可选：监视文件夹变动
        loadAndPlayMedia()   // 启动时读取并播放
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupFileMonitor()
        loadAndPlayMedia()
    }
    
    deinit {
        // 释放监视器
        fileMonitor?.cancel()
    }

    // MARK: - 1. 构造“共享目录”路径
    private func getSharedSaverDirectory() -> URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("❌ [Saver] 无法定位到 Application Support")
            return nil
        }
        let shared = appSupport.appendingPathComponent("com.TzJ.DesktopVideo", isDirectory: true)
        return shared
    }

    // MARK: - 2. 读取目录并播放
    private func loadAndPlayMedia() {
        guard let sharedDir = getSharedSaverDirectory() else { return }
        let fm = FileManager.default

        // 列出目录下所有文件
        var contents: [URL] = []
        do {
            contents = try fm.contentsOfDirectory(at: sharedDir,
                                                  includingPropertiesForKeys: [.contentTypeKey],
                                                  options: [])
        } catch {
            NSLog("❌ [Saver] 读取共享目录失败: \(error)")
            return
        }
        NSLog("▶️ [Saver] 共享目录下文件: \(contents.map { $0.lastPathComponent })")
        
        // 找一个能播放的视频或图片
        guard let mediaURL = contents.first(where: { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                return false
            }
            return type.conforms(to: .movie) || type.conforms(to: .image)
        }) else {
            NSLog("❌ [Saver] 没有找到可播放的媒体文件")
            return
        }
        NSLog("▶️ [Saver] 找到媒体：\(mediaURL.lastPathComponent)")
        
        // 根据扩展名播放视频或显示图片
        let ext = mediaURL.pathExtension.lowercased()
        if ext == "mov" || ext == "mp4" {
            playVideo(from: mediaURL)
        } else {
            showImage(from: mediaURL)
        }
    }

    // MARK: 3. 播放视频
    private func playVideo(from url: URL) {
        // 如果已经在播了，就先把旧播放器 remove
        playerLayer?.removeFromSuperlayer()
        player?.pause()

        player = AVPlayer(url: url)
        player?.actionAtItemEnd = .none

        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        
        // 挂到 view 上
        self.layer = CALayer()
        if let pl = playerLayer {
            self.layer?.addSublayer(pl)
        }
        self.wantsLayer = true
        
        // 循环通知
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(loopVideo),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: player?.currentItem)
        
        // 视图还没 add 到屏幕上，这里只准备，不播放到界面
    }

    // MARK: 4. 显示图片
    private func showImage(from url: URL) {
        playerLayer?.removeFromSuperlayer()
        player?.pause()
        player = nil

        imageView?.removeFromSuperview()
        guard let image = NSImage(contentsOf: url) else {
            NSLog("❌ [Saver] 加载图片失败")
            return
        }

        imageView = NSImageView(frame: self.bounds)
        imageView?.image = image
        imageView?.imageScaling = .scaleAxesIndependently
        imageView?.autoresizingMask = [.width, .height]
        self.addSubview(imageView!)
    }

    // MARK: 5. startAnimation / animateOneFrame 确保 Layer 覆盖全屏
    override func startAnimation() {
        super.startAnimation()
        if let pl = playerLayer {
            pl.frame = self.bounds
        }
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        if let pl = playerLayer {
            pl.frame = self.bounds
        }
    }

    @objc private func loopVideo() {
        player?.seek(to: .zero)
        player?.play()
    }

    // MARK: 6. 可选：文件夹监视，让正在运行的屏保及时更新
    private func setupFileMonitor() {
        guard let sharedDir = getSharedSaverDirectory() else { return }
        let path = sharedDir.path

        // 打开一个只读的文件描述符
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("❌ [Saver] 无法监视目录 \(path)")
            return
        }

        // 创建一个文件系统事件源，监听目录内容变化（写入或删除）
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: .write,
                                                               queue: DispatchQueue.main)
        source.setEventHandler { [weak self] in
            // 当目录里有新文件或文件被修改时，重新 load 并播放
            NSLog("▶️ [Saver] 共享目录内容发生变化，重新加载媒体")
            self?.loadAndPlayMedia()
            // 如果此时正在播放视频，新的视频会被切换到新 AVPlayer 上
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitor = source
    }
}
