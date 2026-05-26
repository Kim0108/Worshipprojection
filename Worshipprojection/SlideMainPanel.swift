import SwiftUI
import PhotosUI

struct SlideMainPanel: View {
    @ObservedObject var manager: LyricManager
    @ObservedObject var backgroundManager: BackgroundManager
    let sizeClass: UserInterfaceSizeClass?
    var switchMode: ((ProjectionMode) -> Void)?
    @Binding var selectedSlidePhotoItems: [PhotosPickerItem]
    @Binding var showingPDFImporter: Bool
    var isCompactLayout = false

    var body: some View {
        if isCompactLayout {
            compactLayout
        } else {
            ipadLayout
        }
    }

    private var ipadLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 18) {
                ScaledPreviewView(manager: manager, backgroundManager: backgroundManager)
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

    private var compactLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { geo in
                VStack(spacing: 10) {
                    ScaledPreviewView(manager: manager, backgroundManager: backgroundManager)
                        .frame(maxHeight: geo.size.height * 0.56)
                        .padding(.horizontal, 12)
                    compactControls
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
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
        }
        .padding(.horizontal, sizeClass == .compact ? 12 : 28)
        .padding(.vertical, sizeClass == .compact ? 10 : 18)
    }

    private var largeControls: some View {
        VStack(spacing: 18) {
            HStack {
                slideStatusText(titleFont: .title.weight(.bold), subtitleFont: .body)

                Spacer()

                PhotosPicker(selection: $selectedSlidePhotoItems, matching: .images) {
                    Label("加入圖片", systemImage: "photo.badge.plus")
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingPDFImporter = true
                } label: {
                    Label("匯入 PDF", systemImage: "doc.richtext")
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: 54)
                }
                .buttonStyle(.bordered)
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

            slideKeyboardShortcuts
        }
    }

    private var compactControls: some View {
        VStack(spacing: 10) {
            HStack {
                slideStatusText(titleFont: .headline.weight(.bold), subtitleFont: .caption)

                Spacer()

                PhotosPicker(selection: $selectedSlidePhotoItems, matching: .images) {
                    Label("加入", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    showingPDFImporter = true
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
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

            slideKeyboardShortcuts
        }
    }

    private func slideStatusText(titleFont: Font, subtitleFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pageLabel)
                .font(titleFont)
            Text(activeSlideName)
                .font(subtitleFont)
                .foregroundColor(.secondary)
                .lineLimit(1)
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

    private var slideKeyboardShortcuts: some View {
        Group {
            Button("上一張") { manager.goToPreviousSlide() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(manager.slideLibrary.isEmpty || manager.activeSlideIndex == 0)
            Button("上一張") { manager.goToPreviousSlide() }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(manager.slideLibrary.isEmpty || manager.activeSlideIndex == 0)
            Button("下一張") { manager.goToNextSlide() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(manager.slideLibrary.isEmpty || manager.activeSlideIndex >= manager.slideLibrary.count - 1)
            Button("下一張") { manager.goToNextSlide() }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(manager.slideLibrary.isEmpty || manager.activeSlideIndex >= manager.slideLibrary.count - 1)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
