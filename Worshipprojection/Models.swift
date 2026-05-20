import SwiftUI
import Foundation
internal import UniformTypeIdentifiers

enum AppRole: String, CaseIterable, Identifiable {
    case broadcaster
    case teleprompter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .broadcaster: "廣播主控端"
        case .teleprompter: "提詞接收端"
        }
    }

    var subtitle: String {
        switch self {
        case .broadcaster: "管理歌曲、背景、流程，並把目前歌詞送到外接螢幕與提詞機。"
        case .teleprompter: "只接收主控端送出的歌詞，避免誤觸投放控制。"
        }
    }

    var iconName: String {
        switch self {
        case .broadcaster: "play.tv.fill"
        case .teleprompter: "display.2"
        }
    }
}

enum ProjectionMode: String, CaseIterable, Identifiable, Codable {
    case lyricsWithBackground
    case slides

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyricsWithBackground: "歌詞＋背景"
        case .slides: "投影片模式"
        }
    }

    var subtitle: String {
        switch self {
        case .lyricsWithBackground: "使用歌詞段落，背景可切換或純黑。"
        case .slides: "預留給圖片或 .pptx 投影片播放。"
        }
    }
}

enum TextHorizontalAlignment: String, CaseIterable, Identifiable, Codable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: "靠左"
        case .center: "置中"
        case .trailing: "靠右"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

enum ProjectExportFormat: String, CaseIterable, Identifiable {
    case json
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .text: "TXT"
        }
    }

    var contentType: UTType {
        switch self {
        case .json: .json
        case .text: .plainText
        }
    }

    var defaultFilename: String {
        switch self {
        case .json: "WorshipProjectionProject.json"
        case .text: "WorshipProjectionProject.txt"
        }
    }
}

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
    var horizontalAlignment: TextHorizontalAlignment = .center
    var verticalPosition: CGFloat = 0.5
    var horizontalPaddingRatio: CGFloat = 0.05
    var backgroundDimOpacity: Double = 0.0

    enum CodingKeys: String, CodingKey {
        case fontSize, textColor, shadowRadius, transitionDuration, lineSpacing
        case horizontalAlignment, verticalPosition, horizontalPaddingRatio, backgroundDimOpacity
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 80
        textColor = try container.decodeIfPresent(ColorData.self, forKey: .textColor) ?? ColorData(r: 1, g: 1, b: 1)
        shadowRadius = try container.decodeIfPresent(CGFloat.self, forKey: .shadowRadius) ?? 10
        transitionDuration = try container.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? 0.5
        lineSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? 20
        horizontalAlignment = try container.decodeIfPresent(TextHorizontalAlignment.self, forKey: .horizontalAlignment) ?? .center
        verticalPosition = try container.decodeIfPresent(CGFloat.self, forKey: .verticalPosition) ?? 0.5
        horizontalPaddingRatio = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalPaddingRatio) ?? 0.05
        backgroundDimOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundDimOpacity) ?? 0.0
    }
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

struct BackgroundFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var backgrounds: [BackgroundItem] = []
}

struct SlideItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var displayName: String

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}

struct SlideFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var slides: [SlideItem] = []
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

struct LiveSyncState: Codable {
    var lyric: String
    var style: TextSettings
}

struct WorshipProjectPackage: Codable {
    var exportedAt: Date
    var songs: [Song]
    var todaySetlist: [Song]
}

extension UTType {
    static let worshipProjectPackage = UTType(exportedAs: "com.worshipprojection.package")
}

struct WorshipProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.worshipProjectPackage, .json, .plainText] }

    var package: WorshipProjectPackage
    var format: ProjectExportFormat = .json

    init(package: WorshipProjectPackage, format: ProjectExportFormat = .json) {
        self.package = package
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType == .plainText,
           let text = String(data: data, encoding: .utf8) {
            package = WorshipProjectPackage.textPackage(from: text)
            format = .text
        } else {
            package = try JSONDecoder().decode(WorshipProjectPackage.self, from: data)
            format = .json
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(package)
        case .text:
            data = package.textExport().data(using: .utf8) ?? Data()
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

extension WorshipProjectPackage {
    func textExport() -> String {
        var output: [String] = [
            "# WorshipProjection TXT v1",
            "# 每首歌用 ## Song: 開頭；段落使用 [主歌]、[副歌] 這類標籤。",
            "# style: fontSize,lineSpacing,shadowRadius,horizontalPaddingRatio,textColorHex",
            ""
        ]

        for song in songs {
            output.append("## Song: \(song.title)")
            output.append("fontSize: \(Int(song.style.fontSize))")
            output.append("lineSpacing: \(Int(song.style.lineSpacing))")
            output.append("shadowRadius: \(Int(song.style.shadowRadius))")
            output.append("horizontalPaddingRatio: \(String(format: "%.2f", Double(song.style.horizontalPaddingRatio)))")
            output.append("textColor: \(song.style.textColor.hexString)")
            output.append("")
            output.append(song.rawText.trimmingCharacters(in: .whitespacesAndNewlines))
            output.append("")
        }

        return output.joined(separator: "\n")
    }

    static func textPackage(from text: String) -> WorshipProjectPackage {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let chunks = normalized.components(separatedBy: "\n## Song:")
        var songs: [Song] = []

        for rawChunk in chunks {
            let chunk = rawChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunk.isEmpty, !chunk.hasPrefix("# WorshipProjection") else { continue }

            let lines = chunk.components(separatedBy: "\n")
            guard let titleLine = lines.first else { continue }
            let title = titleLine.replacingOccurrences(of: "## Song:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            var style = TextSettings()
            var lyricStartIndex = 1

            for (index, line) in lines.dropFirst().enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    lyricStartIndex = index + 2
                    break
                }

                let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2 else {
                    lyricStartIndex = index + 1
                    break
                }

                switch parts[0] {
                case "fontSize":
                    style.fontSize = CGFloat(Double(parts[1]) ?? Double(style.fontSize))
                case "lineSpacing":
                    style.lineSpacing = CGFloat(Double(parts[1]) ?? Double(style.lineSpacing))
                case "shadowRadius":
                    style.shadowRadius = CGFloat(Double(parts[1]) ?? Double(style.shadowRadius))
                case "horizontalPaddingRatio":
                    style.horizontalPaddingRatio = CGFloat(Double(parts[1]) ?? Double(style.horizontalPaddingRatio))
                case "textColor":
                    style.textColor = ColorData(hex: parts[1]) ?? style.textColor
                default:
                    break
                }
            }

            let rawText = lines.dropFirst(lyricStartIndex).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { continue }

            var song = Song(title: title, rawText: rawText, style: style)
            song.parseSegments()
            songs.append(song)
        }

        if songs.isEmpty {
            let rawText = normalized
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawText.isEmpty {
                var song = Song(title: "未命名歌曲", rawText: rawText)
                song.parseSegments()
                songs.append(song)
            }
        }

        return WorshipProjectPackage(exportedAt: Date(), songs: songs, todaySetlist: songs)
    }
}

extension ColorData {
    var hexString: String {
        let red = max(0, min(255, Int(round(r * 255))))
        let green = max(0, min(255, Int(round(g * 255))))
        let blue = max(0, min(255, Int(round(b * 255))))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255.0
        g = Double((value >> 8) & 0xFF) / 255.0
        b = Double(value & 0xFF) / 255.0
    }
}
