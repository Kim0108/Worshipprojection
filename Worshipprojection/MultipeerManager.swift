import Foundation
import MultipeerConnectivity
import UIKit
internal import Combine

class MultipeerManager: NSObject, ObservableObject {
    // ⚠️ 務必確保你的 Info.plist 裡面的 Bonjour 服務名稱是 _worship-sync._tcp 和 _worship-sync._udp
    private let serviceType = "worship-sync"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    
    // 為了雙向連線，我們同時宣告廣播與搜尋器
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    @Published var session: MCSession!
    @Published var isActive = false // 💡 統整成一個開關狀態，給 UI 按鈕使用
    @Published var connectedPeers: [MCPeerID] = []
    @Published var connectionRole: ConnectionRole = .idle

    enum ConnectionRole {
        case idle
        case broadcaster
        case receiver
        case bidirectional
    }
    
    // 收到資料時的回呼函式 (讓 LyricManager 接收處理防回音鎖)
    var onReceivedData: ((Data) -> Void)?

    override init() {
        super.init()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    // MARK: - 連線控制 (雙向連線)
    
    // 💡 取代原本的 startHosting 與 startBrowsing
    func startConnection(role: ConnectionRole = .bidirectional) {
        stopAll()
        
        isActive = true // 更新按鈕為開啟狀態
        connectionRole = role
        
        if role == .broadcaster || role == .bidirectional {
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: ["role": "broadcaster"], serviceType: serviceType)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
        }
        
        if role == .receiver || role == .bidirectional {
            browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
        }
        
        print("🔄 連線啟動：\(role)")
    }
    
    // 停止連線
    func stopAll() {
        isActive = false // 更新按鈕為關閉狀態
        
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        
        browser?.stopBrowsingForPeers()
        browser = nil
        
        session.disconnect()
        connectionRole = .idle
        
        DispatchQueue.main.async {
            self.connectedPeers.removeAll()
        }
        print("🛑 已停止所有連線服務")
    }

    // 發送歌詞給所有連線的設備
    func send(lyric: String) {
        guard !session.connectedPeers.isEmpty else { return }
        if let data = lyric.data(using: .utf8) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }

    func send(state: LiveSyncState) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate (處理資料收發)
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 將收到的資料傳出去，交給 LyricManager 處理 (避免畫面與網路無限迴圈)
        DispatchQueue.main.async {
            self.onReceivedData?(data)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser & Browser Delegate (處理自動配對)
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    // 收到連線請求：無條件自動接受
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("🤝 收到來自 \(peerID.displayName) 的連線請求，已自動允許。")
        invitationHandler(true, session)
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    // 找到目標：自動發出連線邀請
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("✨ 找到目標連線: \(peerID.displayName)，正在送出自動邀請...")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
