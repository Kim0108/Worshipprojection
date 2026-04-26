import SwiftUI
import PhotosUI

struct ContentView: View {
    @EnvironmentObject var manager: LyricManager
    
    @State private var showingSongEditor = false
    @State private var editingTarget: Song? = nil
    @State private var selectedPhotosItem: PhotosPickerItem? = nil
    
    // --- 原有命名相關狀態 ---
    @State private var showNamingAlert = false
    @State private var tempName = ""

    var body: some View {
        HStack(spacing: 0) {
            // ==========================================
            // 1. 左側資源管理區 (固定寬度 450)
            // ==========================================
            VStack(spacing: 0) {
                // 左上：分類與清單 (第一欄 + 第二欄)
                HStack(spacing: 0) {
                    // 第一欄：圖示選單
                    VStack(spacing: 30) {
                        sidebarIconButton(title: "所有歌曲", icon: "music.note.list", type: .all)
                        sidebarIconButton(title: "今日流程", icon: "star.fill", type: .today)
                        
                        Spacer()
                        
                        Button {
                            showingSongEditor = true
                        } label: {
                            VStack(spacing: 6) { // spacing 控制圖示與文字之間的上下距離
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24)) // 讓圖示大一點，凸顯重點
                                Text("新增歌曲")
                                    .font(.caption)          // 使用 caption (說明文字) 大小，符合 Sidebar 風格
                                    .bold()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .foregroundColor(.blue)          // 設定統一的主題色
                            .background(Color.blue.opacity(0.1)) // 加上淡淡的透明背景，增加按鈕的點擊感
                            .cornerRadius(8)                 // 圓角處理
                        }
//                        Button { showingSongEditor = true } label: {
//                            Image(systemName: "plus.circle.fill")
//                                .font(.system(size: 36))
//                                .foregroundColor(.blue)
//                        Text("新增歌曲")
//                            .font(.system(size: 14))
//                            .foregroundColor(.blue)
//                            .padding(.bottom, 10)
//
//                        }
                    }
                    .frame(width: 90)
                    .padding(.vertical, 30)
                    .background(Color(UIColor.systemGray6))
                    
                    Divider()
                    
                    // 第二欄：歌曲列表
                    songListSection
                        .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // 左下：背景素材庫 (維持你喜歡的區塊)
                backgroundLibraryArea
                    .frame(height: 400)
            }
            .frame(width: 450)
            
            Divider()
            
            // ==========================================
            // 2. 右側 Live 控制區 (自動填滿)
            // ==========================================
            VStack(spacing: 0) {
                // 右上：Master Preview (16:9 預覽)
                Text("Live控制區").font(.title).foregroundColor(.red).bold()
                livePreviewArea
                    .frame(height: 400)
                    .clipped()
                
                Divider()
                
                // 右下：段落控制按鈕
                lyricSegmentsArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(UIColor.secondarySystemBackground))
        }
        .ignoresSafeArea(.all, edges: .bottom)
        
        // --- 彈跳視窗與邏輯 (原封不動保留) ---
        .sheet(isPresented: Binding(
            get: { showingSongEditor || editingTarget != nil },
            set: { if !$0 { showingSongEditor = false; editingTarget = nil } }
        )) {
            SongEditorView(manager: manager, editingSong: editingTarget)
        }
        .onChange(of: selectedPhotosItem) { newItem in
            if newItem != nil {
                // 選取後不立刻匯入，先清空名稱並跳出對話框
                tempName = ""
                showNamingAlert = true
            }
        }
        .alert("命名素材", isPresented: $showNamingAlert) {
            TextField("輸入背景名稱 (例如：動態星空)", text: $tempName)
            Button("確定") {
                if let item = selectedPhotosItem {
                    Task {
                        // 呼叫我們修改過、支援 customName 的匯入函式
                        await manager.importBackground(from: item, customName: tempName)
                        selectedPhotosItem = nil // 處理完後重置
                    }
                }
            }
            Button("取消", role: .cancel) {
                selectedPhotosItem = nil // 取消也要重置，否則下次選同檔案不會觸發 onChange
            }
        } message: {
            Text("請為此素材取一個好辨識的名字，這將顯示在背景庫中。")
        }
    }
}

// MARK: - UI 子組件擴充
extension ContentView {
    
    // ⭐️ 第一欄：側邊欄按鈕 (具備 Drop 功能，接收拖曳進來的歌)
    private func sidebarIconButton(title: String, icon: String, type: LyricManager.SidebarCategory) -> some View {
        Button {
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
    
    // ⭐️ 第二欄：歌曲列表 (具備 Drag 功能與右鍵編輯/刪除)
    private var songListSection: some View {
            // 💡 融合第二段的外層結構：帶有標題與新增按鈕的 VStack
            VStack(alignment: .leading) {
                HStack {
                    // 讓標題根據目前的分類動態改變
                    Text(manager.currentCategory == .all ? "所有歌曲" : "今日流程")
                        .font(.headline)
                    Spacer()
//                    Button { showingSongEditor = true } label: {
//                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.blue)
//                    }
                }
                .padding([.horizontal, .top])
                
                // 💡 融合第一段的精緻 List 內容與強大功能 (拖曳、雙分類、播放圖示)
                List {
                    let list = manager.currentCategory == .all ? manager.allSongs : manager.todaySetlist
                    
                    ForEach(list) { song in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(song.title).font(.headline)
                                Text("\(song.segments.count) 個段落").font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            // 選中時顯示橘色播放鍵 (第一段的 UI)
                            if manager.selectedSong?.id == song.id {
                                Image(systemName: "play.circle.fill").foregroundColor(.orange).font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { manager.selectedSong = song } // 使用點擊取代 NavigationLink，以適配三欄式佈局
                        .onDrag { NSItemProvider(object: song.id.uuidString as NSString) } // 支援拖曳
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
                                        manager.deleteSong(at: IndexSet(integer: idx))
                                    }
                                } label: { Label("刪除歌曲", systemImage: "trash") }
                            }
                        }
                    }
                    .onDelete { offsets in
                        if manager.currentCategory == .today {
                            manager.removeFromSetlist(at: offsets)
                        } else {
                            manager.deleteSong(at: offsets)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    // 左下：背景庫區塊 (原汁原味保留)
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
            
            // 💡 1. 改成垂直 ScrollView，讓內容往上下延伸
            ScrollView(.vertical, showsIndicators: true) {
                // 💡 2. 定義網格欄位（例如每列固定顯示 2 或 3 個）
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(manager.backgroundLibrary) { bg in
                        Button {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                manager.selectedBackground = bg
                            }
                        } label: {
                            VStack(spacing: 6) {
                                // 💡 3. 調整 previewImage 的大小，讓它在網格中變大
                                previewImage(for: bg)
                                    .frame(maxWidth: .infinity) // 寬度自動填滿網格
                                    .frame(height: 80)        // 高度加高 (原本可能是 60)
                                
                                Text(bg.displayName)
                                    .font(.system(size: 15))   // 字體稍微調大
                                    .lineLimit(1)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let index = manager.backgroundLibrary.firstIndex(where: { $0.id == bg.id }) {
                                    manager.deleteBackground(at: IndexSet(integer: index))
                                }
                            } label: {
                                Label("刪除背景", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(height: 400) // 你設定的高度
        .background(Color(UIColor.secondarySystemBackground))
    }
    //右上：livePreviewArea
    private var livePreviewArea: some View {
        VStack {
            LiveDisplayView(manager: manager) // 直接套用封裝好的組件
                .aspectRatio(16/9, contentMode: .fit)
//            ScaledPreviewView(manager: manager) // 新的寫法：等比縮放畫布，如要使用記得把上面兩行//掉
                .cornerRadius(12)
                .shadow(radius: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.8), lineWidth: 2) // 紅框代表正在直播
                )
                .padding()
            
            Text("AirPlay 輸出畫面預覽").font(.title2).foregroundColor(.gray).bold()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
    }

    // 右下：段落控制區 (0424修改好了)
    private var lyricSegmentsArea: some View {
        VStack(alignment: .leading) {
            Text("當前歌曲段落選擇").font(.headline).padding([.horizontal, .top])
            
            if let song = manager.selectedSong {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(song.segments) { segment in
                            Button {
                                // 💡 關鍵修正：點擊時，同時將「樣式」與「內容」推播到 Live 畫面
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
                            withAnimation(.easeInOut(duration: 0.5)) {
                                manager.activeLyricContent = ""
                            }
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
        .frame(height: 375) //原本250 0423!!
    }
//Preview 修改好了0424
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
    
// MARK: - beta2複製來的：等比縮放預覽區組件 0424修改好了
struct livePreviewArea: View {
    @ObservedObject var manager: LyricManager

    // 定義我們的標準外接螢幕解析度 (通常是 1080p, 16:9)
    let standardWidth: CGFloat = 1920
    let standardHeight: CGFloat = 1080

    var body: some View {
        GeometryReader { geo in
            // 計算 iPad 預覽框目前的寬度，與 1920 的比例
            let scale = geo.size.width / standardWidth

            LiveDisplayView(manager: manager)
                // 1. 強迫用 1920x1080 的真實解析度來渲染 (字體 80 就是相對於這個畫布)
                .frame(width: standardWidth, height: standardHeight)
                .clipped()
                // 2. 將這個巨大的畫布，從左上角開始等比縮小到符合 geo 的大小
                .scaleEffect(scale, anchor: .topLeading)
        }
        // 3. 限制這個元件的外框永遠保持 16:9，才不會多出空白吃掉 iPad 的排版空間
        .aspectRatio(16/9, contentMode: .fit)
    }
}



// MARK: - beta2的ContentView
//import SwiftUI
//import PhotosUI
//
//struct ContentView: View {
//    @EnvironmentObject var manager: LyricManager
//    
//    @State private var showingSongEditor = false
//    @State private var editingTarget: Song? = nil
//    @State private var selectedPhotosItem: PhotosPickerItem? = nil
//    
//    // --- 1. 新增命名相關狀態 ---
//    @State private var showNamingAlert = false
//    @State private var tempName = ""
//
//    var body: some View {
//        NavigationSplitView {
//            sidebarSection
//        } detail: {
//            HStack(spacing: 0) {
//                leftResourceColumn
//                Divider()
//                rightControlColumn
//            }
//            .navigationTitle("                                                   Live 控制台")
//            .navigationBarTitleDisplayMode(.inline)
//        }
//        .sheet(isPresented: Binding(
//            get: { showingSongEditor || editingTarget != nil },
//            set: { if !$0 { showingSongEditor = false; editingTarget = nil } }
//        )) {
//            SongEditorView(manager: manager, editingSong: editingTarget)
//        }
//        // --- 2. 修改 onChange 邏輯 ---
//        .onChange(of: selectedPhotosItem) { newItem in
//            if newItem != nil {
//                // 選取後不立刻匯入，先清空名稱並跳出對話框
//                tempName = ""
//                showNamingAlert = true
//            }
//        }
//        // --- 3. 實作命名對話框 ---
//        .alert("命名素材", isPresented: $showNamingAlert) {
//            TextField("輸入背景名稱 (例如：動態星空)", text: $tempName)
//            Button("確定") {
//                if let item = selectedPhotosItem {
//                    Task {
//                        // 呼叫我們修改過、支援 customName 的匯入函式
//                        await manager.importBackground(from: item, customName: tempName)
//                        selectedPhotosItem = nil // 處理完後重置
//                    }
//                }
//            }
//            Button("取消", role: .cancel) {
//                selectedPhotosItem = nil // 取消也要重置，否則下次選同檔案不會觸發 onChange
//            }
//        } message: {
//            Text("請為此素材取一個好辨識的名字，這將顯示在背景庫中。")
//        }
//    }
//}
//// MARK: - Sub-views 拆解
//extension ContentView {
//    private var sidebarSection: some View {
//        List {
//            NavigationLink(destination: Text("所有歌曲清單")) {
//                Label("所有歌曲", systemImage: "music.note.list")
//            }
//            Section("我的資料夾") {
//                Text("暫無資料夾").foregroundColor(.gray).font(.caption)
//            }
//        }
//        .navigationTitle("資料夾")
//    }
//    
//    private var leftResourceColumn: some View {
//        VStack(spacing: 0) {
//            songSelectionArea
//            Divider()
//            backgroundLibraryArea
//        }
//        .frame(width: 400) //原本320 0423!!
//    }
//    
//    private var rightControlColumn: some View {
//        VStack(spacing: 0) {
//            livePreviewArea
//            Divider()
//            segmentControlArea
//        }
//        .frame(maxWidth: .infinity)
//    }
//    
//    private var songSelectionArea: some View {
//        VStack(alignment: .leading) {
//            HStack {
//                Text("歌曲選擇").font(.headline)
//                Spacer()
//                Button { showingSongEditor = true } label: {
//                    Image(systemName: "plus.circle.fill").font(.title3)
//                }
//            }
//            .padding([.horizontal, .top])
//            
//            List(selection: $manager.selectedSong) {
//                ForEach(manager.allSongs) { song in
//                    NavigationLink(value: song) {
//                        VStack(alignment: .leading) {
//                            Text(song.title).font(.headline)
//                            Text("\(song.segments.count) 個段落").font(.caption).foregroundColor(.gray)
//                        }
//                    }
//                    .contextMenu {
//                        Button("編輯歌詞") { editingTarget = song }
//                        Button(role: .destructive) {
//                            if let index = manager.allSongs.firstIndex(where: { $0.id == song.id }) {
//                                manager.allSongs.remove(at: index)
//                            }
//                        } label: {
//                            Label("刪除", systemImage: "trash")
//                        }
//                    }
//                }
//            }
//            .listStyle(.plain)
//        }
//    }
//  
//    private var backgroundLibraryArea: some View {
//        VStack(alignment: .leading, spacing: 15) {
//            HStack {
//                Text("背景素材").font(.headline)
//                Spacer()
//                PhotosPicker(selection: $selectedPhotosItem, matching: .any(of: [.videos, .images])) {
//                    Image(systemName: "photo.badge.plus").font(.title3)
//                }
//            }
//            .padding([.horizontal, .top])
//
//            // 💡 1. 改成垂直 ScrollView，讓內容往上下延伸
//            ScrollView(.vertical, showsIndicators: true) {
//                // 💡 2. 定義網格欄位（例如每列固定顯示 2 或 3 個）
//                let columns = [
//                    GridItem(.flexible(), spacing: 12),
//                    GridItem(.flexible(), spacing: 12)
//                ]
//                
//                LazyVGrid(columns: columns, spacing: 15) {
//                    ForEach(manager.backgroundLibrary) { bg in
//                        Button {
//                            withAnimation(.easeInOut(duration: 1.0)) {
//                                manager.selectedBackground = bg
//                            }
//                        } label: {
//                            VStack(spacing: 6) {
//                                // 💡 3. 調整 previewImage 的大小，讓它在網格中變大
//                                previewImage(for: bg)
//                                    .frame(maxWidth: .infinity) // 寬度自動填滿網格
//                                    .frame(height: 80)        // 高度加高 (原本可能是 60)
//                                
//                                Text(bg.displayName)
//                                    .font(.system(size: 15))   // 字體稍微調大
//                                    .lineLimit(1)
//                            }
//                        }
//                        .contextMenu {
//                            Button(role: .destructive) {
//                                if let index = manager.backgroundLibrary.firstIndex(where: { $0.id == bg.id }) {
//                                    manager.deleteBackground(at: IndexSet(integer: index))
//                                }
//                            } label: {
//                                Label("刪除背景", systemImage: "trash")
//                            }
//                        }
//                    }
//                }
//                .padding(.horizontal)
//            }
//        }
//        .frame(height: 400) // 你設定的高度
//        .background(Color(UIColor.secondarySystemBackground))
//    }
//    
//    // 💡 核心修正：讓 LivePreviewArea 非常乾淨，只負責呼叫組件
//    private var livePreviewArea: some View {
//        VStack {
//            LiveDisplayView(manager: manager) // 直接套用封裝好的組件
//                .aspectRatio(16/9, contentMode: .fit)
//            //ScaledPreviewView(manager: manager) // 新的寫法：等比縮放畫布，如要使用記得把上面兩行//掉
//                .cornerRadius(12)
//                .shadow(radius: 5)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12)
//                        .stroke(Color.red.opacity(0.8), lineWidth: 2) // 紅框代表正在直播
//                )
//                .padding()
//            
//            Text("AirPlay 輸出畫面預覽").font(.caption).foregroundColor(.gray)
//            Spacer()
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(Color.black.opacity(0.05))
//    }
//    
//    private var segmentControlArea: some View {
//        VStack(alignment: .leading) {
//            Text("當前歌曲段落選擇").font(.headline).padding([.horizontal, .top])
//            
//            if let song = manager.selectedSong {
//                ScrollView {
//                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
//                        ForEach(song.segments) { segment in
//                            Button {
//                                // 💡 關鍵修正：點擊時，同時將「樣式」與「內容」推播到 Live 畫面
//                                withAnimation(.easeInOut(duration: 0.5)) {
//                                    manager.activeStyle = song.style
//                                    manager.activeLyricContent = segment.content
//                                }
//                            } label: {
//                                VStack {
//                                    Text(segment.label).font(.system(size: 18, weight: .bold))
//                                    Text(segment.content).font(.system(size: 10)).lineLimit(1).opacity(0.7)
//                                }
//                                .frame(maxWidth: .infinity, minHeight: 80)
//                                .background(manager.activeLyricContent == segment.content ? Color.orange : Color.blue)
//                                .foregroundColor(.white)
//                                .cornerRadius(12)
//                                .shadow(radius: manager.activeLyricContent == segment.content ? 5 : 0)
//                            }
//                        }
//                        
//                        Button {
//                            withAnimation(.easeInOut(duration: 0.5)) {
//                                manager.activeLyricContent = ""
//                            }
//                        } label: {
//                            Text("清空文字")
//                                .frame(maxWidth: .infinity, minHeight: 80)
//                                .background(Color.gray.opacity(0.3))
//                                .cornerRadius(12)
//                        }
//                    }
//                    .padding()
//                }
//            } else {
//                ContentUnavailableView("選取歌曲以顯示段落", systemImage: "hand.tap")
//            }
//        }
//        .frame(height: 375) //原本250 0423!!
//    }
//    @ViewBuilder
//    private func previewImage(for bg: BackgroundItem) -> some View {
//        ZStack {
//            if bg.isVideo {
//                Rectangle().fill(Color.black)
//                    .overlay(Image(systemName: "video.fill").foregroundColor(.white.opacity(0.5)))
//            } else if let uiImage = UIImage(contentsOfFile: bg.fileURL.path) {
//                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
//            } else {
//                Rectangle().fill(Color.gray.opacity(0.3))
//            }
//        }
//        .frame(width: 100, height: 60)
//        .cornerRadius(8)
//        .clipped()
//        .overlay(RoundedRectangle(cornerRadius: 8)
//            .stroke(manager.selectedBackground?.id == bg.id ? Color.orange : Color.clear, lineWidth: 3))
//    }
//
//}
//// MARK: - 等比縮放預覽區組件
//struct ScaledPreviewView: View {
//    @ObservedObject var manager: LyricManager
//    
//    // 定義我們的標準外接螢幕解析度 (通常是 1080p, 16:9)
//    let standardWidth: CGFloat = 1920
//    let standardHeight: CGFloat = 1080
//    
//    var body: some View {
//        GeometryReader { geo in
//            // 計算 iPad 預覽框目前的寬度，與 1920 的比例
//            let scale = geo.size.width / standardWidth
//            
//            LiveDisplayView(manager: manager)
//                // 1. 強迫用 1920x1080 的真實解析度來渲染 (字體 80 就是相對於這個畫布)
//                .frame(width: standardWidth, height: standardHeight)
//                .clipped()
//                // 2. 將這個巨大的畫布，從左上角開始等比縮小到符合 geo 的大小
//                .scaleEffect(scale, anchor: .topLeading)
//        }
//        // 3. 限制這個元件的外框永遠保持 16:9，才不會多出空白吃掉 iPad 的排版空間
//        .aspectRatio(16/9, contentMode: .fit)
//    }
//}
