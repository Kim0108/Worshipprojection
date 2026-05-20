import SwiftUI
import UIKit
internal import Combine
import PhotosUI
internal import UniformTypeIdentifiers

class LyricManager: ObservableObject {
    private var isReceivingFromNetwork = false
    @Published var appRole: AppRole?
    @Published var projectionMode: ProjectionMode = .lyricsWithBackground
    
// 💡 新增：儲存與內存的顯示字串
    @Published var storageUsageString: String = "計算中..."
    @Published var memoryUsageString: String = "計算中..."
    private var memoryTimer: AnyCancellable? // 用來定時刷新內存
    
    // --- 1. 資料庫：歌詞與背景 ---
    @Published var allSongs: [Song] = [] {
        didSet { saveSongs() }
    }
    @Published var backgroundFolders: [BackgroundFolder] = [] {
        didSet { saveBackgrounds() }
    }
    @Published var activeBackgroundFolderID: UUID?
    @Published var slideFolders: [SlideFolder] = [] {
        didSet { saveSlides() }
    }
    @Published var activeSlideIndex: Int = 0
    @Published var activeSlideFolderID: UUID?
    @Published var isSlideBlackout = false
    
    // ⭐️ 新增：今日流程與分類狀態
    @Published var todaySetlist: [Song] = [] {
        didSet { saveSetlist() }
    }
    
    enum SidebarCategory { case all, today }
    @Published var currentCategory: SidebarCategory = .today { // 預設看今日流程
        didSet { synchronizeSongsBetweenLists() }
    }
    @Published var selectedSong: Song? // 單純紀錄選中的歌供 UI 預備，不觸發 Live 畫面
    
    @Published var activeStyle: TextSettings = TextSettings() {
        didSet {
            if !isReceivingFromNetwork {
                sendActiveState()
            }
        }
    } // 正在投影的樣式
    // ⭐️ 1. 新增：建立同步管理器
    @Published var multipeerManager = MultipeerManager()
    @Published var webServer = WebTeleprompterServer()
//    @Published var activeLyricContent: String = "" // 目前投影在銀幕上的文字內容
    // ⭐️ 2. 修改：當文字改變時，自動發送給台上的設備
    @Published var activeLyricContent: String = "" {
        didSet {
                // 傳送限制：只有在「不是」從網路接收資料時（代表是自己手動點擊歌詞），才廣播給對方
                if !isReceivingFromNetwork {
                    sendActiveState()
                }
            }
    }
    
    @Published var previousBackground: BackgroundItem? = nil
    @Published var selectedBackground: BackgroundItem? {
        didSet {
            // 邏輯：當新背景被賦值時，把舊背景存到 previousBackground
            if selectedBackground == nil {
                previousBackground = nil
            } else if let old = oldValue, old.id != selectedBackground?.id {
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
    private var backgroundFoldersURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("background_folders_v1.json")
    }
    private var slidesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("slides_v1.json")
    }
    private var slideFoldersURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("slide_folders_v1.json")
    }
    // ⭐️ 新增 Setlist 儲存路徑
    private var setlistURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("setlist_v2.json")
    }
    // 儲存路徑
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
// 💡 在變數宣告區，加上這行（用來儲存訂閱狀態）
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadSongs()
        loadBackgrounds()
        loadSlides()
        loadSetlist() // 載入今日流程
        updateStorageUsage() // 💡 啟動時先算一次容量
        startMemoryMonitoring()
        clearTempDirectory()// 💡 加上這行：一打開 App 就把沒用的暫存全砍了
        // 在 LyricManager 的 init() 裡面：
        multipeerManager.onReceivedData = { [weak self] data in
            self?.receive(data)
        }
// 轉發機制：
        multipeerManager.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send() // 當內層變動，觸發外層刷新
                }
            }
            .store(in: &cancellables)

        webServer.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    func setRole(_ role: AppRole) {
        appRole = role
        switch role {
        case .broadcaster:
            multipeerManager.startConnection(role: .broadcaster)
        case .teleprompter:
            multipeerManager.startConnection(role: .receiver)
        }
    }

    func leaveCurrentRole() {
        appRole = nil
        multipeerManager.stopAll()
    }

    private func sendActiveState() {
        let state = LiveSyncState(lyric: activeLyricContent, style: activeStyle)
        webServer.publish(state)

        guard appRole == .broadcaster || multipeerManager.connectionRole == .broadcaster else { return }
        multipeerManager.send(state: state)
    }

    private func receive(_ data: Data) {
        isReceivingFromNetwork = true
        defer { isReceivingFromNetwork = false }

        if let state = try? JSONDecoder().decode(LiveSyncState.self, from: data) {
            activeStyle = state.style
            activeLyricContent = state.lyric
            return
        }

        if let receivedText = String(data: data, encoding: .utf8) {
            activeLyricContent = receivedText
        }
    }
// MARK: - 🗑️ 修正版：實體物理刪除背景
    // 💡 同時刪除硬碟實體檔案、清空記憶體播放器、並從對應的資料夾陣列中移除
    func deleteBackground(_ item: BackgroundItem, from folderID: UUID) {
        // 1. 物理刪除硬碟檔案（避免 App 越來越大）
        let fileURL = item.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑️ 成功從硬碟徹底刪除檔案：\(item.fileName)")
            } catch {
                print("❌ 物理刪除檔案失敗：\(error.localizedDescription)")
            }
        }
        
        // 2. 如果刪除的是當前畫面上正在播的背景，立刻清空它，釋放記憶體
        if selectedBackground?.id == item.id {
            selectedBackground = nil
        }
        if previousBackground?.id == item.id {
            previousBackground = nil
        }
        
        // 3. 從正確的資料夾中將它移除，並觸發 didSet 存檔
        if let folderIndex = backgroundFolders.firstIndex(where: { $0.id == folderID }) {
            backgroundFolders[folderIndex].backgrounds.removeAll(where: { $0.id == item.id })
            // 重新賦值以觸發 @Published 的 didSet 存檔機制
            backgroundFolders = backgroundFolders
        }
        
        // 4. 刪除完畢，立刻重新計算硬碟大小
        updateStorageUsage()
        clearTempDirectory()
    }

    // MARK: - 📊 效能與內存監測工具
    
    /// 核心功能：計算沙盒 Documents 資料夾的總大小
    func updateStorageUsage() {
        let fileManager = FileManager.default
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [])
            var totalSize: Int64 = 0
            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            
            DispatchQueue.main.async {
                self.storageUsageString = formatter.string(fromByteCount: totalSize)
            }
        } catch {
            print("❌ 計算硬碟空間失敗: \(error)")
        }
    }
    
    /// 核心功能：每 2 秒抓取一次 iOS 系統分配給此 App 的真實執行內存 (RAM)
    private func startMemoryMonitoring() {
        memoryTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMemoryUsage()
            }
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedBytes = Double(info.resident_size)
            let usedMB = usedBytes / 1024.0 / 1024.0
            DispatchQueue.main.async {
                self.memoryUsageString = String(format: "%.1f MB", usedMB)
            }
        }
    }
    // 💡 3. 刪除「整個背景資料夾」時，一併刪除裡面的所有檔案
    func deleteBackgroundFolder(at offsets: IndexSet) {
        for index in offsets {
            let folder = backgroundFolders[index]
            // 迴圈把該資料夾內的所有背景檔案通通物理刪除
            for bg in folder.backgrounds {
                let fileURL = documentsDirectory.appendingPathComponent(bg.fileName)
                try? FileManager.default.removeItem(at: fileURL)
                print("🗑️ 已跟隨資料夾刪除檔案：\(bg.fileName)")
            }
        }
        
        // 從陣列中移除資料夾
        backgroundFolders.remove(atOffsets: offsets)
        
        // 重新計算容量
        updateStorageUsage()
    }
    // MARK: - ⭐️ 今日流程管理邏輯
    func addToSetlist(_ song: Song) {
        synchronizeSongsBetweenLists()
        if !todaySetlist.contains(where: { $0.id == song.id }) {
            todaySetlist.append(canonicalSong(for: song))
        }
    }
    
    func removeFromSetlist(at offsets: IndexSet) {
        todaySetlist.remove(atOffsets: offsets)
    }

    // MARK: - 原有核心：歌曲管理
    func addSong(
        title: String,
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        shadowRadius: CGFloat = 10,
        verticalPosition: CGFloat = 0.5,
        horizontalPaddingRatio: CGFloat = 0.05,
        backgroundDimOpacity: Double = 0.0,
        horizontalAlignment: TextHorizontalAlignment = .center,
        textColor: Color
    ) {
        let comps = UIColor(textColor).cgColor.components ?? [1, 1, 1]
        let colorData = ColorData(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]))
        
        var newSong = Song(title: title, rawText: text)
        newSong.style.fontSize = fontSize
        newSong.style.lineSpacing = lineSpacing // 存入行距
        newSong.style.shadowRadius = shadowRadius
        newSong.style.verticalPosition = verticalPosition
        newSong.style.horizontalPaddingRatio = horizontalPaddingRatio
        newSong.style.backgroundDimOpacity = backgroundDimOpacity
        newSong.style.horizontalAlignment = horizontalAlignment
        newSong.style.textColor = colorData
        newSong.parseSegments()
        
        allSongs.append(newSong)
    }

    func updateSong(_ song: Song) {
        var updated = song
        updated.parseSegments()

        if let allIndex = allSongs.firstIndex(where: { $0.id == updated.id }) {
            allSongs[allIndex] = updated
        } else {
            allSongs.append(updated)
        }

        if let setlistIndex = todaySetlist.firstIndex(where: { $0.id == updated.id }) {
            todaySetlist[setlistIndex] = updated
        }

        if selectedSong?.id == updated.id {
            selectedSong = updated
        }
    }

    func synchronizeSongsBetweenLists() {
        guard !allSongs.isEmpty || !todaySetlist.isEmpty else { return }

        var canonicalById = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })

        for song in todaySetlist where canonicalById[song.id] == nil {
            canonicalById[song.id] = song
            allSongs.append(song)
        }

        todaySetlist = todaySetlist.map { song in
            canonicalById[song.id] ?? song
        }

        if let selected = selectedSong, let canonical = canonicalById[selected.id] {
            selectedSong = canonical
        }
    }

    func canonicalSong(for song: Song) -> Song {
        allSongs.first(where: { $0.id == song.id }) ?? song
    }
    
    
    func deleteSong(at offsets: IndexSet) {
        allSongs.remove(atOffsets: offsets)
    }

    // MARK: - 背景庫管理 (關鍵重構)

    var activeBackgroundFolder: BackgroundFolder? {
        guard let index = activeBackgroundFolderIndex else { return nil }
        return backgroundFolders[index]
    }

    var backgroundLibrary: [BackgroundItem] {
        activeBackgroundFolder?.backgrounds ?? []
    }

    var totalBackgroundCount: Int {
        backgroundFolders.reduce(0) { $0 + $1.backgrounds.count }
    }

    private var activeBackgroundFolderIndex: Int? {
        if let id = activeBackgroundFolderID,
           let index = backgroundFolders.firstIndex(where: { $0.id == id }) {
            return index
        }
        return backgroundFolders.indices.first
    }

    private func ensureBackgroundFolder() -> Int {
        if let index = activeBackgroundFolderIndex {
            if activeBackgroundFolderID == nil {
                activeBackgroundFolderID = backgroundFolders[index].id
            }
            return index
        }

        let folder = BackgroundFolder(name: "預設背景")
        backgroundFolders.append(folder)
        activeBackgroundFolderID = folder.id
        return 0
    }

    func createBackgroundFolder(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = trimmedName.isEmpty ? "新背景資料夾" : trimmedName
        let folder = BackgroundFolder(name: folderName)
        backgroundFolders.append(folder)
        activeBackgroundFolderID = folder.id
    }

    func selectBackgroundFolder(_ folder: BackgroundFolder) {
        guard backgroundFolders.contains(where: { $0.id == folder.id }) else { return }
        activeBackgroundFolderID = folder.id
    }

    func deleteBackgroundFolder(_ folder: BackgroundFolder) {
        guard let index = backgroundFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        for background in backgroundFolders[index].backgrounds {
            let fileURL = documentsDirectory.appendingPathComponent(background.fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if selectedBackground?.id == background.id {
                selectedBackground = nil
            }
        }

        backgroundFolders.remove(at: index)
        if backgroundFolders.isEmpty {
            activeBackgroundFolderID = nil
        } else {
            let nextIndex = min(index, backgroundFolders.count - 1)
            activeBackgroundFolderID = backgroundFolders[nextIndex].id
        }
    }

    func renameBackgroundFolder(_ folder: BackgroundFolder, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = backgroundFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        backgroundFolders[index].name = trimmedName
    }

    func renameBackground(_ background: BackgroundItem, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        for folderIndex in backgroundFolders.indices {
            if let backgroundIndex = backgroundFolders[folderIndex].backgrounds.firstIndex(where: { $0.id == background.id }) {
                backgroundFolders[folderIndex].backgrounds[backgroundIndex].displayName = trimmedName
                if selectedBackground?.id == background.id {
                    selectedBackground = backgroundFolders[folderIndex].backgrounds[backgroundIndex]
                }
                return
            }
        }
    }
    
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
                let folderIndex = self.ensureBackgroundFolder()
                // 2. 決定要顯示在介面上的名字
                // 如果 customName 有值就用它，否則用原本的邏輯
                let display = (customName == nil || customName!.isEmpty) ?
                              (isVideo ? "新影片背景" : "新圖片背景") : customName!
                
                let newBG = BackgroundItem(
                    fileName: fileName,
                    displayName: display,
                    isVideo: isVideo
                )
                self.backgroundFolders[folderIndex].backgrounds.append(newBG)
                self.selectedBackground = newBG
                self.updateStorageUsage()
                self.clearTempDirectory() // 💡 匯入完成後，立刻把 tmp 裡的過渡檔案刪除！
            }
        } catch {
            print("❌ 匯入失敗: \(error.localizedDescription)")
        }
        
    }
    
    func deleteBackground(at offsets: IndexSet) {
        guard let folderIndex = activeBackgroundFolderIndex else { return }
        for index in offsets {
            let bg = backgroundFolders[folderIndex].backgrounds[index]
            
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
        backgroundFolders[folderIndex].backgrounds.remove(atOffsets: offsets)
    }

    func deleteAllBackgrounds() {
        for folder in backgroundFolders {
            for bg in folder.backgrounds {
                let fileURL = documentsDirectory.appendingPathComponent(bg.fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        selectedBackground = nil
        previousBackground = nil
        backgroundFolders.removeAll()
        activeBackgroundFolderID = nil
        updateStorageUsage()
        updateMemoryUsage()
    }
/// 💡 供 UI 按鈕直接呼叫的「一鍵清除與同步刷新」
    func triggerAppSlimming() {
        // 1. 執行物理刪除暫存垃圾
        clearTempDirectory()
        
        // 2. 強制系統做一次記憶體垃圾回收（有助於降低 RAM 數字）
        // iOS 沒有手動 GC，但我們可以透過清空沒用到的緩存間接釋放
        if selectedBackground == nil {
            // 如果當前沒播背景，通知系統釋放一些記憶體
            URLCache.shared.removeAllCachedResponses()
        }
        
        // 3. ⭐️ 關鍵：不等定時器，點擊的「當下」立刻強制計算最新數據
        updateStorageUsage()
        updateMemoryUsage()
    }
    // MARK: - 投影片管理

    var activeSlideFolder: SlideFolder? {
        guard let index = activeSlideFolderIndex else { return nil }
        return slideFolders[index]
    }

    var slideLibrary: [SlideItem] {
        activeSlideFolder?.slides ?? []
    }

    var activeSlide: SlideItem? {
        guard !isSlideBlackout, slideLibrary.indices.contains(activeSlideIndex) else { return nil }
        return slideLibrary[activeSlideIndex]
    }

    private var activeSlideFolderIndex: Int? {
        if let id = activeSlideFolderID,
           let index = slideFolders.firstIndex(where: { $0.id == id }) {
            return index
        }
        return slideFolders.indices.first
    }

    private func ensureSlideFolder() -> Int {
        if let index = activeSlideFolderIndex {
            if activeSlideFolderID == nil {
                activeSlideFolderID = slideFolders[index].id
            }
            return index
        }

        let folder = SlideFolder(name: "預設簡報")
        slideFolders.append(folder)
        activeSlideFolderID = folder.id
        activeSlideIndex = 0
        return 0
    }

    func createSlideFolder(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = trimmedName.isEmpty ? "新簡報" : trimmedName
        let folder = SlideFolder(name: folderName)
        slideFolders.append(folder)
        activeSlideFolderID = folder.id
        activeSlideIndex = 0
        isSlideBlackout = false
    }

    func selectSlideFolder(_ folder: SlideFolder) {
        guard slideFolders.contains(where: { $0.id == folder.id }) else { return }
        activeSlideFolderID = folder.id
        activeSlideIndex = 0
        isSlideBlackout = false
    }

    func deleteSlideFolder(_ folder: SlideFolder) {
        guard let index = slideFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        for slide in slideFolders[index].slides {
            let fileURL = documentsDirectory.appendingPathComponent(slide.fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        slideFolders.remove(at: index)
        if slideFolders.isEmpty {
            activeSlideFolderID = nil
            activeSlideIndex = 0
            isSlideBlackout = false
        } else {
            let nextIndex = min(index, slideFolders.count - 1)
            activeSlideFolderID = slideFolders[nextIndex].id
            activeSlideIndex = 0
            isSlideBlackout = false
        }
    }

    func importSlides(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpegData = image.jpegData(compressionQuality: 0.85) else { continue }

                let id = UUID().uuidString
                let fileName = "slide_\(id).jpg"
                let destination = documentsDirectory.appendingPathComponent(fileName)
                try jpegData.write(to: destination)

                await MainActor.run {
                    let folderIndex = self.ensureSlideFolder()
                    let slide = SlideItem(
                        fileName: fileName,
                        displayName: "投影片 \(self.slideFolders[folderIndex].slides.count + 1)"
                    )
                    self.slideFolders[folderIndex].slides.append(slide)
                    if self.slideFolders[folderIndex].slides.count == 1 {
                        self.activeSlideIndex = 0
                    }
                    self.isSlideBlackout = false
                }
            } catch {
                print("❌ 投影片匯入失敗: \(error.localizedDescription)")
            }
        }
    }

    func selectSlide(_ slide: SlideItem) {
        guard let index = slideLibrary.firstIndex(where: { $0.id == slide.id }) else { return }
        activeSlideIndex = index
        isSlideBlackout = false
    }

    func goToPreviousSlide() {
        guard !slideLibrary.isEmpty else { return }
        activeSlideIndex = max(activeSlideIndex - 1, 0)
        isSlideBlackout = false
    }

    func goToNextSlide() {
        guard !slideLibrary.isEmpty else { return }
        activeSlideIndex = min(activeSlideIndex + 1, slideLibrary.count - 1)
        isSlideBlackout = false
    }

    func deleteSlide(_ slide: SlideItem) {
        guard let folderIndex = activeSlideFolderIndex,
              let index = slideFolders[folderIndex].slides.firstIndex(where: { $0.id == slide.id }) else { return }
        let fileURL = documentsDirectory.appendingPathComponent(slide.fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        slideFolders[folderIndex].slides.remove(at: index)
        activeSlideIndex = min(activeSlideIndex, max(slideLibrary.count - 1, 0))
    }

    func deleteSlides(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard slideLibrary.indices.contains(index) else { continue }
            deleteSlide(slideLibrary[index])
        }
    }

    func moveSlides(from source: IndexSet, to destination: Int) {
        guard let folderIndex = activeSlideFolderIndex else { return }
        let currentSlideID = activeSlide?.id
        slideFolders[folderIndex].slides.move(fromOffsets: source, toOffset: destination)
        if let currentSlideID,
           let newIndex = slideFolders[folderIndex].slides.firstIndex(where: { $0.id == currentSlideID }) {
            activeSlideIndex = newIndex
        } else {
            activeSlideIndex = min(activeSlideIndex, max(slideLibrary.count - 1, 0))
        }
    }

    func exportPackage(format: ProjectExportFormat = .json) -> WorshipProjectDocument {
        synchronizeSongsBetweenLists()
        let songsForExport = uniqueSongsPreservingOrder(allSongs)
        let exportedSongIDs = Set(songsForExport.map(\.id))
        let setlistForExport = uniqueSongsPreservingOrder(todaySetlist.map { canonicalSong(for: $0) })
            .filter { exportedSongIDs.contains($0.id) }

        let package = WorshipProjectPackage(
            exportedAt: Date(),
            songs: songsForExport,
            todaySetlist: [],
            todaySetlistIDs: setlistForExport.map(\.id)
        )
        return WorshipProjectDocument(package: package, format: format)
    }

    func importPackage(_ package: WorshipProjectPackage) throws {
        var importedByOriginalId: [UUID: Song] = [:]

        for song in package.songs {
            if let existing = existingSongMatching(song) {
                importedByOriginalId[song.id] = existing
                continue
            }

            let imported = uniqueImportedSong(from: song)
            allSongs.append(imported)
            importedByOriginalId[song.id] = imported
        }

        let setlistSongs: [Song]
        if let setlistIDs = package.todaySetlistIDs {
            setlistSongs = setlistIDs.compactMap { id in
                importedByOriginalId[id] ?? allSongs.first(where: { $0.id == id })
            }
        } else {
            setlistSongs = package.todaySetlist
        }

        for song in setlistSongs {
            let imported: Song
            if let alreadyImported = importedByOriginalId[song.id] {
                imported = alreadyImported
            } else if let existing = existingSongMatching(song) {
                imported = existing
                importedByOriginalId[song.id] = existing
            } else {
                imported = uniqueImportedSong(from: song)
                allSongs.append(imported)
                importedByOriginalId[song.id] = imported
            }

            if !todaySetlist.contains(where: { $0.id == imported.id }) {
                todaySetlist.append(imported)
            }
        }

        if selectedSong == nil {
            selectedSong = importedByOriginalId.values.first ?? todaySetlist.first ?? allSongs.first
        }
    }

    func importProjectData(_ data: Data, suggestedFilename: String? = nil) throws {
        let lowercasedName = suggestedFilename?.lowercased() ?? ""
        let package: WorshipProjectPackage

        if lowercasedName.hasSuffix(".txt"),
           let text = String(data: data, encoding: .utf8) {
            package = WorshipProjectPackage.textPackage(from: text)
        } else if let decoded = try? JSONDecoder().decode(WorshipProjectPackage.self, from: data) {
            package = decoded
        } else if let text = String(data: data, encoding: .utf8) {
            package = WorshipProjectPackage.textPackage(from: text)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try importPackage(package)
    }

    private func uniqueImportedSong(from song: Song) -> Song {
        var imported = song
        if allSongs.contains(where: { $0.id == imported.id || $0.title == imported.title }) ||
            todaySetlist.contains(where: { $0.id == imported.id }) {
            imported.id = UUID()
        }
        imported.parseSegments()
        return imported
    }

    private func existingSongMatching(_ song: Song) -> Song? {
        allSongs.first { existing in
            existing.id == song.id || songContentKey(existing) == songContentKey(song)
        }
    }

    private func uniqueSongsPreservingOrder(_ songs: [Song]) -> [Song] {
        var seenIDs = Set<UUID>()
        var seenContentKeys = Set<String>()
        var uniqueSongs: [Song] = []

        for song in songs {
            let contentKey = songContentKey(song)
            guard !seenIDs.contains(song.id), !seenContentKeys.contains(contentKey) else { continue }
            seenIDs.insert(song.id)
            seenContentKeys.insert(contentKey)
            uniqueSongs.append(song)
        }

        return uniqueSongs
    }

    private func songContentKey(_ song: Song) -> String {
        let title = song.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rawText = song.rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(title)\u{1F}\(rawText)"
    }

    func startWebTeleprompter() {
        webServer.start(initialState: LiveSyncState(lyric: activeLyricContent, style: activeStyle))
    }

    func stopWebTeleprompter() {
        webServer.stop()
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
            let data = try JSONEncoder().encode(backgroundFolders)
            try data.write(to: backgroundFoldersURL)
        } catch { print("❌ 背景庫存檔失敗: \(error)") }
    }

    private func loadBackgrounds() {
        if let data = try? Data(contentsOf: backgroundFoldersURL),
           let decoded = try? JSONDecoder().decode([BackgroundFolder].self, from: data) {
            backgroundFolders = decoded
            activeBackgroundFolderID = decoded.first?.id
            return
        }

        guard let data = try? Data(contentsOf: backgroundsURL) else { return }
        if let legacyBackgrounds = try? JSONDecoder().decode([BackgroundItem].self, from: data) {
            backgroundFolders = [BackgroundFolder(name: "預設背景", backgrounds: legacyBackgrounds)]
            activeBackgroundFolderID = backgroundFolders.first?.id
        }
    }

    private func saveSlides() {
        do {
            let data = try JSONEncoder().encode(slideFolders)
            try data.write(to: slideFoldersURL)
        } catch { print("❌ 投影片存檔失敗: \(error)") }
    }

    private func loadSlides() {
        if let data = try? Data(contentsOf: slideFoldersURL),
           let decoded = try? JSONDecoder().decode([SlideFolder].self, from: data) {
            slideFolders = decoded
            activeSlideFolderID = decoded.first?.id
            return
        }

        guard let data = try? Data(contentsOf: slidesURL) else { return }
        if let legacySlides = try? JSONDecoder().decode([SlideItem].self, from: data) {
            slideFolders = [SlideFolder(name: "預設簡報", slides: legacySlides)]
            activeSlideFolderID = slideFolders.first?.id
        }
    }
// MARK: - 🧹 系統深度清理 (清除幽靈暫存檔)
    func clearTempDirectory() {
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil, options: [])
            for file in tempFiles {
                try FileManager.default.removeItem(at: file)
                print("🧹 成功清除殘留暫存檔：\(file.lastPathComponent)")
            }
        } catch {
            print("❌ 清除暫存檔失敗：\(error)")
        }
    }
}
