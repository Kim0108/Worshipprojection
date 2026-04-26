import SwiftUI
internal import Combine

class ExternalDisplayManager: ObservableObject {
    // 儲存外接螢幕的視窗，防止被系統釋放
    private var additionalWindow: UIWindow?
    
    // 強持有 LyricManager，確保投影畫面能即時同步數據
    var manager: LyricManager
    
    init(manager: LyricManager) {
        self.manager = manager
        setupSceneNotifications()
        checkForExistingScenes()
    }
    
    /// 監聽螢幕連接與斷開的通知 (iOS 13+ / 16+ 推薦寫法)
    private func setupSceneNotifications() {
        // 當連接新的螢幕（AirPlay 或實體線路）
        NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene,
                  // 確保這個場景是外部顯示器，而不是 iPad 的分屏
                  scene.session.role == .windowExternalDisplayNonInteractive else { return }
            
            self?.setupExternalWindow(for: scene)
        }
        
        // 當螢幕斷開
        NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene,
                  scene.session.role == .windowExternalDisplayNonInteractive else { return }
            
            self?.additionalWindow = nil
            print("❌ 外接顯示器已斷開")
        }
    }
    
    /// 啟動時檢查是否已經插著螢幕
    private func checkForExistingScenes() {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               windowScene.session.role == .windowExternalDisplayNonInteractive {
                setupExternalWindow(for: windowScene)
            }
        }
    }
    
    /// 核心邏輯：建立外接視窗並植入 LiveDisplayView
    private func setupExternalWindow(for scene: UIWindowScene) {
        print("🚀 偵測到外接螢幕！解析度: \(scene.screen.bounds.size)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 根據外接螢幕的 Scene 建立視窗
            let window = UIWindow(windowScene: scene)
            
            // 2. 注入 LiveDisplayView 並傳入 manager
            // 這裡確保投影出去的是純淨的畫面，無視安全區域 [cite: 35]
            let view = LiveDisplayView(manager: self.manager)
                .edgesIgnoringSafeArea(.all)
            
            // 3. 使用 UIHostingController 將 SwiftUI 包裝進 UIKit 視窗 [cite: 35, 36]
            let hostingController = UIHostingController(rootView: view)
            window.rootViewController = hostingController
            
            // 4. 設定顯示
            window.isHidden = false
            self.additionalWindow = window
            print("✅ 外接視窗已成功啟動輸出")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
