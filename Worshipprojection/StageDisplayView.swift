import SwiftUI

struct StageDisplayView: View {
    @ObservedObject var multipeerManager: MultipeerManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // 黑底保護眼睛不刺眼
            
            // 顯示接收到的文字
            Text(multipeerManager.receivedLyric)
                .font(.system(size: 80, weight: .bold)) // 提詞機字體固定放大
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
                .minimumScaleFactor(0.3) // 如果字太多自動縮小
                .transition(.opacity)
                .id(multipeerManager.receivedLyric)
            
            // 退出與狀態列 (隱藏在四角落，或是輕點喚出)
            VStack {
                HStack {
                    Button(action: {
                        multipeerManager.stopAll()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    Spacer()
                    
                    // 顯示連線狀態小綠點
                    Circle()
                        .fill(multipeerManager.connectedPeers.isEmpty ? Color.red : Color.green)
                        .frame(width: 15, height: 15)
                        .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            // 一進來就自動開始尋找主控台
            multipeerManager.startBrowsing()
        }
    }
}
