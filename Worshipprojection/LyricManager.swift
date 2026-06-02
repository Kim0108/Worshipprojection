import SwiftUI
import UIKit
internal import Combine
import PhotosUI
import PDFKit
internal import UniformTypeIdentifiers

class LyricManager: ObservableObject {
    private var isReceivingFromNetwork = false
    @Published var appRole: AppRole?
    @Published var projectionMode: ProjectionMode = .lyricsWithBackground

    // --- 1. 資料庫：歌詞與投影片 ---
    @Published var allSongs: [Song] = [] {
        didSet { saveSongs() }
    }
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
    // --- 3. 儲存路徑 ---
    private var songsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("songs_v2.json")
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
        loadSlides()
        loadSetlist() // 載入今日流程
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
        transitionDuration: Double = 0.12,
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
        newSong.style.transitionDuration = transitionDuration
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

    func renameSlideFolder(_ folder: SlideFolder, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = slideFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        slideFolders[index].name = trimmedName
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

    func importPDFSlides(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let jpegData = renderPDFPageAsJPEG(page) else { continue }

            let id = UUID().uuidString
            let fileName = "slide_pdf_\(id).jpg"
            let destination = documentsDirectory.appendingPathComponent(fileName)
            try jpegData.write(to: destination)

            await MainActor.run {
                let folderIndex = self.ensureSlideFolder()
                let slide = SlideItem(
                    fileName: fileName,
                    displayName: "\(baseName) \(pageIndex + 1)"
                )
                self.slideFolders[folderIndex].slides.append(slide)
                if self.slideFolders[folderIndex].slides.count == 1 {
                    self.activeSlideIndex = 0
                }
                self.isSlideBlackout = false
            }
        }
    }

    private func renderPDFPageAsJPEG(_ page: PDFPage) -> Data? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

        let maxPixelSide: CGFloat = 1920
        let scale = min(maxPixelSide / max(pageBounds.width, pageBounds.height), 3.0)
        let targetSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: targetSize.height)
            cgContext.scaleBy(x: scale, y: -scale)
            cgContext.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            page.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
        }

        return image.jpegData(compressionQuality: 0.9)
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

    func renameSlide(_ slide: SlideItem, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let folderIndex = activeSlideFolderIndex,
              let index = slideFolders[folderIndex].slides.firstIndex(where: { $0.id == slide.id }) else { return }
        slideFolders[folderIndex].slides[index].displayName = trimmedName
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
}
