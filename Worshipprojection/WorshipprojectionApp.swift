import SwiftUI
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
            ContentView()
                .environmentObject(lyricManager)
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
