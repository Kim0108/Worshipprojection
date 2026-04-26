import SwiftUI

struct SongEditorView: View {
    @ObservedObject var manager: LyricManager
    @Environment(\.dismiss) var dismiss
    
    var editingSong: Song? = nil
    
    @State private var title: String = ""
    @State private var rawText: String = ""
    
    // 保持使用 Double 適配 TextField
    @State private var fontSize: Double = 80
    @State private var lineSpacing: Double = 20
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
                        let paddingX = geo.size.width * 0.05
                        
                        VStack(alignment: .center) {
                            // ⭐️ 修正：這裡改用剛剛寫好的 previewText
                            Text(previewText)
                                .font(.system(size: calcFontSize, weight: .bold))
                                .foregroundColor(textColor)
                                .multilineTextAlignment(.center)
                                .lineSpacing(calcLineSpacing)
                                .padding(.horizontal, paddingX)
                                .shadow(color: .black.opacity(0.8), radius: 10, x: 2, y: 2)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .background(Color.black.opacity(0.9))
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
            if let index = manager.allSongs.firstIndex(where: { $0.id == song.id }) {
                var updated = manager.allSongs[index]
                updated.title = title
                updated.rawText = rawText
                
                updated.style.fontSize = CGFloat(fontSize)
                updated.style.lineSpacing = CGFloat(lineSpacing)
                updated.style.textColor = newColorData
                
                updated.parseSegments()
                manager.allSongs[index] = updated
                
                if manager.selectedSong?.id == updated.id {
                    manager.selectedSong = updated
                }
            }
        } else {
            manager.addSong(title: title,
                            text: rawText,
                            fontSize: CGFloat(fontSize),
                            lineSpacing: CGFloat(lineSpacing),
                            textColor: textColor)
        }
        dismiss()
    }
}
//上面是新加的！0423
//下面是原本可以用的
//import SwiftUI
//
//struct SongEditorView: View {
//    @ObservedObject var manager: LyricManager
//    @Environment(\.dismiss) var dismiss
//    
//    // 編輯模式目標
//    var editingSong: Song? = nil
//    
//    // 表單狀態
//    @State private var title: String = ""
//    @State private var rawText: String = ""
//    @State private var fontSize: CGFloat = 80
//    @State private var textColor: Color = .white
//    
//    var body: some View {
//        NavigationStack {
//            Form {
//                Section(header: Text("歌曲資訊"), footer: Text("使用 [段落名稱] 來分隔歌詞，例如：[主歌1]、[副歌]")) {
//                    TextField("歌曲標題", text: $title)
//                    
//                    TextEditor(text: $rawText)
//                        .frame(minHeight: 300)
//                        .font(.system(.body, design: .monospaced))
//                }
//                
//                Section("文字樣式預覽") {
//                    VStack(alignment: .center, spacing: 10) {
//                        Text("預覽文字內容")
//                            .font(.system(size: fontSize))
//                            .foregroundColor(textColor)
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(Color.black.opacity(0.8))
//                            .cornerRadius(8)
//                            .shadow(color: .black, radius: 5)
//                        
//                        Slider(value: $fontSize, in: 20...200, step: 1) {
//                            Text("字體大小")
//                        } minimumValueLabel: {
//                            Text("A").font(.caption)
//                        } maximumValueLabel: {
//                            Text("A").font(.title)
//                        }
//                        
//                        ColorPicker("文字顏色", selection: $textColor)
//                    }
//                    .padding(.vertical)
//                }
//            }
//            .navigationTitle(editingSong == nil ? "新增歌曲" : "編輯歌詞")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Button("取消") { dismiss() }
//                }
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button("儲存") {
//                        saveAction()
//                    }
//                    .disabled(title.isEmpty || rawText.isEmpty)
//                }
//            }
//            .onAppear {
//                prepareInitialData()
//            }
//        }
//    }
//    
//    // 載入初始資料（若是編輯模式）
//    private func prepareInitialData() {
//        if let song = editingSong {
//            title = song.title
//            rawText = song.rawText
//            fontSize = song.style.fontSize
//            
//            // 轉換儲存的 ColorData 回 SwiftUI Color
//            let data = song.style.textColor
//            textColor = Color(red: data.r, green: data.g, blue: data.b)
//        }
//    }
//    
//    private func saveAction() {
//        let colorComps = UIColor(textColor).cgColor.components ?? [1, 1, 1]
//        let newColorData = ColorData(r: Double(colorComps[0]),
//                                    g: Double(colorComps[1]),
//                                    b: Double(colorComps[2]))
//        
//        if let song = editingSong {
//            // --- 修改現有歌曲 ---
//            if let index = manager.allSongs.firstIndex(where: { $0.id == song.id }) {
//                var updated = manager.allSongs[index]
//                updated.title = title
//                updated.rawText = rawText
//                updated.style.fontSize = fontSize
//                updated.style.textColor = newColorData
//                
//                // 重新解析 [段落]
//                updated.parseSegments()
//                
//                manager.allSongs[index] = updated
//                
//                // 如果目前正在播放這首歌，同步更新 Live 狀態
//                if manager.selectedSong?.id == updated.id {
//                    manager.selectedSong = updated
//                }
//            }
//        } else {
//            // --- 新增歌曲 ---
//            manager.addSong(title: title,
//                           text: rawText,
//                           fontSize: fontSize,
//                           textColor: textColor)
//        }
//        dismiss()
//    }
//}
