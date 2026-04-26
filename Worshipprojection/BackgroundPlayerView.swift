import SwiftUI
import AVKit
internal import Combine

struct BackgroundPlayerView: View {
    let item: BackgroundItem?
    
    // 使用 StateObject 確保播放器在 View 更新時依然存活
    @StateObject private var playerManager = BackgroundPlayerManager()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底色：防止切換瞬間出現白色閃爍
                Color.black.ignoresSafeArea()
                
                if let bgItem = item {
                    if bgItem.isVideo {
                        // 💡 關鍵修正：使用自定義的純淨播放器，取代會導致 AirPlay 閃退的 VideoPlayer
                        CustomVideoPlayerView(player: playerManager.player)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .onAppear {
                                playerManager.setupPlayer(url: bgItem.fileURL)
                            }
                            .onChange(of: bgItem) { newItem in
                                playerManager.setupPlayer(url: newItem.fileURL)
                            }
                    } else {
                        // 圖片顯示層
                        if let data = try? Data(contentsOf: bgItem.fileURL),
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

    func setupPlayer(url: URL) {
        // 檢查是否已經在播放同一個 URL，避免重複初始化
        if let currentItem = player?.items().first,
           (currentItem.asset as? AVURLAsset)?.url == url {
            player?.play()
            return
        }

        // 清理舊的播放器
        player?.pause()
        playerLooper = nil

        // 建立循環播放器
        let playerItem = AVPlayerItem(url: url)
        let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
        newQueuePlayer.isMuted = true // 背景通常不需要聲音
        newQueuePlayer.actionAtItemEnd = .none
        
        // 使用 AVPlayerLooper 實現無縫循環
        playerLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)
        
        self.player = newQueuePlayer
        newQueuePlayer.play()
    }
}
//舊代碼
//import SwiftUI
//import AVKit
//internal import Combine
//
//struct BackgroundPlayerView: View {
//    // 傳入目前的背景項目（由 LyricManager.selectedBackground 提供）
//    let item: BackgroundItem?
//    
//    // 使用 StateObject 確保播放器在 View 更新時依然存活
//    @StateObject private var playerManager = BackgroundPlayerManager()
//
//    var body: some View {
//        GeometryReader { geo in
//            ZStack {
//                // 底色：防止切換瞬間出現白色閃爍
//                Color.black.ignoresSafeArea()
//                
//                if let bgItem = item {
//                    if bgItem.isVideo {
//                        // 影片播放層
//                        VideoPlayer(player: playerManager.player)
//                            .aspectRatio(contentMode: .fill)
//                            .frame(width: geo.size.width, height: geo.size.height)
//                            .onAppear {
//                                playerManager.setupPlayer(url: bgItem.fileURL)
//                            }
//                            // 當選取的背景對象改變時，重新載入影片
//                            .onChange(of: bgItem) { newItem in
//                                playerManager.setupPlayer(url: newItem.fileURL)
//                            }
//                    } else {
//                        // 圖片顯示層
//                        if let data = try? Data(contentsOf: bgItem.fileURL),
//                           let uiImage = UIImage(data: data) {
//                            Image(uiImage: uiImage)
//                                .resizable()
//                                .aspectRatio(contentMode: .fill)
//                                .frame(width: geo.size.width, height: geo.size.height)
//                                .clipped()
//                                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
//                        } else {
//                            Text("圖片載入失敗")
//                                .foregroundColor(.gray)
//                        }
//                    }
//                } else {
//                    // 無背景狀態
//                    Text("無背景媒體")
//                        .foregroundColor(.gray)
//                }
//            }
//        }
//    }
//}
//
//// MARK: - 播放管理器 (確保影片穩定性與循環播放)
//
//class BackgroundPlayerManager: ObservableObject {
//    @Published var player: AVPlayer?
//    private var playerLooper: AVPlayerLooper?
//    private var queuePlayer: AVQueuePlayer?
//
//    func setupPlayer(url: URL) {
//        // 檢查是否已經在播放同一個 URL，避免重複初始化
//        if let currentItem = queuePlayer?.items().first,
//           (currentItem.asset as? AVURLAsset)?.url == url {
//            queuePlayer?.play()
//            return
//        }
//
//        // 清理舊的播放器
//        queuePlayer?.pause()
//        queuePlayer = nil
//        playerLooper = nil
//
//        // 建立循環播放器
//        let playerItem = AVPlayerItem(url: url)
//        let newQueuePlayer = AVQueuePlayer(playerItem: playerItem)
//        newQueuePlayer.isMuted = true // 背景通常不需要聲音
//        
//        // 使用 AVPlayerLooper 實現無縫循環
//        playerLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: playerItem)
//        
//        self.queuePlayer = newQueuePlayer
//        self.player = newQueuePlayer
//        
//        newQueuePlayer.play()
//    }
//}
