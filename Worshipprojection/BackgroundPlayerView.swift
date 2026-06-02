import SwiftUI
import AVKit
import UIKit
internal import Combine

struct BackgroundPlayerView: View {
    let item: BackgroundItem?
    let replayToken: Int

    @State private var layerABackground: BackgroundItem?
    @State private var layerBBackground: BackgroundItem?
    @State private var layerAOpacity = 0.0
    @State private var layerBOpacity = 0.0
    @State private var activeLayer: BackgroundLayer = .a
    @State private var transitionToken = 0

    private enum BackgroundLayer {
        case a
        case b
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let layerABackground {
                BackgroundMediaView(item: layerABackground, replayToken: replayToken)
                    .opacity(layerAOpacity)
                    .zIndex(0)
            }

            if let layerBBackground {
                BackgroundMediaView(item: layerBBackground, replayToken: replayToken)
                    .opacity(layerBOpacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            layerABackground = item
            layerAOpacity = item == nil ? 0.0 : 1.0
            layerBBackground = nil
            layerBOpacity = 0.0
            activeLayer = .a
            transitionToken = 0
        }
        .onChange(of: item) { _, newBackground in
            crossfade(to: newBackground)
        }
    }

    private func crossfade(to newBackground: BackgroundItem?) {
        let currentBackground = activeLayer == .a ? layerABackground : layerBBackground
        guard currentBackground?.id != newBackground?.id else { return }

        transitionToken += 1
        let currentToken = transitionToken
        let targetLayer: BackgroundLayer = activeLayer == .a ? .b : .a

        switch targetLayer {
        case .a:
            layerABackground = newBackground
            layerAOpacity = 0.0
        case .b:
            layerBBackground = newBackground
            layerBOpacity = 0.0
        }

        withAnimation(.easeInOut(duration: 0.9)) {
            switch targetLayer {
            case .a:
                layerAOpacity = newBackground == nil ? 0.0 : 1.0
                layerBOpacity = 0.0
            case .b:
                layerBOpacity = newBackground == nil ? 0.0 : 1.0
                layerAOpacity = 0.0
            }
        }

        activeLayer = targetLayer

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            guard currentToken == transitionToken else { return }
            switch targetLayer {
            case .a:
                layerBBackground = nil
            case .b:
                layerABackground = nil
            }
        }
    }
}

private struct BackgroundMediaView: View {
    let item: BackgroundItem
    let replayToken: Int

    @StateObject private var playerManager = BackgroundPlayerManager()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底色：防止切換瞬間出現白色閃爍
                Color.black.ignoresSafeArea()
                
                if item.isVideo {
                        // 💡 關鍵修正：使用自定義的純淨播放器，取代會導致 AirPlay 閃退的 VideoPlayer
                        CustomVideoPlayerView(player: playerManager.player)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .onAppear {
                                playerManager.setupPlayer(url: item.fileURL)
                            }
                            .onChange(of: item) { _, newItem in
                                playerManager.setupPlayer(url: newItem.fileURL)
                            }
                            .onChange(of: replayToken) { _, _ in
                                playerManager.restartCurrentVideo()
                            }
                            .onDisappear {
                                playerManager.stop()
                            }
                } else {
                        // 圖片顯示層
                        if let data = try? Data(contentsOf: item.fileURL),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                        } else {
                            Text("圖片載入失敗")
                                .foregroundColor(.gray)
                        }
                }
            }
        }
    }
}

// MARK: - 自定義無 UI 影片播放層 (UIViewRepresentable)
// 這是解決 AirPlay 閃退的核心：剝離所有蘋果系統預設的影片控制介面
struct CustomVideoPlayerView: UIViewRepresentable {
    var player: AVPlayer?
    
    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let playerUIView = uiView as? PlayerUIView else { return }
        playerUIView.playerLayer.player = player
    }
}

class PlayerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

// MARK: - 播放管理器 (確保影片穩定性與循環播放)
class BackgroundPlayerManager: ObservableObject {
    @Published var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentURL: URL?
    private var recoveryAttempts = 0
    private var healthTimer: AnyCancellable?
    private var itemObservers: [NSObjectProtocol] = []
    private var standbyPlayer: AVQueuePlayer?
    private var standbyLooper: AVPlayerLooper?
    private var standbyObservers: [NSObjectProtocol] = []
    private var standbyStatusObserver: AnyCancellable?
    private var hardReplayToken = 0

    func setupPlayer(url: URL, forceRestart: Bool = false) {
        // 檢查是否已經在播放同一個 URL，避免重複初始化
        if !forceRestart,
           let currentItem = player?.items().first,
           (currentItem.asset as? AVURLAsset)?.url == url {
            recoveryAttempts = 0
            player?.play()
            startHealthCheck()
            return
        }

        cleanupPlayer()
        currentURL = url
        recoveryAttempts = 0

        // 建立循環播放器
        let playerItem = AVPlayerItem(url: url)
        let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
        newQueuePlayer.isMuted = true // 背景通常不需要聲音
        newQueuePlayer.actionAtItemEnd = .none
        
        // 使用 AVPlayerLooper 實現無縫循環
        playerLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)
        
        self.player = newQueuePlayer
        observe(item: playerItem)
        startHealthCheck()
        newQueuePlayer.play()
    }

    func restartCurrentVideo() {
        guard let currentURL else { return }
        softReplayCurrentVideo(fallbackURL: currentURL)
    }

    func stop() {
        cleanupPlayer()
        currentURL = nil
    }

    private func recoverPlayback() {
        guard let player else { return }

        if recoveryAttempts == 0 {
            recoveryAttempts += 1
            player.play()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self,
                      let player = self.player,
                      player.rate == 0,
                      player.currentItem?.status != .unknown else { return }
                self.prepareHardReplay()
            }
        } else {
            prepareHardReplay()
        }
    }

    private func softReplayCurrentVideo(fallbackURL: URL) {
        guard let player,
              let item = player.currentItem,
              item.status == .readyToPlay else {
            prepareHardReplay(url: fallbackURL)
            return
        }

        recoveryAttempts = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                if finished {
                    player.play()
                    self.startHealthCheck()
                } else {
                    self.prepareHardReplay(url: fallbackURL)
                }
            }
        }
    }

    private func prepareHardReplay(url explicitURL: URL? = nil) {
        guard let url = explicitURL ?? currentURL else { return }

        hardReplayToken += 1
        let currentToken = hardReplayToken
        cleanupStandbyPlayer()

        let playerItem = AVPlayerItem(url: url)
        let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
        newQueuePlayer.isMuted = true
        newQueuePlayer.actionAtItemEnd = .none
        let newLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)

        standbyPlayer = newQueuePlayer
        standbyLooper = newLooper
        observeStandby(item: playerItem, token: currentToken)
        newQueuePlayer.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  self.hardReplayToken == currentToken,
                  self.standbyPlayer === newQueuePlayer,
                  playerItem.status == .readyToPlay else { return }
            self.promoteStandbyPlayer(url: url)
        }
    }

    private func startHealthCheck() {
        healthTimer?.cancel()
        healthTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPlaybackHealth()
            }
    }

    private func checkPlaybackHealth() {
        guard let player,
              let item = player.currentItem else { return }

        if item.status == .failed {
            prepareHardReplay()
            return
        }

        guard item.status == .readyToPlay else { return }

        if player.timeControlStatus == .playing {
            recoveryAttempts = 0
            return
        }

        if player.rate == 0 {
            recoverPlayback()
        }
    }

    private func observe(item: AVPlayerItem) {
        removeItemObservers()

        let center = NotificationCenter.default
        let stalled = center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPlayback()
        }

        let failed = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.prepareHardReplay()
        }

        itemObservers = [stalled, failed]
    }

    private func observeStandby(item: AVPlayerItem, token: Int) {
        removeStandbyObservers()

        let center = NotificationCenter.default
        let failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupStandbyPlayer()
        }

        standbyObservers = [failedObserver]
        standbyStatusObserver = item.publisher(for: \.status, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.promoteStandbyIfReady(token: token)
                } else if status == .failed {
                    self?.cleanupStandbyPlayer()
                }
            }

        DispatchQueue.main.async { [weak self] in
            self?.promoteStandbyIfReady(token: token)
        }
    }

    private func promoteStandbyIfReady(token: Int) {
        guard hardReplayToken == token,
              let standbyPlayer,
              let standbyItem = standbyPlayer.currentItem,
              standbyItem.status == .readyToPlay else { return }
        promoteStandbyPlayer(url: (standbyItem.asset as? AVURLAsset)?.url ?? currentURL)
    }

    private func promoteStandbyPlayer(url: URL?) {
        guard let standbyPlayer,
              let standbyLooper else { return }

        let oldPlayer = player
        let oldLooper = playerLooper
        removeItemObservers()

        playerLooper = standbyLooper
        player = standbyPlayer
        currentURL = url ?? currentURL
        recoveryAttempts = 0

        if let item = standbyPlayer.currentItem {
            observe(item: item)
        }
        startHealthCheck()

        self.standbyPlayer = nil
        self.standbyLooper = nil
        removeStandbyObservers()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            oldPlayer?.pause()
            _ = oldLooper
        }
    }

    private func removeItemObservers() {
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
    }

    private func removeStandbyObservers() {
        for observer in standbyObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        standbyObservers.removeAll()
        standbyStatusObserver?.cancel()
        standbyStatusObserver = nil
    }

    private func cleanupStandbyPlayer() {
        removeStandbyObservers()
        standbyPlayer?.pause()
        standbyPlayer = nil
        standbyLooper = nil
    }

    private func cleanupPlayer() {
        healthTimer?.cancel()
        healthTimer = nil
        removeItemObservers()
        cleanupStandbyPlayer()
        player?.pause()
        player = nil
        playerLooper = nil
    }

    deinit {
        stop()
    }
}
