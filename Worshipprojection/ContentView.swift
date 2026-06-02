import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var manager: LyricManager
    @EnvironmentObject var backgroundManager: BackgroundManager
    var switchMode: ((ProjectionMode) -> Void)? = nil
    
    // 偵測螢幕大小 (iPhone 會是 .compact，iPad 橫向會是 .regular)
    @Environment(\.horizontalSizeClass) var sizeClass
    
    @State private var showingSongEditor = false
    @State private var editingTarget: Song? = nil
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingFileManagement = false
    @State private var exportFormat: ProjectExportFormat = .json
    @State private var exportDocument: WorshipProjectDocument?
    @State private var importErrorMessage: String?
    @State private var selectedSongIDs = Set<UUID>()
    @State private var isSelectingSongs = false
    @State private var isLayoutEditing = false
    @State private var resizeStartHeight: Double?
    @State private var showingLayoutSettings = false

    @AppStorage("lyricsLivePreviewHeightPad") private var ipadLivePreviewHeight = 320.0
    @AppStorage("lyricsLivePreviewHeightPhone") private var iphoneLivePreviewHeight = 230.0
    @AppStorage("lyricsSegmentColumnCount") private var segmentColumnCount = 3
    @AppStorage("lyricsSegmentCardHeight") private var segmentCardHeight = 80.0
    @AppStorage("lyricsLeftPanelHidden") private var isLeftPanelHidden = false
    
    var body: some View {
        Group {
            // 💡 根據設備自動切換排版
            if sizeClass == .compact {
                iphoneTabView
            } else {
                ipadHStackView
            }
        }
        .sheet(isPresented: Binding(
            get: { showingSongEditor || editingTarget != nil },
            set: { if !$0 { showingSongEditor = false; editingTarget = nil } }
        )) {
            SongEditorView(manager: manager, editingSong: editingTarget)
        }
        .sheet(isPresented: $showingFileManagement) {
            NavigationStack {
                fileManagementArea
                    .navigationTitle("檔案管理")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showingFileManagement = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingLayoutSettings) {
            NavigationStack {
                layoutSettingsArea
                    .navigationTitle("版面設定")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showingLayoutSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportFormat.contentType,
            defaultFilename: exportFormat.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                importErrorMessage = "匯出失敗：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.worshipProjectPackage, .json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert("檔案處理", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }
}

// MARK: - 📱 iPhone 與 iPad 專屬佈局
extension ContentView {
    
// MARK: - 📱 iPhone 專用的底部 TabView 佈局
    private var iphoneTabView: some View {
        TabView {
            // 分頁 1：歌曲清單
            VStack {
                HStack {
                    sidebarIconButton(title: "所有歌曲", icon: "music.note.list", type: .all)
                    sidebarIconButton(title: "今日流程", icon: "star.fill", type: .today)
                    
                    Spacer()

                    Button { showingSongEditor = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.title2)
                            Text("新增").font(.caption).bold()
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .background(Color(UIColor.systemGray6))
                
                songListSection
            }
            .tabItem { Label("歌曲", systemImage: "music.note.list") }
            
            // 分頁 2：Live 控制 (預覽 + 歌詞段落)
            VStack(spacing: 0) {
                HStack {
                    Text("Live 控制台")
                        .font(.headline)
                    Spacer()
                    replayBackgroundButton
                    layoutMenu
                    if let switchMode {
                        Button {
                            switchToSlides(using: switchMode)
                        } label: {
                            Label("PPT", systemImage: "rectangle.on.rectangle.angled")
                        }
                        .buttonStyle(.bordered)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .zIndex(10)
                livePreviewArea.frame(height: CGFloat(iphoneLivePreviewHeight)).clipped()
                if isLayoutEditing {
                    previewResizeHandle
                } else {
                    Divider()
                }
                lyricSegmentsArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .tabItem { Label("歌詞段落", systemImage: "play.tv.fill") }
            
            // 分頁 3：背景素材庫
            backgroundLibraryArea
            .tabItem { Label("背景", systemImage: "photo.fill") }

            fileManagementArea
            .tabItem { Label("檔案", systemImage: "shippingbox.fill") }
        }
    }
    
    // 💻 iPad 專用的橫向佈局 (你原本的設計)
    private var ipadHStackView: some View {
        HStack(spacing: 0) {
            // 左側資源管理區
            if !isLeftPanelHidden {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // 第一欄
                        VStack(spacing: 18) {
                            sidebarIconButton(title: "所有歌曲", icon: "music.note.list", type: .all)
                            sidebarIconButton(title: "今日流程", icon: "star.fill", type: .today)

                            Spacer()

                            Button {
                                showingFileManagement = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "shippingbox.fill").font(.system(size: 24))
                                    Text("檔案").font(.caption).bold()
                                }
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .foregroundColor(.teal)
                                .background(Color.teal.opacity(0.1))
                                .cornerRadius(8)
                            }

                            Button {
                                showingSongEditor = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 24))
                                    Text("新增歌曲").font(.caption).bold()
                                }
                                .padding(.vertical, 8).padding(.horizontal, 12)
                                .foregroundColor(.blue)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .frame(width: 90)
                        .padding(.vertical, 30)
                        .background(Color(UIColor.systemGray6))

                        Divider()

                        // 第二欄
                        songListSection.frame(maxWidth: .infinity)
                    }

                    Divider()
                    backgroundLibraryArea.frame(height: 400)
                }
                .frame(width: 450)

                Divider()
            }
            
            // 右側 Live 區
            VStack(spacing: 0) {
                HStack {
                    Text("Live 控制台")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    replayBackgroundButton
                    layoutMenu
                    if let switchMode {
                        Button {
                            switchToSlides(using: switchMode)
                        } label: {
                            Label("PPT 簡報", systemImage: "rectangle.on.rectangle.angled")
                        }
                        .buttonStyle(.bordered)
                        .contentShape(Rectangle())
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .zIndex(10)
                
                livePreviewArea.frame(height: CGFloat(ipadLivePreviewHeight)).clipped()
                if isLayoutEditing {
                    previewResizeHandle
                } else {
                    Divider()
                }
                lyricSegmentsArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(UIColor.secondarySystemBackground))
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
}

// MARK: - UI 子組件擴充 (功能皆保留你的原版設計)
extension ContentView {
    
    private func sidebarIconButton(title: String, icon: String, type: LyricManager.SidebarCategory) -> some View {
        Button {
            manager.synchronizeSongsBetweenLists()
            manager.currentCategory = type
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption).bold()
            }
            .foregroundColor(manager.currentCategory == type ? .blue : .gray)
            .frame(maxWidth: .infinity)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            providers.first?.loadObject(ofClass: NSString.self) { string, _ in
                if let songID = string as? String {
                    DispatchQueue.main.async {
                        if let song = manager.allSongs.first(where: { $0.id.uuidString == songID }) {
                            manager.addToSetlist(song)
                        }
                    }
                }
            }
            return true
        }
    }
    
    private var songListSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(manager.currentCategory == .all ? "所有歌曲" : "今日流程")
                    .font(.headline)
                Spacer()
                if isSelectingSongs {
                    Button(selectedSongIDs.count == currentSongList.count ? "取消全選" : "全選") {
                        toggleSelectAllSongs()
                    }
                    .font(.subheadline)
                }
                Button(isSelectingSongs ? "完成" : "選取") {
                    isSelectingSongs.toggle()
                    if !isSelectingSongs {
                        selectedSongIDs.removeAll()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding([.horizontal, .top])

            if isSelectingSongs {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        deleteSelectedSongs()
                    } label: {
                        Label(manager.currentCategory == .all ? "刪除" : "移除", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedSongIDs.isEmpty)

                    Button {
                        moveSelectedSongs()
                    } label: {
                        Label(manager.currentCategory == .all ? "加入今日流程" : "移回所有歌曲", systemImage: manager.currentCategory == .all ? "star.fill" : "music.note.list")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSongIDs.isEmpty)
                }
                .padding(.horizontal)
            }
            
            List {
                ForEach(currentSongList) { song in
                    let displaySong = manager.canonicalSong(for: song)
                    HStack {
                        if isSelectingSongs {
                            Image(systemName: selectedSongIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedSongIDs.contains(song.id) ? .blue : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(displaySong.title).font(.headline)
                            Text("\(displaySong.segments.count) 個段落").font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        if manager.selectedSong?.id == song.id {
                            Image(systemName: "play.circle.fill").foregroundColor(.orange).font(.title3)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectingSongs {
                            toggleSongSelection(song.id)
                        } else {
                            manager.selectedSong = displaySong
                        }
                    }
                    .onDrag { NSItemProvider(object: song.id.uuidString as NSString) }
                    .contextMenu {
                        Button { editingTarget = displaySong } label: { Label("編輯歌曲", systemImage: "pencil") }
                        if manager.currentCategory == .today {
                            Button(role: .destructive) {
                                if let idx = manager.todaySetlist.firstIndex(where: { $0.id == song.id }) {
                                    manager.todaySetlist.remove(at: idx)
                                }
                            } label: { Label("從今日流程移除", systemImage: "minus.circle") }
                        } else {
                            Button(role: .destructive) {
                                if let idx = manager.allSongs.firstIndex(where: { $0.id == song.id }) {
                                    manager.allSongs.remove(at: idx)
                                }
                            } label: { Label("刪除歌曲", systemImage: "trash") }
                        }
                    }
                }
                .onDelete { offsets in
                    if manager.currentCategory == .today {
                        manager.todaySetlist.remove(atOffsets: offsets)
                    } else {
                        manager.allSongs.remove(atOffsets: offsets)
                    }
                }
            }
            .listStyle(.plain)
        }
        .onChange(of: manager.currentCategory) { _, _ in
            selectedSongIDs.removeAll()
            isSelectingSongs = false
        }
    }
    
    private var backgroundLibraryArea: some View {
        BackgroundLibraryPanel(backgroundManager: backgroundManager)
    }

    private var fileManagementArea: some View {
        List {
            Section("可攜式專案包") {
                Picker("匯出格式", selection: $exportFormat) {
                    ForEach(ProjectExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }

                Button {
                    beginProjectExport()
                } label: {
                    Label("匯出歌曲、流程與格式", systemImage: "square.and.arrow.up")
                }

                Button {
                    beginProjectImport()
                } label: {
                    Label("匯入專案包", systemImage: "square.and.arrow.down")
                }
            }

            Section("Web 提詞機") {
                if manager.webServer.isRunning {
                    LabeledContent("網址", value: manager.webServer.urlString ?? "取得中")
                    if let urlString = manager.webServer.urlString {
                        Button {
                            UIPasteboard.general.string = urlString
                            importErrorMessage = "已複製 Web 提詞機網址：\(urlString)"
                        } label: {
                            Label("複製網址", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        manager.stopWebTeleprompter()
                    } label: {
                        Label("停止 Web 提詞機", systemImage: "stop.circle")
                    }
                } else {
                    Text("iPad 開啟後，同一路由器內的手機或電腦可用瀏覽器開啟網址觀看歌詞。")
                        .foregroundColor(.secondary)
                    Button {
                        manager.startWebTeleprompter()
                    } label: {
                        Label("啟動 Web 提詞機", systemImage: "network")
                    }
                }
            }

            Section("目前內容") {
                LabeledContent("歌曲", value: "\(manager.allSongs.count) 首")
                LabeledContent("今日流程", value: "\(manager.todaySetlist.count) 首")
                LabeledContent("背景素材", value: "\(backgroundManager.totalBackgroundCount) 個（不打包）")
                LabeledContent("投放模式", value: manager.projectionMode.title)
            }

            Section("移除所有背景檔") {
                Button(role: .destructive) {
                    backgroundManager.deleteAllBackgrounds()
                } label: {
                    Label("刪除全部背景素材", systemImage: "trash")
                }
            }
            // 💡 新增：App 狀態與內存儀表板
            Section(header: Text("App 資源監測")) {
                HStack {
                    Label("目前執行記憶體", systemImage: "cpu")
                    Spacer()
                    Text(backgroundManager.memoryUsageString)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                HStack {
                    Label("背景素材使用空間", systemImage: "internaldrive")
                    Spacer()
                    Text(backgroundManager.storageUsageString)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var fileManagementToolbar: some View {
        HStack(spacing: 12) {
            Button {
                beginProjectExport()
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                beginProjectImport()
            } label: {
                Label("匯入", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    private func beginProjectExport() {
        exportDocument = manager.exportPackage(format: exportFormat)
        if showingFileManagement {
            showingFileManagement = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingExporter = true
            }
        } else {
            showingExporter = true
        }
    }

    private func beginProjectImport() {
        if showingFileManagement {
            showingFileManagement = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingImporter = true
            }
        } else {
            showingImporter = true
        }
    }
    
    private var livePreviewArea: some View {
        VStack {
            ScaledPreviewView(manager: manager, backgroundManager: backgroundManager) // 💡 替換成下方修正後的結構名稱
                .cornerRadius(8)
                .shadow(radius: 3)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                .padding()
            
            Text("AirPlay 輸出畫面預覽").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
    }

    private var replayBackgroundButton: some View {
        Button {
            backgroundManager.replaySelectedBackground()
        } label: {
            Label("重播背景", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(backgroundManager.selectedBackground?.isVideo != true)
    }

    private var layoutMenu: some View {
        Button {
            showingLayoutSettings = true
        } label: {
            Label("版面", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
    }

    private var layoutSettingsArea: some View {
        Form {
            Section("調整") {
                Toggle("調整版面", isOn: $isLayoutEditing)
                if sizeClass != .compact {
                    Toggle("顯示左側管理欄", isOn: Binding(
                        get: { !isLeftPanelHidden },
                        set: { isLeftPanelHidden = !$0 }
                    ))
                }
            }

            Section("Live 預覽") {
                Picker("預覽大小", selection: previewSizeBinding) {
                    Text("小").tag(PreviewSize.small)
                    Text("中").tag(PreviewSize.medium)
                    Text("大").tag(PreviewSize.large)
                    Text("自訂").tag(PreviewSize.custom)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("高度")
                    Slider(
                        value: currentPreviewHeightBinding,
                        in: sizeClass == .compact ? 160...340 : 240...520,
                        step: 10
                    )
                    Text("\(Int(currentPreviewHeight))")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Section("段落按鈕") {
                Picker("欄數", selection: $segmentColumnCount) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)

                Picker("大小", selection: segmentCardSizeBinding) {
                    Text("小").tag(SegmentCardSize.small)
                    Text("中").tag(SegmentCardSize.medium)
                    Text("大").tag(SegmentCardSize.large)
                    Text("自訂").tag(SegmentCardSize.custom)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("高度")
                    Slider(value: $segmentCardHeight, in: 56...120, step: 4)
                    Text("\(Int(segmentCardHeight))")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Section {
                Button {
                    resetLayoutSettings()
                } label: {
                    Label("重設版面", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private var previewResizeHandle: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 54, height: 5)
        }
        .frame(height: 18)
        .background(Color(UIColor.secondarySystemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let currentHeight = sizeClass == .compact ? iphoneLivePreviewHeight : ipadLivePreviewHeight
                    if resizeStartHeight == nil {
                        resizeStartHeight = currentHeight
                    }
                    let startHeight = resizeStartHeight ?? currentHeight
                    let lowerLimit = sizeClass == .compact ? 160.0 : 240.0
                    let upperLimit = sizeClass == .compact ? 340.0 : 520.0
                    setPreviewHeight(min(max(startHeight + Double(value.translation.height), lowerLimit), upperLimit))
                }
                .onEnded { _ in
                    resizeStartHeight = nil
                }
        )
    }

    private func setPreviewHeight(_ height: Double) {
        if sizeClass == .compact {
            iphoneLivePreviewHeight = height
        } else {
            ipadLivePreviewHeight = height
        }
    }

    private var currentPreviewHeight: Double {
        sizeClass == .compact ? iphoneLivePreviewHeight : ipadLivePreviewHeight
    }

    private var currentPreviewHeightBinding: Binding<Double> {
        Binding(
            get: { currentPreviewHeight },
            set: { setPreviewHeight($0) }
        )
    }

    private var previewSizeBinding: Binding<PreviewSize> {
        Binding(
            get: { PreviewSize(height: currentPreviewHeight, isCompact: sizeClass == .compact) },
            set: { size in
                if let height = size.height(isCompact: sizeClass == .compact) {
                    setPreviewHeight(height)
                }
            }
        )
    }

    private var segmentCardSizeBinding: Binding<SegmentCardSize> {
        Binding(
            get: { SegmentCardSize(height: segmentCardHeight) },
            set: { size in
                if let height = size.height {
                    segmentCardHeight = height
                }
            }
        )
    }

    private func resetLayoutSettings() {
        withAnimation(.easeInOut(duration: 0.2)) {
            ipadLivePreviewHeight = 320
            iphoneLivePreviewHeight = 230
            segmentColumnCount = 3
            segmentCardHeight = 80
            isLeftPanelHidden = false
            isLayoutEditing = false
        }
    }

    private var lyricSegmentsArea: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("當前歌曲段落選擇")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: manager.activeStyle.transitionDuration)) {
                        manager.activeLyricContent = ""
                    }
                } label: {
                    Label("清空文字", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(manager.activeLyricContent.isEmpty)
            }
            .padding([.horizontal, .top])

            if let song = manager.selectedSong {
                ScrollView {
                    LazyVGrid(columns: lyricSegmentColumns, spacing: 10) {
                        ForEach(song.segments) { segment in
                            Button {
                                withAnimation(.easeInOut(duration: song.style.transitionDuration)) {
                                    manager.activeStyle = song.style
                                    manager.activeLyricContent = segment.content
                                }
                            } label: {
                                VStack {
                                    Text(segment.label)
                                        .font(.system(size: 18, weight: .bold))
                                    Text(segment.content)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .opacity(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: CGFloat(segmentCardHeight))
                                .background(manager.activeLyricContent == segment.content ? Color.orange : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(radius: manager.activeLyricContent == segment.content ? 5 : 0)
                            }
                        }
                        Button {
                            withAnimation(.easeInOut(duration: manager.activeStyle.transitionDuration)) { manager.activeLyricContent = "" }
                        } label: {
                            Text("清空文字")
                                .frame(maxWidth: .infinity, minHeight: CGFloat(segmentCardHeight))
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("選取歌曲以顯示段落", systemImage: "hand.tap")
            }
        }
    }

    private var lyricSegmentColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: min(max(segmentColumnCount, 2), 4)
        )
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer {
                if needsStop {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            try manager.importProjectData(data, suggestedFilename: url.lastPathComponent)
        } catch {
            importErrorMessage = "匯入失敗：\(error.localizedDescription)"
        }
    }

    private func switchToSlides(using switchMode: (ProjectionMode) -> Void) {
        manager.projectionMode = .slides
        manager.isSlideBlackout = false
        switchMode(.slides)
    }

    private var currentSongList: [Song] {
        manager.currentCategory == .all ? manager.allSongs : manager.todaySetlist
    }

    private func toggleSongSelection(_ id: UUID) {
        if selectedSongIDs.contains(id) {
            selectedSongIDs.remove(id)
        } else {
            selectedSongIDs.insert(id)
        }
    }

    private func toggleSelectAllSongs() {
        if selectedSongIDs.count == currentSongList.count {
            selectedSongIDs.removeAll()
        } else {
            selectedSongIDs = Set(currentSongList.map(\.id))
        }
    }

    private func deleteSelectedSongs() {
        guard !selectedSongIDs.isEmpty else { return }
        if manager.currentCategory == .all {
            manager.allSongs.removeAll { selectedSongIDs.contains($0.id) }
            manager.todaySetlist.removeAll { selectedSongIDs.contains($0.id) }
            if let selected = manager.selectedSong, selectedSongIDs.contains(selected.id) {
                manager.selectedSong = nil
            }
        } else {
            manager.todaySetlist.removeAll { selectedSongIDs.contains($0.id) }
        }
        selectedSongIDs.removeAll()
    }

    private func moveSelectedSongs() {
        guard !selectedSongIDs.isEmpty else { return }
        if manager.currentCategory == .all {
            let selectedSongs = manager.allSongs.filter { selectedSongIDs.contains($0.id) }
            selectedSongs.forEach { manager.addToSetlist($0) }
            manager.currentCategory = .today
        } else {
            manager.todaySetlist.removeAll { selectedSongIDs.contains($0.id) }
            manager.currentCategory = .all
        }
        selectedSongIDs.removeAll()
        isSelectingSongs = false
    }

}

private enum PreviewSize: Hashable {
    case small
    case medium
    case large
    case custom

    init(height: Double, isCompact: Bool) {
        let small = isCompact ? 180.0 : 260.0
        let medium = isCompact ? 230.0 : 320.0
        let large = isCompact ? 300.0 : 420.0
        if abs(height - small) < 1 {
            self = .small
        } else if abs(height - medium) < 1 {
            self = .medium
        } else if abs(height - large) < 1 {
            self = .large
        } else {
            self = .custom
        }
    }

    func height(isCompact: Bool) -> Double? {
        switch self {
        case .small:
            isCompact ? 180 : 260
        case .medium:
            isCompact ? 230 : 320
        case .large:
            isCompact ? 300 : 420
        case .custom:
            nil
        }
    }
}

private enum SegmentCardSize: Hashable {
    case small
    case medium
    case large
    case custom

    init(height: Double) {
        if abs(height - 64) < 1 {
            self = .small
        } else if abs(height - 80) < 1 {
            self = .medium
        } else if abs(height - 104) < 1 {
            self = .large
        } else {
            self = .custom
        }
    }

    var height: Double? {
        switch self {
        case .small:
            64
        case .medium:
            80
        case .large:
            104
        case .custom:
            nil
        }
    }
}

struct BackgroundLibraryPanel: View {
    @ObservedObject var backgroundManager: BackgroundManager
    private static let thumbnailCache = NSCache<NSURL, UIImage>()

    @State private var selectedPhotosItems: [PhotosPickerItem] = []
    @State private var showingNewBackgroundFolderAlert = false
    @State private var newBackgroundFolderName = ""
    @State private var renamingBackground: BackgroundItem?
    @State private var backgroundRenameText = ""
    @State private var renamingBackgroundFolder: BackgroundFolder?
    @State private var backgroundFolderRenameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            backgroundFolderStrip
            backgroundGrid
        }
        .background(Color(UIColor.secondarySystemBackground))
        .onChange(of: selectedPhotosItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    await backgroundManager.importBackground(from: item)
                }
                selectedPhotosItems = []
            }
        }
        .alert("新增背景資料夾", isPresented: $showingNewBackgroundFolderAlert) {
            TextField("例如：第一堂背景", text: $newBackgroundFolderName)
            Button("建立") {
                backgroundManager.createBackgroundFolder(named: newBackgroundFolderName)
                newBackgroundFolderName = ""
            }
            Button("取消", role: .cancel) {
                newBackgroundFolderName = ""
            }
        } message: {
            Text("不同聚會或不同主題的背景可以分開整理。")
        }
        .alert("重新命名背景", isPresented: Binding(
            get: { renamingBackground != nil },
            set: { if !$0 { renamingBackground = nil } }
        )) {
            TextField("背景名稱", text: $backgroundRenameText)
            Button("儲存") {
                if let renamingBackground {
                    backgroundManager.renameBackground(renamingBackground, to: backgroundRenameText)
                }
                renamingBackground = nil
                backgroundRenameText = ""
            }
            Button("取消", role: .cancel) {
                renamingBackground = nil
                backgroundRenameText = ""
            }
        }
        .alert("重新命名背景資料夾", isPresented: Binding(
            get: { renamingBackgroundFolder != nil },
            set: { if !$0 { renamingBackgroundFolder = nil } }
        )) {
            TextField("資料夾名稱", text: $backgroundFolderRenameText)
            Button("儲存") {
                if let renamingBackgroundFolder {
                    backgroundManager.renameBackgroundFolder(renamingBackgroundFolder, to: backgroundFolderRenameText)
                }
                renamingBackgroundFolder = nil
                backgroundFolderRenameText = ""
            }
            Button("取消", role: .cancel) {
                renamingBackgroundFolder = nil
                backgroundFolderRenameText = ""
            }
        }
    }

    private var header: some View {
        HStack {
            Text("背景素材").font(.headline)
            Section(header: Text("本機素材佔用空間")) {
                HStack {
                    Text(backgroundManager.storageUsageString)
                        .foregroundColor(backgroundManager.storageUsageString.contains("GB") ? .red : .gray)
                }
            }
            Spacer()
            Button {
                showingNewBackgroundFolderAlert = true
            } label: {
                Image(systemName: "folder.badge.plus").font(.title2)
            }
            PhotosPicker(selection: $selectedPhotosItems, matching: .any(of: [.videos, .images])) {
                Image(systemName: "photo.badge.plus").font(.title2)
            }
        }
        .padding([.horizontal, .top])
    }

    private var backgroundFolderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if backgroundManager.backgroundFolders.isEmpty {
                    Button {
                        showingNewBackgroundFolderAlert = true
                    } label: {
                        Label("建立第一個資料夾", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ForEach(backgroundManager.backgroundFolders) { folder in
                        Button {
                            backgroundManager.selectBackgroundFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(folder.id == backgroundManager.activeBackgroundFolder?.id ? .blue : .gray)
                        .contextMenu {
                            Button {
                                renamingBackgroundFolder = folder
                                backgroundFolderRenameText = folder.name
                            } label: {
                                Label("重新命名資料夾", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                backgroundManager.deleteBackgroundFolder(folder)
                            } label: {
                                Label("刪除資料夾", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var backgroundGrid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 15) {
                Button {
                    withAnimation { backgroundManager.selectedBackground = nil }
                } label: {
                    VStack(spacing: 6) {
                        Rectangle().fill(Color.black).frame(height: 80).cornerRadius(8)
                        Text("純黑 (無背景)").font(.system(size: 15))
                    }.foregroundColor(.primary)
                }
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(backgroundManager.selectedBackground == nil ? Color.orange : Color.clear, lineWidth: 3))

                if let folder = backgroundManager.backgroundFolders.first(where: { $0.id == backgroundManager.activeBackgroundFolderID }) {
                    ForEach(folder.backgrounds) { background in
                        Button {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                backgroundManager.selectedBackground = background
                            }
                        } label: {
                            VStack(spacing: 6) {
                                previewImage(for: background)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                Text(background.displayName).font(.system(size: 15)).lineLimit(1)
                            }
                        }
                        .contextMenu {
                            Button {
                                renamingBackground = background
                                backgroundRenameText = background.displayName
                            } label: {
                                Label("重新命名", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                backgroundManager.deleteBackground(background, from: folder.id)
                            } label: {
                                Label("刪除背景", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    Text("請先選擇或建立背景資料夾")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func previewImage(for background: BackgroundItem) -> some View {
        ZStack {
            if background.isVideo {
                if let thumbnail = videoThumbnail(for: background.fileURL) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(alignment: .center) {
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.85))
                        }
                } else {
                    Rectangle().fill(Color.black)
                        .overlay(Image(systemName: "video.fill").foregroundColor(.white.opacity(0.5)))
                }
            } else if let uiImage = UIImage(contentsOfFile: background.fileURL.path) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 100, height: 60)
        .cornerRadius(8)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(backgroundManager.selectedBackground?.id == background.id ? Color.orange : Color.clear, lineWidth: 3))
    }

    private func videoThumbnail(for url: URL) -> UIImage? {
        if let cached = Self.thumbnailCache.object(forKey: url as NSURL) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        let image = UIImage(cgImage: cgImage)
        Self.thumbnailCache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - 💡 修正原本命名衝突的結構 (struct 首字母需大寫)
struct ScaledPreviewView: View {
    @ObservedObject var manager: LyricManager
    @ObservedObject var backgroundManager: BackgroundManager

    let standardWidth: CGFloat = 1920
    let standardHeight: CGFloat = 1080

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / standardWidth
            LiveDisplayView(manager: manager, backgroundManager: backgroundManager)
                .frame(width: standardWidth, height: standardHeight)
                .clipped()
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
}
