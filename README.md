# Worship Projection

Worship Projection 是一款為教會敬拜、聚會與現場活動設計的 iPadOS / iOS 投放工具。App 目前分成兩個獨立模式：

- A. 敬拜歌詞＋背景模式
- B. PPT 簡報模式

兩個模式從入口就分流，操作邏輯彼此分開，避免現場投放時互相干擾。

## 使用方法

1. 下載或 clone 專案。
2. 用 Xcode 開啟 `Worshipprojection.xcodeproj`。
3. 選擇實體 iPad / iPhone 作為執行裝置。
4. 確認 Signing & Capabilities 使用自己的 Apple Developer Team。
5. 按 Run build 到裝置上測試。

建議使用實體 iPad 測試外接螢幕、AirPlay、藍牙鍵盤與 Photos 匯入；模擬器不適合驗證這些現場投放功能。

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
  - 批次匯入圖片 / 影片
  - 重新命名
  - 刪除

背景狀態由 `BackgroundManager` 管理，Live 輸出渲染由 `BackgroundPlayerView` 處理，避免選擇歌詞段落時整個背景素材庫跟著重刷。

### Web 提詞機

- 可由 App 啟動本機 Web server。
- 同一路由器內的手機或電腦可用瀏覽器開啟網址觀看目前歌詞。
- Web 提詞機會跟隨每次歌詞段落變換更新。
- 可複製 Web 提詞機網址。
- iPhone 可只負責開 Web 提詞機，不需要啟動主控台廣播功能。

### B. PPT 簡報模式

- 簡報模式與歌詞模式獨立。
- 支援匯入圖片作為投影片。
- 支援匯入 PDF，App 會將 PDF 每一頁轉成投影片圖片。
- 目前不直接原生解析 `.pptx`；建議先從 PowerPoint / Keynote 匯出 PDF，再用 App 匯入 PDF。
- 支援簡報資料夾：
  - 新增資料夾
  - 切換不同場次或主題的簡報
  - 重新命名資料夾
  - 刪除資料夾
- 支援投影片操作：
  - 上一張
  - 下一張
  - 黑畫面 / 恢復畫面
  - 點選縮圖切換
  - 重新命名投影片
  - 滑動刪除
  - 排序模式中拖移調整順序
- 支援藍牙鍵盤 / 外接鍵盤：
  - 左鍵 / 上鍵：上一張
  - 右鍵 / 下鍵：下一張
  - 文字輸入框正在編輯時不會搶走鍵盤焦點
- iPad 使用大預覽與右側投影片清單。
- iPhone 使用上半部預覽控制、下半部投影片清單的版面。

## 外接輸出與 Live 預覽

- 支援 AirPlay / 外接螢幕輸出。
- iPad / iPhone 上保留控制台畫面。
- 外接輸出顯示乾淨的 LiveDisplayView。
- 歌詞＋背景模式輸出歌詞與背景。
- 簡報模式輸出目前投影片。

iPad / iPhone 上的 Live 預覽與 AirPlay / 外接螢幕輸出使用同一套 `LiveDisplayView` 狀態來源，但外接螢幕會用獨立 window 顯示乾淨畫面，不顯示控制台。

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

注意：目前可攜式專案包主要處理歌曲與今日流程；背景素材與投影片素材仍存放於裝置 App Documents 目錄。

## App 名稱

目前 App 顯示名稱設定在 `Worshipprojection/Info.plist`：

- `CFBundleDisplayName`: `PSchurch投影程式`

如果要改 App 在 iPad 主畫面上的名稱，修改這個值後重新 build 即可。

## 打包成 IPA

### 第一步：從 Xcode Archive 產生 IPA

1. 在 Xcode 執行 `Product > Archive`。
2. Archive 完成後，在 Organizer 對該 Archive 選 `Show in Finder`。
3. 打開 Terminal，切到使用者根目錄，執行：

```bash
chmod 777 ipagen.sh
```

4. 繼續執行：

```bash
./ipagen.sh <file-path>
```

`<file-path>` 可以直接把剛剛 Finder 找到的 Archive 檔拖進 Terminal。指令前面不需要輸入 `$`。

5. 完成後，桌面會產生一個 `App.ipa`。
6. 記得把 `App.ipa` 安裝到要測試的設備裡。

### 第二步：用 SideStore 安裝到設備

1. 在 iLoader 登入 Apple ID。
2. 在旁邊找到要載入的 device。
3. device 需要先下載 `LocalDevVPN`；如果 iLoader 找不到 device，就改用接線。
4. 安裝 SideStore。
5. 在 SideStore 登入 Apple ID。
6. 到 `My Apps`，按左上角 `+`。
7. 找到剛剛打包好的 `App.ipa`，安裝即可。

注意事項：

- 打包 IPA 仍需要完整 Xcode toolchain；只有 Command Line Tools 不夠。
- `ipagen.sh` 需放在執行指令的目錄，或用完整路徑執行。
- 使用 Apple ID、iLoader、SideStore 與 LocalDevVPN 時，請確認設備與帳號授權狀態正常。

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
├── SlideMainPanel.swift             # 簡報模式預覽與控制台
├── SlideLibraryPanel.swift          # 簡報資料夾與投影片清單
├── SlideKeyboardCommandBridge.swift # 藍牙 / 外接鍵盤方向鍵控制
├── LiveDisplayView.swift            # Live / AirPlay 輸出畫面
├── BackgroundManager.swift          # 背景資料夾、素材匯入與狀態管理
├── BackgroundPlayerView.swift       # 背景圖片與影片播放器
├── SongEditorView.swift             # 歌詞與文字樣式編輯
├── StageDisplayView.swift           # 接收端提詞顯示
├── WebTeleprompterServer.swift      # Web 提詞機 HTTP server
├── LyricManager.swift               # 歌曲、今日流程、簡報與專案包管理
├── MultipeerManager.swift           # iPad 廣播同步
├── ExternalDisplayManager.swift     # AirPlay / HDMI 外接螢幕管理
└── Models.swift                     # Song、背景、簡報、專案包等資料模型
```

## 版本與回復

目前功能開發分支：

- `codex/穩定性`

如果更新後不穩定，建議先保留目前狀態，再回到已知穩定 commit：

```bash
git branch backup-before-rollback
git reset --hard <stable-commit>
```

如果已經 push 到 GitHub，回退遠端分支前請確認團隊沒有其他人正在基於最新 commit 開發，再使用：

```bash
git push --force-with-lease origin codex/穩定性
```

## 開發備註

建議在每次提交前至少執行：

```bash
xcrun swiftc -parse Worshipprojection/*.swift
plutil -lint Worshipprojection/Info.plist
git diff --check
```
