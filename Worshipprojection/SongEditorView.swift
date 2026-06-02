import SwiftUI
import UIKit
internal import UniformTypeIdentifiers

struct SongEditorView: View {
    @ObservedObject var manager: LyricManager
    @Environment(\.dismiss) var dismiss

    var editingSong: Song? = nil

    @State private var title: String = ""
    @State private var rawText: String = ""
    @State private var segments: [EditableLyricSegment] = []
    @State private var selectedPreviewSegmentID: UUID?
    @State private var editorMode: LyricEditorMode = .segments
    @State private var isSyncingText = false
    @State private var draggingSegmentID: UUID?

    @State private var fontSize: Double = 80
    @State private var lineSpacing: Double = 20
    @State private var shadowRadius: Double = 10
    @State private var transitionDuration: Double = 0.12
    @State private var verticalPosition: Double = 0.5
    @State private var horizontalPaddingRatio: Double = 0.05
    @State private var backgroundDimOpacity: Double = 0.0
    @State private var horizontalAlignment: TextHorizontalAlignment = .center
    @State private var textColor: Color = .white

    private var previewText: String {
        if let selectedPreviewSegmentID,
           let segment = segments.first(where: { $0.id == selectedPreviewSegmentID }),
           !segment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return segment.content
        }

        if let firstContent = segments.first(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.content {
            return firstContent
        }

        return "預覽文字第一行\n預覽文字第二行"
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    songInfoSection
                    editorModePicker

                    if editorMode == .segments {
                        segmentEditorSection
                    } else {
                        rawTextEditorSection
                    }

                    stylePreviewSection
                    styleControlsSection
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(editingSong == nil ? "新增歌曲" : "編輯歌詞")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveAction()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                prepareInitialData()
            }
            .onChange(of: rawText) { _, newValue in
                guard !isSyncingText else { return }
                syncSegments(from: newValue)
            }
            .onChange(of: segments) { _, _ in
                guard !isSyncingText else { return }
                syncRawTextFromSegments()
            }
        }
    }

    private var songInfoSection: some View {
        editorPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("歌曲資訊")
                    .font(.headline)

                TextField("歌曲標題", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var editorModePicker: some View {
        Picker("編輯模式", selection: $editorMode) {
            ForEach(LyricEditorMode.allCases) { mode in
                Label(mode.title, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var segmentEditorSection: some View {
        editorPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("段落卡片")
                        .font(.headline)
                    Spacer()
                    Button {
                        addSegment()
                    } label: {
                        Label("新增段落", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if segments.isEmpty {
                    ContentUnavailableView("尚未建立段落", systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array($segments.enumerated()), id: \.element.id) { index, $segment in
                            EditableSegmentCard(
                                segment: $segment,
                                index: index,
                                isPreviewSelected: selectedPreviewSegmentID == segment.id,
                                onPreview: { selectedPreviewSegmentID = segment.id },
                                onDelete: { deleteSegment(id: segment.id) },
                                onDrag: {
                                    draggingSegmentID = segment.id
                                    let provider = NSItemProvider()
                                    provider.registerDataRepresentation(
                                        forTypeIdentifier: UTType.editableLyricSegment.identifier,
                                        visibility: .ownProcess
                                    ) { completion in
                                        completion(segment.id.uuidString.data(using: .utf8), nil)
                                        return nil
                                    }
                                    return provider
                                }
                            )
                            .onDrop(
                                of: [.editableLyricSegment],
                                delegate: EditableSegmentDropDelegate(
                                    targetID: segment.id,
                                    segments: $segments,
                                    draggingSegmentID: $draggingSegmentID
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var rawTextEditorSection: some View {
        editorPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("原文")
                        .font(.headline)
                    Spacer()
                    Button {
                        syncSegments(from: rawText)
                        editorMode = .segments
                    } label: {
                        Label("轉成段落", systemImage: "rectangle.grid.1x2")
                    }
                    .buttonStyle(.bordered)
                }

                TextEditor(text: $rawText)
                    .frame(minHeight: 260)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("使用 [主歌1]、[副歌]、[Bridge] 等標籤分隔段落。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var stylePreviewSection: some View {
        editorPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("所見即所得預覽")
                        .font(.headline)
                    Spacer()
                    if !segments.isEmpty {
                        Picker("預覽段落", selection: Binding(
                            get: { selectedPreviewSegmentID ?? segments.first?.id },
                            set: { selectedPreviewSegmentID = $0 }
                        )) {
                            ForEach(segments) { segment in
                                Text(segment.label.isEmpty ? "未命名" : segment.label).tag(Optional(segment.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }

                GeometryReader { geo in
                    let calcFontSize = geo.size.height * (CGFloat(fontSize) / 1000.0)
                    let calcLineSpacing = geo.size.height * (CGFloat(lineSpacing) / 1000.0)
                    let paddingX = geo.size.width * CGFloat(horizontalPaddingRatio)

                    VStack(alignment: .center) {
                        Text(previewText)
                            .font(.system(size: calcFontSize, weight: .bold))
                            .foregroundColor(textColor)
                            .multilineTextAlignment(horizontalAlignment.textAlignment)
                            .lineSpacing(calcLineSpacing)
                            .padding(.horizontal, paddingX)
                            .shadow(color: .black.opacity(0.5), radius: shadowRadius, x: 1, y: 1)
                            .frame(maxWidth: .infinity, alignment: horizontalAlignment.frameAlignment)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    .background(Color.black.opacity(0.9))
                    .offset(y: geo.size.height * CGFloat(verticalPosition - 0.5))
                }
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var styleControlsSection: some View {
        editorPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("樣式設定")
                    .font(.headline)

                numericSlider("字體大小", value: $fontSize, range: 20...200, suffix: "")
                numericSlider("行距設定", value: $lineSpacing, range: 0...150, suffix: "")

                ColorPicker("文字顏色", selection: $textColor)

                Picker("文字對齊", selection: $horizontalAlignment) {
                    ForEach(TextHorizontalAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)

                valueSlider("垂直位置", value: $verticalPosition, range: 0.15...0.85) {
                    "\(Int(verticalPosition * 100))%"
                }

                valueSlider("左右留白", value: $horizontalPaddingRatio, range: 0.02...0.2) {
                    "\(Int(horizontalPaddingRatio * 100))%"
                }

                valueSlider("陰影強度", value: $shadowRadius, range: 0...30) {
                    "\(Int(shadowRadius))"
                }

                valueSlider("切換速度", value: $transitionDuration, range: 0.05...0.8) {
                    "\(String(format: "%.2f", transitionDuration)) 秒"
                }

                valueSlider("背景壓暗", value: $backgroundDimOpacity, range: 0...0.75) {
                    "\(Int(backgroundDimOpacity * 100))%"
                }
            }
        }
    }

    private func editorPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func numericSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            TextField("數值", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .keyboardType(.numberPad)
            if !suffix.isEmpty {
                Text(suffix)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: @escaping () -> String) -> some View {
        HStack {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: range, step: title == "切換速度" ? 0.01 : 0.05)
            Text(label())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func prepareInitialData() {
        if let song = editingSong {
            let canonicalSong = manager.canonicalSong(for: song)
            title = canonicalSong.title
            rawText = canonicalSong.rawText

            fontSize = Double(canonicalSong.style.fontSize)
            lineSpacing = Double(canonicalSong.style.lineSpacing)
            shadowRadius = Double(canonicalSong.style.shadowRadius)
            transitionDuration = canonicalSong.style.transitionDuration
            verticalPosition = Double(canonicalSong.style.verticalPosition)
            horizontalPaddingRatio = Double(canonicalSong.style.horizontalPaddingRatio)
            backgroundDimOpacity = canonicalSong.style.backgroundDimOpacity
            horizontalAlignment = canonicalSong.style.horizontalAlignment

            let data = canonicalSong.style.textColor
            textColor = Color(red: data.r, green: data.g, blue: data.b)
        }

        syncSegments(from: rawText)
    }

    private func syncSegments(from text: String) {
        isSyncingText = true
        let parsedSegments = Self.parseSegments(from: text)
        segments = parsedSegments
        if selectedPreviewSegmentID == nil || !parsedSegments.contains(where: { $0.id == selectedPreviewSegmentID }) {
            selectedPreviewSegmentID = parsedSegments.first?.id
        }
        DispatchQueue.main.async {
            isSyncingText = false
        }
    }

    private func syncRawTextFromSegments() {
        isSyncingText = true
        rawText = Self.rawText(from: segments)
        if selectedPreviewSegmentID == nil || !segments.contains(where: { $0.id == selectedPreviewSegmentID }) {
            selectedPreviewSegmentID = segments.first?.id
        }
        DispatchQueue.main.async {
            isSyncingText = false
        }
    }

    private func addSegment() {
        let newSegment = EditableLyricSegment(label: "新段落", content: "")
        segments.append(newSegment)
        selectedPreviewSegmentID = newSegment.id
    }

    private func deleteSegment(id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedPreviewSegmentID == id {
            selectedPreviewSegmentID = segments.first?.id
        }
    }

    private func saveAction() {
        let finalRawText = Self.rawText(from: segments)

        let uiColor = UIColor(textColor)
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let newColorData = ColorData(r: Double(red), g: Double(green), b: Double(blue))

        if let song = editingSong {
            var updated = manager.canonicalSong(for: song)
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.rawText = finalRawText

            updated.style.fontSize = CGFloat(fontSize)
            updated.style.lineSpacing = CGFloat(lineSpacing)
            updated.style.shadowRadius = CGFloat(shadowRadius)
            updated.style.transitionDuration = transitionDuration
            updated.style.verticalPosition = CGFloat(verticalPosition)
            updated.style.horizontalPaddingRatio = CGFloat(horizontalPaddingRatio)
            updated.style.backgroundDimOpacity = backgroundDimOpacity
            updated.style.horizontalAlignment = horizontalAlignment
            updated.style.textColor = newColorData

            manager.updateSong(updated)
        } else {
            manager.addSong(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                text: finalRawText,
                fontSize: CGFloat(fontSize),
                lineSpacing: CGFloat(lineSpacing),
                shadowRadius: CGFloat(shadowRadius),
                transitionDuration: transitionDuration,
                verticalPosition: CGFloat(verticalPosition),
                horizontalPaddingRatio: CGFloat(horizontalPaddingRatio),
                backgroundDimOpacity: backgroundDimOpacity,
                horizontalAlignment: horizontalAlignment,
                textColor: textColor
            )
        }
        dismiss()
    }

    private static func parseSegments(from rawText: String) -> [EditableLyricSegment] {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        let pattern = "\\[(.*?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [EditableLyricSegment(label: "內容", content: rawText)]
        }

        let nsString = rawText as NSString
        let matches = regex.matches(in: rawText, options: [], range: NSRange(location: 0, length: nsString.length))

        guard !matches.isEmpty else {
            return [EditableLyricSegment(label: "內容", content: rawText)]
        }

        return matches.enumerated().compactMap { index, match in
            let label = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let contentStart = match.range.location + match.range.length
            let contentEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsString.length
            let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            let content = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !label.isEmpty || !content.isEmpty else { return nil }
            return EditableLyricSegment(label: label.isEmpty ? "未命名" : label, content: content)
        }
    }

    private static func rawText(from segments: [EditableLyricSegment]) -> String {
        segments
            .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { segment in
                let label = segment.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : segment.label.trimmingCharacters(in: .whitespacesAndNewlines)
                return "[\(label)]\n\(segment.content.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n\n")
    }
}

private struct EditableSegmentCard: View {
    @Binding var segment: EditableLyricSegment
    let index: Int
    let isPreviewSelected: Bool
    let onPreview: () -> Void
    let onDelete: () -> Void
    let onDrag: () -> NSItemProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextField("段落名稱", text: $segment.label)
                    .textFieldStyle(.roundedBorder)

                Button(action: onPreview) {
                    Image(systemName: isPreviewSelected ? "eye.fill" : "eye")
                }
                .buttonStyle(.bordered)
                .tint(isPreviewSelected ? .orange : .blue)
                .accessibilityLabel("預覽此段落")

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("刪除段落", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)

                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("拖曳排序")
                    .onDrag(onDrag)
            }

            TextEditor(text: $segment.content)
                .frame(minHeight: 96)
                .padding(8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .font(.body)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPreviewSelected ? Color.orange : Color.clear, lineWidth: 2)
        )
    }
}

private struct EditableSegmentDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var segments: [EditableLyricSegment]
    @Binding var draggingSegmentID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingSegmentID,
              draggingSegmentID != targetID,
              let fromIndex = segments.firstIndex(where: { $0.id == draggingSegmentID }),
              let toIndex = segments.firstIndex(where: { $0.id == targetID }) else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            segments.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSegmentID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct EditableLyricSegment: Identifiable, Equatable {
    var id = UUID()
    var label: String
    var content: String
}

private enum LyricEditorMode: String, CaseIterable, Identifiable {
    case segments
    case rawText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .segments: "段落"
        case .rawText: "原文"
        }
    }

    var icon: String {
        switch self {
        case .segments: "rectangle.grid.1x2"
        case .rawText: "text.alignleft"
        }
    }
}

private extension UTType {
    static let editableLyricSegment = UTType(exportedAs: "com.worshipprojection.editable-lyric-segment")
}
