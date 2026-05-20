import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject var manager: LyricManager
    
    // 偵測螢幕大小 (iPhone 會是 .compact，iPad 橫向會是 .regular)
    @Environment(\.horizontalSizeClass) var sizeClass
    
    @State private var showingSongEditor = false
    @State private var editingTarget: Song? = nil
    @State private var selectedPhotosItem: PhotosPickerItem? = nil
    
    @State private var showNamingAlert = false
    @State private var tempName = ""
    
    // ⭐️ 舞台同步的狀態控制
    @State private var showStageDisplay = false

    var body: some View {
        Group {
            // 💡 根據設備自動切換排版
            if sizeClass == .compact {
                iphoneTabView
            } else {
                ipadHStackView
            }
        }
        // ⭐️ 進入舞台提詞機全螢幕畫面
        .fullScreenCover(isPresented: $showStageDisplay) {
            // 注意：這裡需要確保你已經建立了我們上一部討論的 StageDisplayView
            StageDisplayView(multipeerManager: manager.multipeerManager)
        }
        .sheet(isPresented: Binding(
            get: { showingSongEditor || editingTarget != nil },
            set: { if !$0 { showingSongEditor = false; editingTarget = nil } }
        )) {
            SongEditorView(manager: manager, editingSong: editingTarget)
        }
        .onChange(of: selectedPhotosItem) { newItem in
            if newItem != nil {
                tempName = ""
                showNamingAlert = true
            }
        }
        .alert("命名素材", isPresented: $showNamingAlert) {
            TextField("輸入背景名稱 (例如：動態星空)", text: $tempName)
            Button("確定") {
                if let item = selectedPhotosItem {
                    Task {
                        // 確保 manager 內有這個方法
                        await manager.importBackground(from: item, customName: tempName)
                        selectedPhotosItem = nil
                    }
                }
            }
            Button("取消", role: .cancel) {
                selectedPhotosItem = nil
            }
        } message: {
            Text("請為此素材取一個好辨識的名字，這將顯示在背景庫中。")
        }
    }
}

// MARK: - 📱 iPhone 與 iPad 專屬佈局
extension ContentView {
    
    // 📱 iPhone 專用的底部 TabView 佈局
    private var iphoneTabView: some View {
        TabView {
            // 分頁 1：歌曲清單
            VStack {
                HStack {
                    sidebarIconButton(title: "所有歌曲", icon: "music.note.list", type: .all)
                    sidebarIconButton(title: "今日流程", icon: "star.fill", type: .today)
                    
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
                livePreviewArea.frame(height: 250).clipped()
                Divider()
                lyricSegmentsArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(UIColor.secondarySystemBackground))
            .tabItem { Label("Live 控制", systemImage: "play.tv.fill") }
            
            // 分頁 3：背景素材庫
            backgroundLibraryArea
            .tabItem { Label("背景", systemImage: "photo.fill") }
            
            // 分頁 4：舞台同步設定
            multipeerControlArea
            .tabItem { Label("多螢幕同步", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
    
    // 💻 iPad 專用的橫向佈局 (你原本的設計)
    private var ipadHStackView: some View {
        HStack(spacing: 0) {
            // 左側資源管理區
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 第一欄
                    VStack(spacing: 30) {
                        sidebarIconButton(title: "所有歌曲", icon: "music.note.list", type: .all)
                        sidebarIconButton(title: "今日流程", icon: "star.fill", type: .today)
                        
                        Spacer()
                        
                        // ⭐️ 舞台同步按鈕 (iPad 放這裡)
                        Button {
                            showStageDisplay = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "display.2").font(.system(size: 24))
                                Text("提詞機").font(.caption).bold()
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .foregroundColor(.purple)
                            .background(Color.purple.opacity(0.1))
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
            
            // 右側 Live 區
            VStack(spacing: 0) {
                HStack {
                    Text("Live 控制台").font(.title).foregroundColor(.red).bold()
                    Spacer()
                    // ⭐️ 主控端廣播開關
                    Toggle("廣播同步", isOn: Binding(
                        get: { manager.multipeerManager.isHosting },
                        set: { isHosting in
                            if isHosting { manager.multipeerManager.startHosting() }
                            else { manager.multipeerManager.stopAll() }
                        }
                    ))
                    .toggleStyle(.button)
                    .tint(.green)
                }
                .padding()
                
                livePreviewArea.frame(height: 400).clipped()
                Divider()
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
        Button { manager.currentCategory = type } label: {
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
            }
            .padding([.horizontal, .top])
            
            List {
                let list = manager.currentCategory == .all ? manager.allSongs : manager.todaySetlist
                ForEach(list) { song in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(song.title).font(.headline)
                            Text("\(song.segments.count) 個段落").font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        if manager.selectedSong?.id == song.id {
                            Image(systemName: "play.circle.fill").foregroundColor(.orange).font(.title3)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { manager.selectedSong = song }
                    .onDrag { NSItemProvider(object: song.id.uuidString as NSString) }
                    .contextMenu {
                        Button { editingTarget = song } label: { Label("編輯歌曲", systemImage: "pencil") }
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
    }
    
    private var backgroundLibraryArea: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("背景素材").font(.headline)
                Spacer()
                PhotosPicker(selection: $selectedPhotosItem, matching: .any(of: [.videos, .images])) {
                    Image(systemName: "photo.badge.plus").font(.title3)
                }
            }
            .padding([.horizontal, .top])
            
            ScrollView(.vertical, showsIndicators: true) {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 15) {
                    // 加入清空背景的選項
                    Button {
                        withAnimation { manager.selectedBackground = nil }
                    } label: {
                        VStack(spacing: 6) {
                            Rectangle().fill(Color.black).frame(height: 80).cornerRadius(8)
                            Text("純黑 (無背景)").font(.system(size: 15))
                        }.foregroundColor(.primary)
                    }
                    
                    ForEach(manager.backgroundLibrary) { bg in
                        Button {
                            withAnimation(.easeInOut(duration: 1.0)) { manager.selectedBackground = bg }
                        } label: {
                            VStack(spacing: 6) {
                                previewImage(for: bg)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                Text(bg.displayName).font(.system(size: 15)).lineLimit(1)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let index = manager.backgroundLibrary.firstIndex(where: { $0.id == bg.id }) {
                                    // 確保 LyricManager 中有對應的刪除邏輯
                                    manager.backgroundLibrary.remove(at: index)
                                }
                            } label: { Label("刪除背景", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
    
    private var livePreviewArea: some View {
        VStack {
            ScaledPreviewView(manager: manager) // 💡 替換成下方修正後的結構名稱
                .cornerRadius(12)
                .shadow(radius: 5)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.8), lineWidth: 2))
                .padding()
            
            Text("AirPlay 輸出畫面預覽").font(.headline).foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
    }

    private var lyricSegmentsArea: some View {
        VStack(alignment: .leading) {
            Text("當前歌曲段落選擇").font(.headline).padding([.horizontal, .top])
            if let song = manager.selectedSong {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(song.segments) { segment in
                            Button {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    manager.activeStyle = song.style
                                    manager.activeLyricContent = segment.content
                                }
                            } label: {
                                VStack {
                                    Text(segment.label).font(.system(size: 18, weight: .bold))
                                    Text(segment.content).font(.system(size: 10)).lineLimit(1).opacity(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .background(manager.activeLyricContent == segment.content ? Color.orange : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(radius: manager.activeLyricContent == segment.content ? 5 : 0)
                            }
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.5)) { manager.activeLyricContent = "" }
                        } label: {
                            Text("清空文字")
                                .frame(maxWidth: .infinity, minHeight: 80)
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
    
    // iPhone 專用的連線面板
    private var multipeerControlArea: some View {
        List {
            Section("主控台廣播設定") {
                Toggle("開啟廣播同步", isOn: Binding(
                    get: { manager.multipeerManager.isHosting },
                    set: { isHosting in
                        if isHosting { manager.multipeerManager.startHosting() }
                        else { manager.multipeerManager.stopAll() }
                    }
                ))
                if manager.multipeerManager.isHosting {
                    Text("已連線設備：\(manager.multipeerManager.connectedPeers.count) 台")
                        .foregroundColor(.green)
                }
            }
            Section("接收端設定") {
                Button(action: { showStageDisplay = true }) {
                    Label("進入舞台提詞機畫面", systemImage: "display.2")
                }
            }
        }
        .navigationTitle("多螢幕同步")
    }

    @ViewBuilder
    private func previewImage(for bg: BackgroundItem) -> some View {
        ZStack {
            if bg.isVideo {
                Rectangle().fill(Color.black)
                    .overlay(Image(systemName: "video.fill").foregroundColor(.white.opacity(0.5)))
            } else if let uiImage = UIImage(contentsOfFile: bg.fileURL.path) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 100, height: 60)
        .cornerRadius(8)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(manager.selectedBackground?.id == bg.id ? Color.orange : Color.clear, lineWidth: 3))
    }
}
    
// MARK: - 💡 修正原本命名衝突的結構 (struct 首字母需大寫)
struct ScaledPreviewView: View {
    @ObservedObject var manager: LyricManager

    let standardWidth: CGFloat = 1920
    let standardHeight: CGFloat = 1080

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / standardWidth
            LiveDisplayView(manager: manager)
                .frame(width: standardWidth, height: standardHeight)
                .clipped()
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
}
