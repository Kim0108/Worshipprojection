import SwiftUI
import Foundation

// --- 1. 支援顏色與樣式儲存的格式 ---
struct ColorData: Codable, Hashable {
    var r, g, b: Double
    // 支援顏色儲存的格式
    // 新增這個屬性，方便將儲存的資料轉回 SwiftUI 的 Color
    var asColor: Color {
        Color(red: r, green: g, blue: b)
    }
}


struct TextSettings: Codable, Hashable {
    var fontSize: CGFloat = 80
    var textColor: ColorData = ColorData(r: 1, g: 1, b: 1)
    var shadowRadius: CGFloat = 10
    var transitionDuration: Double = 0.5
    var lineSpacing: CGFloat = 20 // 1. 新增：預設行距 0423
}

// --- 2. 獨立的背景庫模型 ---
struct BackgroundItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String    // 存儲在 App 內的原始檔名
    var displayName: String // 顯示在介面上的名稱
    var isVideo: Bool       // 判斷是影片還是照片
    
    // 計算屬性：取得檔案的實體 URL
    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}

// --- 3. 歌詞段落模型 ---
struct LyricSegment: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String    // [段落名稱]
    var content: String  // 該段落實際要投影的文字內容
}

// --- 4. 歌曲模型 (不再綁定特定背景) ---
struct Song: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var rawText: String
    var segments: [LyricSegment] = []
    var style: TextSettings = TextSettings()
    
    // 核心解析邏輯：將 [段落] 歌詞內容拆解
    mutating func parseSegments() {
        self.segments = []
        
        // 使用正則表達式尋找 [任何文字] 格式
        let pattern = "\\[(.*?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsString = rawText as NSString
        let matches = regex.matches(in: rawText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for (index, match) in matches.enumerated() {
            // 提取標籤文字 (不含中括號)
            let label = nsString.substring(with: match.range(at: 1))
            
            // 決定內容的起點與終點
            let contentStart = match.range.location + match.range.length
            let contentEnd = (index + 1 < matches.count) ? matches[index + 1].range.location : nsString.length
            
            let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !content.isEmpty {
                self.segments.append(LyricSegment(label: label, content: content))
            }
        }
        
        // 防呆：如果完全沒匹配到標籤，就把整段當成「內容」
        if segments.isEmpty && !rawText.isEmpty {
            segments.append(LyricSegment(label: "內容", content: rawText))
        }
    }
    
    // 符合 Hashable
//    func hash(into hasher: inout Hasher) { hasher.combine(id) }
  //  static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
}

