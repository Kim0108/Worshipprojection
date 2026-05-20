import SwiftUI
import PhotosUI
import UIKit

struct SlideModeView: View {
    @EnvironmentObject var manager: LyricManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    var switchMode: ((ProjectionMode) -> Void)? = nil
    @State private var selectedSlidePhotoItems: [PhotosPickerItem] = []
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var isReorderingSlides = false

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                ipadLayout
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            manager.projectionMode = .slides
            manager.isSlideBlackout = false
        }
        .onChange(of: selectedSlidePhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await manager.importSlides(from: newItems)
                selectedSlidePhotoItems = []
            }
        }
        .alert("新增簡報資料夾", isPresented: $showingNewFolderAlert) {
            TextField("例如：主日第一堂", text: $newFolderName)
            Button("建立") {
                manager.createSlideFolder(named: newFolderName)
                newFolderName = ""
            }
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("每個資料夾可以放不同場次或不同主題的簡報。")
        }
    }

    private var ipadLayout: some View {
        HStack(spacing: 0) {
            mainPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            slideLibraryPanel
                .frame(width: 380)
                .background(Color(UIColor.secondarySystemBackground))
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        ScaledPreviewView(manager: manager)
                            .frame(maxHeight: geo.size.height * 0.28)
                            .padding(.horizontal, 12)
                        compactControls
                            .padding(.horizontal, 12)
                    }
                    .frame(height: geo.size.height * 0.5)

                    Divider()
                    slideLibraryPanel
                        .frame(height: geo.size.height * 0.5)
                }
            }
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 18) {
                ScaledPreviewView(manager: manager)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                largeControls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PPT 簡報模式")
                    .font(sizeClass == .compact ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                Text("圖片投影片獨立投放，控制與歌詞模式分開。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let switchMode {
                Button {
                    switchMode(.lyricsWithBackground)
                } label: {
                    Label("歌詞＋背景", systemImage: "music.mic")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if sizeClass != .compact {
                Toggle("廣播同步", isOn: Binding(
                    get: { manager.multipeerManager.isActive },
                    set: { isActive in
                        if isActive {
                            manager.multipeerManager.startConnection(role: .broadcaster)
                        } else {
                            manager.multipeerManager.stopAll()
                        }
                    }
                ))
                .toggleStyle(.button)
                .tint(.green)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, sizeClass == .compact ? 12 : 28)
        .padding(.vertical, sizeClass == .compact ? 10 : 18)
    }

    private var largeControls: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pageLabel)
                        .font(.title.weight(.bold))
                    Text(activeSlideName)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                PhotosPicker(selection: $selectedSlidePhotoItems, matching: .images) {
                    Label("加入圖片", systemImage: "photo.badge.plus")
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 14) {
                slideActionButton(
                    title: "上一張",
                    icon: "chevron.left",
                    isDisabled: manager.slideLibrary.isEmpty || manager.activeSlideIndex == 0
                ) {
                    manager.goToPreviousSlide()
                }

                slideActionButton(
                    title: manager.isSlideBlackout ? "恢復畫面" : "黑畫面",
                    icon: manager.isSlideBlackout ? "eye" : "eye.slash",
                    tint: manager.isSlideBlackout ? .green : .black,
                    isDisabled: manager.slideLibrary.isEmpty
                ) {
                    manager.isSlideBlackout.toggle()
                }

                slideActionButton(
                    title: "下一張",
                    icon: "chevron.right",
                    isDisabled: manager.slideLibrary.isEmpty || manager.activeSlideIndex >= manager.slideLibrary.count - 1
                ) {
                    manager.goToNextSlide()
                }
            }
        }
    }

    private var compactControls: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pageLabel)
                        .font(.headline.weight(.bold))
                    Text(activeSlideName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                PhotosPicker(selection: $selectedSlidePhotoItems, matching: .images) {
                    Label("加入", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                compactSlideActionButton(title: "上一張", icon: "chevron.left", isDisabled: manager.slideLibrary.isEmpty || manager.activeSlideIndex == 0) {
                    manager.goToPreviousSlide()
                }
                compactSlideActionButton(title: manager.isSlideBlackout ? "恢復" : "黑畫面", icon: manager.isSlideBlackout ? "eye" : "eye.slash", tint: manager.isSlideBlackout ? .green : .black, isDisabled: manager.slideLibrary.isEmpty) {
                    manager.isSlideBlackout.toggle()
                }
                compactSlideActionButton(title: "下一張", icon: "chevron.right", isDisabled: manager.slideLibrary.isEmpty || manager.activeSlideIndex >= manager.slideLibrary.count - 1) {
                    manager.goToNextSlide()
                }
            }
        }
    }

    private var slideLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("簡報資料夾")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    showingNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                if !manager.slideLibrary.isEmpty {
                    Button(isReorderingSlides ? "完成" : "排序") {
                        isReorderingSlides.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                PhotosPicker(selection: $selectedSlidePhotoItems, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            folderStrip

            Divider()

            if manager.slideLibrary.isEmpty {
                ContentUnavailableView("此資料夾尚未匯入投影片", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(manager.slideLibrary.enumerated()), id: \.element.id) { index, slide in
                        slideRow(slide, index: index)
                            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    }
                    .onDelete(perform: manager.deleteSlides)
                    .onMove(perform: manager.moveSlides)
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isReorderingSlides ? .active : .inactive))
            }
        }
    }

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if manager.slideFolders.isEmpty {
                    Button {
                        showingNewFolderAlert = true
                    } label: {
                        Label("建立第一個資料夾", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ForEach(manager.slideFolders) { folder in
                        Button {
                            manager.selectSlideFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(folder.id == manager.activeSlideFolder?.id ? .blue : .gray)
                        .contextMenu {
                            Button(role: .destructive) {
                                manager.deleteSlideFolder(folder)
                            } label: {
                                Label("刪除資料夾", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var pageLabel: String {
        guard !manager.slideLibrary.isEmpty else { return "尚未匯入投影片" }
        return "第 \(manager.activeSlideIndex + 1) / \(manager.slideLibrary.count) 張"
    }

    private var activeSlideName: String {
        guard let slide = manager.activeSlide else {
            return manager.slideLibrary.isEmpty ? "加入圖片後即可開始投放" : "目前為黑畫面"
        }
        return slide.displayName
    }

    private func slideActionButton(
        title: String,
        icon: String,
        tint: Color = .blue,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 76)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isDisabled)
    }

    private func compactSlideActionButton(
        title: String,
        icon: String,
        tint: Color = .blue,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isDisabled)
    }

    private func slideRow(_ slide: SlideItem, index: Int) -> some View {
        Button {
            manager.selectSlide(slide)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if let uiImage = UIImage(contentsOfFile: slide.fileURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    }
                }
                .frame(width: sizeClass == .compact ? 116 : 132, height: sizeClass == .compact ? 66 : 74)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(slide.displayName)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("拖移右側把手可調整順序")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .background(Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(index == manager.activeSlideIndex && !manager.isSlideBlackout ? Color.orange : Color.clear)
                .frame(width: 4)
        }
        .contextMenu {
            Button(role: .destructive) {
                manager.deleteSlide(slide)
            } label: {
                Label("刪除投影片", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                manager.deleteSlide(slide)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                manager.deleteSlide(slide)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}
