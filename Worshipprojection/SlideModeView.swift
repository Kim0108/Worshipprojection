import SwiftUI
import PhotosUI
internal import UniformTypeIdentifiers

struct SlideModeView: View {
    @EnvironmentObject var manager: LyricManager
    @EnvironmentObject var backgroundManager: BackgroundManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    var switchMode: ((ProjectionMode) -> Void)? = nil

    @State private var selectedSlidePhotoItems: [PhotosPickerItem] = []
    @State private var showingNewFolderAlert = false
    @State private var showingPDFImporter = false
    @State private var importErrorMessage: String?
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
        .fileImporter(
            isPresented: $showingPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImportResult(result)
        }
        .alert("匯入 PDF", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var ipadLayout: some View {
        HStack(spacing: 0) {
            SlideMainPanel(
                manager: manager,
                backgroundManager: backgroundManager,
                sizeClass: sizeClass,
                switchMode: switchMode,
                selectedSlidePhotoItems: $selectedSlidePhotoItems,
                showingPDFImporter: $showingPDFImporter
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SlideLibraryPanel(
                manager: manager,
                sizeClass: sizeClass,
                selectedSlidePhotoItems: $selectedSlidePhotoItems,
                showingNewFolderAlert: $showingNewFolderAlert,
                showingPDFImporter: $showingPDFImporter,
                isReorderingSlides: $isReorderingSlides
            )
            .frame(width: 380)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            SlideMainPanel(
                manager: manager,
                backgroundManager: backgroundManager,
                sizeClass: sizeClass,
                switchMode: switchMode,
                selectedSlidePhotoItems: $selectedSlidePhotoItems,
                showingPDFImporter: $showingPDFImporter,
                isCompactLayout: true
            )

            Divider()

            SlideLibraryPanel(
                manager: manager,
                sizeClass: sizeClass,
                selectedSlidePhotoItems: $selectedSlidePhotoItems,
                showingNewFolderAlert: $showingNewFolderAlert,
                showingPDFImporter: $showingPDFImporter,
                isReorderingSlides: $isReorderingSlides
            )
        }
    }

    private func handlePDFImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            Task {
                do {
                    try await manager.importPDFSlides(from: url)
                    if needsStop {
                        url.stopAccessingSecurityScopedResource()
                    }
                } catch {
                    if needsStop {
                        url.stopAccessingSecurityScopedResource()
                    }
                    await MainActor.run {
                        importErrorMessage = "PDF 匯入失敗：\(error.localizedDescription)"
                    }
                }
            }
        } catch {
            importErrorMessage = "PDF 匯入失敗：\(error.localizedDescription)"
        }
    }
}
