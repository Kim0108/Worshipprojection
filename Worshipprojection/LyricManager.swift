import SwiftUI
internal import Combine
import PhotosUI
internal import UniformTypeIdentifiers

class LyricManager: ObservableObject {
    // --- 1. 資料庫：歌詞與背景 ---
    @Published var allSongs: [Song] = [] {
        didSet { saveSongs() }
    }
    @Published var backgroundLibrary: [BackgroundItem] = [] {
        didSet { saveBackgrounds() }
    }
    
    // ⭐️ 新增：今日流程與分類狀態
    @Published var todaySetlist: [Song] = [] {
        didSet { saveSetlist() }
    }
    
    enum SidebarCategory { case all, today }
    @Published var currentCategory: SidebarCategory = .today // 預設看今日流程
    @Published var selectedSong: Song? // 單純紀錄選中的歌供 UI 預備，不觸發 Live 畫面
// 很爛刪掉
//    // --- 2. Live 狀態控制 ---
//    @Published var selectedSong: Song? {
//        didSet {
//            // ⭐️ 當點選歌曲時，自動載入該歌曲記憶的樣式設定
//            if let song = selectedSong {
//                activeStyle = song.style
//                // 預設切換到第一段歌詞內容
//                if let first = song.segments.first {
//                    activeLyricContent = first.content
//                }
//            }
//        }
//    }
    
    @Published var activeStyle: TextSettings = TextSettings() // 正在投影的樣式
    // ⭐️ 1. 新增：建立同步管理器
    @Published var multipeerManager = MultipeerManager()
//    @Published var activeLyricContent: String = "" // 目前投影在銀幕上的文字內容
    // ⭐️ 2. 修改：當文字改變時，自動發送給台上的設備
    @Published var activeLyricContent: String = "" {
        didSet {
            multipeerManager.send(lyric: activeLyricContent)
        }
    }
    
    @Published var previousBackground: BackgroundItem? = nil
    @Published var selectedBackground: BackgroundItem? {
        didSet {
            // 邏輯：當新背景被賦值時，把舊背景存到 previousBackground
            if let old = oldValue, old.id != selectedBackground?.id {
                previousBackground = old
            }
        }
    }
    
    // --- 3. 儲存路徑 ---
    private var songsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("songs_v2.json")
    }
    private var backgroundsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("backgrounds_v2.json")
    }
    // ⭐️ 新增 Setlist 儲存路徑
    private var setlistURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("setlist_v2.json")
    }
    // 儲存路徑
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        loadSongs()
        loadBackgrounds()
        loadSetlist() // 載入今日流程
    }

    // MARK: - ⭐️ 今日流程管理邏輯
    func addToSetlist(_ song: Song) {
        if !todaySetlist.contains(where: { $0.id == song.id }) {
            todaySetlist.append(song)
        }
    }
    
    func removeFromSetlist(at offsets: IndexSet) {
        todaySetlist.remove(atOffsets: offsets)
    }

    // MARK: - 原有核心：歌曲管理
    func addSong(title: String, text: String, fontSize: CGFloat, lineSpacing: CGFloat, textColor: Color) {
        let comps = UIColor(textColor).cgColor.components ?? [1, 1, 1]
        let colorData = ColorData(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]))
        
        var newSong = Song(title: title, rawText: text)
        newSong.style.fontSize = fontSize
        newSong.style.lineSpacing = lineSpacing // 存入行距
        newSong.style.textColor = colorData
        newSong.parseSegments()
        
        allSongs.append(newSong)
    }
    
    
    func deleteSong(at offsets: IndexSet) {
        allSongs.remove(atOffsets: offsets)
    }

    // MARK: - 背景庫管理 (關鍵重構)
    
    /// 從 PhotosPicker 匯入媒體到背景庫
    // 修改後的匯入函式
    func importBackground(from item: PhotosPickerItem, customName: String? = nil) async {
        do {
            let isVideo = item.supportedContentTypes.contains { type in
                type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .quickTimeMovie) || type.conforms(to: .mpeg4Movie)
            }
            
            let fileName: String
            // 1. 決定儲存在硬碟的實體檔名（建議維持 UUID 避免重複，只改顯示名稱）
            let id = UUID().uuidString
            
            if isVideo {
                guard let videoAsset = try await item.loadTransferable(type: VideoPickerTransferable.self) else { return }
                fileName = "bg_video_\(id).\(videoAsset.url.pathExtension)"
                let destination = documentsDirectory.appendingPathComponent(fileName)
                try FileManager.default.copyItem(at: videoAsset.url, to: destination)
            } else {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return }
                
                fileName = "bg_img_\(id).jpg"
                let destination = documentsDirectory.appendingPathComponent(fileName)
                try jpegData.write(to: destination)
            }

            await MainActor.run {
                // 2. 決定要顯示在介面上的名字
                // 如果 customName 有值就用它，否則用原本的邏輯
                let display = (customName == nil || customName!.isEmpty) ?
                              (isVideo ? "新影片背景" : "新圖片背景") : customName!
                
                let newBG = BackgroundItem(
                    fileName: fileName,
                    displayName: display,
                    isVideo: isVideo
                )
                self.backgroundLibrary.append(newBG)
                self.selectedBackground = newBG
                self.saveBackgrounds() // 記得儲存庫存狀態
            }
        } catch {
            print("❌ 匯入失敗: \(error.localizedDescription)")
        }
    }
    
    func deleteBackground(at offsets: IndexSet) {
        for index in offsets {
            let bg = backgroundLibrary[index]
            
            // 1. 取得檔案在沙盒中的路徑
            let fileURL = documentsDirectory.appendingPathComponent(bg.fileName)
            
            // 2. 物理刪除檔案（釋放 iPad 空間）
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ 已成功從硬碟刪除檔案：\(bg.fileName)")
                }
            } catch {
                print("❌ 無法刪除實體檔案：\(error.localizedDescription)")
            }
            
            // 3. 如果這個背景正在被 Live 使用，先清空它防止閃退
            if selectedBackground?.id == bg.id {
                selectedBackground = nil
            }
        }
        
        // 4. 從 UI 陣列中移除
        backgroundLibrary.remove(atOffsets: offsets)
    }

    // MARK: - 永久化存取
    private func saveSongs() {
        do {
            let data = try JSONEncoder().encode(allSongs)
            try data.write(to: songsURL)
        } catch { print("❌ 歌詞存檔失敗: \(error)") }
    }

    private func loadSongs() {
        guard let data = try? Data(contentsOf: songsURL) else { return }
        if let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            allSongs = decoded
        }
    }

    // ⭐️ 新增儲存/讀取今日流程
    private func saveSetlist() {
        if let data = try? JSONEncoder().encode(todaySetlist) {
            try? data.write(to: setlistURL)
        }
    }

    private func loadSetlist() {
        guard let data = try? Data(contentsOf: setlistURL),
              let decoded = try? JSONDecoder().decode([Song].self, from: data) else { return }
        todaySetlist = decoded
    }

    private func saveBackgrounds() {
        do {
            let data = try JSONEncoder().encode(backgroundLibrary)
            try data.write(to: backgroundsURL)
        } catch { print("❌ 背景庫存檔失敗: \(error)") }
    }

    private func loadBackgrounds() {
        guard let data = try? Data(contentsOf: backgroundsURL) else { return }
        if let decoded = try? JSONDecoder().decode([BackgroundItem].self, from: data) {
            backgroundLibrary = decoded
        }
    }
}
