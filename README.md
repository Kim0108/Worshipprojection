# Worship Projection

這是一款專為教會敬拜與現場活動設計的 **Live 投影 iPadOS App**。
具備簡單易懂的三欄式介面，支援實時背景影片/圖片切換、動態歌詞段落控制，以及AirPlay/實體線路無縫全螢幕輸出。

## Features

* **雙螢幕獨立渲染**：iPad 端顯示操作面板，外接螢幕自動偵測並全螢幕滿版輸出純淨畫面（無任何 UI 遮擋）。
* **三欄式直覺介面**：
    * **左欄 (選單)**：支援「所有歌曲」與「今日流程」快速切換。
    * **中欄 (資源庫)**：顯示歌曲列表與背景素材網格，支援實時預覽。
    * **右欄 (Live 控制台)**：具備 16:9 實時等比例預覽框，以及一鍵觸發的動態歌詞段落按鈕。
* **無縫背景播放器**：支援 `.mp4` / `.mov` 等動態影片及靜態圖片背景。內建無縫循環 (Seamless Looping) 與淡入淡出 (Crossfade) 轉場效果。
* **所見即所得歌詞編輯**：支援使用 `[主歌1]`、`[副歌]` 標籤自動解析段落。可獨立儲存每首歌曲的字體大小、顏色與行距設定。
* **本地持久化儲存**：全檔案採沙盒 (Sandbox) 本地儲存，無須依賴外部網路，保證 Live 現場的絕對穩定性與流暢度。

---

## Architecture

本專案採用 **MVVM 架構** 結合 SwiftUI 的宣告式 UI 設計，嚴格遵守「畫面與邏輯分離」的原則。

```text
WorshipProjection/
│
├── Views (使用者介面)
│   ├── ContentView.swift           # 主畫面入口 (內含 Sidebar, ResourceLibrary, LiveControlBoard 等模組)
│   ├── LiveDisplayView.swift       # 投影輸出與 16:9 預覽畫面核心，負責疊加背景與文字轉場
│   ├── SongEditorView.swift        # 歌詞編輯器、排版設定與即時解析預覽
│   └── BackgroundPlayerView.swift  # 封裝 AVPlayer 的底層無縫循環播放器
│
├── ViewModels & Managers (業務邏輯與狀態)
│   ├── LyricManager.swift          # 核心大腦：狀態管理 (所有歌曲、背景庫) 與 本地檔案 I/O
│   └── ExternalDisplayManager.swift# 螢幕監聽器：負責偵測 AirPlay/HDMI 並建立獨立 UIWindow
│
├── Models & Utils (資料與工具)
│   ├── Models.swift                # 定義 Song, BackgroundItem, TextSettings 等核心資料結構
│   └── Utils.swift                 # 共用工具 (如 VideoPickerTransferable 影片沙盒匯入協定)
│
└── App & Configurations (系統配置)
    ├── WorshipprojectionApp.swift  # App 進入點，負責初始化全域唯一的 Managers
    └── Info.plist                  # 宣告背景音訊權限 (Audio Background Modes 確保鎖定時不中斷)
