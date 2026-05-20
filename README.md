# Worship Projection

Worship Projection 是一款為教會敬拜、聚會與現場活動設計的 iPadOS / iOS 投放工具。App 目前分成兩個獨立模式：

- A. 敬拜歌詞＋背景模式
- B. PPT 簡報模式

兩個模式從入口就分流，操作邏輯彼此分開，避免現場投放時互相干擾。

## 使用方法
檔案下載下來，用xcode開啟，build在同帳號的設備上，就可以使用了！
（應該啦，不確定？）

## 主要功能

### A. 敬拜歌詞＋背景模式

- 管理「所有歌曲」與「今日流程」。
- 使用 `[主歌]`、`[副歌]`、`[Bridge]` 等標籤自動解析歌詞段落。
- 點選段落即可更新 Live 投放畫面與 Web 提詞機狀態。
- 每首歌可保存文字樣式：
  - 字體大小
  - 文字顏色
  - 行距
  - 陰影
  - 其他排版參數
- 支援批次選取歌曲：
  - 全選 / 取消全選
  - 從所有歌曲批次加入今日流程
  - 從今日流程批次移除
  - 批次刪除歌曲

### 背景素材管理

- 支援圖片背景與影片背景。
- 背景切換保留淡入淡出效果。
- 可選擇純黑無背景。
- 背景素材不會被打包進專案包，避免檔案過大。
- 支援背景資料夾：
  - 新增資料夾
  - 切換資料夾
  - 重新命名資料夾
  - 刪除資料夾
- 支援背景素材：
  - 預覽圖片
  - 影片取第一幀作為預覽
  - 重新命名
  - 刪除

### Web 提詞機

- 可由 App 啟動本機 Web server。
- 同一路由器內的手機或電腦可用瀏覽器開啟網址觀看目前歌詞。
- Web 提詞機會跟隨每次歌詞段落變換更新。
- 可複製 Web 提詞機網址。
- iPhone 可只負責開 Web 提詞機，不需要啟動主控台廣播功能。

### B. PPT 簡報模式

- 簡報模式與歌詞模式獨立。
- 支援匯入圖片作為投影片。
- 支援簡報資料夾：
  - 新增資料夾
  - 切換不同場次或主題的簡報
  - 刪除資料夾
- 支援投影片操作：
  - 上一張
  - 下一張
  - 黑畫面 / 恢復畫面
  - 點選縮圖切換
  - 滑動刪除
  - 排序模式中拖移調整順序
- iPad 使用大預覽與右側投影片清單。
- iPhone 使用上半部預覽控制、下半部投影片清單的版面。

## 外接輸出與 Live 預覽

- 支援 AirPlay / 外接螢幕輸出。
- iPad / iPhone 上保留控制台畫面。
- 外接輸出顯示乾淨的 LiveDisplayView。
- 歌詞＋背景模式輸出歌詞與背景。
- 簡報模式輸出目前投影片。

## 檔案管理與可攜式專案包

- 支援匯出可攜式專案包。
- 支援 JSON 與 TXT 格式。
- 匯出內容包含：
  - 所有歌曲
  - 今日流程順序
  - 歌詞格式設定
- 匯出內容不包含背景素材，避免專案包過大。
- 匯入專案包採「新增歌曲」邏輯，不會整批取代原本資料。
- 匯入時會避免完全相同歌曲重複新增。
- JSON 專案包使用 `todaySetlistIDs` 保存今日流程，避免同一首歌在包內重複存完整歌詞。

## 目前資料儲存

App 使用本機沙盒儲存資料：

- `songs_v2.json`: 所有歌曲
- `setlist_v2.json`: 今日流程
- `background_folders_v1.json`: 背景資料夾
- `slide_folders_v1.json`: 簡報資料夾
- 背景與投影片素材檔案存放於 App Documents 目錄

舊版資料仍會嘗試遷移：

- 舊背景庫會搬入「預設背景」
- 舊投影片庫會搬入「預設簡報」

## 專案結構

```text
Worshipprojection/
├── WorshipprojectionApp.swift       # App 入口與 A/B 模式切換
├── ContentView.swift                # 敬拜歌詞＋背景模式主畫面
├── SlideModeView.swift              # PPT 簡報模式主畫面
├── LiveDisplayView.swift            # Live / AirPlay 輸出畫面
├── BackgroundPlayerView.swift       # 背景圖片與影片播放器
├── SongEditorView.swift             # 歌詞與文字樣式編輯
├── StageDisplayView.swift           # 接收端提詞顯示
├── WebTeleprompterServer.swift      # Web 提詞機 HTTP server
├── LyricManager.swift               # 核心狀態、匯入匯出、資料持久化
├── MultipeerManager.swift           # iPad 廣播同步
├── ExternalDisplayManager.swift     # AirPlay / HDMI 外接螢幕管理
└── Models.swift                     # Song、背景、簡報、專案包等資料模型
```

## 已知問題

目前已知風險整理在 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。

## 開發備註

目前主要分支：

- `codex/slide-image-mode-mvp`

建議在每次提交前至少執行：

```bash
xcrun swiftc -parse Worshipprojection/*.swift
plutil -lint Worshipprojection/Info.plist
git diff --check
```
