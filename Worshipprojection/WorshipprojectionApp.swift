import SwiftUI
import UIKit
internal import UniformTypeIdentifiers

@main
struct WorshipProjectionApp: App {
    @StateObject private var lyricManager = LyricManager()
    @StateObject private var externalDisplayManager: ExternalDisplayManager

    init() {
        // 只在這裡建立唯一的 Source of Truth
        let sharedManager = LyricManager()
        _lyricManager = StateObject(wrappedValue: sharedManager)
        _externalDisplayManager = StateObject(wrappedValue: ExternalDisplayManager(manager: sharedManager))
    }

    var body: some Scene {
        WindowGroup {
            RoleGateView()
                .environmentObject(lyricManager)
        }
    }
}

struct RoleGateView: View {
    @EnvironmentObject var manager: LyricManager
    @State private var selectedMode: ProjectionMode?

    var body: some View {
        Group {
            if selectedMode == .lyricsWithBackground {
                ContentView(switchMode: { switchProjectionMode(to: $0) })
                    .onAppear {
                        activateMode(.lyricsWithBackground)
                    }
            } else if selectedMode == .slides {
                SlideModeView(switchMode: { switchProjectionMode(to: $0) })
                    .onAppear {
                        activateMode(.slides)
                    }
            } else {
                ModeSelectionView { mode in
                    selectedMode = mode
                }
            }
        }
    }

    private func switchProjectionMode(to mode: ProjectionMode) {
        activateMode(mode)
        selectedMode = mode
    }

    private func activateMode(_ mode: ProjectionMode) {
        manager.projectionMode = mode
        if mode == .slides {
            manager.isSlideBlackout = false
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            manager.setRole(.broadcaster)
        } else {
            manager.leaveCurrentRole()
        }
    }
}

struct ModeSelectionView: View {
    var onSelect: (ProjectionMode) -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("選擇使用模式")
                        .font(.largeTitle.weight(.bold))
                    Text("歌詞投放與簡報投放分開操作，畫面與流程互不干擾。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                ViewThatFits {
                    roleButtons(axis: .horizontal)
                    roleButtons(axis: .vertical)
                }
                .frame(maxWidth: 760)
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private func roleButtons(axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 18)) : AnyLayout(VStackLayout(spacing: 18))
        layout {
            ForEach([ProjectionMode.lyricsWithBackground, ProjectionMode.slides]) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: mode == .lyricsWithBackground ? "music.mic" : "rectangle.on.rectangle.angled")
                            .font(.system(size: 36, weight: .semibold))
                        Text(mode == .lyricsWithBackground ? "A. 敬拜歌詞＋背景模式" : "B. PPT 簡報模式")
                            .font(.title2.weight(.bold))
                        Text(mode == .lyricsWithBackground ? "管理歌曲、今日流程、背景素材與歌詞投放。" : "匯入圖片投影片，使用大型控制台投放簡報。")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                    .padding(22)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
// MARK: - 輔助工具：影片匯入傳輸協定
// 這是為了讓 PhotosPicker 能正確識別並拷貝影片檔案到 App 沙盒中
struct VideoPickerTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // 建立暫存路徑
            let fileName = received.file.lastPathComponent
            let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            // 如果暫存檔已存在則先刪除
            if FileManager.default.fileExists(atPath: tempCopy.path) {
                try? FileManager.default.removeItem(at: tempCopy)
            }
            
            // 拷貝檔案到暫存區供 LyricManager 使用
            try FileManager.default.copyItem(at: received.file, to: tempCopy)
            return VideoPickerTransferable(url: tempCopy)
        }
    }
}
