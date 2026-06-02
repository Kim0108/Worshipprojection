import SwiftUI
import PhotosUI
import UIKit

struct SlideLibraryPanel: View {
    @ObservedObject var manager: LyricManager
    let sizeClass: UserInterfaceSizeClass?
    @Binding var selectedSlidePhotoItems: [PhotosPickerItem]
    @Binding var showingNewFolderAlert: Bool
    @Binding var showingPDFImporter: Bool
    @Binding var isReorderingSlides: Bool
    @State private var folderPendingRename: SlideFolder?
    @State private var slidePendingRename: SlideItem?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            folderStrip
            Divider()
            slideList
        }
        .alert("重新命名資料夾", isPresented: Binding(
            get: { folderPendingRename != nil },
            set: { if !$0 { folderPendingRename = nil } }
        )) {
            TextField("資料夾名稱", text: $renameText)
            Button("儲存") {
                if let folderPendingRename {
                    manager.renameSlideFolder(folderPendingRename, to: renameText)
                }
                folderPendingRename = nil
                renameText = ""
            }
            Button("取消", role: .cancel) {
                folderPendingRename = nil
                renameText = ""
            }
        }
        .alert("重新命名投影片", isPresented: Binding(
            get: { slidePendingRename != nil },
            set: { if !$0 { slidePendingRename = nil } }
        )) {
            TextField("投影片名稱", text: $renameText)
            Button("儲存") {
                if let slidePendingRename {
                    manager.renameSlide(slidePendingRename, to: renameText)
                }
                slidePendingRename = nil
                renameText = ""
            }
            Button("取消", role: .cancel) {
                slidePendingRename = nil
                renameText = ""
            }
        }
    }

    private var header: some View {
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

            Button {
                showingPDFImporter = true
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
                            Button {
                                startRenaming(folder)
                            } label: {
                                Label("重新命名", systemImage: "pencil")
                            }

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

    @ViewBuilder
    private var slideList: some View {
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

    private func slideRow(_ slide: SlideItem, index: Int) -> some View {
        Button {
            manager.selectSlide(slide)
        } label: {
            HStack(spacing: 12) {
                slideThumbnail(slide)
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
            Button {
                startRenaming(slide)
            } label: {
                Label("重新命名", systemImage: "pencil")
            }

            Button(role: .destructive) {
                manager.deleteSlide(slide)
            } label: {
                Label("刪除投影片", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                startRenaming(slide)
            } label: {
                Label("重新命名", systemImage: "pencil")
            }
            .tint(.blue)

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

    private func startRenaming(_ folder: SlideFolder) {
        renameText = folder.name
        slidePendingRename = nil
        folderPendingRename = folder
    }

    private func startRenaming(_ slide: SlideItem) {
        renameText = slide.displayName
        folderPendingRename = nil
        slidePendingRename = slide
    }

    private func slideThumbnail(_ slide: SlideItem) -> some View {
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
    }
}
