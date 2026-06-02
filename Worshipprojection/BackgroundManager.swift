import SwiftUI
import PhotosUI
import UIKit
internal import Combine

class BackgroundManager: ObservableObject {
    @Published var backgroundFolders: [BackgroundFolder] = [] {
        didSet { saveBackgrounds() }
    }
    @Published var activeBackgroundFolderID: UUID?
    @Published var storageUsageString: String = "計算中..."
    @Published var memoryUsageString: String = "計算中..."
    @Published var previousBackground: BackgroundItem? = nil
    @Published var backgroundReplayToken = 0
    @Published var selectedBackground: BackgroundItem? {
        didSet {
            if selectedBackground == nil {
                previousBackground = nil
            } else if let old = oldValue, old.id != selectedBackground?.id {
                previousBackground = old
            }
        }
    }

    func replaySelectedBackground() {
        guard selectedBackground?.isVideo == true else { return }
        backgroundReplayToken += 1
    }

    private var memoryTimer: AnyCancellable?

    private var backgroundsURL: URL {
        documentsDirectory.appendingPathComponent("backgrounds_v2.json")
    }

    private var backgroundFoldersURL: URL {
        documentsDirectory.appendingPathComponent("background_folders_v1.json")
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        loadBackgrounds()
        updateStorageUsage()
        startMemoryMonitoring()
        clearTempDirectory()
    }

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
        updateStorageUsage()
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

    func importBackground(from item: PhotosPickerItem, customName: String? = nil) async {
        do {
            let isVideo = item.supportedContentTypes.contains { type in
                type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .quickTimeMovie) || type.conforms(to: .mpeg4Movie)
            }

            let id = UUID().uuidString
            let fileName: String

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
                let display = (customName == nil || customName!.isEmpty) ?
                    (isVideo ? "新影片背景" : "新圖片背景") : customName!
                let newBackground = BackgroundItem(
                    fileName: fileName,
                    displayName: display,
                    isVideo: isVideo
                )
                self.backgroundFolders[folderIndex].backgrounds.append(newBackground)
                self.selectedBackground = newBackground
                self.updateStorageUsage()
                self.clearTempDirectory()
            }
        } catch {
            print("❌ 匯入失敗: \(error.localizedDescription)")
        }
    }

    func deleteBackground(_ item: BackgroundItem, from folderID: UUID) {
        let fileURL = item.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑️ 成功從硬碟徹底刪除檔案：\(item.fileName)")
            } catch {
                print("❌ 物理刪除檔案失敗：\(error.localizedDescription)")
            }
        }

        if selectedBackground?.id == item.id {
            selectedBackground = nil
        }
        if previousBackground?.id == item.id {
            previousBackground = nil
        }

        if let folderIndex = backgroundFolders.firstIndex(where: { $0.id == folderID }) {
            backgroundFolders[folderIndex].backgrounds.removeAll(where: { $0.id == item.id })
            backgroundFolders = backgroundFolders
        }

        updateStorageUsage()
        clearTempDirectory()
    }

    func deleteBackground(at offsets: IndexSet) {
        guard let folderIndex = activeBackgroundFolderIndex else { return }
        for index in offsets {
            let background = backgroundFolders[folderIndex].backgrounds[index]
            let fileURL = documentsDirectory.appendingPathComponent(background.fileName)

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ 已成功從硬碟刪除檔案：\(background.fileName)")
                }
            } catch {
                print("❌ 無法刪除實體檔案：\(error.localizedDescription)")
            }

            if selectedBackground?.id == background.id {
                selectedBackground = nil
            }
        }

        backgroundFolders[folderIndex].backgrounds.remove(atOffsets: offsets)
        updateStorageUsage()
    }

    func deleteAllBackgrounds() {
        for folder in backgroundFolders {
            for background in folder.backgrounds {
                let fileURL = documentsDirectory.appendingPathComponent(background.fileName)
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

    func triggerAppSlimming() {
        clearTempDirectory()
        if selectedBackground == nil {
            URLCache.shared.removeAllCachedResponses()
        }
        updateStorageUsage()
        updateMemoryUsage()
    }

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

    private func saveBackgrounds() {
        do {
            let data = try JSONEncoder().encode(backgroundFolders)
            try data.write(to: backgroundFoldersURL)
        } catch {
            print("❌ 背景庫存檔失敗: \(error)")
        }
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
