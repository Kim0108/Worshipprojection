import SwiftUI

struct LiveDisplayView: View {
    @ObservedObject var manager: LyricManager
    
    var body: some View {
        ZStack {
            // 1. 最底層黑布：防止轉場時透出白邊
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 2. 底層：舊背景 (當前正在淡出的對象)
            if let oldBg = manager.previousBackground {
                BackgroundPlayerView(item: oldBg)
                    .id(oldBg.id.uuidString + "_old") // 加上 _old 確保 ID 唯一
//                    .transition(.opacity) 嘗試調整一下淡入淡出
                    .transition(.opacity.animation(.easeInOut(duration: 1.5)))
                    .zIndex(0) // 確保舊背景乖乖待在下層
            }
            
            // 3. 中層：新背景 (正在淡入的對象)
            if let currentBg = manager.selectedBackground {
                BackgroundPlayerView(item: currentBg)
                    .id(currentBg.id.uuidString + "_new") // 確保 SwiftUI 視為全新視圖來播放
                //                    .transition(.opacity) 嘗試調整一下淡入淡出
                    .transition(.opacity.animation(.easeInOut(duration: 1.5)))
                    .zIndex(1) // 確保新背景疊加在上層淡入
            }
            
            // 4.1 修改後的頂層歌詞內容
            GeometryReader { geo in
                VStack(alignment: .center) { // 修正 1：明確指定垂直容器內部水平置中
                    //Spacer() //這個會讓有東西卡住！
                    
                    Text(manager.activeLyricContent)
                        .id(manager.activeLyricContent)
                        .font(.system(size: geo.size.height * (manager.activeStyle.fontSize / 1000), weight: .bold))
                        .foregroundColor(manager.activeStyle.textColor.asColor)
                        .multilineTextAlignment(.center) // 這是文字「內部的多行對齊」
                    //下面這行新增的！0423
                        .lineSpacing(geo.size.height * (manager.activeStyle.lineSpacing / 1000))
                        .padding(.horizontal, geo.size.width * 0.05) //
                        //.padding(.bottom, geo.size.height * 0.1)
                        .shadow(color: .black.opacity(0.8), radius: manager.activeStyle.shadowRadius, x: 2, y: 2)
                        .transition(.opacity)
                        // 修正 2：強迫 Text 填滿整個水平寬度，這樣 multilineTextAlignment 才會在寬空間中生效
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                // 修正 3：確保整個 VStack 撐滿 GeometryReader 的所有空間
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .zIndex(2)

        }
        .clipped() // 確保內容不會溢出邊框
    }
}
