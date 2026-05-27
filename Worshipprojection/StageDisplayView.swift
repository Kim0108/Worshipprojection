import SwiftUI
import UIKit

struct StageDisplayView: View {
    @ObservedObject var multipeerManager: MultipeerManager
    @EnvironmentObject var lyricManager: LyricManager // 💡 新增：引入歌詞管理器取得最新歌詞
    @Environment(\.dismiss) var dismiss
    var onExit: (() -> Void)? = nil
    
    // 💡 實戰優化：控制是否顯示「退出」與「連線狀態」按鈕，避免在舞台上穿幫、刺眼
    @State private var showControls = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // 黑底保護眼睛不刺眼
            
            GeometryReader { geo in
                Text(lyricManager.activeLyricContent.isEmpty ? "等待主控端發送歌詞..." : lyricManager.activeLyricContent)
                    .font(.system(size: geo.size.height * (lyricManager.activeStyle.fontSize / 1000), weight: .bold))
                    .foregroundColor(lyricManager.activeLyricContent.isEmpty ? .gray : lyricManager.activeStyle.textColor.asColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(geo.size.height * (lyricManager.activeStyle.lineSpacing / 1000))
                    .padding(.horizontal, geo.size.width * lyricManager.activeStyle.horizontalPaddingRatio)
                    .shadow(color: .black.opacity(0.5), radius: lyricManager.activeStyle.shadowRadius, x: 1, y: 1)
                    .minimumScaleFactor(0.3)
                    .id(lyricManager.activeLyricContent)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            
            // 退出與狀態列 (放入 if 判斷式，可以隨時隱藏)
            if showControls {
                VStack {
                    HStack {
                        Button(action: {
                            multipeerManager.stopAll()
                            onExit?()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .padding()
                        
                        Spacer()
                        
                        // 顯示連線狀態小燈與文字
                        HStack(spacing: 8) {
                            Circle()
                                .fill(multipeerManager.connectedPeers.isEmpty ? Color.red : Color.green)
                                .frame(width: 12, height: 12)
                            
                            Text(multipeerManager.connectedPeers.isEmpty ? "未連線" : "已連線")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity) // 讓按鈕淡入淡出
            }
        }
        // 💡 貼心功能：點擊螢幕任意地方，可以切換顯示/隱藏控制按鈕
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
        .onAppear {
            // 💡 修改：改為呼叫全新改版的「雙向自動連線」
            if multipeerManager.connectionRole != .receiver {
                multipeerManager.startConnection(role: .receiver)
            }
            
            // 💡 自動化體驗：進入提詞機畫面 3 秒後，自動隱藏控制鈕，保持舞台畫面純淨
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
}
