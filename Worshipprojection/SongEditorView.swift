import SwiftUI
import UIKit

struct SongEditorView: View {
    @ObservedObject var manager: LyricManager
    @Environment(\.dismiss) var dismiss
    
    var editingSong: Song? = nil
    
    @State private var title: String = ""
    @State private var rawText: String = ""
    
    // 保持使用 Double 適配 TextField
    @State private var fontSize: Double = 80
    @State private var lineSpacing: Double = 20
    @State private var shadowRadius: Double = 10
    @State private var transitionDuration: Double = 0.12
    @State private var verticalPosition: Double = 0.5
    @State private var horizontalPaddingRatio: Double = 0.05
    @State private var backgroundDimOpacity: Double = 0.0
    @State private var horizontalAlignment: TextHorizontalAlignment = .center
    @State private var textColor: Color = .white
    
    // ⭐️ 核心新增：即時解析第一個段落的計算屬性
    private var previewText: String {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return "預覽文字第一行\n預覽文字第二行"
        }
        
        let pattern = "\\[(.*?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return rawText
        }
        
        let nsString = rawText as NSString
        let matches = regex.matches(in: rawText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 如果完全沒有標籤，就把整段當成內容預覽
        if matches.isEmpty {
            return rawText
        }
        
        // 抓取第一個 [] 的內容
        let firstMatch = matches[0]
        let contentStart = firstMatch.range.location + firstMatch.range.length
        let contentEnd = (matches.count > 1) ? matches[1].range.location : nsString.length
        
        let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
        let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果只有打標籤 [主歌] 但還沒打歌詞，給個提示
        return content.isEmpty ? "(此段落尚未輸入歌詞)" : content
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("歌曲資訊"), footer: Text("使用 [段落名稱] 來分隔歌詞，例如：[主歌1]、[副歌]")) {
                    TextField("歌曲標題", text: $title)
                    
                    TextEditor(text: $rawText)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section("樣式設定與所見即所得預覽") {
                    // 1. 16:9 等比預覽畫布
                    GeometryReader { geo in
                        let calcFontSize = geo.size.height * (CGFloat(fontSize) / 1000.0)
                        let calcLineSpacing = geo.size.height * (CGFloat(lineSpacing) / 1000.0)
                        let paddingX = geo.size.width * CGFloat(horizontalPaddingRatio)
                        
                        VStack(alignment: .center) {
                            // ⭐️ 修正：這裡改用剛剛寫好的 previewText
                            Text(previewText)
                                .font(.system(size: calcFontSize, weight: .bold))
                                .foregroundColor(textColor)
                                .multilineTextAlignment(horizontalAlignment.textAlignment)
                                .lineSpacing(calcLineSpacing)
                                .padding(.horizontal, paddingX)
                                .shadow(color: .black.opacity(0.5), radius: shadowRadius, x: 1, y: 1)
                                .frame(maxWidth: .infinity, alignment: horizontalAlignment.frameAlignment)
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .background(Color.black.opacity(0.9))
                        .offset(y: geo.size.height * CGFloat(verticalPosition - 0.5))
                    }
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(8)
                    .padding(.vertical, 5)
                    
                    // 2. 數值輸入與滑桿 (字體大小)
                    HStack {
                        Text("字體大小")
                        Slider(value: $fontSize, in: 20...200, step: 1)
                        TextField("數值", value: $fontSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                    }
                    
                    // 3. 數值輸入與滑桿 (行距)
                    HStack {
                        Text("行距設定")
                        Slider(value: $lineSpacing, in: 0...150, step: 1)
                        TextField("數值", value: $lineSpacing, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                    }
                    
                    ColorPicker("文字顏色", selection: $textColor)

                    Picker("文字對齊", selection: $horizontalAlignment) {
                        ForEach(TextHorizontalAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("垂直位置")
                        Slider(value: $verticalPosition, in: 0.15...0.85, step: 0.01)
                        Text("\(Int(verticalPosition * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("左右留白")
                        Slider(value: $horizontalPaddingRatio, in: 0.02...0.2, step: 0.01)
                        Text("\(Int(horizontalPaddingRatio * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("陰影強度")
                        Slider(value: $shadowRadius, in: 0...30, step: 1)
                        Text("\(Int(shadowRadius))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("切換速度")
                        Slider(value: $transitionDuration, in: 0.05...0.8, step: 0.01)
                        Text("\(String(format: "%.2f", transitionDuration)) 秒")
                            .font(.caption.monospacedDigit())
                            .frame(width: 64, alignment: .trailing)
                    }

                    HStack {
                        Text("背景壓暗")
                        Slider(value: $backgroundDimOpacity, in: 0...0.75, step: 0.05)
                        Text("\(Int(backgroundDimOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .navigationTitle(editingSong == nil ? "新增歌曲" : "編輯歌詞")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveAction()
                    }
                    .disabled(title.isEmpty || rawText.isEmpty)
                }
            }
            .onAppear {
                prepareInitialData()
            }
        }
    }
    
    private func prepareInitialData() {
        if let song = editingSong {
            title = song.title
            rawText = song.rawText
            
            fontSize = Double(song.style.fontSize)
            lineSpacing = Double(song.style.lineSpacing)
            shadowRadius = Double(song.style.shadowRadius)
            transitionDuration = song.style.transitionDuration
            verticalPosition = Double(song.style.verticalPosition)
            horizontalPaddingRatio = Double(song.style.horizontalPaddingRatio)
            backgroundDimOpacity = song.style.backgroundDimOpacity
            horizontalAlignment = song.style.horizontalAlignment
            
            let data = song.style.textColor
            textColor = Color(red: data.r, green: data.g, blue: data.b)
        }
    }
    
    private func saveAction() {
        let uiColor = UIColor(textColor)
        let components: [CGFloat] = uiColor.cgColor.components ?? [1.0, 1.0, 1.0]
        
        let r = Double(components.indices.contains(0) ? components[0] : 1.0)
        let g = Double(components.indices.contains(1) ? components[1] : 1.0)
        let b = Double(components.indices.contains(2) ? components[2] : 1.0)

        let newColorData = ColorData(r: r, g: g, b: b)

        if let song = editingSong {
            var updated = manager.canonicalSong(for: song)
            updated.title = title
            updated.rawText = rawText

            updated.style.fontSize = CGFloat(fontSize)
            updated.style.lineSpacing = CGFloat(lineSpacing)
            updated.style.shadowRadius = CGFloat(shadowRadius)
            updated.style.transitionDuration = transitionDuration
            updated.style.verticalPosition = CGFloat(verticalPosition)
            updated.style.horizontalPaddingRatio = CGFloat(horizontalPaddingRatio)
            updated.style.backgroundDimOpacity = backgroundDimOpacity
            updated.style.horizontalAlignment = horizontalAlignment
            updated.style.textColor = newColorData

            manager.updateSong(updated)
        } else {
            manager.addSong(title: title,
                            text: rawText,
                            fontSize: CGFloat(fontSize),
                            lineSpacing: CGFloat(lineSpacing),
                            shadowRadius: CGFloat(shadowRadius),
                            transitionDuration: transitionDuration,
                            verticalPosition: CGFloat(verticalPosition),
                            horizontalPaddingRatio: CGFloat(horizontalPaddingRatio),
                            backgroundDimOpacity: backgroundDimOpacity,
                            horizontalAlignment: horizontalAlignment,
                            textColor: textColor)
        }
        dismiss()
    }
}
