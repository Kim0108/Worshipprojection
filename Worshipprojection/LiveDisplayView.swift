import SwiftUI
import UIKit

struct LiveDisplayView: View {
    @ObservedObject var manager: LyricManager
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
            // 1. 最底層黑布：防止轉場時透出白邊
            Color.black.edgesIgnoringSafeArea(.all)

            if manager.projectionMode == .slides {
                slideDisplay
            } else {
                lyricDisplay
            }
        }
        .clipped() // 確保內容不會溢出邊框
        .onAppear {
            layerABackground = manager.selectedBackground
            layerAOpacity = manager.selectedBackground == nil ? 0.0 : 1.0
            layerBBackground = nil
            layerBOpacity = 0.0
            activeLayer = .a
            transitionToken = 0
        }
        .onChange(of: manager.selectedBackground) { _, newBackground in
            crossfade(to: newBackground)
        }
    }

    @ViewBuilder
    private var slideDisplay: some View {
        if let slide = manager.activeSlide,
           let image = UIImage(contentsOfFile: slide.fileURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        }
    }

    private var lyricDisplay: some View {
        ZStack {
            Color.clear
            
            if let layerABackground {
                BackgroundPlayerView(item: layerABackground)
                    .opacity(layerAOpacity)
                    .zIndex(0)
            }

            if let layerBBackground {
                BackgroundPlayerView(item: layerBBackground)
                    .opacity(layerBOpacity)
                    .zIndex(1)
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
                        .padding(.horizontal, geo.size.width * manager.activeStyle.horizontalPaddingRatio) //
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
